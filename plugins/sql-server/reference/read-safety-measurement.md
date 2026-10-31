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
| `requestTimeoutMs` | 30000 | No-contention reads finish in tens of milliseconds to a few seconds (row cap and topology tables), so the request timeout only stops a runaway query; it cancelled within 130 ms of its value, with no open transaction after |
| `lockTimeoutMs` | 5000 | Each lock timeout ended the read within 79 ms of its value, with no open transaction after. A `READ COMMITTED` reader held up a writer for 6 ms, so the value mainly sets how long the agent waits; 5000 ms rides out the short writer locks seen here (126 ms at most, under 8 processes) |
| `rowCap` | 1000 | Capping cancelled the stream promptly (57 ms for 1000 rows against 218 ms for all 200000) and left no transaction open. Measured with a fast consumer and no writer: how long a slow or paused consumer holds locks before the cap was not measured |
| `isolation` | READ COMMITTED | A writer waited 6 ms on a `READ COMMITTED` reader transaction, against the full 3000 ms hold under `REPEATABLE READ` and `SERIALIZABLE` |
| `POOL_MAX` | 2 | Peak agent sessions were exactly 2 per busy process (16 for 8 processes), so a pool of 2 bounds each session's load on the server |
| `IDLE_TIMEOUT_MS` | 30000 | Not stressed by this measurement; kept, since an idle session holds no locks |

Topology: one stdio server process per registration per client session stays the default.
Connections grow by exactly `POOL_MAX` per busy process. With 1, 2 or 4 processes no request was
blocked; at 8 processes (16 concurrent scans in a 2 GB container) up to 2 requests were briefly
blocked, and the writer's slowest update rose from 39 ms to 126 ms. Earlier runs on the same day
saw up to 5 blocked requests and a 217 ms writer at 8 processes, so these figures vary by run. The cause
(lock waits or CPU) was not separated. Nothing measured here calls for a shared process (ADR 0086
section 4); recheck if a consumer runs many concurrent sessions against one shared server.

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
| executor, no lock or request timeout | -1 | none | returned | 8008 | 77 | 0 |
| executor, lock timeout only | 500 | none | lock timeout (error 1222) | 579 | 5 | 0 |
| executor, lock timeout only | 1000 | none | lock timeout (error 1222) | 1075 | 9 | 0 |
| executor, lock timeout only | 2000 | none | lock timeout (error 1222) | 2075 | 19 | 0 |
| executor, lock timeout only | 5000 | none | lock timeout (error 1222) | 5075 | 49 | 0 |
| executor, request timeout only | -1 | 1000 | request timeout | 1064 | 9 | 0 |
| executor, request timeout only | -1 | 3000 | request timeout | 3060 | 29 | 0 |
| raw session in BEGIN TRAN, XACT_ABORT OFF, cancelled at 2000 ms, kept open | -1 | 2000 (client cancel) | cancelled | 2001 | - | 1 |
| raw session in BEGIN TRAN, XACT_ABORT ON, cancelled at 2000 ms, kept open | -1 | 2000 (client cancel) | cancelled | 2004 | - | 0 |

### A statement that opens a transaction (sent past the reject list)

| Reader | Outcome | Open transactions after |
| --- | --- | --- |
| raw session, connection kept | returned | 1 |
| executor (statement fails with error 266, connection discarded) | error: Transaction count after EXECUTE indicates a mismatching number of BEGIN and COMMIT statements. Previous count = 0, current count = 1. | 0 |

### Pinned isolation: writer wait on a reader transaction held 3000 ms

| Reader isolation | Writer waited (ms) |
| --- | --- |
| READ COMMITTED | 6 |
| REPEATABLE READ | 3005 |
| SERIALIZABLE | 3004 |

### Row cap: `SELECT id, payload` over 200000 rows, no contention

| Row cap | Rows returned | Truncated | Call (ms) | Open transactions after |
| --- | --- | --- | --- | --- |
| 100 | 100 | true | 57 | 0 |
| 1000 | 1000 | true | 57 | 0 |
| 10000 | 10000 | true | 70 | 0 |
| none | 200000 | false | 218 | 0 |

Guard overhead: a `SELECT 1` averages 1.40 ms through the executor (guard batch, statement,
`@@TRANCOUNT` check) and 0.42 ms on a raw session, over 50 calls on a pooled connection.

### Forced timeouts at the shipped defaults (request 30000 ms, lock 5000 ms, row cap 1000)

- Writer holds a row lock 10000 ms: lock timeout (error 1222) after 5075 ms; open transactions after timeout: 0
- A cross join that runs past the request timeout: request timeout after 30124 ms; open transactions after timeout: 0

### Process topology: N stdio server processes, 4 concurrent `query` calls each, pool max 2, idle close 30000 ms

A writer updates one random row in autocommit every 20 ms throughout.

| Processes | Calls | Peak agent sessions | Peak blocked requests | Call median (ms) | Call max (ms) | Wall (ms) | Writer max (ms) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 4 | 2 | 0 | 1276 | 1290 | 1456 | 39 |
| 2 | 8 | 4 | 0 | 1776 | 1877 | 2016 | 70 |
| 4 | 16 | 8 | 0 | 2032 | 2876 | 3012 | 55 |
| 8 | 32 | 16 | 2 | 2403 | 3686 | 3849 | 126 |
<!-- measure-read-safety:results:end -->
