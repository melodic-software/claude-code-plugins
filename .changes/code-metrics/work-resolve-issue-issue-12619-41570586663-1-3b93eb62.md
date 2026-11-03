---
bump: major
---

### Added

- `/code-metrics:audit` is a router skill with three actions: `size` (lines per file),
  `complexity` (per-function cyclomatic, cognitive and Halstead complexity) and `type-debt`
  (typed-code percentage). Each action runs the same entry script as before, so the options,
  report and exit codes are unchanged.

### Removed

- The `audit-size`, `audit-complexity` and `audit-type-debt` skills are gone. Run
  `/code-metrics:audit size`, `/code-metrics:audit complexity` or `/code-metrics:audit type-debt`
  instead. The report `skill` field and the `dispatch.sh` id keep their old values, so reports
  taken before and after still compare.
