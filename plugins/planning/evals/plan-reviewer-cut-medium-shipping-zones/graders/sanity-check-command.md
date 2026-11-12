---
type: regex
pattern: '^\s*\*{0,2}Sanity Check:?\*{0,2}:?[^\n]*\b(?:looks? (?:right|correct|good|fine)|as expected|works (?:correctly|properly))'
flags: mi
match: not_contains
target:
  source: file
  path: .work/shipping-zones/PLAN.md
---
