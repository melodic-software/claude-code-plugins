---
bump: patch
---

### Changed

- The design skill's copy of the shared door definition (`reference/one-way-doors.md`) rates
  migrations by its own test: one that rewrites, deletes or narrows existing data or structure is a
  one-way door; an additive one is a two-way door while the previous code still runs against the
  new schema; turning a feature off after users wrote data through it is a one-way door; what a
  migration costs to run is not a door question.
