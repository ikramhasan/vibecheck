# AGENTS.md

## Code style

- Don't write comments in code. Make the code clear through naming and
  structure instead.
- Follow YAGNI: build only what the current task needs. No speculative options,
  abstractions, extension points or defensive code for cases that can't happen
  yet.

## Never modify agent files

vibecheck only observes agents. Its code must never write, move, rename,
delete, truncate, lock, or change the attributes of any file an agent owns:
transcripts, session registries (`~/.claude/sessions/`, `~/.codex/`, pi's
session folders), settings, logs, or anything else under an agent's data
directories.

- Open agent files read-only (`FileHandle(forReadingFrom:)`, `O_RDONLY`,
  `O_EVTONLY`), and only to read or watch them.
- The app may write only to its own locations: the status directory
  (`~/Library/Application Support/vibecheck/sessions`, or
  `$VIBECHECK_DIR`) and its own preferences.
- Opt-in hooks and extensions may write only status files to that status
  directory. Installing them is the user's choice and is documented, never done
  silently.
- Tests that need to write use temp files or fixtures, never real agent data.

## Reference projects

Third-party projects cloned into `reference/` to study or port from. The whole
folder is gitignored.

```bash
git clone --depth 1 <url> reference/<name>
```

| Project | License | Why it's here |
|---|---|---|
| [agentsview](https://github.com/kenn-io/agentsview) | MIT | Archive, search and cost tracking for ~60 agents. Its per-agent parsers in `internal/parser/` document where each agent stores sessions and what format it uses |
| [thinking-orbs](https://github.com/yogesharc/thinking-orbs) | MIT | The dot-sphere status orbs. `apps/web/registry/orb/orb-core.ts` is ported to `apps/macos/Sources/Vibecheck/Orbs/Orb.swift` |
| [codexbar](https://github.com/steipete/CodexBar) | MIT | Plan usage clients for ~100 providers. `Sources/CodexBarCore/Providers/<Provider>/` is where usage endpoints, credential locations and response shapes come from |

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
  search, cost and analytics.
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

## Plan usage

Usage (5h, weekly, monthly limits) is fetched natively in
`apps/macos/Sources/CompanionCore/Usage/`, one `UsageProvider` per agent, ported from
`reference/codexbar`. There is no CodexBar binary or other helper.

- **Supported now: Claude, Codex and Kiro only.** Settings offers just these three. Other agents
  get usage later, one provider at a time, ported the same way.
- **Read the agent's own sign-in, read-only.** Claude: `~/.claude/.credentials.json` or the
  `Claude Code-credentials` keychain item, read with `/usr/bin/security find-generic-password -w`
  (Claude Code writes the item with that tool, so reading it this way doesn't prompt). Codex:
  `~/.codex/auth.json`. Kiro: kiro-cli's SQLite database, opened with `immutable=1` so no lock or
  journal file is created.
- **Never refresh tokens.** Refresh tokens rotate; redeeming one without writing it back logs the
  agent out. Check the token's expiry first and show "Sign-in expired. Run <agent> to refresh it"
  instead of sending the request.
- **Always try the agent's credential store.** CodexBar only reads Claude Code's keychain item
  behind a default-off setting, so its CLI reported "credentials not found" for signed-in users.
  Don't gate credential reads behind settings or prompts.
- **No placeholder windows.** If the response has no limits, report "No plan limits reported".
  Never invent a 0% window; CodexBar's web source did, and the panel showed 0% for a busy account.
- Decode leniently (unknown fields ignored, one bad entry skipped) and test each provider's mapping
  against trimmed real responses in `UsageTests.swift`.

## Remote machines

`RemoteSessionSource` streams sessions from other machines over one ssh connection running
`RemoteScript`. The Mac side feeds the reported facts into the same discovery functions and
transcript parsers as local sessions; don't parse agent formats in the script.

- The script is read-only, like everything else here. It may read agent files, `/proc` and
  git, and must never write, lock or run anything that can (no `git` commands outside the
  fixed query list, always `GIT_OPTIONAL_LOCKS=0`).
- Every request from the Mac is validated in the script: follows only `.jsonl` files under
  the agents' session folders, git queries only by name with checked arguments, file reads
  only inside the checkout.
- Remote sessions have `host` set and no `pid`; `sshPID` is the local ssh process used to
  jump to them.

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

## Releasing

vibecheck ships through the Homebrew tap
[ikramhasan/homebrew-tap](https://github.com/ikramhasan/homebrew-tap). Users install
with `brew install --cask ikramhasan/tap/vibecheck`. The tap holds the cask
(`Casks/vibecheck.rb`) and the release zips; this repo has no releases of its own.

Pushing a `v*` tag runs `.github/workflows/release.yml`. It builds the app, publishes
the zip as a release of the tap and updates the cask's `version` and `sha256`. Never
edit those two lines in the tap by hand.

The same run signs the zip with the Sparkle key (`SPARKLE_PRIVATE_KEY` secret) and
rewrites `appcast.xml` in the tap, which the app's updater reads. The release notes
and the update dialog both list the commit subjects since the previous tag, without
`docs:`, `chore:`, `ci:` and `test:` commits (`apps/macos/scripts/changelog.sh`). Write
commit subjects with users in mind.

Release only when asked to. Then:

1. Make sure you're on `main`, the working tree is clean and `main` matches `origin/main`.
2. Find the current release: `git fetch --tags` then
   `git describe --tags --abbrev=0 --match 'v*'`. Cross-check it against
   `gh release list -R ikramhasan/homebrew-tap`. If there's no tag yet, the first
   release is `v0.3.0`.
3. Read the commits since that tag (`git log <tag>..HEAD --oneline`) and choose the
   next version with semantic versioning:
   - any breaking change (`!` after the type, or a `BREAKING CHANGE:` footer) → major.
     While the version is `0.x`, bump the minor instead.
   - otherwise any `feat:` → minor
   - otherwise (`fix:`, `perf:`, and so on) → patch
   - only `docs:`, `chore:`, `ci:` or `test:` → nothing user-facing changed; say so and
     ask before releasing anyway.

   Versions only go up. Never reuse, move or delete an existing tag.
4. Tell the user the current version, the proposed one and the commits that justify
   it, and wait for their confirmation. A pushed tag publishes a release to users.
5. `git tag vX.Y.Z && git push origin vX.Y.Z`, then follow the run with
   `gh run watch -R ikramhasan/vibecheck`.
6. Confirm the release exists in the tap and the cask there shows the new `version`.
   If the workflow failed, report the failing step's output. Don't retry by moving or
   re-pushing the tag; fix forward with the next patch version.
