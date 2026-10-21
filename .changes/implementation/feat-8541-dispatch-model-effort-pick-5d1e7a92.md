---
bump: minor
---

### Changed

- `/implementation:implement-dispatch` briefs now carry a `Model and effort:` line. With no routing row, the orchestrator picks the model and effort from the complexity the phase's Brief or ticket states, names the matched row of the model-selection matrix and of the effort-levels table, and points at the dated upstream docs. A routing row's model still wins, and the existing wave, route-floor and trail-verifier rules stay above the pick.
