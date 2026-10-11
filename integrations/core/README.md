# Integration contract

Agent Companion doesn't know about specific agents. Each agent integration writes
one JSON file per live session to:

```
~/Library/Application Support/AgentCompanion/sessions/<agent>--<session>.json
```

(`$AGENT_COMPANION_DIR/sessions` if set.) The format is `session-status.schema.json`.

- Write atomically (temp file + rename). Delete the file when the session ends.
- Include `pid` of the long-lived agent process. The app prunes files whose
  process has exited, so crashes don't leave ghost sessions.
- `status` is `working`, `needs_attention`, `idle`, `blocked` or `error`.
  `needs_attention` expands the panel automatically.
- The app also reads Claude Code, Codex and pi transcripts directly, with nothing
  installed. A status file is only needed for what transcripts can't show
  (permission prompts, dialogs). When both describe the same session (same agent
  id and session id), the status file wins.

## Adding an agent

1. Create `integrations/<agent>/`.
2. Use `reporter.ts` (`SessionReporter`). It handles paths, atomic writes,
   throttling and cleanup. The integration only maps the agent's events to
   `reporter.update({...})`.
3. Optionally add branding in
   `apps/macos/Sources/AgentCompanion/Panel/AgentAppearance.swift`. Unknown
   agents get a generic icon.

The app needs no changes. For agents that run hook *commands* per event
(rather than an in-process extension), the hook script loads the session's state
and writes it with the same reporter. Pass the agent's process id as `pid`.
