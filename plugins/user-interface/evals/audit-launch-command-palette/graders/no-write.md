---
type: regex
target: trace
match: not_contains
arm: both
pattern: '"name":"(?:Write|Edit|MultiEdit|NotebookEdit)","input":\{|"name":"Skill","input":\{[^}]*?--fix'
---
