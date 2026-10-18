---
bump: minor
---

### Fixed

- `/code-metrics:audit-suppressions`: the frozen count can now match the report. The bundled `suppression-scan.py` takes `--exclude <glob>` (repeatable) and `--exclude-from <file>`, so a caller passes the resolved paths and its `scope.exclude` globs and `--count` skips the same files the report does. Without them the output is unchanged. The skill's "Freezing the count" section shows how.
