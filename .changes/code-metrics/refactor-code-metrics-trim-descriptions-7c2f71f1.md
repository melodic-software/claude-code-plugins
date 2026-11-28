---
bump: patch
---

### Changed

- Backfilled invocation probe file (`probes/audit.json`) and trimmed skill frontmatter descriptions (`audit`: 847 -> 339 chars, `audit-coverage`: 474 -> 330 chars, `audit-duplication`: 434 -> 302 chars, `audit-suppressions`: 898 -> 419 chars, `principles`: 415 -> 307 chars, `setup`: 944 -> 147 chars; total 4,012 -> 1,844 chars, saving 2,168 chars) while preserving all modes, directive families, `Not for` sibling exclusions, report-only/no-gate posture, and zero probe TR or FP regressions across all 4 probed skills.
