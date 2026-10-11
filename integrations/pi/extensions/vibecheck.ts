/**
 * vibecheck — pi integration.
 *
 * Translates pi extension events into the agent-neutral session state defined in
 * integrations/core. All file handling lives in the shared SessionReporter; this
 * file is only the pi → contract mapping.
 */
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { SessionReporter, oneLine, type SessionState } from "../../core/reporter.ts";

const AGENT = { id: "pi", name: "pi" };

/**
 * Which sessions are shown:
 * - tui: always (pi in a terminal).
 * - rpc: only persisted sessions. GUI hosts such as T3 Code drive real chat
 *   threads over RPC; their throwaway helper runs use --no-session and have no
 *   session file.
 * - print/json: never; they are one-shot runs.
 * pi-subagents child processes are always skipped.
 */
export function shouldReport(ctx: ExtensionContext, env: NodeJS.ProcessEnv = process.env): boolean {
	if (env.VIBECHECK_DISABLE === "1") return false;
	if (env.PI_SUBAGENT_CHILD === "1") return false;
	if (env.VIBECHECK_ALL_MODES === "1") return true;
	if (ctx.mode === "tui") return true;
	if (ctx.mode === "rpc") return Boolean(ctx.sessionManager.getSessionFile());
	return false;
}

function textOf(content: unknown): string | undefined {
	if (typeof content === "string") return content;
	if (!Array.isArray(content)) return undefined;
	return content
		.filter((c): c is { type: "text"; text: string } => c?.type === "text" && typeof c.text === "string")
		.map((c) => c.text)
		.join(" ");
}

function modelLabel(ctx: ExtensionContext): string | undefined {
	return ctx.model?.id;
}

function homeRelative(path: string): string {
	const home = process.env.HOME;
	return home && path.startsWith(`${home}/`) ? `~${path.slice(home.length)}` : path;
}

/** Short human description of a tool call for the panel's activity line. */
export function describeTool(toolName: string, args: any): string {
	const a = args && typeof args === "object" ? args : {};
	const path = typeof a.path === "string" ? homeRelative(a.path) : undefined;
	switch (toolName) {
		case "read":
			return `Reading ${path ?? "a file"}`;
		case "write":
			return `Writing ${path ?? "a file"}`;
		case "edit":
			return `Editing ${path ?? "a file"}`;
		case "bash":
			return `Running ${oneLine(a.command, 80) ?? "a command"}`;
		case "web_search":
			return `Searching ${oneLine(a.query ?? a.queries?.[0], 70) ?? "the web"}`;
		case "fetch_content":
			return `Fetching ${oneLine(a.url ?? a.urls?.[0], 70) ?? "a page"}`;
		case "subagent":
			return "Running subagents";
		case "codemode":
			return "Running a script";
		default:
			return `Using ${toolName}`;
	}
}

export default function vibecheck(pi: ExtensionAPI) {
	let reporter: SessionReporter | undefined;
	// Blocking dialogs can nest; attention clears when the last one closes.
	let openPrompts = 0;
	let statusBeforePrompt: SessionState["status"] = "idle";

	const stop = () => {
		reporter?.close();
		reporter = undefined;
		openPrompts = 0;
	};

	pi.on("session_start", (_event, ctx) => {
		stop();
		if (!shouldReport(ctx)) return;
		const sm = ctx.sessionManager;
		reporter = new SessionReporter({
			agent: AGENT,
			sessionId: sm.getSessionId(),
			initial: {
				status: "idle",
				cwd: ctx.cwd,
				name: sm.getSessionName(),
				model: modelLabel(ctx),
				task: lastUserPrompt(ctx),
			},
		});
	});

	pi.on("session_shutdown", () => stop());

	pi.on("session_info_changed", (event) => reporter?.update({ name: event.name }));

	pi.on("model_select", (event) => reporter?.update({ model: event.model?.id }));

	pi.on("before_agent_start", (event) => {
		const task = oneLine(event.prompt);
		if (task) reporter?.update({ task });
	});

	pi.on("agent_start", () => reporter?.update({ status: "working", activity: "Thinking…", attention: null }));

	pi.on("turn_start", () => {
		if (reporter?.current.status === "working") reporter.update({ activity: "Thinking…" });
	});

	pi.on("message_update", (event) => {
		if (!reporter || reporter.current.status !== "working") return;
		const t = event.assistantMessageEvent?.type;
		if (t === "thinking_start") reporter.update({ activity: "Thinking…" });
		else if (t === "text_start") reporter.update({ activity: "Writing a response…" });
	});

	pi.on("tool_execution_start", (event) => {
		if (!reporter || event.parentToolCallId) return;
		if (reporter.current.status === "needs_attention") return;
		reporter.update({ status: "working", activity: describeTool(event.toolName, event.args) });
	});

	// Any blocking dialog (confirm/select/input/editor) means pi is waiting on the user.
	pi.on("ui_prompt_start", (event) => {
		if (!reporter) return;
		if (openPrompts === 0) statusBeforePrompt = reporter.current.status;
		openPrompts += 1;
		reporter.update({
			status: "needs_attention",
			attention: {
				kind: event.kind === "confirm" ? "permission" : event.kind === "select" ? "question" : "input",
				message: oneLine(event.title) ?? "Waiting for your answer",
			},
		});
	});

	pi.on("ui_prompt_end", () => {
		if (!reporter) return;
		openPrompts = Math.max(0, openPrompts - 1);
		if (openPrompts > 0) return;
		reporter.update({
			status: statusBeforePrompt === "needs_attention" ? "working" : statusBeforePrompt,
			attention: null,
		});
	});

	pi.on("agent_end", (event) => {
		if (!reporter) return;
		const last = [...(event.messages ?? [])].reverse().find((m: any) => m?.role === "assistant") as any;
		if (last?.stopReason === "error") {
			reporter.update({ status: "error", activity: oneLine(last.errorMessage, 120) ?? "Run failed" });
		} else if (last?.stopReason === "aborted") {
			reporter.update({ activity: "Stopped" });
		}
	});

	// Final: pi will not continue on its own. Leave error state visible.
	pi.on("agent_settled", () => {
		if (!reporter) return;
		openPrompts = 0;
		const failed = reporter.current.status === "error";
		reporter.update({
			status: failed ? "error" : "idle",
			activity: failed ? reporter.current.activity : reporter.current.activity === "Stopped" ? "Stopped" : undefined,
			attention: null,
		});
	});
}

/** Restore the task line when resuming an existing session. */
function lastUserPrompt(ctx: ExtensionContext): string | undefined {
	try {
		const branch = ctx.sessionManager.getBranch();
		for (let i = branch.length - 1; i >= 0; i--) {
			const entry: any = branch[i];
			if (entry?.type === "message" && entry.message?.role === "user") {
				return oneLine(textOf(entry.message.content));
			}
		}
	} catch {
		// Best effort only.
	}
	return undefined;
}
