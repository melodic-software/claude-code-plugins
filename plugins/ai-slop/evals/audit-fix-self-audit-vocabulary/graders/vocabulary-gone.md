---
type: regex
flags: i
target: { source: file, path: docs/release-note.md }
arm: both
pattern: 'pivotal|delve|leverag|showcas'
match: not_contains
---
