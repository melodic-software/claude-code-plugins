---
type: regex
pattern: '^(?![\s\S]*(?:"command":"(?:pr edit|pr comment|comment edit|push|pr merge|pr review|pr create|pr close|pr update-branch|issue comment|issue edit|resolve thread|api [A-Z]+|api graphql mutation)"|"args":\["pr","ready"))[\s\S]*isInMergeQueue'
target: { source: file, path: .git/eval-forge/calls.jsonl }
arm: with-only
---
