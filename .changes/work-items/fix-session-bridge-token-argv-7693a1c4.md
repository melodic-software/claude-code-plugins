---
bump: patch
---

### Fixed

- Shared `watch.sh` synced: the control token reaches curl on stdin (`-H @-`), so it is in no process's argv.
- Shared `session_bridge.py` synced: on Windows the control server refuses address reuse and binds with `SO_EXCLUSIVEADDRUSE`.
