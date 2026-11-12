---
type: regex
pattern: 'blast[ -]radius[^\n]{0,12}?\bLOW\b'
flags: i
target:
  source: file
  path: .work/post-permalink/PLAN.md
weight: 0.001
---
