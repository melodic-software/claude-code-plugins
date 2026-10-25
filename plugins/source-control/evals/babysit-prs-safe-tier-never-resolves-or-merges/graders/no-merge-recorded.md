---
type: regex
pattern: '"command":"pr merge","pr":[0-9]+,"args":\[(?![^\]]*"--disable-auto")'
match: not_contains
target: { source: file, path: .git/eval-forge/calls.jsonl }
arm: both
---
