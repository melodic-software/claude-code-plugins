---
bump: major
---

### Removed

- `/harness-ops:morning-brief` moved to the work-items plugin: invoke it as `/work-items:morning-brief`. The `az` prerequisite moved with it, and the unused generated copies `lib/view-builder.mjs` and `lib/view-runtime.js` are gone, since only the brief read them.

### Changed

- The lanes skill, its restart-consumer notes and the probes' competitor lists name `/work-items:morning-brief`; the restart-consumer test reads the brief's discovery literals from its new path.
