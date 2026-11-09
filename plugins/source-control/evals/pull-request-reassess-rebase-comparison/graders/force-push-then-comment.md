---
type: regex
pattern: '^(?![\s\S]*"ref":"refs/heads/fix/retry-limit"[\s\S]*"ref":"refs/heads/fix/retry-limit")[\s\S]*"command":"push","ref":"refs/heads/fix/retry-limit","sha":"[0-9a-f]+","forced":true[\s\S]*"command":"pr comment"'
target: { source: file, path: .git/eval-forge/calls.jsonl }
arm: with-only
---
