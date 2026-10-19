---
type: regex
pattern: '### Constraints(?:[^#]|#(?!#))*?\n- Quality requirement:[^\n]*(?:\b2\s?(?:s|seconds?)\b|\bdown\b|unavailable|\bfails?\b|time\s?out|timeout)'
flags: i
target: { source: file, path: .work/address-validation/PLAN.md }
---
