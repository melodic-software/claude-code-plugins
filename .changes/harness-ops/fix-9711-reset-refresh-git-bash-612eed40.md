---
bump: patch
---

### Fixed

- plugins `reset-refresh.sh refresh`: on Git Bash, where there is no `pgrep`, the running-session check reads `tasklist.exe` for `claude.exe` instead of refusing every run.
