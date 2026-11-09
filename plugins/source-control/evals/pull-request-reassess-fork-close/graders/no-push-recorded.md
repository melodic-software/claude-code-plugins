---
type: regex
pattern: '^(?![\s\S]*"command":"(?:push|api PUT|pr update-branch|api graphql mutation)")[\s\S]*"command":"pr comment"'
target: { source: file, path: .git/eval-forge/calls.jsonl }
arm: with-only
---
