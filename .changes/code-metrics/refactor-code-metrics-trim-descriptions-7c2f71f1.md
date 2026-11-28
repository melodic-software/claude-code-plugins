---
bump: patch
---

### Changed

- Backfilled invocation probe file (`probes/audit.json`) and trimmed skill frontmatter descriptions (`audit`: 847 -> 400 chars, `audit-coverage`: 474 -> 336 chars, `audit-duplication`: 434 -> 333 chars, `audit-suppressions`: 898 -> 495 chars, `principles`: 415 -> 307 chars, `setup`: 1,001 -> 147 chars; total 4,069 -> 2,018 chars, saving 2,051 chars) while preserving all modes, report-only/no-gate posture, and probe parity. `audit-suppressions` still names every directive family the scanner reads (pylint, pyright, SuppressMessage, `@SuppressWarnings`, istanbul, coverage.py, bandit), and `audit` and `audit-suppressions` each keep a `Not for` pointer to their confusable neighbor.
