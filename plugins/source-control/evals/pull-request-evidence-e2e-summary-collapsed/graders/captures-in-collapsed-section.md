---
type: regex
pattern: '^(?=[\s\S]*?Verification evidence for [0-9a-f]{40})(?=[\s\S]*?<details(?:(?!</details>)[\s\S])*?!\[)(?![\s\S]*?\n\|\s*(?:\*\*)?Before(?:\*\*)?\s*\|)'
target: { source: file, path: .git/eval-forge/comment-body.md }
---
