---
type: regex
pattern: '###\s*Load-bearing assumptions[^\n]*\n(?:(?!#)[^\n]*\n)*?\|[^\n]*(?:semicolon|separator|spreadsheet|import)'
flags: i
target:
  source: file
  path: .work/export-delimiter/PLAN.md
---
