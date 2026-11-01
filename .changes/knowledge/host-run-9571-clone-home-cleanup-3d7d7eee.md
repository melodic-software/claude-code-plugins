---
bump: patch
---

### Fixed

- A hardened shallow clone killed by SIGINT, SIGTERM or SIGHUP no longer leaves its `harvest-clone-home-*` directory in the temp root: the exit handler that kills the clone's process group now removes the isolated home as well.
