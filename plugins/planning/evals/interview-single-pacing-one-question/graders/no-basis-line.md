---
type: regex
pattern: '(?:^|\n)[^\S\n]{0,4}(?:[^\w\s]{1,2}[^\S\n]*)?(?:\*\*)?(?:Basis|Origin)(?:\*\*)?:'
match: not_contains
target: last_message
arm: both
---
