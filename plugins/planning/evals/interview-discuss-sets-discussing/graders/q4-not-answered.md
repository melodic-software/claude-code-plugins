---
type: regex
pattern: '(?:^|\n)- Q4 \| `?answered`? \|'
match: not_contains
target: { source: file, path: .work/webhook-retries/interview-checklist.md }
arm: both
---
