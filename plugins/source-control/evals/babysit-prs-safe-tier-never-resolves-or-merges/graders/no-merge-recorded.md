---
type: regex
pattern: '^(?![\s\S]*"command":"pr merge","pr":[0-9]+,"args":\[(?![^\]]*"--disable-auto"))[\s\S]*?"command":'
target: { source: file, path: .git/eval-forge/calls.jsonl }
arm: with-only
---
