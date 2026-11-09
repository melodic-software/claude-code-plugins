---
type: regex
pattern: '^(?![\s\S]*(?:"command":"(?:pr edit|pr comment|push|pr merge|api [A-Z]+)"|"command":"comment edit","pr":512,"args":\["9002"))[\s\S]*"command":"comment edit"'
target: { source: file, path: .git/eval-forge/calls.jsonl }
arm: with-only
---
