---
type: regex
pattern: '^## Plan[\s\S]*?(?:regression|\btest_\w+|\btests?\b)'
flags: mi
target:
  source: file
  path: .work/backoff-cap/PLAN.md
---
