---
bump: minor
---

### Added

- `/instruction-placement:audit`, `delta`, `check` and `realign` accept the target-scope forms
  (`--repo`, `--repos-from`, `--owner`, `--fleet`, `--skip`). The audit keeps one findings
  artifact per repository, in that repository's worktree on the branch
  `instruction-placement/realign`, and reports a section several repositories' always-loaded files
  repeat as a report-only row naming the machine layer or the standards repository as a single
  home. `delta` keeps one baseline per repository in that worktree, `check` gates each other
  repository's `origin/HEAD` in a throwaway worktree and exits non-zero when any one fails, and `realign` applies one repository's findings at a time,
  leaving its changes for that repository's own pull request. With no target form, each skill
  behaves as before.
- The plugin ships `reference/target-scope.md`, a generated copy of the shared target-scope
  contract.
