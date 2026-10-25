---
bump: patch
---

### Fixed

- **plugin-eval:** the validity gate's new `session started` check marks a run INVALID when it ended at 0 turns with no run error, or when its kept trace shows the shell sandbox failing to start. Both had passed as VALID and scored a session that never ran or had no shell. The sandbox notes give the `TMPDIR` workaround and its upstream pointers.
