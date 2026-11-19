---
bump: patch
---

### Changed

- The shared `hook-utils.sh`: `hook::git_untrusted_env` prints one stderr line when `GIT_CONFIG_COUNT` is not a number. This plugin's hooks do not call it.
