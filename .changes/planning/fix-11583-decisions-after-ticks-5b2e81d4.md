---
bump: patch
---

### Fixed

- `/planning:interview`'s page Brief lists a decision once, in its final status, when its commitments are ticked at Confirm. `export-brief` rewrites a Decisions recap line taken while unticked commitments held the row `open` as `answered`, with the row's whole answer (also when the recap cut that answer short), so the row adds no second Constraints line.
- SKILL.md and the page surface guide now agree that on the page the restate goes out over a procedure-check exit 1 when the only `open` rows are accepted questions waiting on commitment ticks, since the page offers those ticks in the restatement box.
