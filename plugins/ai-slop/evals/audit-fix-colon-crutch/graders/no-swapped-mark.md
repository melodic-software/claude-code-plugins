---
type: regex
flags: m
target: { source: file, path: docs/paging.md }
arm: both
pattern: '^(?=[^\n]*(?:short version|three (?:times|retries)))[^\n]*(?:[;—–]| - )'
match: not_contains
---
