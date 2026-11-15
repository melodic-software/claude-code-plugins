---
type: regex
flags: i
target: { source: file, path: docs/opening.md }
arm: both
pattern: 'friction\s+kills|lives\s+where'
match: not_contains
---
