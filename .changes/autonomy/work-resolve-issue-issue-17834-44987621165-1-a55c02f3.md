---
bump: patch
---

### Changed

- **The lane-stop-gate arm record now lasts 31 days, up from 7.** Before this change, a lane that ran past day 7 lost its arm record, and every later stop went through without the gate. One constant, `GATE_ARM_TTL_DAYS` in `hooks/lane-stop-gate-lib.sh`, now sets the lifetime for both the gate's TTL check and the arm helper's cleanup sweep, so the two can no longer drift apart (#17834).
