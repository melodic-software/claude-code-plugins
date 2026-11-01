---
type: regex
target: trace
pattern: '"name":"Write","input":\{[^\n]*?manifest\.json[^\n]*?lookAt|"name":"Bash","input":\{[^\n]*?(?:<<|printf|\btee\b|>)[^\n]*?manifest\.json[^\n]*?lookAt|"name":"Bash","input":\{[^\n]*?lookAt[^\n]*?>\s*[^\s]*manifest\.json'
---
