---
type: regex
pattern: '^\|\s*`?(?:requirements[\w.-]*\.txt|pyproject\.toml|setup\.cfg|Pipfile)`?\s*\||tabulate'
flags: mi
match: not_contains
weight: 0.001
target:
  source: file
  path: .work/reorder-points/PLAN.md
---
