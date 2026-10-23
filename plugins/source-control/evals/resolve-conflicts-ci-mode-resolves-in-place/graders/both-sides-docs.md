---
type: regex
pattern: '^(?![\s\S]*maxRetries)(?=[\s\S]*transient failures)(?=[\s\S]*`maxAttempts`)(?=[\s\S]*`backoffJitter`)(?=[\s\S]*## Jitter)'
target: { source: file, path: docs/retry.md }
---
