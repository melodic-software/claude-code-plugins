# Changelog

All notable changes to the `sql-server` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.3.2] - 2026-10-31

### Added

- `scripts/measure-read-safety.mjs`, which starts a local SQL Server Linux container, measures each read control (lock timeout, request timeout, row cap, pinned isolation, the `@@TRANCOUNT` check) against a concurrent writer and the per-session process topology with 1 to 8 server processes, writes the dated results with the image tag into `reference/read-safety-measurement.md`, and removes the container.
- `reference/read-safety-measurement.md`: the results of the 2026-10-31 run against `mssql/server:2025-CU8-ubuntu-24.04` and the defaults chosen from them, with a unit test that holds each shipped default to that row.

### Changed

- The defaults (30000 ms request timeout, 5000 ms lock timeout, 1000-row cap, `READ COMMITTED`, a pool of 2 closing idle connections after 30 seconds, one process per registration) are no longer provisional: the measurement backs each value.

## [0.3.1] - 2026-10-31

### Added

- An integration test of the read path, `node plugins/sql-server/integration/read-path.mjs`. It starts a local SQL Server 2022 container (Developer edition) with a read-only login and a second database, runs the stdio server on a registration confined to one database, and prints one PASS or FAIL line for each of #5940's S1/S2, S5, S6 and S7. S1/S2 passes when every write, DDL and session-state attempt is refused on each round and the data is unchanged. A write the reject list lets through, or one sent straight to the server, must meet the login's permission refusal. S5 passes when the second database cannot be reached, S6 when no password appears in the plugin, config or registration files, and S7 when `tools/list` never changes. Without Docker it prints `SKIP: docker not available` and exits 0.

## [0.3.0] - 2026-10-31

### Added

- The database executor (`src/executor.mjs`): every `query`, `list_objects` and `describe_object` call now runs on SQL Server through `tedious` 20.3.8, which `package.json` declares with `@azure/identity` 4.14.1. Each call opens with one batch of `IF @@TRANCOUNT > 0 ROLLBACK`, `SET IMPLICIT_TRANSACTIONS OFF`, `SET XACT_ABORT ON`, `READ COMMITTED` and `SET LOCK_TIMEOUT`, runs its statement in autocommit, then checks `@@TRANCOUNT` and closes the connection when it is above 0.
- A client-side request timeout and a streaming row cap, each of which cancels the request. A capped result returns the rows it kept with `truncated: true`. The connection is closed after a timeout, a cancel, an error or a capped result. The defaults (30000 ms, 5000 ms lock timeout, 1000 rows) stay provisional until measured.
- The plugin's own pool: at most two connections, idle ones closed after 30 seconds and one the server has ended never reused, each session named `sql-server-plugin (agent session)`. A `server` of the form `host\INSTANCE` connects to that named instance. `sql-login` reads its user and password from the named environment variables; `entra-default` uses a `DefaultAzureCredential` through `tedious`'s `token-credential` type.
- `package-lock.json`, which pins every package under `tedious` and `@azure/identity` with its integrity hash, and a Dependabot `npm` entry for the plugin. A plugin root with a lockfile also gets Claude Code's automatic dependency install each time the plugin is cached.
- Unit tests that drive the executor through a fake `tedious` connection, with no database and no installed dependencies.

### Changed

- A tool call that passes its checks no longer returns the "no database executor" tool error.

## [0.2.0] - 2026-10-31

### Added

- The stdio MCP server (`node src/launch.mjs --config <path> --environment <name>`), bound to one environment and its database allow-list. It exposes exactly three tools, `query`, `list_objects` and `describe_object`, declares `tools` with `listChanged` false and returns the same list on every `tools/list`. A `database` outside the allow-list is refused before the executor runs, an omitted `database` takes the first allowed one, and a statement the reject list refuses comes back as a tool error. The server answers both the stateless 2026-07-28 protocol (`server/discover`, per-request `_meta`) and the `initialize`-based 2025-11-25 protocol.
- This release has no database executor yet: every tool call that passes its checks returns a tool error saying so. Unit tests drive the server through a fake executor.

## [0.1.0] - 2026-10-31

### Added

- The `sql-server` plugin, off by default: the versioned config schema `schemas/config.v1.schema.json` (JSON Schema draft 2020-12) and its loader, which refuses a `--config` path inside the project directory, an unknown `schemaVersion`, an unknown property and a literal password or connection string, with credentials named by environment variable.
- The single-statement reject list (`src/statement.mjs`), a heuristic control per ADR 0086: it accepts one `SELECT`, optionally led by `WITH`, refuses every other statement kind plus `INTO`, a user `OPTION (...)`, `OPENROWSET`, `OPENQUERY`, `OPENDATASOURCE` and the lock-holding table hints, and reads tokens, so keywords in comments, string literals and bracketed identifiers do not count.
- Unit tests for both, run with `npm test` in the plugin directory and by CI's test-node lane. The README's control table marks the read-only principal as the guarantee.
