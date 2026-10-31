---
type: regex
target: trace
match: not_contains
arm: both
pattern: '"name":"Bash","input":\{[^\n]*?(?:(?:<<|printf|\btee\b|[^0-9&]>)[^\n]*?(?:analytics\.example)|(?:analytics\.example)[^\n]*?(?:\btee\b|[^0-9&]>(?!\s*/dev/null)))'
---
