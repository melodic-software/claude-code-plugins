---
bump: patch
---

### Fixed

- `/verification:confirm`: the per-worker session-names rule now points at `/testing:run-e2e`'s own-driving Session names section, where that rule moved, and says that on a run through `/app-control:drive` the drive skill and the app's control skill own the browser sessions.
