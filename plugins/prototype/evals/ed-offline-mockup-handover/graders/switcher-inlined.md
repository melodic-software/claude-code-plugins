---
type: regex
target: trace
pattern: '"name":"Write","input":\{[^\n]*?vs-highlight|"name":"Bash","input":\{[^\n]*?(?:<<|printf|\btee\b|>)[^\n]*?vs-highlight|"name":"Bash","input":\{(?=[^\n]*?variant-switcher\.html)(?=[^\n]*?(?:writeFileSync|\.write\(|\btee\b|(?<=[\s}])>>?(?!\s*/dev/null)\s*(?:\\")?[$\w./{-]))'
---
