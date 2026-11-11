---
type: regex
pattern: '^###\s*Phase[\s\S]*?^\s*[-*]\s+[^\n]*(?:\bdigest)'
flags: mi
target:
  source: file
  path: .work/quiet-hours/PLAN.md
---
