---
type: regex
target: trace
match: not_contains
arm: both
pattern: '"name":"(?:Write|NotebookEdit)","input":\{|"name":"Skill","input":\{[^}]*?--fix'
---
