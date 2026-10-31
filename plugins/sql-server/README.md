# sql-server

Read-only access to SQL Server-family databases (a local SQL Server container, Azure SQL Database)
for agents. The design is [ADR 0086](../../docs/adr/0086-bound-the-sql-server-read-tier-by-a-read-only-principal-and-fixed-registrations.md).

This release ships the parts that need no database: the versioned config schema, its loader, the
single-statement reject list and the stdio MCP server with its three tools. The database executor
and the setup skill come in later releases. Until the executor ships, every tool call that passes
its checks returns a tool error saying no executor exists, so the plugin is off by default.

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
| Request timeout | guarantee | Later release |
| Streaming row cap with prompt cancel | guarantee | Later release |
| Transaction check after each call (`@@TRANCOUNT` above 0 discards the connection) | guarantee | Later release |
| Rollback guard before each call (`IF @@TRANCOUNT > 0 ROLLBACK`) | guarantee | Later release |
| Discard the connection after a timeout, cancel or error | guarantee | Later release |
| `SET XACT_ABORT ON` per call | heuristic | Later release |
| Pinned isolation (`READ COMMITTED`) per call | heuristic | Later release |
| `SET LOCK_TIMEOUT` per call | heuristic | Later release |
| Single-statement reject list | heuristic | `src/statement.mjs` |

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

The unit tests need Node.js 22 or later and no database:

```bash
npm test --prefix plugins/sql-server
```
