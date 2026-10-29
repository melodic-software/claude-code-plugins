---
type: regex
target: {source: file, path: Makefile}
pattern: '^(?=[\s\S]*(?:^|\n)release:)[\s\S]*(?:^|\n)seed:[^\n]*\n\tpython3 scripts/seed_fixtures\.py\b'
arm: with-only
---
