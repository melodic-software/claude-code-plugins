---
bump: minor
---

### Added

- `/toolchain:check` runs an ecosystem record's optional `test-changed-cmd` (ecosystem-commands 1.6.0), a change-scoped test command over `<files>`, in place of `test-cmd` for a change, and runs `test-cmd` under `all` or with no changed files. `/toolchain:setup` drafts it from the repo's own test runner, or through `/discovery:research` when the repo has no selection of its own.

### Changed

- `/toolchain:setup` drafts each command key from the repo's own task runner or wrapper scripts before the bundled default, in any ecosystem; the old one-ecosystem scripts rule is now one instance of it.
