---
bump: patch
---

### Changed

- Synced the shared `exec-bash.mjs` launcher, which gains an opt-in `--fail-closed` flag. This plugin's hooks do not pass it. On Windows, a hook whose Git Bash child is killed by a signal now fails with a line naming the signal (such as SIGSEGV) instead of passing through a raw exit code such as 2816.
