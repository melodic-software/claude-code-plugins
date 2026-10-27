---
bump: patch
---

### Fixed

- The `local-file` findings buffer's `append.sh` takes perl's `flock` on `.work/buffer/.lock` where `flock` is absent and perl calls flock(2) itself, so an appender killed with SIGKILL no longer leaves a lock that fails every later append until an operator removes it. Where neither is available, the `.lockdir` lock stays as before.
