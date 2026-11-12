---
type: regex
pattern: '###\s*Load-bearing assumptions[^\n]*\n(?:(?!#)[^\n]*\n)*?\|[^\n]*(?:ISO|8601|YYYY|created|mobile|date format)'
flags: i
target:
  source: file
  path: .work/notes-since/PLAN.md
---
