---
type: regex
pattern: '###\s*Load-bearing assumptions[^\n]*\n(?:(?!#)[^\n]*\n)*?\|[^\n]*(?:noon|12:00|midday|overnight|night)'
flags: i
target:
  source: file
  path: .work/overnight-shifts/PLAN.md
---
