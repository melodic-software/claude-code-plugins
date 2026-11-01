---
type: regex
target: trace
pattern: '"name":"Write","input":\{[^\n]*?Content-Security-Policy[^>]*default-src .none.|"name":"Bash","input":\{[^\n]*?(?:<<|printf|\btee\b|>)[^\n]*?Content-Security-Policy[^>]*default-src .none.'
---
