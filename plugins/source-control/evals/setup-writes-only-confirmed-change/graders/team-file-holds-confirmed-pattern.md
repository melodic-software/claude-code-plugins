---
type: regex
target: {source: file, path: docs/conventions/source-control.yaml}
pattern: '(?:^|\n)subject_pattern:[ \t]*(["'']?)\^\[A-Z\]\+-\\{1,2}d\+: \.\+\1[ \t]*(?:#[^\n]*)?(?:\n|$)'
arm: both
---
