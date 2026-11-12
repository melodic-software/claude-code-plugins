---
type: regex
pattern: '^\s*[-*]\s*B\d+:\s*(?:Edit|Update|Modify|Change|Add)\b'
flags: mi
match: not_contains
target:
  source: file
  path: .work/post-permalink/PLAN.md
---
