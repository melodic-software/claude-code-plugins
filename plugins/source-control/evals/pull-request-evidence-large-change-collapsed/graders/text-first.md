---
type: regex
pattern: 'Verification evidence for [0-9a-f]{40}\n+(?!\||!\[|<details|<img)[^\n]'
target: { source: file, path: .git/eval-forge/comment-body.md }
---
