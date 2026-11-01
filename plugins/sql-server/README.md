# sql-server

Read-only access to SQL Server-family databases (a local SQL Server container, Azure SQL Database)
for agents. The design is [ADR 0086](../../docs/adr/0086-bound-the-sql-server-read-tier-by-a-read-only-principal-and-fixed-registrations.md).

This release ships the versioned config schema, its loader, the single-statement reject list, the
stdio MCP server with its three tools, and the executor that runs each call on SQL Server through
`tedious`. The setup skill comes in a later release, so the plugin is off by default.

## The server

One process serves one registration over stdio:

```bash
node plugins/sql-server/src/launch.mjs --config <path> --environment <name>
```

`--environment` picks one environment from the config: one server and its database allow-list.
Every registration exposes the same three tools, and `tools/list` returns the same list every
time. The `tools` capability declares `listChanged` false.

| Tool | Arguments | Returns |
|---|---|---|
| `query` | `sql` (one `SELECT`, optionally led by `WITH`), `database` | The rows |
| `list_objects` | `database`, `schema` | Schemas, tables and views |
| `describe_object` | `name`, `schema`, `database` | Columns, keys and indexes |

`database` is optional and defaults to the first database in the allow-list. A name outside the
list is refused before any connection opens. No argument names a server or an environment, so
reaching another environment takes another registration. A refusal, whether it comes from the
allow-list, an unknown argument or the reject list, comes back as a tool error (`isError: true`)
with the reason.

The server answers the stateless 2026-07-28 MCP protocol (`server/discover` and per-request
`_meta`) and the `initialize`-based 2025-11-25 protocol.

## What keeps a registration read-only

The read-only database principal you create is the guarantee. A registration on a login that can
write is not read-only, whatever the reject list does. A **guarantee** holds whatever SQL the agent
sends; a **heuristic** holds only until the agent's SQL undoes or evades it.

| Control | Label | In this release |
|---|---|---|
| Read-only principal (a login or Entra identity with read grants only) | guarantee | You create it |
| Request timeout | guarantee | `src/executor.mjs` |
| Streaming row cap with prompt cancel | guarantee | `src/executor.mjs` |
| Transaction check after each call (`@@TRANCOUNT` above 0 discards the connection) | guarantee | `src/executor.mjs` |
| Rollback guard before each call (`IF @@TRANCOUNT > 0 ROLLBACK`) | guarantee | `src/executor.mjs` |
| Discard the connection after a timeout, cancel or error | guarantee | `src/executor.mjs` |
| `SET XACT_ABORT ON` per call | heuristic | `src/executor.mjs` |
| Pinned isolation (`READ COMMITTED`) per call | heuristic | `src/executor.mjs` |
| `SET LOCK_TIMEOUT` per call | heuristic | `src/executor.mjs` |
| Single-statement reject list | heuristic | `src/statement.mjs` |

### The executor

Each call takes a connection from the plugin's own pool and runs, in order:

1. One batch: `IF @@TRANCOUNT > 0 ROLLBACK`, `SET IMPLICIT_TRANSACTIONS OFF`, `SET XACT_ABORT ON`,
   `SET TRANSACTION ISOLATION LEVEL READ COMMITTED` and `SET LOCK_TIMEOUT <lockTimeoutMs>`. It runs
   as a plain batch, because SQL Server restores a `SET` made inside `sp_executesql` when that
   batch returns.
2. The statement, in autocommit: no transaction is opened around it.
3. `SELECT @@TRANCOUNT`. Above 0, the connection is closed, never reused.

A timer of `requestTimeoutMs` starts once the call has a connection, covers the batch, the
statement and the check, and cancels the running request when it fires.
The row cap counts rows as they stream: the first row past `rowCap` cancels the request, and the
call returns the rows it kept with `truncated: true`. After a timeout, a cancel, an error or a
truncated result, the connection is closed. The defaults, `requestTimeoutMs` 30000,
`lockTimeoutMs` 5000 and `rowCap` 1000, come from a measurement against a local container with a
concurrent writer: [reference/read-safety-measurement.md](reference/read-safety-measurement.md)
holds the results, the chosen row and how to rerun `scripts/measure-read-safety.mjs`.

The pool holds at most two connections, each opened to one database of the allow-list, and closes
a connection idle for 30 seconds. Every session carries the application name
`sql-server-plugin (agent session)`, so a server's session list shows which sessions an agent
opened. `sql-login` reads the user and password from the environment variables the config names
when a connection opens. `entra-default` passes one `DefaultAzureCredential` (with `clientId` as
its managed identity client id, when given) to `tedious`'s `token-credential` authentication.

