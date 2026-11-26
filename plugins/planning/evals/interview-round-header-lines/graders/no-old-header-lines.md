---
type: regex
pattern: '(?:^|\n)[^\n]{0,6}(?:Held|Settled by evidence|Decided|Decided so far|Decided earlier|What we have so far)[^\S\n]*:|\bquestions registered\b'
flags: i
match: not_contains
target: last_message
arm: both
---
