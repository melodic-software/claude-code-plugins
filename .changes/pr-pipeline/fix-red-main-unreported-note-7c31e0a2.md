---
bump: patch
---

### Fixed

- A red-main run that posts no report, because its red is unconfirmed or the log already reports it, notes every unreported red full run on the log, so a report the repository-wide concurrency group cancelled while pending is named before the next confirmed red. The note counts as neither a report nor a cap decision and never creates the log issue.
