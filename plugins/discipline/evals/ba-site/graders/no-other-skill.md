---
type: regex
pattern: '"name":"Skill","input":\{[^\n]*?"skill":"(?!(?:discipline:)?be-ambitious")'
match: not_contains
target: trace
arm: both
---
