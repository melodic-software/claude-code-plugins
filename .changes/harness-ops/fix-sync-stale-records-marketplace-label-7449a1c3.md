---
bump: patch
---

### Fixed

- `/harness-ops:plugins sync`'s stale project records row now names the marketplace it covers (`Stale project records (market1): ...`), since the count is built from that marketplace's install records only and read like a machine-wide count. The row also says how many of the counted records are local-scope and that nothing reaps them yet, and the digest's `stale_project_records` gains a `local` count beside `project`.
