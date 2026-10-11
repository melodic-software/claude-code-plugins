---
type: regex
pattern: '^(?![\s\S]*legacy_token)(?=[\s\S]*region)'
target: { source: file, path: api/client.py }
---
