---
bump: minor
---

### Added

- **`/session-flow:audit-sessions sweep-only`, a consumer mode for skills that read the sweep as data.** It runs no collect and writes nothing, sweeps the existing store with `--format json`, and returns the envelope verbatim. The envelope's `schema` (`audit-sessions.sweep/v1`), its additive-within-v1 rule and the exit codes are documented in the skill's store-layout reference.
- The audit-sessions description routes whole-process speed sweeps to `/performance:go-faster`; every existing trigger phrase stays.

### Changed

- `sweep.py` exits 3, not 2, when no store exists under the data directory, so a consumer can tell "never collected here" from a broken store. Exit 3 writes nothing.
