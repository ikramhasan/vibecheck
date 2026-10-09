/**
 * Which app an agent session is running in, captured from the agent's own
 * environment so the app can bring it forward when the session is clicked.
 * Agent-neutral: every integration gets this for free.
 *
 * Only erasable TypeScript syntax (see reporter.ts).
 */

export interface SessionOrigin {
	/** Bundle id of the app that launched the agent (macOS `__CFBundleIdentifier`). */
	bundleId?: string;
	/** `TERM_PROGRAM`, e.g. "Apple_Terminal", "iTerm.app", "ghostty", "WezTerm", "vscode". */
	termProgram?: string;
}

export function detectOrigin(env: NodeJS.ProcessEnv = process.env): SessionOrigin | undefined {
	const origin: SessionOrigin = {};
	if (env.__CFBundleIdentifier) origin.bundleId = env.__CFBundleIdentifier;
	if (env.TERM_PROGRAM) origin.termProgram = env.TERM_PROGRAM;
	return Object.keys(origin).length ? origin : undefined;
}
