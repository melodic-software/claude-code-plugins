---
type: regex
pattern: '^(?=[\s\S]*?Verification evidence for [0-9a-f]{40})(?=[\s\S]*?\n\|\s*(?:\*\*)?Before(?:\*\*)?\s*\|)(?=[\s\S]*?\n\|\s*(?:\*\*)?After(?:\*\*)?\s*\|)(?![\s\S]*?<details)'
target: { source: file, path: .git/eval-forge/comment-body.md }
---
