---
type: regex
flags: i
match: not_contains
arm: both
pattern: '(?:transition|animation)(?:-duration)?\s*:(?:[^;{}]*?,)?(?:[^;{},\d.]|(?<=[a-z_-])\d)*(?<![\d.])(?:(?:25[1-9]|2[6-9]\d|[3-9]\d\d|[1-9]\d{3,})ms|(?:0?\.(?:25[1-9]|2[6-9]|[3-9])\d*|[1-9]\d*(?:\.\d+)?)s)(?![\w-])'
---
