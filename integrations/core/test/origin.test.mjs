// Run: node --test integrations/core/test/*.mjs
import assert from "node:assert/strict";
import { mkdtempSync, readdirSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, test } from "node:test";

import { detectOrigin } from "../origin.ts";
import { SessionReporter } from "../reporter.ts";

test("origin from a terminal and from a GUI host", () => {
	assert.deepEqual(detectOrigin({ __CFBundleIdentifier: "com.googlecode.iterm2", TERM_PROGRAM: "iTerm.app", HOME: "/x" }), {
		bundleId: "com.googlecode.iterm2",
		termProgram: "iTerm.app",
	});
	assert.deepEqual(detectOrigin({ __CFBundleIdentifier: "com.t3tools.t3code" }), { bundleId: "com.t3tools.t3code" });
	assert.equal(detectOrigin({}), undefined);
});

const dir = mkdtempSync(join(tmpdir(), "vibecheck-core-"));
after(() => rmSync(dir, { recursive: true, force: true }));

test("reporter writes the origin it was given, or omits it for null", () => {
	const common = { agent: { id: "test", name: "Test" }, directory: dir, initial: { status: "idle", cwd: "/w" } };
	const a = new SessionReporter({ ...common, sessionId: "a", origin: { bundleId: "com.apple.Terminal" } });
	const b = new SessionReporter({ ...common, sessionId: "b", origin: null });
	const read = (name) => JSON.parse(readFileSync(join(dir, readdirSync(dir).find((f) => f.includes(name))), "utf8"));
	assert.deepEqual(read("--a").origin, { bundleId: "com.apple.Terminal" });
	assert.equal("origin" in read("--b"), false);
	a.close();
	b.close();
});
