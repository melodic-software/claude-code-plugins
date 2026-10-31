---
type: regex
pattern: '^(?![\s\S]*"command":"resolve thread")[\s\S]*?"command":'
target: { source: file, path: .git/eval-forge/calls.jsonl }
arm: with-only
---
