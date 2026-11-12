---
type: regex
pattern: '^###\s*Phase(?:(?!^#{2,3}\s)[\s\S])*?^\s*(?:[-*]|\d+[.)])\s+[^\n]*(?:ValueError|unsupported delimiter|\brefus|\breject|\braise)'
flags: mi
target:
  source: file
  path: .work/export-delimiter/PLAN.md
---
