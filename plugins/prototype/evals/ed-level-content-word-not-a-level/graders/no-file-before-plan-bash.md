---
type: regex
target: trace
match: not_contains
arm: both
pattern: '"name":"Bash","input":\{[^\n]*?(?:<<|\btee\b|\s>>?\s*(?!/dev/null)[^\s&=>])'
---
