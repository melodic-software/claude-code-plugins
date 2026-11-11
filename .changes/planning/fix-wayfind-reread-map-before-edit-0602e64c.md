---
bump: patch
---

### Fixed

- `/planning:wayfind` work: every edit to the map body (Decisions-so-far, Out-of-scope, Not-yet-specified, superseded lines) is applied to a copy of the body read right before the write, so two sessions graduating items on one map no longer overwrite each other's index lines.
