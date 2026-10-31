---
type: regex
target: trace
match: not_contains
arm: both
pattern: '"name":"Write","input":\{|"name":"Bash","input":\{[^\n]*?(?:<<|printf|\btee\b|>)'
---
