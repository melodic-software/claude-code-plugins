---
bump: patch
---

### Changed

- `/verification:confirm` runs the project's own build, test and lint commands when the `toolchain` plugin is not enabled, and its report names `claude plugin enable toolchain`, preceded by `claude plugin install toolchain` when it is not installed.
