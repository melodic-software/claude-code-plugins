---
type: regex
pattern: '(?:^|\n)[^\n]{0,6}Q[1-7]:[^\S\n]*\*\*'
match: not_contains
target: last_message
arm: both
---
