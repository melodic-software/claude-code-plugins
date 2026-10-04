---
type: regex
pattern: '^(?![\s\S]*max_retries)(?=[\s\S]*max_attempts)(?=[\s\S]*backoff_jitter)'
target: { source: file, path: README.md }
---
