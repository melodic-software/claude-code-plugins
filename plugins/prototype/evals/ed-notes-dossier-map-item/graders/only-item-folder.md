---
type: regex
target: { source: file, path: received.txt }
match: not_contains
arm: both
flags: m
pattern: '^file (?!42-parcel-card-layout/|41-return-reasons/|README\.md$|CONTRIBUTING\.md$|\.gitignore$|scripts/check-secrets\.sh$)'
---
