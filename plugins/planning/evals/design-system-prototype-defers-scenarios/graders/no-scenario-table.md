---
type: regex
target: { source: file, path: .work/order-notifications/design/design-threads.md }
flags: mi
match: not_contains
pattern: '^(?=[^\n]*\|)(?=[^\n]*\bstimulus\b)(?=[^\n]*\benvironment\b)(?=[^\n]*\bmeasure\b)[^\n]+$'
---
