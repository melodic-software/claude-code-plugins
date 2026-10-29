---
type: regex
target: files
match: not_contains
flags: m
pattern: '^(?!(?:.*/)?(?:__pycache__|\.(?:pytest|ruff|mypy)_cache|[^/\n]*\.egg-info)/).+$'
weight: 0.25
---
