---
type: regex
pattern: '"command":"read","pr":[0-9]+,"args":\["(?:pr|search|api)"'
target: { source: file, path: .git/eval-forge/calls.jsonl }
arm: with-only
---
