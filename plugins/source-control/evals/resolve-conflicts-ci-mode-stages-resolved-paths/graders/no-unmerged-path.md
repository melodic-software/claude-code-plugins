---
type: regex
pattern: '[\x10\x20\x30]\x0ddocs/retry\.md\x00|[\x10\x20\x30]\x11src/http/retry\.ts\x00'
match: not_contains
target: { source: file, path: .git/index }
---
