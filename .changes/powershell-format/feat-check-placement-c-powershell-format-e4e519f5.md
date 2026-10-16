---
bump: minor
---

### Added

- A git pre-commit entry, `powershell-check`, that formats the staged PowerShell files with Invoke-Formatter, re-stages them, refuses a partly staged file untouched, and blocks a commit only on a PSScriptAnalyzer finding on a line the commit adds. A staged file since deleted from the work tree is analyzed from the index, never rewritten or recreated. `/powershell-format:setup apply install-git-hooks [scope=local|shared]` registers it with lefthook, husky or plain git hooks, and `check` reports its drift.
- The opt-in `powershell_format_end_of_turn` option: when a turn ends, the same check runs over the uncommitted changes, without rewriting, and hands its findings back, at most once per turn.
- The SessionStart probe reports a missing, stale or edited git-hook entry once per session.
- A settings file that declares `CustomRulePath` is approved per content under the repository's git common directory (`powershell-format/trust-approvals`), one store for the end-of-turn row, an agent's commit and a person's. The approval store is no longer `CLAUDE_PLUGIN_DATA`, so an approval made there before this release must be made again.

### Changed

- The per-edit `PostToolUse` rows are gone and no `PostToolBatch` row replaces them: one Invoke-Formatter run measured over the 1 s per-batch ceiling, so PowerShell is rewritten at pre-commit only. Findings no longer reach Claude on each edit; the pre-commit entry reports them.
- A file under `.githooks/` is never rewritten.
- `powershell_format_enabled` now gates only the end-of-turn check and the session-start probe.

### Removed

- The per-edit findings report, the rewrite disclosure, the trust-gate notice on edit, and the `SessionStart` row that reset the findings digest.
- `jq` as a prerequisite: nothing the plugin runs uses it any more, so the session-start probe and `/powershell-format:check` no longer report it.
- The `powershell_format_lint_gitignored` option: nothing runs on edit, and the pre-commit entry only sees tracked and untracked-but-not-ignored files.
