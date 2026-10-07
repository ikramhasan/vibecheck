// Runs the pi extension against a fake ExtensionAPI and checks the files it writes.
// Run: node --test integrations/pi/test/
import assert from "node:assert/strict";
import { mkdtempSync, readdirSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, test } from "node:test";

const dir = mkdtempSync(join(tmpdir(), "agent-companion-"));
process.env.AGENT_COMPANION_DIR = dir;
delete process.env.PI_SUBAGENT_CHILD;
after(() => rmSync(dir, { recursive: true, force: true }));

const { default: extension, describeTool, shouldReport } = await import("../extensions/agent-companion.ts");

function fakePi() {
	const handlers = new Map();
	return {
		on(name, fn) {
			handlers.set(name, [...(handlers.get(name) ?? []), fn]);
			return () => {};
		},
		async emit(name, event = {}, ctx = {}) {
			for (const fn of handlers.get(name) ?? []) await fn({ type: name, ...event }, ctx);
		},
	};
}

function ctx(mode = "tui", sessionId = "sess-1", sessionFile = `/sessions/${sessionId}.jsonl`) {
	return {
		mode,
		cwd: "/work/project",
		model: { id: "test-model" },
		sessionManager: {
			getSessionId: () => sessionId,
			getSessionFile: () => sessionFile,
			getSessionName: () => undefined,
			getBranch: () => [{ type: "message", message: { role: "user", content: "earlier task" } }],
		},
	};
}

const sessionsDir = join(dir, "sessions");
const files = () => {
	try {
		return readdirSync(sessionsDir).filter((f) => f.endsWith(".json"));
	} catch {
		return [];
	}
};
const read = () => JSON.parse(readFileSync(join(sessionsDir, files()[0]), "utf8"));

test("full lifecycle writes the shared contract", async () => {
	const pi = fakePi();
	extension(pi);
	const c = ctx();

	await pi.emit("session_start", { reason: "startup" }, c);
	let s = read();
	assert.equal(s.schemaVersion, 1);
	assert.deepEqual(s.agent, { id: "pi", name: "pi" });
	assert.equal(s.session.id, "sess-1");
	assert.equal(s.session.cwd, "/work/project");
	assert.equal(s.pid, process.pid);
	assert.equal(s.status, "idle");
	assert.equal(s.task, "earlier task");

	await pi.emit("before_agent_start", { prompt: "Add   a\npricing page" }, c);
	await pi.emit("agent_start", {}, c);
	s = read();
	assert.equal(s.status, "working");
	assert.equal(s.task, "Add a pricing page");

	await pi.emit("ui_prompt_start", { reason: "ui_prompt", kind: "confirm", title: "Allow rm -rf build?" }, c);
	s = read();
	assert.equal(s.status, "needs_attention");
	assert.deepEqual(s.attention, { kind: "permission", message: "Allow rm -rf build?" });

	// Tool events while blocked must not clear attention.
	await pi.emit("tool_execution_start", { toolName: "read", args: { path: "/x" } }, c);
	assert.equal(read().status, "needs_attention");

	await pi.emit("ui_prompt_end", { reason: "ui_prompt", kind: "confirm" }, c);
	s = read();
	assert.equal(s.status, "working");
	assert.equal(s.attention, null);

	await pi.emit("agent_end", { messages: [{ role: "assistant", stopReason: "stop" }] }, c);
	await pi.emit("agent_settled", {}, c);
	assert.equal(read().status, "idle");

	await pi.emit("session_shutdown", { reason: "quit" }, c);
	assert.equal(files().length, 0);
});

test("errors stay visible after settling", async () => {
	const pi = fakePi();
	extension(pi);
	const c = ctx("tui", "sess-err");
	await pi.emit("session_start", { reason: "startup" }, c);
	await pi.emit("agent_start", {}, c);
	await pi.emit("agent_end", { messages: [{ role: "assistant", stopReason: "error", errorMessage: "rate limited" }] }, c);
	await pi.emit("agent_settled", {}, c);
	const s = read();
	assert.equal(s.status, "error");
	assert.equal(s.activity, "rate limited");
	await pi.emit("session_shutdown", { reason: "quit" }, c);
});

test("one-shot and ephemeral runs are not reported", async () => {
	const pi = fakePi();
	extension(pi);
	await pi.emit("session_start", { reason: "startup" }, ctx("print"));
	await pi.emit("session_start", { reason: "startup" }, ctx("json"));
	await pi.emit("session_start", { reason: "startup" }, ctx("rpc", "ephemeral", null));
	assert.equal(files().length, 0);
});

test("persisted RPC sessions (GUI hosts like T3 Code) are reported", async () => {
	const pi = fakePi();
	extension(pi);
	const c = ctx("rpc", "t3-thread");
	await pi.emit("session_start", { reason: "startup" }, c);
	assert.deepEqual(files(), ["pi--t3-thread.json"]);
	await pi.emit("session_shutdown", { reason: "quit" }, c);
});

test("subagent children are skipped", () => {
	assert.equal(shouldReport(ctx("tui"), { PI_SUBAGENT_CHILD: "1" }), false);
});

test("session switch replaces the file", async () => {
	const pi = fakePi();
	extension(pi);
	await pi.emit("session_start", { reason: "startup" }, ctx("tui", "old"));
	await pi.emit("session_shutdown", { reason: "new" }, ctx("tui", "old"));
	await pi.emit("session_start", { reason: "new" }, ctx("tui", "new"));
	assert.deepEqual(files(), ["pi--new.json"]);
	await pi.emit("session_shutdown", { reason: "quit" }, ctx("tui", "new"));
});

test("tool descriptions", () => {
	assert.equal(describeTool("bash", { command: "npm   test" }), "Running npm test");
	assert.equal(describeTool("mystery", {}), "Using mystery");
});
