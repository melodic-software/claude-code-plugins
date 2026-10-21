---
type: regex
pattern: '(?:^|\n)- Variation intent: second variant\s*=\s*`?(?:known|category|speculative)\b'
flags: i
match: not_contains
target: { source: file, path: .work/address-validation/PLAN.md }
---
