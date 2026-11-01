---
type: regex
target: trace
match: not_contains
arm: both
pattern: '"name":"Bash","input":\{[^\n]*?(?:(?:<<|printf|\btee\b|\s>>?)[^\n]*?(?:analytics\.example)|(?:analytics\.example)[^\n]*?(?:\btee\b|\s>>?(?!\s*/dev/null)))'
---
