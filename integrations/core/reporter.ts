/**
 * Agent-neutral session reporter.
 *
 * Every agent integration (pi, Claude Code, Codex, …) uses this to publish its
 * session state to the Agent Companion app. Integrations only translate their
 * agent's events into `update()` calls; file layout, atomic writes, throttling
 * and cleanup live here. The on-disk contract is session-status.schema.json.
 *
 * Only erasable TypeScript syntax is used so this runs under jiti and plain
 * `node` (type stripping) alike, with no build step.
 */
import { mkdirSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { detectOrigin, type SessionOrigin } from "./origin.ts";

export type { SessionOrigin } from "./origin.ts";

export const SCHEMA_VERSION = 1;

export type SessionStatus = "working" | "needs_attention" | "idle" | "error";
export type AttentionKind = "question" | "permission" | "input" | "other";

export interface Attention {
	kind: AttentionKind;
	message: string;
}

export interface SessionState {
	status: SessionStatus;
	name?: string;
	cwd: string;
	model?: string;
	task?: string;
	activity?: string;
	attention?: Attention | null;
}

export interface ReporterOptions {
	agent: { id: string; name: string };
	sessionId: string;
	/** PID of the long-lived agent process; defaults to this process. */
	pid?: number;
	initial: SessionState;
	/** Overrides the status directory (tests); otherwise resolved from the environment. */
	directory?: string;
	/** Minimum gap between writes that only change activity text. */
	throttleMs?: number;
	/**
	 * Which app the session runs in, so clicking it can bring that app forward.
	 * Defaults to detecting it from this process's environment, which is right for
	 * in-process extensions and for hook commands the agent spawns (they inherit
	 * its environment). Pass `null` to omit.
	 */
	origin?: SessionOrigin | null;
}

/** Same resolution rules as the app: AGENT_COMPANION_DIR, else Application Support. */
export function statusDirectory(env: NodeJS.ProcessEnv = process.env): string {
	const base = env.AGENT_COMPANION_DIR || join(homedir(), "Library", "Application Support", "AgentCompanion");
	return join(base, "sessions");
}

function safeSegment(value: string): string {
	return value.replace(/[^A-Za-z0-9._-]/g, "_").slice(0, 120);
}

/** Collapse whitespace and cap length so the panel gets clean one-liners. */
export function oneLine(text: string | undefined, max = 160): string | undefined {
	if (!text) return undefined;
	const flat = text.replace(/\s+/g, " ").trim();
	if (!flat) return undefined;
	return flat.length > max ? `${flat.slice(0, max - 1)}…` : flat;
}

export class SessionReporter {
	readonly file: string;
	private readonly dir: string;
	private readonly agent: { id: string; name: string };
	private readonly sessionId: string;
	private readonly pid: number;
	private readonly startedAt = new Date().toISOString();
	private readonly origin: SessionOrigin | undefined;
	private readonly throttleMs: number;
	private state: SessionState;
	private lastWrite = 0;
	private pending: ReturnType<typeof setTimeout> | undefined;
	private closed = false;
	private readonly onExit = () => this.close();

	constructor(options: ReporterOptions) {
		this.agent = options.agent;
		this.sessionId = options.sessionId;
		this.pid = options.pid ?? process.pid;
		this.state = { ...options.initial };
		this.throttleMs = options.throttleMs ?? 150;
		this.dir = options.directory ?? statusDirectory();
		this.origin = options.origin === null ? undefined : (options.origin ?? detectOrigin());
		this.file = join(this.dir, `${safeSegment(this.agent.id)}--${safeSegment(this.sessionId)}.json`);
		// Best effort if the host never runs its shutdown hook.
		process.once("exit", this.onExit);
		this.flush();
	}

	get current(): Readonly<SessionState> {
		return this.state;
	}

	/**
	 * Merge a partial state. Status/attention changes are written immediately so
	 * the panel reacts at once; activity-only churn is coalesced.
	 */
	update(patch: Partial<SessionState>): void {
		if (this.closed) return;
		const urgent =
			(patch.status !== undefined && patch.status !== this.state.status) ||
			(patch.attention !== undefined &&
				JSON.stringify(patch.attention) !== JSON.stringify(this.state.attention ?? null));
		this.state = { ...this.state, ...patch };
		if (urgent || Date.now() - this.lastWrite >= this.throttleMs) {
			this.flush();
		} else if (!this.pending) {
			this.pending = setTimeout(() => this.flush(), this.throttleMs);
			this.pending.unref?.();
		}
	}

	/** Remove the session file. Idempotent. */
	close(): void {
		if (this.closed) return;
		this.closed = true;
		if (this.pending) clearTimeout(this.pending);
		this.pending = undefined;
		process.removeListener("exit", this.onExit);
		try {
			rmSync(this.file, { force: true });
		} catch {
			// The app also prunes files whose pid is gone.
		}
	}

	private flush(): void {
		if (this.pending) clearTimeout(this.pending);
		this.pending = undefined;
		if (this.closed) return;
		const s = this.state;
		const doc = {
			schemaVersion: SCHEMA_VERSION,
			agent: this.agent,
			session: { id: this.sessionId, cwd: s.cwd, name: s.name, model: s.model },
			pid: this.pid,
			origin: this.origin,
			status: s.status,
			task: s.task,
			activity: s.activity,
			attention: s.attention ?? null,
			startedAt: this.startedAt,
			updatedAt: new Date().toISOString(),
		};
		try {
			mkdirSync(this.dir, { recursive: true });
			// Write-then-rename so the app never reads a partial file.
			const tmp = `${this.file}.${process.pid}.tmp`;
			writeFileSync(tmp, JSON.stringify(doc));
			renameSync(tmp, this.file);
			this.lastWrite = Date.now();
		} catch {
			// Never let status reporting break the agent.
		}
	}
}
