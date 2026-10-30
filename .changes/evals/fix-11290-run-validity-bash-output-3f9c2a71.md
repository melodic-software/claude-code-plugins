---
bump: patch
---

### Fixed

- **plugin-eval:** the validity gate's `session started` check no longer fails a run whose Bash calls all exited non-zero but printed output, such as `ls` on a missing path. A failed call that printed output ran in a working shell. The check still fails a run whose sandbox failed to start, and a run of 2 or more Bash calls that all failed with no output past their `Exit code N` line. A run under a read-only `/tmp` whose commands still print output now passes this check.
