---
type: regex
pattern: '###\s*Load-bearing assumptions[^\n]*\n(?:(?!#)[^\n]*\n)*?\|[^\n]*(?:discount_pct|\b100\b|credit|between 0)'
flags: i
target:
  source: file
  path: .work/invoice-discounts/PLAN.md
---
