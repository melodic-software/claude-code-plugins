---
type: regex
pattern: '^(?=[\s\S]*\bdeliver what was accepted,?[ \t]+at that scope\b)(?=[\s\S]*\bproject(?:''|’)?s own instructions still govern\b)'
flags: i
target: last_message
arm: with-only
---
