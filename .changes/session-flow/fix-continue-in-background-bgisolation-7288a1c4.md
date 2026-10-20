---
bump: patch
---

### Fixed

- `/session-flow:continue-in-background`: the dirty-tree gate reads the effective `worktree.bgIsolation` (managed, local, project, user settings files, in that order; a `--settings` value cannot be read and is reported as not covered). With `none` the background session edits the checkout directly, so the gate launches instead of refusing and the launch report warns that the session edits this checkout in place, alongside the user.
