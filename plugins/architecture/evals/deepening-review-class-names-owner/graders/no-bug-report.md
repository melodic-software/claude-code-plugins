---
type: regex
pattern: '\bsteps to reproduce\b|\brepro(duction)? steps\b|\bexpected\b[^\n]{0,80}\bactual\b'
flags: i
match: not_contains
target: last_message
---
