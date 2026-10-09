---
bump: minor
---

### Added

- **`/harness-ops:behavior-probes` ([#6645](https://github.com/melodic-software/claude-code-plugins/issues/6645)).** A live probe harness for Claude Code platform behavior. Each case is a directory (`settings.json`, `prompt.md`, `expect.json`, optional `scaffold.sh`) grouped by area; a stdlib runner launches `claude -p --output-format stream-json` per case in a temp directory with the case's settings and permission mode, reads the target call's outcome from the stream, and reports pass, fail or inconclusive stamped with the Claude Code version. Every negative case names a positive control, and a negative case whose control did not pass is inconclusive. `--dry-run` replaces `claude` with a fake and costs nothing; `--live` is opt-in and capped per case and per suite. The first 18 cases cover auto-mode classifier denials, narrow allow rules, ask rules under `-p` (main agent and subagent), project versus `--settings` `autoMode` rules, `$defaults`, a PreToolUse allow hook, `EnterWorktree` placement, the concurrent-subagent cap and the sandbox network allowlist; their outcomes are recorded in the skill's `records.md`.

### Changed

- `/harness-ops:changelog` `apply` Phase 5 lists the behavior-probe cases whose tags match an item in the applied range, and offers a live rerun of them.
