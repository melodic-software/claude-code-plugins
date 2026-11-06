---
bump: patch
---

### Changed

- The read-safety measurement (`scripts/measure-read-safety.mjs`) attributes every waiting task in its topology runs to a waiter and a blocker (agent, writer, same session, or an unidentified owner), records whether the blocker was itself waiting and the wait class, counts table-level locks agent sessions hold, takes `--runs <n>` (default 3), runs on SQL Server 2025 CU10, and ends with the worst case and a bounded-blocking check. The README states the read path's guarantee as bounded blocking with its preconditions, names `READ_COMMITTED_SNAPSHOT` and its costs as the consumer-side option, and drops the unmeasured paused-consumer caveat, since the server reads rows itself (#5940).
