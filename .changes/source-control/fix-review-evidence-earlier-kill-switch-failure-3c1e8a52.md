---
bump: patch
---

### Fixed

- **Review evidence and an earlier head's kill-switch failure.** A run on an earlier head whose kill-switch job failed before any lane job existed (a setup error, for one) reviewed nothing, so it no longer unbinds the lane with `no-lane-job`. At the pinned head such a run still unbinds.
