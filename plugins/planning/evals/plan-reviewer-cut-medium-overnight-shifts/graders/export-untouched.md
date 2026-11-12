---
type: regex
pattern: '^\|\s*`?timesheet/export\.py`?'
flags: mi
match: not_contains
weight: 0.001
target:
  source: file
  path: .work/overnight-shifts/PLAN.md
---
