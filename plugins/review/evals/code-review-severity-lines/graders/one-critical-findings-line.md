---
type: regex
pattern: '^\s*`?critical-findings: \d{1,6}`?\s*$'
flags: m
match: "count:1"
target: last_message
---
