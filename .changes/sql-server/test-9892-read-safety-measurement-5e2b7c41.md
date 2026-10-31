---
bump: patch
---

### Added

- `scripts/measure-read-safety.mjs`, which starts a local SQL Server Linux container, measures each read control (lock timeout, request timeout, row cap, pinned isolation, the `@@TRANCOUNT` check) against a concurrent writer and the per-session process topology with 1 to 8 server processes, writes the dated results with the image tag into `reference/read-safety-measurement.md`, and removes the container.
- `reference/read-safety-measurement.md`: the results of the 2026-10-31 run against `mssql/server:2025-CU8-ubuntu-24.04` and the defaults chosen from them, with a unit test that holds each shipped default to that row.

### Changed

- The defaults (30000 ms request timeout, 5000 ms lock timeout, 1000-row cap, `READ COMMITTED`, a pool of 2 closing idle connections after 30 seconds, one process per registration) are no longer provisional: the measurement backs each value.
