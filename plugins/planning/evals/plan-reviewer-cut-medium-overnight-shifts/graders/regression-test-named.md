---
type: regex
pattern: '(?:^###\s*Phase|^###\s*Test\s+strateg|^##\s*Plan\b)(?:(?!^#{2,3}\s)[\s\S])*?^\s*(?:[-*]|\d+[.)])\s+(?=[^\n]*(?:regression|\btests?\b|\btest_\w+|\bassert))(?=[^\n]*(?:22:00|overnight|next[ -_]?day|midnight))'
flags: mi
target:
  source: file
  path: .work/overnight-shifts/PLAN.md
---
