# vibecheck

A native macOS edge panel that shows live coding-agent sessions.

```
apps/macos/            Swift package: CompanionCore (agent-neutral) + Vibecheck (app)
integrations/core/     Shared session-status contract + reporter used by every integration
integrations/pi/       pi package (extension) that reports pi sessions
```

Data flow: agent integration → `integrations/core` reporter → status file →
`StatusDirectorySource` → `SessionStore` → panel. See `integrations/core/README.md`
to add another agent.

## Build & run

```bash
apps/macos/scripts/bundle.sh                       # build the .app
open apps/macos/build/vibecheck.app                # live data
```

Launch options:

```bash
open apps/macos/build/vibecheck.app --args --demo              # sample sessions
open apps/macos/build/vibecheck.app --args --demo --settings   # also open Settings
```

Without `--demo` the panel shows running Claude Code, Codex and pi sessions by reading their
own session files; nothing needs to be installed. It stays hidden while none are running.
Hover the tab on the right screen edge to expand it; the gear opens Settings and the
power button quits.

If an older build is still running, quit it first so the new one loads:

```bash
pkill -x Vibecheck
```

## Usage stats (CodexBar)

The app bundles the [CodexBar](https://github.com/steipete/CodexBar) CLI (pinned, checksum-verified
by `apps/macos/scripts/fetch-codexbar.sh`) in `Contents/Helpers/`. It supplies the provider list in
Settings and each agent's 5h/weekly limits, reset times and local cost estimate. CLI reference:
`docs/codexbar/cli.md`. Agent icons and brand colours also come from CodexBar (MIT); refresh them with
`apps/macos/scripts/sync-provider-icons.sh`.

In Settings → Agents, add agents and toggle **Status** (running sessions) and **Usage** per agent.
With any usage enabled the tab stays visible even when no agent is running. Usage refreshes every
5 minutes and when the panel opens with stale data. During `swift run`, set
`VIBECHECK_CODEXBAR=/path/to/CodexBarCLI` or have `codexbar` installed via Homebrew.

## pi extension (optional)

pi sessions show up without it. The extension adds what pi's session files don't record:
its confirm/select dialogs (shown as needing attention) and an exact link between the pi
process and its session.

```bash
pi install "$PWD/integrations/pi"     # uninstall: pi remove "$PWD/integrations/pi"
```

## Behaviour

- No live sessions: hidden.
- Sessions running: small tab on the right edge; hover to expand.
- Finished sessions leave the panel on their own after a delay (Settings → Sessions,
  default 5 minutes; paused while the pointer is over the panel). Hover a finished row
  and click × to dismiss it now, or use the check button in the header to clear them
  all. They come back when they finish another turn; working, waiting, blocked and
  failed sessions always stay.
- A session needs attention (question, permission, input): expands by itself and shows
  only the pending questions, with their options, until you've hovered over it or
  clicked "Show all". A new request re-opens it.
- Sounds play when a session needs input (Ping), finishes a turn (Glass), or fails or
  hits a limit (Basso). Settings → Sounds picks any macOS alert sound per event (or
  None), previews it and sets the volume. Each event type plays at most once every
  3 seconds, so several sessions finishing together make one sound.
- Clicking a session selects its exact tab in Terminal or iTerm2 (and its tmux pane);
  other apps are brought forward.

## Tests

```bash
(cd apps/macos && swift test)
node --test integrations/pi/test/*.test.mjs
```
