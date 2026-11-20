---
bump: minor
---

### Added

- `/mutation-testing:audit --full` accepts the target-scope contract's forms (`--repo`,
  `--repos-from`, `--owner`, `--fleet`, `--skip`, or the same request in words) and runs once per
  repository. Each repository's mutants run in a throwaway worktree of `origin/HEAD`, never in its
  main checkout. Survivor triage stays in a fresh context, the per-file rows from every repository
  rank on one oracle-gap scale, and each repository's findings file goes to its own memory root.
  The diff scope, `--exercised`, `--paths`, `--phase` and record and replay stay single-repository
  and refuse a target form. With no target form, the audit behaves as before.
- The plugin ships `reference/target-scope.md`, a generated copy of the target-scope contract.
