---
type: regex
pattern: '^\s*[-*]\s+(?![^\n]*\b(?:out[ -]of[ -]scope|not|no|never|without|leave|leaves|unchanged|drop\w*|cut|remov\w*|exclud\w*)\b)[^\n]*(?:fahrenheit|unit\s*=|°F)'
flags: mi
match: not_contains
target:
  source: file
  path: .work/temp-decimals/PLAN.md
---
