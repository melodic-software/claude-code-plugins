---
bump: patch
---

### Fixed

- `/harness-ops:plugins` no longer trusts the cwd to pick the project-scope record when sibling worktrees hold a record of the same id. `converge` Step 4 now checks that the intended record moved and reports a misfire as its own row. `sync` reads a project or local version only from the `currentProject` record, and reports an update that moved another record as a failed row.
