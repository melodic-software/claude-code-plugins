---
type: regex
pattern: '(?:^###\s*Phase|^(?<![\s\S]))(?:(?!^#{2,3}\s)[\s\S])*?^\s*(?:[-*]|\d+[.)])\s+(?![^\n]*\b(?:out[ -]of[ -]scope|not|no|never|without|leave|leaves|unchanged|drop\w*|cut|remov\w*|exclude|excluded|excludes|excluding\w*)\b)[^\n]*(?:weekly_report|weekly report)'
flags: mi
match: not_contains
target:
  source: file
  path: .work/reorder-points/PLAN.md
---
