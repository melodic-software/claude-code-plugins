---
type: regex
flags: i
target: { source: file, path: docs/cache.md }
arm: both
pattern: 'in\s+order\s+to|worth\s+noting|due\s+to\s+the\s+fact'
match: not_contains
---
