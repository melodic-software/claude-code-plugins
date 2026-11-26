---
type: regex
pattern: '(?:^|\n)[^\n]{0,6}Q\d+:[^\S\n]*\*\*'
match: not_contains
target: last_message
arm: both
---
