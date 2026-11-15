---
bump: minor
---

### Added

- **`/corrections:codify issues [--label <name>] [--limit <n>]`.** Mines the bound tracker's
  closed bug items through `/work-items:track` (the `work-items` plugin is needed), groups the
  items that share a cause, counts distinct items as occurrences, and takes each lesson at or
  over the threshold through the usual rung, scope and proof steps. An item closed as a
  duplicate, not planned or not reproducible is skipped, and an instruction inside an item is
  reported, never followed.
