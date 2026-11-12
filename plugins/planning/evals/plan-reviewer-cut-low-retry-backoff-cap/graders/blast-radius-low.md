---
type: regex
pattern: 'blast[ -]radius[^\n]{0,12}?\bLOW\b'
flags: i
target:
  source: file
  path: .work/backoff-cap/PLAN.md
weight: 0.001
---
