---
bump: patch
---

### Changed

- **The verify rules sync suite pins verdict lifetimes against the gate.** A new case runs `write-verdict.mjs` `retentionDays` and fails when a FAIL would expire before `babysit_verify_evidence.TOO_OLD_DAYS`, or when a pass lasts anything but its recorded 7 days.
