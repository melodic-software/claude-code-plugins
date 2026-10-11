---
type: regex
flags: im
match: not_contains
arm: both
pattern: '^\s+(?:--[\w-]+|[a-z-]+)\s*:\s*[^;{}\n]*(?:#[0-9a-f]{3,8}(?![\w-])|(?<![\w-])(?:rgba?|hsla?)\()'
---
