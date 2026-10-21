---
type: regex
pattern: '### Goal(?:[^#]|#(?!#))*?\n- Intent \(why, in the user.s words\):[^\n]*re-?keying the weekend.s paper forms'
flags: i
target: { source: file, path: .work/intake-import/PLAN.md }
---
