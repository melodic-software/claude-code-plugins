---
bump: patch
---

### Changed

- `/testing:audit`'s cannot-fail scan runs its per-file rule engine on every core in a whole-tree scan, or on `$CANT_FAIL_SCAN_JOBS` files at a time, then reads the results in scan order, so findings, counts, the coverage block and exit codes are those of a serial run. A `--file` scan, which the edit hooks run, is unchanged. On this repository's 1372 test files a four-job scan takes a third of the serial time (31 s against 93 s).
