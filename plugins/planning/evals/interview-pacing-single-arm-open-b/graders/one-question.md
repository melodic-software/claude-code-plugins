---
type: regex
pattern: '(?:^|\n)[^\n]{0,6}Q\d+:[^\S\n]*\*\*'
flags: i
match: "count:1"
target: last_message
arm: both
---
