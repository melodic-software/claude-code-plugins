---
type: regex
target: {source: file, path: AGENTS.md}
pattern: '\bgh\s+(?:repo\s+list|api)\b|\brepo\s+list\b'
match: not_contains
arm: both
---
