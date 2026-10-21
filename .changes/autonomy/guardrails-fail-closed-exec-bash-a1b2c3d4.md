---
bump: patch
---

### Changed

- Synced the shared `exec-bash.mjs` launcher, which gains an opt-in `--fail-closed` flag. This plugin's hooks do not pass it, so their behavior is unchanged.
