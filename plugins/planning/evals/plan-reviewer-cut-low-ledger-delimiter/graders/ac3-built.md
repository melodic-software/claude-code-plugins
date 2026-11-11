---
type: regex
pattern: '^###\s*Phase[\s\S]*?^\s*[-*]\s+[^\n]*(?:ValueError|unsupported delimiter|\brefus|\breject|\braise)'
flags: mi
target:
  source: file
  path: .work/export-delimiter/PLAN.md
---
