---
type: regex
target: trace
arm: both
pattern: '"name":"Write","input":\{[^\n]*?<meta(?=[^>]*Content-Security-Policy)(?=[^>]*default-src .none.)(?=[^>]*style-src .unsafe-inline.)(?=[^>]*script-src .unsafe-inline.)(?=[^>]*img-src data:)(?=[^>]*font-src data:)|"name":"Bash","input":\{[^\n]*?(?:<<|printf|\btee\b|>)[^\n]*?<meta(?=[^>]*Content-Security-Policy)(?=[^>]*default-src .none.)(?=[^>]*style-src .unsafe-inline.)(?=[^>]*script-src .unsafe-inline.)(?=[^>]*img-src data:)(?=[^>]*font-src data:)'
---
