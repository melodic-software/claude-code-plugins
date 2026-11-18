---
type: regex
pattern: '^(?=[\s\S]*?Verification evidence for [0-9a-f]{40})(?=[\s\S]*?<details)(?=[\s\S]*?\n(?:\*\*)?Before\b)(?=[\s\S]*?\n(?:\*\*)?After\b)'
target: { source: file, path: .git/eval-forge/comment-body.md }
---
