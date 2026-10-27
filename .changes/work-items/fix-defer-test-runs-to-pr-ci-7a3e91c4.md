---
bump: patch
---

### Fixed

- `/work-items:work` CI mode files a test run the lane could not execute in `not_done` as left to the PR's CI with `"required": false`, so the run no longer stops for a suite the PR's CI runs. A test that ran and failed, and any other required check the run could not run, still make the lane report the run `stopped`.
