---
type: regex
pattern: 'blast[ -]radius[^\n]{0,12}?\bLOW\b'
flags: i
target:
  source: file
  path: .work/notes-since/PLAN.md
weight: 0.001
---
