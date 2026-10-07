# Agent Companion

A native macOS edge panel that shows live coding-agent sessions.

```
apps/macos/            Swift package: CompanionCore (agent-neutral) + AgentCompanion (app)
integrations/core/     Shared session-status contract + reporter used by every integration
integrations/pi/       pi package (extension) that reports pi sessions
```

Data flow: agent integration → `integrations/core` reporter → status file →
`StatusDirectorySource` → `SessionStore` → panel. See `integrations/core/README.md`
to add another agent.

## Build & run

```bash
apps/macos/scripts/bundle.sh                       # build the .app
open apps/macos/build/AgentCompanion.app           # live data
```

Launch options:

```bash
open apps/macos/build/AgentCompanion.app --args --demo              # sample sessions
open apps/macos/build/AgentCompanion.app --args --demo --settings   # also open Settings
```

Without `--demo` the panel stays hidden until an agent reports a session (see pi below).
Hover the tab on the right screen edge to expand it; the gear opens Settings and the
power button quits.

If an older build is still running, quit it first so the new one loads:

```bash
pkill -x AgentCompanion
```

## pi

```bash
pi install "$PWD/integrations/pi"     # uninstall: pi remove "$PWD/integrations/pi"
```

## Behaviour

- No live sessions: hidden.
- Sessions running: small tab on the right edge; hover to expand.
- A session needs attention (question, permission, input): expands by itself and
  stays open until you've hovered over it. A new request re-opens it.

## Tests

```bash
(cd apps/macos && swift test)
node --test integrations/pi/test/*.test.mjs
```
