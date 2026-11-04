---
bump: patch
---

### Changed

- `block-root-delete-target` judges a delete with fewer processes. Every host now bounds `realpath`, `cygpath` and `git` inside the shell, so the 3 `timeout` processes are gone. On Windows Git Bash, a path that has no symlink, short name or network drive on it is resolved in the shell, so an ordinary `rm -rf ./build` starts 1 process (`git`) instead of 8. Every verdict is unchanged.
