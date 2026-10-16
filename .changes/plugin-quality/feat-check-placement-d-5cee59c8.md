---
bump: patch
---

### Fixed

- `lib/check-retirements.sh` finds and cleans a `.git/` leftover, such as a retired git hook,
  when run from a linked worktree: such a path resolves under `git rev-parse --git-common-dir`.
