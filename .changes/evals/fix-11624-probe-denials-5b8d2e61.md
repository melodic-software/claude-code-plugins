---
bump: patch
---

### Fixed

- `run-validity.py` treats a denied tool call in an invocation-probe case as a warning when the call is named, is not the Skill call, and could not have steered the graded decision: it comes after the graded Skill call, or the run is a should-not-fire run that never fired. A denial before the Skill call, or in a should-fire run that missed, still takes the strict rules. The check prints each probe case's fire counts in denied and denial-free runs.
