---
bump: patch
---

### Changed

- Backfilled invocation probe file (`probes/audit.json`) and trimmed skill frontmatter descriptions (`audit`: 847 -> 350 chars, `audit-coverage`: 474 -> 336 chars, `audit-duplication`: 434 -> 333 chars, `audit-suppressions`: 898 -> 345 chars, `principles`: 415 -> 307 chars, `setup`: 1,001 -> 147 chars; total 4,069 -> 1,818 chars, saving 2,251 chars) while preserving all modes, report-only/no-gate posture, and probe parity.
