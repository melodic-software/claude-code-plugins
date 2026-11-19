---
type: regex
pattern: '"args":\["pr","ready"[^\n]*\n[\s\S]*"command":"pr comment","pr":655,'
target: { source: file, path: .git/eval-forge/calls.jsonl }
arm: with-only
---
