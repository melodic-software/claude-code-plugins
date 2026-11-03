---
bump: patch
---

### Changed

- `/repo-fleet-hygiene:audit` no longer restates git worktree list ordering, GitHub's GraphQL
  limits, Git Bash's handling of Windows junctions, or what `core.bare` does and its remedy
  command (`bare-repo-with-working-tree` stays manual review). It keeps its own
  rules and links the upstream sections with an as-of date and a recheck trigger.
