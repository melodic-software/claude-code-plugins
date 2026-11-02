---
bump: patch
---

### Fixed

- On Git Bash, the pre-commit entry now names the approval marker in POSIX form (`/c/...`): Git for Windows prints the git directory as `C:/...`, which the drive-letter conversion missed because it matched only backslashes. The marker and markdown-check test suites also pass on Git Bash now.
