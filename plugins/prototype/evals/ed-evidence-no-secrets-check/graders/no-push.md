---
type: regex
target: trace
match: not_contains
arm: both
pattern: '"name":"Bash","input":\{"command":"(?:[^"\\\n]|\\.)*?\bgit\s+(?:-[cC]\s+\S+\s+)*push\b'
---
