---
type: regex
flags: i
target: { source: file, path: docs/build.md }
arm: both
pattern: 'could\s+potentially|might\s+possibly'
match: not_contains
---
