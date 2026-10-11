---
type: regex
flags: i
match: not_contains
arm: both
pattern: '(?:transition|animation)(?:-duration)?\s*:(?:[^;{}]*?,)?(?:[^;{},\d.]|(?<=[a-z_-])\d)*(?<![\d.])(?:(?:40[1-9]|4[1-9]\d|[5-9]\d\d|[1-9]\d{3,})ms|(?:0?\.(?:40[1-9]|4[1-9]|[5-9])\d*|[1-9]\d*(?:\.\d+)?)s)(?![\w-])'
---
