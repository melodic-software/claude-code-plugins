---
bump: patch
---

### Changed

- the lane-binding checker takes an optional store of settled lane runs

  `laneChecker` accepts a `store` that answers a finished run whose every
  attempt left a complete record without reading that run again. A stored
  run binds only a comment its records list; any other comment reads the run
  live. Callers that pass no store behave as before.
