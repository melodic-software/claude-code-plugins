---
type: regex
flags: i
match: not_contains
arm: both
pattern: '(?:transition|animation)(?:-timing-function)?\s*:[^;{}]*(?<![\w-])(?:var\(\s*--)?ease-in(?![\w-])'
---
