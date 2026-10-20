---
type: regex
pattern: '### Constraints(?:[^#]|#(?!#))*?\n- Quality requirement:[^\n]*300\s?(?:ms\b|milliseconds?)'
flags: i
target: { source: file, path: .work/address-validation/PLAN.md }
---
