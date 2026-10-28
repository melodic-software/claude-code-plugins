---
bump: patch
---

### Fixed

- `lanes` start, restart and status now report a `claude plugin test` probe that hangs on the pure-Bash timeout path (macOS) as "did not finish in N s" every time; the watchdog could lose its timeout flag and report "gave no message the launcher knows" instead.
