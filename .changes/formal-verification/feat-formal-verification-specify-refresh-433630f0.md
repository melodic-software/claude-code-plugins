---
bump: minor
---

### Added

- `/formal-verification:specify refresh` brings each `formal-<area>` check back in line with code changed since its sync commit and ends it `in sync`, `updated`, `bug` or `blocked`. It runs each check unchanged, reads and classifies every covered change, updates the verification from the code in a throwaway worktree, and reruns it with a seeded break. A property changes only on a person's yes; a replayed bug goes to `/bugs:write` and `/work-items:track add`. It commits the verification alone, on a ticket branch or through one upkeep pull request, and an unattended run writes only for a check that ends `in sync` or `updated` with its seeded break caught. `--convert <skill-dir>` turns a verification skill outside the contract into a `formal-<area>` skill, attended only.

### Changed

- The contract check's stale-coverage line now ends `run /formal-verification:specify refresh`, so a pull request that touches a covered path is told which check is stale and what refreshes it.
