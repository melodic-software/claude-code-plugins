---
bump: patch
---

### Fixed

- `fleet:reach` warns that Git Bash rewrites a POSIX path such as `/tmp/x` in a `wsl.exe` argument to a Windows path, and says to write it with a leading `//`.
