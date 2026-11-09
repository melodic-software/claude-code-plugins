---
type: regex
pattern: '^(?![\s\S]*(?:"command":"(?:pr edit|pr comment|comment edit|push|pr merge|pr review|pr create|resolve thread|api [A-Z]+)"|"args":\["pr","ready"))[\s\S]*isInMergeQueue'
target: { source: file, path: .git/eval-forge/calls.jsonl }
arm: with-only
---
