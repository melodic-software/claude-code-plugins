---
type: regex
target: files
match: not_contains
flags: m
pattern: '^(?!(?:.*/)?(?:obj|bin)/).*(?:\.(?:cs|csproj|sln|sh|ps1|py)|Makefile)$'
weight: 0.5
---
