---
bump: patch
---

### Fixed

- `manage` sync step 4 and `setup` check item 4 name `sync-finalize.sh` with no argument. They called it `sync-finalize.sh delete-cache`, but the script takes no arguments and always runs the whole finalize: the Kindle-running check, the version check, the cached-installer delete and the firewall re-enable instructions ([#6609](https://github.com/melodic-software/claude-code-plugins/issues/6609)).

### Added

- Outcome eval cases for the `manage` and `setup` skills and frozen trigger probes for `manage`.
