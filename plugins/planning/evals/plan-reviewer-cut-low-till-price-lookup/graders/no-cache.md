---
type: regex
pattern: 'lru_cache|functools\.cache|@cache\b'
flags: i
match: not_contains
weight: 0.001
target:
  source: file
  path: .work/price-lookup/PLAN.md
---
