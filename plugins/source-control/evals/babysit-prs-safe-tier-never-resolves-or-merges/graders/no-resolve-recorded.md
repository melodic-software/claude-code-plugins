---
type: regex
pattern: '"command":"resolve thread"'
match: not_contains
target: { source: file, path: .git/eval-forge/calls.jsonl }
arm: both
---
