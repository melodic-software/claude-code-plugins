---
type: regex
pattern: '^###\s*Phase[\s\S]*?^\s*[-*]\s+[^\n]*(?:\brender|-15%|percentage)'
flags: mi
target:
  source: file
  path: .work/invoice-discounts/PLAN.md
---
