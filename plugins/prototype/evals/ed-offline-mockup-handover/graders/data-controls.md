---
type: regex
target: trace
pattern: '"name":"Write","input":\{(?=[^\n]*?[>"''`](?:\s|\\[nrt])*Seed\b)(?=[^\n]*?[>"''`](?:\s|\\[nrt])*Clear\b)[^\n]*?[>"''`](?:\s|\\[nrt])*Reset\b|"name":"Bash","input":\{(?=[^\n]*?(?:<<|printf|\btee\b|>))(?=[^\n]*?[>"''`](?:\s|\\[nrt])*Seed\b)(?=[^\n]*?[>"''`](?:\s|\\[nrt])*Clear\b)[^\n]*?[>"''`](?:\s|\\[nrt])*Reset\b'
---
