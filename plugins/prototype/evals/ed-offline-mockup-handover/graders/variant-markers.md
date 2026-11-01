---
type: regex
target: trace
pattern: '"name":"Write","input":\{[^\n]*?data-variant-label=|"name":"Bash","input":\{[^\n]*?(?:<<|printf|\btee\b|>)[^\n]*?data-variant-label='
---
