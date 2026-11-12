---
type: regex
pattern: '^\|\s*`?(?:requirements[\w.-]*\.txt|pyproject\.toml|setup\.cfg|Pipfile)`?\s*\|'
flags: mi
match: not_contains
weight: 0.001
target:
  source: file
  path: .work/export-delimiter/PLAN.md
---
