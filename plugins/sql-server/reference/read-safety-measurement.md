# Read-safety and topology measurement

[ADR 0086](../../../docs/adr/0086-bound-the-sql-server-read-tier-by-a-read-only-principal-and-fixed-registrations.md)
sections 1 and 4 left the read-control defaults and the process topology provisional until a
measurement against a local container with a concurrent writer. This file records that
measurement and the defaults chosen from it.

## How to rerun

On a Linux host with Docker and Node 22, from `plugins/sql-server`:

```bash
npm ci --ignore-scripts --no-audit --no-fund
node scripts/measure-read-safety.mjs [--image <tag>] [--doc <path>]
```

The script starts a SQL Server Linux container under a generated name with `--memory 2g`, bound to
`127.0.0.1` on a free port, with an SA password generated for the run and never written or
printed. It creates a 200000-row table and a login that is a member of `db_datareader` only, runs
every scenario, rewrites the block between the results markers below, and removes the container.
It exits 0 when every scenario ran.

The container's TLS certificate is self-signed, and the executor keeps `encrypt` on without
`trustServerCertificate`. The script therefore hands the executor a `tedious` whose `Connection`
sets `trustServerCertificate`; every other line of the executor and the stdio server runs as
shipped. The scenarios call the executor directly, so a statement the reject list would refuse
(`BEGIN TRAN`) can test the `@@TRANCOUNT` guarantee, and a lock timeout of `-1`, which the config
schema refuses, can serve as the no-control baseline.

## Chosen defaults

| Setting | Default | Basis |
|---|---|---|
| `requestTimeoutMs` | 30000 | Reads without contention finish well inside it (row cap and topology tables), so it only stops a runaway query. In the read-controls table each request timeout cancels within tens of milliseconds of its value and leaves no transaction open |
| `lockTimeoutMs` | 5000 | In the read-controls table each lock timeout ends the read within tens of milliseconds of its value and leaves no transaction open. The isolation table shows a `READ COMMITTED` reader barely holds up a writer, so the value mainly sets how long the agent waits; 5000 ms is well above the writer's slowest update in the topology table |
| `rowCap` | 1000 | The row-cap table shows a capped read returning faster than the full 200000 rows, with no transaction left open. That run used a fast consumer and no writer; lock hold under a slow or paused consumer before the cap fires was not measured |
| `isolation` | READ COMMITTED | The isolation table: a writer waits a few milliseconds on a `READ COMMITTED` reader transaction, and the full hold under `REPEATABLE READ` and `SERIALIZABLE` |
| `POOL_MAX` | 2 | The topology table: peak agent sessions are exactly 2 per busy process, so a pool of 2 bounds each session's load on the server |
| `IDLE_TIMEOUT_MS` | 30000 | Not stressed by this measurement; kept, since an idle session holds no locks |

The basis above cites the tables in Results by name rather than by figure, so a rerun that moves the
numbers leaves it accurate. If a rerun breaks one of these statements, revisit the chosen row.

Topology: one stdio server process per registration per client session stays the default.
Connections grow by exactly `POOL_MAX` per busy process. The topology table records blocked
requests and the writer's slowest update as processes rise. Runs so far blocked no request with
up to 2 processes and briefly blocked a few at 8 processes (16 concurrent scans in a 2 GB
container); how many, and how slow the writer got, varies by run, and the cause (lock waits or
CPU) was not separated. Nothing measured here calls for a shared process (ADR 0086 section 4);
recheck if a consumer runs many concurrent sessions against one shared server.

The forced timeouts below ran with the shipped defaults: `grep -c 'open transactions after
timeout: 0'` on this file counts them. The baseline rows show what the discard rule prevents: a
session cancelled inside a transaction with `XACT_ABORT OFF` and kept open still holds one.
Through `query`, a statement that opens a transaction fails with SQL Server's error 266 when
`sp_executesql` returns, so the executor discards the connection on the error path; the
`@@TRANCOUNT` check after the statement is a backstop this run did not reach.

## Results

