---
type: regex
flags: i
match: not_contains
arm: both
pattern: '(?:transition|animation)(?:-duration)?\s*:[^;{}]*(?<![\d.])(?:(?:3\d[1-9]|3[1-9]\d|[4-9]\d\d|[1-9]\d{3,})ms|(?:0?\.(?:3[1-9]|30[1-9]|[4-9])\d*|[1-9]\d*(?:\.\d+)?)s)(?![\w-])'
---
