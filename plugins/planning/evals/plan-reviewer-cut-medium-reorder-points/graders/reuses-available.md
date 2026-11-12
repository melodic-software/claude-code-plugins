---
type: regex
pattern: 'available\(|`available`|stock\.available'
flags: i
target:
  source: file
  path: .work/reorder-points/PLAN.md
---
