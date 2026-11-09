---
type: regex
pattern: '"command":"pr comment"'
match: 'count:1'
target: { source: file, path: .git/eval-forge/calls.jsonl }
arm: with-only
---
