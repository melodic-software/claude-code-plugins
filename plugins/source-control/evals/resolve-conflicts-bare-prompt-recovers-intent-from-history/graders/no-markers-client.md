---
type: regex
pattern: '^(?:<{7}|={7}|>{7})'
flags: m
match: not_contains
target: { source: file, path: api/client.py }
---
