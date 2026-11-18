---
type: regex
pattern: '^(?=[\s\S]*?Verification evidence for [0-9a-f]{40})(?=[\s\S]*?\n\|\s*Criterion\s*\|\s*Files\s*\|\s*Test or check\s*\|\s*Result\s*\|)(?=(?:[\s\S]*?\n\|\s*The (?:cart|checkout|receipt) page shows the total in currency\s*\|\s*`?src/cart\.ts`?\s*\|){3})'
target: { source: file, path: .git/eval-forge/comment-body.md }
---
