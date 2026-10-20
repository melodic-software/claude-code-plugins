---
type: regex
pattern: '### Captured assumptions(?:[^#]|#(?!#))*?\n- (?:[^\n]*\b(?:handheld|scanners?)\b[^\n]*\(from PRD\)|[^\n]*\(from PRD\)[^\n]*\b(?:handheld|scanners?)\b)'
flags: i
target: { source: file, path: .work/pick-list-reprint/PLAN.md }
---
