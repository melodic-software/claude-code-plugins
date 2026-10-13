---
type: regex
pattern: '^(?![\s\S]*maxRetries)(?=[\s\S]*maxAttempts:\s*number)(?=[\s\S]*backoffJitter:\s*boolean)(?=[\s\S]*maxAttempts:\s*3)(?=[\s\S]*backoffJitter:\s*false)'
target: { source: file, path: src/http/retry.ts }
---
