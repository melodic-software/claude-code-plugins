---
bump: minor
---

### Added

- A git pre-commit entry, `actionlint-check`, that lints the staged `.github/workflows/*.yml` and `*.yaml` files and blocks a commit only on a finding actionlint reports on a line the commit adds, printed as `<path>:<line>: <message>`. A partly staged file, or a staged one since deleted from the work tree, is linted as staged and nothing is rewritten. `/actionlint:setup apply install-git-hooks [scope=local|shared]` registers it with lefthook, husky or plain git hooks, and `check` reports its drift.
- The pre-commit entry refuses a commit while `.github/actionlint.yaml` has an unstaged edit or deletion, naming the file, since actionlint reads the work tree's copy and the commit holds the index's.
- The opt-in `actionlint_end_of_turn` option: when a turn ends, the same check runs over the uncommitted workflow changes and hands its findings back, at most once per turn.
- The SessionStart probe reports a missing, stale or edited git-hook entry once per session.

### Changed

- Workflow findings no longer reach Claude on each edit; the pre-commit entry reports them. The plugin registers no `PostToolUse` or `PostToolBatch` row.
- `jq` is no longer required.

### Removed

- The per-edit `PostToolUse` lint, its missing-actionlint and missing-jq notices on edit (the session-start probe still reports a missing actionlint), and the `SessionStart` row that reset the findings digest.
- The `actionlint_lint_gitignored` and `stdin_read_timeout` options, which only the per-edit hook read.
