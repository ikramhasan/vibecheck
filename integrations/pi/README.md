# pi integration

A pi package that reports each interactive pi session to Agent Companion. It maps
pi extension events onto the shared contract in `../core`; it has no file
handling of its own.

| pi event | Companion state |
|---|---|
| `session_start` / `session_shutdown` | session file created / removed |
| `before_agent_start` | `task` (the prompt) |
| `agent_start`, `tool_execution_start` | `working` + `activity` |
| `ui_prompt_start` / `ui_prompt_end` | `needs_attention` (question / permission / input) |
| `agent_end` (error) | `error` |
| `agent_settled` | `idle` |

Reported: interactive terminal sessions (`tui`) and persisted RPC sessions, which is
how GUI hosts such as T3 Code run pi. Skipped: print/JSON runs, `--no-session` RPC
helper runs, and pi-subagents child processes. Set `AGENT_COMPANION_ALL_MODES=1` to
report every mode, or `AGENT_COMPANION_DISABLE=1` to turn reporting off for one run.

## Install / uninstall

This uses pi's standard package commands with a local path:

```bash
pi install /absolute/path/to/AgentCompanion/integrations/pi
pi remove  /absolute/path/to/AgentCompanion/integrations/pi    # or: pi uninstall …
```

`pi list` shows it, and `pi config` can disable it without removing it. Restart
running pi sessions (or run `/reload`) after installing.

## Test

```bash
node --test integrations/pi/test/*.test.mjs
```
