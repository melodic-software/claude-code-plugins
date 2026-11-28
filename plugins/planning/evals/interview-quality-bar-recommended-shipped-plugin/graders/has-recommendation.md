---
type: regex
pattern: '(?:^|\n)[^\n]{0,6}(?:\*\*)?My recommendation(?:\*\*)?:[^\S\n]*\S'
flags: i
match: contains
target: last_message
arm: both
---
