---
type: regex
pattern: '^\W*surface: \S[^\n]*\(default\)\. Also available: [^\n]+$'
flags: m
match: "count:1"
target: last_message
arm: with-only
---
