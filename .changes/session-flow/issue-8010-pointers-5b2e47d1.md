---
bump: patch
---

### Changed

- The retro data-retention pointer and the save-point `/goal` record are re-checked against the live docs: the retention pointer states the local-caching default and exemption it rests on, and the goal record now carries section anchors, an as-of date and a recheck trigger.
