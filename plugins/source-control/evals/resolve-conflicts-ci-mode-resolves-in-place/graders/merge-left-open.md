---
type: regex
pattern: 'commit \(merge\)'
match: not_contains
target: { source: file, path: .git/logs/HEAD }
---
