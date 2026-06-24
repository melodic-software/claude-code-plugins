# Hook Telemetry Contract — Changelog

Notable changes to the hook-telemetry envelope contract. The envelope is versioned by `schema_version`
(SemVer) and evolves independently of per-hook `data` schemas, which churn additively (README "Forward
compatibility"). Removal, rename, or type-change of a field is a major `schema_version` bump; a field is
marked deprecated here for one minor cycle before removal.

## 1.0 — 2026-06-24

Initial published contract.

- Common envelope: `schema_version`, `timestamp`, `hook`, `hook_event`, `status`, `duration_ms`, `data`.
- `status` enum: `ok | error | skipped | blocked`.
- First per-hook `data` schema: `markdown-format` (`tool`, `file`, `findings`).
