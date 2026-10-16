---
bump: minor
---

### Added

- A git pre-commit entry, `shell-check`, that formats the staged `.sh` and `.bash` files an `.editorconfig` section governs, re-stages them, refuses a partly staged governed script untouched, and blocks a commit only on a ShellCheck finding (warning and above) on a line the commit adds. `/bash-format:setup apply install-git-hooks [scope=local|shared]` registers it with lefthook, husky or plain git hooks, and `check` reports its drift.
- The opt-in `bash_format_end_of_turn` option: when a turn ends, the ShellCheck half runs over the uncommitted changes, without rewriting, and hands its findings back, at most once per turn.
- The SessionStart probe reports a missing, stale or edited git-hook entry once per session.

### Changed

- The per-edit `PostToolUse` rows are replaced by one `PostToolBatch` row that runs shfmt once over every shell file a batch wrote, where an `.editorconfig` section names shell files, and prints nothing. ShellCheck findings no longer reach Claude on each edit; the pre-commit entry reports them.
- A file under `.githooks/` is never rewritten, and a file that only a `Read` named is never rewritten.
- The batch payload carries no pre-edit bytes, so a file that already drifted from the repository's shfmt style is formatted whole.

### Removed

- The per-edit findings report, the missing-tool notices on edit (the session-start probe still reports them), the rewrite disclosure, and the `SessionStart` row that reset the findings digest.
