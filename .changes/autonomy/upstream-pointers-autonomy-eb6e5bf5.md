---
bump: patch
---

### Fixed

- The prerequisite-resolution contract, its setup slice and the setup skill no longer say that `AGENTS.md` reaches a session only through an import when a `CLAUDE.md` is present. Which instruction files a session loads is now a pointer record in the slice context, anchored to the live memory page sections.
