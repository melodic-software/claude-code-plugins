---
bump: patch
---

### Changed

- **Plugin-variable behavior is read from the plugins reference.** `principles` keeps its `<plugin-root>` placeholder rule and points at where each plugin variable resolves instead of restating it, and the report-directory comment in `persist-report.sh` points at that one record.
