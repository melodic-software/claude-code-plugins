---
type: regex
target: trace
match: not_contains
arm: both
pattern: '"name":"(?:Edit|MultiEdit|NotebookEdit)","input":\{|"name":"Skill","input":\{[^\n]*?--fix'
---
