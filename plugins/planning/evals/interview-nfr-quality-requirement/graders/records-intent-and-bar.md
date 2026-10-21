---
type: regex
pattern: '^(?=[\s\S]*(?:^|\n)- Quality bar:\s*`?production\b)(?=[\s\S]*(?:^|\n)- Variation intent: second variant\s*=\s*`?speculative\b)'
flags: i
target: { source: file, path: .work/address-validation/PLAN.md }
---
