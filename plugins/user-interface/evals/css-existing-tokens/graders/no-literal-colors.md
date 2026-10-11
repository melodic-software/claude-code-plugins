---
type: regex
flags: i
match: not_contains
arm: both
pattern: '(?<![\w-])(?!(?:-webkit-)?mask)[a-z][a-z-]*\s*:\s*[^;{}\n]*(?:#[0-9a-f]{3,8}(?![\w-])|(?<![\w-])(?:oklch|rgba?|hsla?)\()'
---
