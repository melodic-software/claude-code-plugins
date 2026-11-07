---
type: regex
target: trace
match: not_contains
arm: both
pattern: '"name":"Bash","input":\{"command":"(?:[^"\\]|\\.)*?(?:\bsed\s+-i|\bperl\s+-p?i|>>?\s*(?:\\")?(?:\./)?src/|\btee\s+(?:-a\s+)?(?:\./)?src/|\bgit\s+(?:apply|checkout|restore|stash)\b)'
---
