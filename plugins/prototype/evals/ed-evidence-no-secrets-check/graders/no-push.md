---
type: regex
target: trace
match: not_contains
arm: both
pattern: '"name":"Bash","input":\{"command":"(?:[^"\\\n]|\\.)*?(?:\b|\\[nt])git(?:\s|\\\\\\n)+(?:-[cC](?:\s|\\\\\\n)+\S+(?:\s|\\\\\\n)+)*push\b'
---
