---
bump: minor
---

### Added

- The database executor (`src/executor.mjs`): every `query`, `list_objects` and `describe_object` call now runs on SQL Server through `tedious` 20.3.8, which `package.json` declares with `@azure/identity` 4.14.1. Each call opens with one batch of `IF @@TRANCOUNT > 0 ROLLBACK`, `SET IMPLICIT_TRANSACTIONS OFF`, `SET XACT_ABORT ON`, `READ COMMITTED` and `SET LOCK_TIMEOUT`, runs its statement in autocommit, then checks `@@TRANCOUNT` and closes the connection when it is above 0.
- A client-side request timeout and a streaming row cap, each of which cancels the request. A capped result returns the rows it kept with `truncated: true`. The connection is closed after a timeout, a cancel, an error or a capped result. The defaults (30000 ms, 5000 ms lock timeout, 1000 rows) stay provisional until measured.
- The plugin's own pool: at most two connections, idle ones closed after 30 seconds and one the server has ended never reused, each session named `sql-server-plugin (agent session)`. A `server` of the form `host\INSTANCE` connects to that named instance. `sql-login` reads its user and password from the named environment variables; `entra-default` uses a `DefaultAzureCredential` through `tedious`'s `token-credential` type.
- Unit tests that drive the executor through a fake `tedious` connection, with no database and no installed dependencies.

### Changed

- A tool call that passes its checks no longer returns the "no database executor" tool error.
