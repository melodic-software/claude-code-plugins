---
type: regex
pattern: '(?:^|\n)[^\n]{0,6}No recommendation:[^\S\n]*\S[^\n]*\n(?:[^\S\n]*\n)?[^\n]{0,6}Your answer settles:[^\S\n]*\S'
target: last_message
arm: both
---
