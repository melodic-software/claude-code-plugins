---
bump: patch
---

### Changed

- The read-safety measurement (`scripts/measure-read-safety.mjs`) attributes every waiting task in its topology runs to a waiter and a blocker (agent, writer, same session, or an unidentified owner) by wait class, takes `--runs <n>` (default 3), and ends with a bounded-blocking check. The README states the read path's guarantee as bounded blocking and drops the unmeasured paused-consumer caveat, since the server reads rows itself (#5940).
