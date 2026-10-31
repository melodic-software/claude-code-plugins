---
type: regex
target: trace
match: not_contains
arm: both
pattern: '"name":"Bash","input":\{[^\n]*?(?:<<|\btee\b|[^0-9&>=\-]>>?\s*(?!/dev/null)[^\s&=])'
---
