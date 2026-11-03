---
type: regex
pattern: '^\s+has_more\s*:\s*bool\b'
flags: m
match: not_contains
target: { source: file, path: .work/invoice-totals/design/type-inventory.md }
---
