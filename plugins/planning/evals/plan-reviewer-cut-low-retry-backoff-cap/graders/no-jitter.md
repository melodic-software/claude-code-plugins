---
type: regex
pattern: 'import random|random\.(?:uniform|random|randint)'
flags: i
match: not_contains
weight: 0.001
target:
  source: file
  path: .work/backoff-cap/PLAN.md
---
