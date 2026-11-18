---
bump: patch
---

### Changed

- The shared `hook-utils.sh` adds `hook::git_untrusted_env`, which passes the overrides `hook::git_untrusted` uses to a child process through `GIT_CONFIG_COUNT`, appended after any pairs the caller set. Both read one override list. This plugin's hooks do not call it.
