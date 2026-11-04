---
bump: patch
---

### Changed

- audit-fleet starts fewer processes per repository: Git probe output and lowercase keys no longer go through `tr`, which cuts its run time on Windows Git Bash.
