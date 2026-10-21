---
bump: patch
---

### Fixed

- `video-digest`'s repository clone no longer survives a SIGINT or SIGTERM that reaches the harvester between starting the clone and tracking it: the parent's handlers are installed before the clone is spawned.
