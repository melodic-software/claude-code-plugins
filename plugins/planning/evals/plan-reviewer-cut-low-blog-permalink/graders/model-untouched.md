---
type: regex
pattern: '^\|\s*`?blog/models\.py`?\s*\|\s*(?:modify|create|edit)'
flags: mi
match: not_contains
weight: 0.001
target:
  source: file
  path: .work/post-permalink/PLAN.md
---
