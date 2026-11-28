---
bump: patch
---

### Changed

- Backfilled invocation probe file (`probes/audit.json`) and trimmed skill frontmatter descriptions (`audit`: 847 -> 349 chars, `audit-coverage`: 474 -> 336 chars, `audit-duplication`: 434 -> 333 chars, `audit-suppressions`: 898 -> 419 chars, `principles`: 415 -> 307 chars, `setup`: 944 -> 147 chars; total 4,012 -> 1,891 chars, saving 2,121 chars) while preserving all modes, directive families, `Not for` sibling exclusions, report-only/no-gate posture, and probe parity.
