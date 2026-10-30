---
bump: patch
---

### Security

- The work-loop and attend-queue lanes take their `Lane telemetry: <lane>` issue only when the lane's write identity opened it. An exact-title issue another account opened is skipped and named in the lane's report, and with none left the lane creates its own.
