---
type: regex
pattern: 'check-open-questions|round\.sh|export-ledger|\bexit (?:code |status )?[0-9]|\bexited (?:with )?[0-9]|\bprocedure=|\bstatus=clean'
flags: i
match: not_contains
target: last_message
arm: both
---
