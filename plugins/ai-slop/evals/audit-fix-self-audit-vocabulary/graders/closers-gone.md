---
type: regex
flags: i
target: { source: file, path: docs/release-note.md }
arm: both
pattern: 'hope this helps|future looks bright'
match: not_contains
---
