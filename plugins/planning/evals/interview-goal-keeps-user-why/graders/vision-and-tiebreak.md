---
type: regex
pattern: '### Goal(?=(?:[^#]|#(?!#))*?\n- Vision \(where this heads\):[^\n]*\bqueue\b)(?=(?:[^#]|#(?!#))*?\n- When goals conflict, prefer:\s*`?none stated\b)'
flags: i
target: { source: file, path: .work/intake-import/PLAN.md }
---
