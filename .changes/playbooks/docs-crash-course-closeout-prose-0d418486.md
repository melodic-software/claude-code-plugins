---
bump: patch
---

### Added

- `fable-5`: the recovery chapter adds a wrong-output taxonomy for output that is wrong when no tool call failed. A fact never loaded gets loaded, one loaded but ignored gets fresh context, and one that is stale or a wrong tool result is re-fetched before anything is cleared. The skill body's recovery rules and chapter routing table point at it.
