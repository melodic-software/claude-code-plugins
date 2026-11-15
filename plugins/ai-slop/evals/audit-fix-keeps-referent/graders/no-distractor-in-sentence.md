---
type: regex
flags: m
target: { source: file, path: docs/opening.md }
arm: both
pattern: '^(?=(?:(?!\n\n)[\s\S])*6:15)(?:(?!\n\n)[\s\S])*[Ii]nvoice'
match: not_contains
---
