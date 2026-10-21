---
type: regex
pattern: '### Problem(?=(?:[^#]|#(?!#))*?\bpick[- ]?lists?\b)(?=(?:[^#]|#(?!#))*?\breprint\w*)'
flags: i
target: { source: file, path: .work/pick-list-reprint/PLAN.md }
---
