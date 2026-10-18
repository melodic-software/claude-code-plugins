---
bump: patch
---

### Fixed
- The spec-container label fallback in `/work-items:ship` discovery and decompose's container lifecycle now accepts only an item whose body carries the `**Execution shape:**` line; a labelled item without it is skipped and named in the report, and a fetched `#<number>` without it is reported as not a spec container (#7993).
