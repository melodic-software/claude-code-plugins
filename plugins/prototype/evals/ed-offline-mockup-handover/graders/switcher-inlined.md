---
type: regex
target: trace
pattern: '"name":"Write","input":\{[^\n]*?vs-highlight|"name":"Bash","input":\{[^\n]*?(?:<<|printf|\btee\b|>)[^\n]*?vs-highlight|"name":"Bash","input":\{(?=[^\n]*?variant-switcher\.html)(?=[^\n]*?(?:writeFileSync|(?<!std(?:out|err))\.write\(|write_text\(|\bsed\s+-i\b|\btee\b|(?<=[\s}])>>?(?!\s*(?:/dev/null|\d))\s*(?:\\")?[$\w./{-]))'
---
