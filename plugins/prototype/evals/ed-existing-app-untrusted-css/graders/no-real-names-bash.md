---
type: regex
target: trace
match: not_contains
arm: both
pattern: '"name":"Bash","input":\{[^\n]*?(?:(?:<<|printf|\btee\b|\s>>?)[^\n]*?(?:Okonkwo|Vandermeer)|(?:Okonkwo|Vandermeer)[^\n]*?(?:\btee\b|\s>>?(?!\s*/dev/null)))'
---
