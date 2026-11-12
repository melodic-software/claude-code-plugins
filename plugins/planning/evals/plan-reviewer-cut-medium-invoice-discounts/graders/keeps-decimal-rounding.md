---
type: regex
pattern: '\bfloat\(|round\([^)\n]*,\s*2\s*\)'
flags: i
match: not_contains
weight: 0.001
target:
  source: file
  path: .work/invoice-discounts/PLAN.md
---
