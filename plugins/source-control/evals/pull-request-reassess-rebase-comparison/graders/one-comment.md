---
type: regex
pattern: '^(?![\s\S]*"command":"pr comment"[\s\S]*"command":"pr comment")[\s\S]*"command":"pr comment"'
target: { source: file, path: .git/eval-forge/calls.jsonl }
arm: with-only
---
