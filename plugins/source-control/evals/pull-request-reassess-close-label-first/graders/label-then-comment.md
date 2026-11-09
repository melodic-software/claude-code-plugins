---
type: regex
pattern: '"command":"pr edit","pr":512,"args":\[[^\n]*do-not-merge[^\n]*\n[\s\S]*"command":"pr comment"'
target: { source: file, path: .git/eval-forge/calls.jsonl }
arm: with-only
---
