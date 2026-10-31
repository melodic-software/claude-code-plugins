---
type: regex
target: trace
pattern: '"name":"Write","input":\{[^\n]*?pressure-test-[A-Za-z0-9]{6}/|"name":"Bash","input":\{[^\n]*?(?:<<|printf|\btee\b|>)[^\n]*?pressure-test-[A-Za-z0-9]{6}/'
---
