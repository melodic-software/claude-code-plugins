---
type: regex
flags: i
target: { source: file, path: docs/paging.md }
arm: both
pattern: 'short version\s*[:;\u2014\u2013-]'
match: not_contains
---
