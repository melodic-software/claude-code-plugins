---
type: regex
pattern: 'blast[ -]radius[^\n]{0,12}?\bMEDIUM\b'
flags: i
target:
  source: file
  path: .work/shipping-zones/PLAN.md
weight: 0.001
---
