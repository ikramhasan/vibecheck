# AGENTS.md

## Code style

- Don't write comments in code. Make the code clear through naming and
  structure instead.
- Follow YAGNI: build only what the current task needs. No speculative options,
  abstractions, extension points or defensive code for cases that can't happen
  yet.

## Reference projects

Third-party projects cloned into `reference/` to study or port from. The whole
folder is gitignored.

```bash
git clone --depth 1 <url> reference/<name>
```

| Project | License | Why it's here |
|---|---|---|
| [agentsview](https://github.com/kenn-io/agentsview) | MIT | Archive, search and cost tracking for ~60 agents. Its per-agent parsers in `internal/parser/` document where each agent stores sessions and what format it uses |

When code is ported from a project here, respect its license and credit it at
the place it's used.

## How sessions are detected

Sessions work with nothing installed. Hooks and extensions are optional extras
for the few things transcripts can't show. Three layers feed one session state:

| Layer | Install | Provides |
|---|---|---|
| Transcript reader | none | prompts, replies, tool calls and results, stop reasons, interrupts, limits, compaction, context usage |
| Live registry | none | which sessions run: pid, cwd, tty, host app (Claude's `~/.claude/sessions/<pid>.json`; a process scan for Codex and pi) |
| Hooks / extensions | opt-in | permission prompts, pi dialogs, exact session end. They write status files per `integrations/core` |

- When a status file and a transcript report the same session, the status file
  wins. Never make a feature depend on hooks if the transcript can provide it.
- The transcript parsers emit one normalized event stream per agent. Status,
  activity, context usage and a future full transcript view all read from it.
  Grow the event model when a feature needs more content; don't add a second
  parser.
- Process scanning uses libproc/sysctl only (no subprocesses) and reads only
  the user's own processes.

## Porting agent session detection from agentsview

- **Source of truth:** `reference/agentsview/internal/parser/<agent>*.go` for
  where sessions live and how to parse them. `internal/parser/termination.go`
  (`Classify`) for the end-of-session rules.
- **Port, don't bundle:** reimplement in Swift as a `SessionSource` in
  `apps/macos/Sources/CompanionCore`. Port only what the panel needs: discovery,
  cwd, model, name, latest prompt, current tool, context usage, and state. Skip archiving,
  search, cost and analytics (CodexBar covers usage).
- **Read incrementally:** remember each file's byte offset and parse only new
  lines. Ignore a trailing partial line until it's complete.
- **Read the tail first:** transcripts reach 30 MB. On first open read only the
  last 1 MB, then follow new lines.
- **State mapping:**
  - Last assistant message ended its turn (Claude `end_turn`, Codex
    `task_complete`, pi `stopReason: "stop"`) → `idle` ("your turn"). Notify on
    the working → idle transition.
  - Pending tool call → `working`, with the tool as activity. If the tool is a
    question tool (Claude `AskUserQuestion`, `ExitPlanMode`, Codex
    `request_user_input`) → `needs_attention`.
  - Last line is a user prompt or tool result → `working`.
  - Interrupt (Claude `[Request interrupted by user]`, Codex `turn_aborted`, pi
    `stopReason: "aborted"`) → `idle`, without a "done" notification.
  - Usage or rate limit (Claude `rate_limit` API error, Codex
    `usage_limit_exceeded`) → `blocked`. Other errors → `error`.
  - Use the agent's stop reason, not the message's content type. Claude writes
    each part of a reply as its own line, and a text part followed by a tool
    call carries `stop_reason: "tool_use"`, not `end_turn`.
- **Known gaps without hooks:** permission prompts aren't written to
  transcripts, so they look like a running tool. pi's extension dialogs aren't
  either. Linking a pi process to its session file is a heuristic (cwd + start
  time), so two pi sessions in one folder can swap.
- **Tests:** add fixture transcripts per agent under
  `apps/macos/Tests/CompanionCoreTests/Fixtures/<agent>/` and test the state
  mapping against them.

## Settle delay before updating state

Agents append several lines in quick succession (one per reply part, then the
tool result). Re-deriving state on every file event makes the panel flicker and
wastes work.

- After a transcript changes, wait **300 ms** with no further writes, then parse
  and update the session.
- If writes keep coming, update anyway at least every **1 s**, so a busy
  session never looks frozen.
- Keep both values as named constants in one place. Raise them only if a
  specific agent needs it, and say why in the commit message.
