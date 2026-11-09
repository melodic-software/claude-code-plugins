---
type: regex
pattern: '^(?![\s\S]*(?:"command":"(?:pr edit|pr comment|push|pr merge|pr review|pr create|pr close|pr update-branch|issue comment|issue edit|resolve thread|api [A-Z]+|api graphql mutation)"|"args":\["pr","ready"|"command":"comment edit","pr":512,"args":\["9002"))[\s\S]*"command":"comment edit"'
target: { source: file, path: .git/eval-forge/calls.jsonl }
arm: with-only
---
