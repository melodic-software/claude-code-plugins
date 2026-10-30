---
bump: patch
---

### Security

- The babysit-loop lane takes its `Lane telemetry: babysit-loop` issue only when the lane's write identity opened it. An exact-title issue another account opened is skipped and named in the cycle report, and with none left the lane creates its own.
