---
type: regex
pattern: '^\s*<!-- evidence-verification -->\s*\n### Verification evidence for [0-9a-f]{40}'
target: { source: file, path: .git/eval-forge/comment-body.md }
arm: with-only
---
