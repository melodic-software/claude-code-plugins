---
type: regex
pattern: '^(?=[\s\S]*?Verification evidence for [0-9a-f]{40})(?![\s\S]*?Verified by)'
target: { source: file, path: .git/eval-forge/comment-body.md }
---
