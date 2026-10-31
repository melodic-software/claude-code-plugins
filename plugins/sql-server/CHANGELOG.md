# Changelog

All notable changes to the `sql-server` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.1.0] - 2026-10-31

### Added

- The `sql-server` plugin, off by default: the versioned config schema `schemas/config.v1.schema.json` (JSON Schema draft 2020-12) and its loader, which refuses a `--config` path inside the project directory, an unknown `schemaVersion`, an unknown property and a literal password or connection string, with credentials named by environment variable.
- The single-statement reject list (`src/statement.mjs`), a heuristic control per ADR 0086: it accepts one `SELECT`, optionally led by `WITH`, refuses every other statement kind plus `INTO`, a user `OPTION (...)`, `OPENROWSET`, `OPENQUERY`, `OPENDATASOURCE` and the lock-holding table hints, and reads tokens, so keywords in comments, string literals and bracketed identifiers do not count.
- Unit tests for both, run with `npm test` in the plugin directory and by CI's test-node lane. The README's control table marks the read-only principal as the guarantee.
