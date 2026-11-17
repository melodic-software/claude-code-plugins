---
bump: minor
---

### Added

- `/toolchain:lint` and `/toolchain:check` run an ecosystem record's `lint-cmd` (ecosystem-commands 1.5.0), the report-only lint command, in place of `check-cmd` when it is set. No hook runs a record's command; these skills run it on request. `/toolchain:setup` reports `lint-cmd` and is the one writer of `fix-cmd` and `lint-cmd`.
