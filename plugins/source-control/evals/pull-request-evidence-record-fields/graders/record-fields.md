---
type: regex
pattern: '^(?=[\s\S]*?Verification evidence for [0-9a-f]{40})(?=[\s\S]*?Verified by[^\n]*?Dana Okafor)(?=[\s\S]*?Verified at[^\n]*?\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2})(?=[\s\S]*?Issues found)'
target: { source: file, path: .git/eval-forge/comment-body.md }
---
