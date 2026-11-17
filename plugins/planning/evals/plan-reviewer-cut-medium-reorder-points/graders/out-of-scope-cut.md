---
type: regex
pattern: '(?:^###\s*Phase|^(?<![\s\S]))(?:(?!^#{2,3}\s)[\s\S])*?^\s*(?:[-*]|\d+[.)])\s+(?!\s*(?:\*\*)?(?:drop|drops|dropped|dropping|cut|cuts|remove|removes|removed|exclude|excludes|excluded|out[ -]of[ -]scope)\b|\s*(?:\*\*)?(?:do not|don''t|never|no changes? to|leave|leaves|keep|keeps|without changing)\b[^\n:;]*$|[^\n]*\b(?:dropped|cut|removed|excluded|unchanged|out[ -]of[ -]scope)\s*[.:]?\s*$)[^\n]*(?:weekly_report|weekly report)'
flags: mi
match: not_contains
target:
  source: file
  path: .work/reorder-points/PLAN.md
---
