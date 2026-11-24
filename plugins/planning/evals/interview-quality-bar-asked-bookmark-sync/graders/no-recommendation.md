---
type: regex
pattern: '(?:^|\n)[^\n]{0,6}(?:\*\*)?My recommendation(?:\*\*)?:'
flags: i
match: not_contains
target: last_message
arm: both
---