The executor loads `tedious` and `@azure/identity`, the dependencies in `package.json`, on the
first call, so the server starts without them and a call made before they are installed fails
with a tool error saying so. `package-lock.json` pins their whole tree, and Claude Code installs
that tree when it copies the plugin into its cache.

### The reject list

`checkStatement(sql)` accepts one `SELECT`, optionally led by `WITH`, and refuses every other
statement kind. Inside the query it refuses `INTO`, a user `OPTION (...)`, `OPENROWSET`,
`OPENQUERY`, `OPENDATASOURCE` and the lock hints `HOLDLOCK`, `SERIALIZABLE`, `REPEATABLEREAD`,
`UPDLOCK`, `XLOCK`, `PAGLOCK`, `TABLOCK` and `TABLOCKX`. It reads tokens, so a keyword inside a
comment, a string literal or a bracketed or quoted identifier does not count. A column named like
a refused word must be bracketed, as in `[TABLOCK]`.

What the list lets through, because it is a heuristic:

- **Linked servers.** A four-part name such as `SELECT * FROM linkedsrv.db.dbo.t` reaches outside
  the registered server just as `OPENQUERY` does, and the list does not refuse it: on tokens it
  cannot be told apart from a `db.schema.table.column` reference. The remote read runs under the
  linked server's login mapping, which can be more privileged than your read-only principal, so
  that principal bounds it only when no linked server maps it to a remote login.
- **Unreserved statement starters.** The list stops a second statement only at a reserved keyword.
  A statement led by an unreserved word, such as `RECEIVE` (a Service Broker dequeue, a destructive
  read) or `ENABLE TRIGGER`, passes when it follows a complete `SELECT` with no semicolon, as in
  `SELECT 1 AS a RECEIVE TOP(1) * FROM q`. The read-only principal, which holds no `RECEIVE` or
  `ALTER` permission, is what refuses it.

## Config

One JSON file, validated by [`schemas/config.v1.schema.json`](schemas/config.v1.schema.json)
(JSON Schema draft 2020-12). A registration names it with `--config <path>`; the loader refuses a
path inside the project directory, a `schemaVersion` other than `1`, an unknown property, a
`password` holding a value instead of a reference, a connection string property, and any value
that looks like a password key-value pair or a connection string. Credentials are named by
environment variable:

```json
{
  "schemaVersion": 1,
  "environments": {
    "local": {
      "server": "localhost",
      "port": 1433,
      "databases": ["app"],
      "auth": { "type": "sql-login", "user": { "env": "SQL_READER_USER" }, "password": { "env": "SQL_READER_PASSWORD" } }
    }
  }
}
```

`auth.type` is `sql-login` or `entra-default` (an optional `clientId`). `defaults` and each
environment's `limits` take `requestTimeoutMs`, `lockTimeoutMs` and `rowCap`.

## Tests

The unit tests need Node.js 22 or later and no database or installed dependencies: the executor's
tests drive it through a fake `tedious` connection.

```bash
npm test --prefix plugins/sql-server
```

### Integration test

`integration/read-path.mjs` runs the server against a real SQL Server. It needs Docker, `openssl`
and the plugin's installed dependencies:

```bash
npm ci --prefix plugins/sql-server
node plugins/sql-server/integration/read-path.mjs
```

The script starts a `mcr.microsoft.com/mssql/server:2022-latest` container (Developer edition)
on a random local port, with a self-signed certificate for `localhost` that only this run trusts.
It creates a read-only login, a database `app` that the login can read and a database `other` that
it cannot, and starts the server on a registration confined to `app`. Each password is generated
for the run and reaches the plugin's server only through environment variables. It then checks the S1/S2,
S5, S6 and S7 requirements of
[#5940](https://github.com/melodic-software/claude-code-plugins/issues/5940) and prints one line
per check:

| Check | What passes |
|---|---|
| S1/S2 | Every write, DDL and session-state statement sent through `query` is refused, in each of two rounds. A statement the reject list lets through, such as `SELECT NEXT VALUE FOR` on a sequence, must meet a permission refusal. Each write is also sent straight to the server as the read-only login, past the reject list, and must meet a permission refusal there. After each attempt, a probe call shows the per-call settings in force and no plugin session holds a transaction. The database, read as `sa`, is unchanged at the end. |
| S5 | Each tool refuses `database: "other"` before connecting. A three-part name into `other` is refused because the login cannot access that database. `list_objects` shows only `app`. |
| S6 | Neither password appears in the plugin's files, in the config and registration files the run wrote, or in the server's output. |
| S7 | `tools/list` returns the same list after every tool call of the run. The `tools` capability declares `listChanged` false. |

It exits 0 when every check passes and 1 when a check or the setup fails. Without a reachable
Docker daemon it prints `SKIP: docker not available` and exits 0. It removes the container and
its temporary files when it ends.
