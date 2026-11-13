---
type: regex
pattern: '^\s*`?severity: CRITICAL`?\s*$'
flags: m
match: not_contains
target: last_message
---
