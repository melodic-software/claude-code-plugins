---
bump: minor
---

### Added

- `/toolchain:lint` and `/toolchain:check` run an ecosystem record's `lint-cmd` (ecosystem-commands 1.4.0), the report-only lint command, in place of `check-cmd` when it is set, so they run the same lint verb as the format and lint plugins' git hooks. `/toolchain:setup` reports `lint-cmd` and is the one writer of `fix-cmd` and `lint-cmd`.
