---
bump: patch
---

### Fixed

- The pre-push full lint of identical scripts in two directories now lints them once on every run. The probe for sourced files fed the script to ShellCheck through a pipe, so a ShellCheck that exited before reading all of it broke the pipe, the probe counted as failed, and each copy was linted separately.
