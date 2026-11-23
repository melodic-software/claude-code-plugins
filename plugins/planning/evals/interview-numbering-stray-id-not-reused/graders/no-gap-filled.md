---
type: regex
pattern: '(?:^|\n)[^\n]{0,6}Q(?:[3-9]|[1-9]\d|[1-5]\d\d):[^\S\n]*\*\*'
match: not_contains
target: last_message
arm: both
---
