---
type: regex
target: trace
pattern: '"name":"Write","input":\{(?=[^\n]*?[>"''`]\s*Seed\b)(?=[^\n]*?[>"''`]\s*Clear\b)[^\n]*?[>"''`]\s*Reset\b|"name":"Bash","input":\{(?=[^\n]*?(?:<<|printf|\btee\b|>))(?=[^\n]*?[>"''`]\s*Seed\b)(?=[^\n]*?[>"''`]\s*Clear\b)[^\n]*?[>"''`]\s*Reset\b'
---
