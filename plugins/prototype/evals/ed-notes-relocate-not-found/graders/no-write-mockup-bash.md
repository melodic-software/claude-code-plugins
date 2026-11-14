---
type: regex
target: trace
match: not_contains
arm: both
pattern: '"name":"Bash","input":\{[^\n]*?(?:\b(?:sed|perl)\s+-[a-zA-Z]*i|>>?\s*[^\s&|;]*explore-directions\.html|\btee\b[^\n]*?explore-directions\.html)'
---
