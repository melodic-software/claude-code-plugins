# sql-server

Read-only access to SQL Server-family databases (a local SQL Server container, Azure SQL Database)
for agents. The design is [ADR 0086](../../docs/adr/0086-bound-the-sql-server-read-tier-by-a-read-only-principal-and-fixed-registrations.md).

This release ships the parts that need no database: the versioned config schema, its loader and
the single-statement reject list. The MCP server, its tools and the setup skill come in later
releases, so the plugin has nothing to invoke yet and is off by default.

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
