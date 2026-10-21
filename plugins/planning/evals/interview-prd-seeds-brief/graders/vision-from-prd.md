---
type: regex
pattern: '### Goal(?:[^#]|#(?!#))*?\n- Vision \(where this heads\):[^\n]*\b(?:floor tasks?|devices?)\b'
flags: i
target: { source: file, path: .work/pick-list-reprint/PLAN.md }
---
