---
type: regex
flags: m
target: { source: file, path: docs/opening.md }
arm: both
pattern: '^(?=[^\n]*6:15)[^\n]*[Ii]nvoice'
match: not_contains
---
