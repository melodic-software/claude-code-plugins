---
type: regex
pattern: '^[ \t]*- C\d+[ \t]*\|[^\n]*\b(?:handheld|scanners?|browser)\b'
flags: mi
match: not_contains
target: { source: file, path: .work/pick-list-reprint/interview-checklist.md }
---
