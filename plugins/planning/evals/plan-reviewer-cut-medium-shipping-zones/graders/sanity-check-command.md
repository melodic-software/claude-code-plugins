---
type: regex
pattern: 'Sanity Check[^\n]*\b(?:looks? (?:right|correct|good|fine)|as expected|works (?:correctly|properly))'
flags: i
match: not_contains
target:
  source: file
  path: .work/shipping-zones/PLAN.md
---
