---
bump: patch
---

### Fixed

- **`/work-items:triage` shapes an unstructured bug report without the `bugs` plugin.** It calls `/bugs:write` only when `bugs` is installed; otherwise it shapes the report inline into the same five fields and says once what `bugs` would add.
