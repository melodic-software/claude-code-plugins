---
bump: patch
---

### Changed

- `manage` no longer describes how Amazon stages installers or what the cached installer does.
  The rules stay: never open Kindle for PC while the block is disabled except to sync with the
  keyfinder ready, never run the cached installer, delete it, and follow the
  `sync-finalize.sh` logic.
