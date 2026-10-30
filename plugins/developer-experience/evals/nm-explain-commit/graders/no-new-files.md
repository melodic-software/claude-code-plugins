---
type: regex
target: files
match: not_contains
flags: m
pattern: '^(?!(?:.*/)?(?:obj|bin)/).+$'
weight: 0.25
---
