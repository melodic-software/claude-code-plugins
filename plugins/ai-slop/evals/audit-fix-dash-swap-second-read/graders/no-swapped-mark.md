---
type: regex
flags: i
target: { source: file, path: docs/upgrade.md }
arm: both
pattern: '(?:changed the most|got stricter|is safer|was renamed|fail loudly)\s*(?:[:—–(]|-\s)'
match: not_contains
---
