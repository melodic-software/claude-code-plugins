---
type: regex
target: trace
pattern: '"name":"Write","input":\{[^\n]*?explore-directions-[A-Za-z0-9]{6}/|"name":"Bash","input":\{[^\n]*?(?:<<|printf|\btee\b|>)[^\n]*?explore-directions-[A-Za-z0-9]{6}/'
---
