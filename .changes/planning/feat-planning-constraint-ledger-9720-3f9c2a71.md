---
bump: minor
---

### Added

- **`interview` surface:** a `constraint` op records a constraint on the page's own ledger, and the page header lists them under "Constraints (N)". `export-brief` takes Constraints from a confirmed restatement; with none it lists the page's constraints and the `--ledger` file's `## Constraint ledger` rows, instead of printing "none recorded".
