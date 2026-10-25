---
bump: patch
---

### Fixed

- `/work-items:work` CI mode states that a required test run the lane could not execute is deferred to PR CI, and any other required check it could not run still makes the lane report the run `stopped`.
