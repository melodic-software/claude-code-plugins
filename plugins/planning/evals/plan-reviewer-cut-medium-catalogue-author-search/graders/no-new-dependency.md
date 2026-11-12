---
type: regex
pattern: '^\|\s*`?(?:requirements[\w.-]*\.txt|pyproject\.toml|setup\.cfg|Pipfile)`?\s*\||rapidfuzz|whoosh'
flags: mi
match: not_contains
weight: 0.001
target:
  source: file
  path: .work/author-search/PLAN.md
---
