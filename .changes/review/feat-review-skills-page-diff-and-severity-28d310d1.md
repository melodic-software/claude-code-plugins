---
bump: patch
---

### Fixed

- `/review:code-review` and `/review:security-review` read the file under review (the incremental diff when the wrapper names one, else the full diff) to its last line by paging Read with `offset` and `limit`, and no longer let Grep or Glob stand in for reading a section of it.
- `/review:code-review` writes one `severity: IMPORTANT` or `severity: SUGGESTION` line per inline comment and one `critical-findings: <n>` line in its summary, so the merge gate no longer counts its findings as CRITICAL.