<!-- measure-read-safety:results:start -->
Run on 2026-10-31 by `scripts/measure-read-safety.mjs` against `mcr.microsoft.com/mssql/server:2025-CU8-ubuntu-24.04`
(`sha256:4bab24f36c1ecd48e85f7d37df26e6bf301641d84c3fe652f9a0dcc947d512e1`), SQL Server 17.0.4075.5 Enterprise Developer Edition (64-bit), in a container capped at 2 GB.
Database `measure`: 200000 rows; READ_COMMITTED_SNAPSHOT off,
accelerated database recovery off, optimized locking off.
Reads run as `measure_reader`, a member of `db_datareader` only.

### Read controls while a writer holds a row lock for 8000 ms

| Reader | Lock timeout (ms) | Request timeout (ms) | Outcome | Blocked (ms) | Lock-wait samples | Open transactions after |
| --- | --- | --- | --- | --- | --- | --- |
| executor, no lock or request timeout | -1 | none | returned | 8006 | 77 | 0 |
| executor, lock timeout only | 500 | none | lock timeout (error 1222) | 576 | 5 | 0 |
| executor, lock timeout only | 1000 | none | lock timeout (error 1222) | 1076 | 9 | 0 |
| executor, lock timeout only | 2000 | none | lock timeout (error 1222) | 2078 | 19 | 0 |
| executor, lock timeout only | 5000 | none | lock timeout (error 1222) | 5077 | 49 | 0 |
| executor, request timeout only | -1 | 1000 | request timeout | 1067 | 9 | 0 |
| executor, request timeout only | -1 | 3000 | request timeout | 3068 | 29 | 0 |
| raw session in BEGIN TRAN, XACT_ABORT OFF, cancelled at 2000 ms, kept open | -1 | 2000 (client cancel) | cancelled | 2002 | - | 1 |
| raw session in BEGIN TRAN, XACT_ABORT ON, cancelled at 2000 ms, kept open | -1 | 2000 (client cancel) | cancelled | 2004 | - | 0 |

### A statement that opens a transaction (sent past the reject list)

| Reader | Outcome | Open transactions after |
| --- | --- | --- |
| raw session, connection kept | returned | 1 |
| executor (statement fails with error 266, connection discarded) | error: Transaction count after EXECUTE indicates a mismatching number of BEGIN and COMMIT statements. Previous count = 0, current count = 1. | 0 |

### Pinned isolation: writer wait on a reader transaction held 3000 ms

| Reader isolation | Writer waited (ms) |
| --- | --- |
| READ COMMITTED | 5 |
| REPEATABLE READ | 3003 |
| SERIALIZABLE | 3007 |

### Row cap: `SELECT id, payload` over 200000 rows, no contention

| Row cap | Rows returned | Truncated | Call (ms) | Open transactions after |
| --- | --- | --- | --- | --- |
| 100 | 100 | true | 58 | 0 |
| 1000 | 1000 | true | 54 | 0 |
| 10000 | 10000 | true | 64 | 0 |
| none | 200000 | false | 208 | 0 |

Guard overhead: a `SELECT 1` averages 1.13 ms through the executor (guard batch, statement,
`@@TRANCOUNT` check) and 0.34 ms on a raw session, over 50 calls on a pooled connection.

### Forced timeouts at the shipped defaults (request 30000 ms, lock 5000 ms, row cap 1000)

- Writer holds a row lock 10000 ms: lock timeout (error 1222) after 5076 ms; open transactions after timeout: 0
- A cross join that runs past the request timeout: request timeout after 30154 ms; open transactions after timeout: 0

### Process topology: N stdio server processes, 4 concurrent `query` calls each, pool max 2, idle close 30000 ms

A writer updates one random row in autocommit every 20 ms throughout.

| Processes | Calls | Peak agent sessions | Peak blocked requests | Call median (ms) | Call max (ms) | Wall (ms) | Writer max (ms) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 4 | 2 | 0 | 972 | 972 | 1123 | 43 |
| 2 | 8 | 4 | 0 | 1878 | 1896 | 2039 | 46 |
| 4 | 16 | 8 | 0 | 1977 | 2588 | 2785 | 104 |
| 8 | 32 | 16 | 1 | 2502 | 3663 | 3971 | 162 |
<!-- measure-read-safety:results:end -->
