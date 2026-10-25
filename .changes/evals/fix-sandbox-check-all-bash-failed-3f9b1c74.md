---
bump: patch
---

### Fixed

- **plugin-eval:** the validity gate's `session started` check also marks a run INVALID when it made 2 or more Bash calls and every one failed. This catches a broken sandbox whatever its error text says, including runs under a read-only `/tmp` where each command runs but reports a failure.
