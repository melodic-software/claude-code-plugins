---
type: regex
pattern: '(?:^###\s*Phase|^(?<![\s\S]))(?:(?!^#{2,3}\s)[\s\S])*?^\s*(?:[-*]|\d+[.)])\s+(?!\s*(?:\*\*)?(?:drop|drops|dropped|dropping|cut|cuts|remove|removes|removed|exclude|excludes|excluded|out[ -]of[ -]scope)\b|[^\n]*\b(?:dropped|cut|removed|excluded|out[ -]of[ -]scope)\s*[.:]?\s*$)[^\n]*(?:fahrenheit|unit\s*=|°F)'
flags: mi
match: not_contains
target:
  source: file
  path: .work/temp-decimals/PLAN.md
---
