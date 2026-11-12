---
type: regex
pattern: 'blast[ -]radius[^\n]{0,12}?\bLOW\b'
flags: i
target:
  source: file
  path: .work/export-delimiter/PLAN.md
weight: 0.001
---
