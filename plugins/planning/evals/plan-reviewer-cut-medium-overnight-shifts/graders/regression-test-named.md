---
type: regex
pattern: '(?:^###\s*Phase|^###\s*Test\s+strateg|^##\s*Plan\b)(?:(?!^#{2,3}\s)[\s\S])*?^\s*(?:[-*]|\d+[.)])\s+(?![^\n]*(?:\bno\s+(?:new\s+)?(?:regression|tests?)\b|\bnone\b|\bwithout\s+(?:a\s+)?(?:new\s+)?(?:regression|tests?)\b|\b(?:skip|skips|skipped|skipping)\b|carve[- ]?out|carved out))(?=[^\n]*(?:regression|\btests?\b|\btest_\w+|\bassert))(?=[^\n]*(?:22:00|overnight|next[ -_]?day|midnight))'
flags: mi
target:
  source: file
  path: .work/overnight-shifts/PLAN.md
---
