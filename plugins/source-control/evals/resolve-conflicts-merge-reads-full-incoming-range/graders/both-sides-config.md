---
type: regex
pattern: '^(?=[\s\S]*max_attempts:\s*5\b)(?=[\s\S]*backoff_seconds:\s*2\b)'
target: { source: file, path: config/retry.yaml }
---
