---
bump: patch
---

### Changed

- pr-merge's `post-merge-dispatch` carries the completed run attempts its post-merge check read from one tick to the next, as `attempts.json` in the `pr-merge-post-merge-report` artifact it already keeps. The check step copies the last trusted run's file (read by `last-report.mjs`) to the path it names in `BABYSIT_POSTMERGE_ATTEMPTS`, and keeps the file the check leaves, whether the check runs or an idle tick reuses the report. On the 2026-10-28 ticks this spares the 8 attempt reads each check made, of the job's 50 to 57 GITHUB_TOKEN calls. The `merge` job's check names no file and reads as before. Permissions are unchanged.
