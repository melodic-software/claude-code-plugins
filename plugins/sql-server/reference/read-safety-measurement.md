# Read-safety and topology measurement

[ADR 0086](../../../docs/adr/0086-bound-the-sql-server-read-tier-by-a-read-only-principal-and-fixed-registrations.md)
sections 1 and 4 left the read-control defaults and the process topology provisional until a
measurement against a local container with a concurrent writer. This file records that
measurement and the defaults chosen from it.

## How to rerun

On a Linux host with Docker and Node 22, from `plugins/sql-server`:

```bash
npm ci --ignore-scripts --no-audit --no-fund
node scripts/measure-read-safety.mjs [--image <tag>] [--doc <path>] [--runs <n>]
```

The script starts a SQL Server Linux container under a generated name with `--memory 2g`, bound to
`127.0.0.1` on a free port, with an SA password generated for the run and never written or
printed. It creates a 200000-row table and a login that is a member of `db_datareader` only, runs
every scenario, runs the topology table `--runs` times (default 3), rewrites the block between the
results markers below, and removes the container. It exits 0 when every scenario ran.

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
| `rowCap` | 1000 | The row-cap table shows a capped read returning faster than the full 200000 rows, with no transaction left open. The server process reads the rows itself and cancels at the cap, so no client can pause the stream while locks are held (`src/executor.mjs`, `run`) |
| `isolation` | READ COMMITTED | The isolation table: a writer waits a few milliseconds on a `READ COMMITTED` reader transaction, and the full hold under `REPEATABLE READ` and `SERIALIZABLE` |
| `POOL_MAX` | 2 | The topology table: peak agent sessions are exactly 2 per busy process, so a pool of 2 bounds each session's load on the server |
| `IDLE_TIMEOUT_MS` | 30000 | Not stressed by this measurement; kept, since an idle session holds no locks |

The basis above cites the tables in Results by name rather than by figure, so a rerun that moves the
numbers leaves it accurate. If a rerun breaks one of these statements, revisit the chosen row.

Topology: one stdio server process per registration per client session stays the default.
Connections grow by exactly `POOL_MAX` per busy process. The waiting-tasks table attributes every
task that waited on another session, by waiter, blocker and wait class, and the worst-case line
under it sums them over the runs. The guarantee it checks is bounded blocking, not none: with
`READ_COMMITTED_SNAPSHOT` off a `READ COMMITTED` read takes shared locks, so a writer can wait on
it. The lock timeout ends an agent's own lock waits; the request timeout ends the read, and any
wait it causes, at the latest. The bounded-blocking check fails if an agent lock wait reaches the
lock timeout, a wait on an agent session reaches the request timeout, or a transaction is left
open. Compare the writer's slowest update in the topology table with its longest wait on an agent
session in the worst-case line: any part of the slowest update that the waiting-tasks table does
not show as a wait on an agent session was not a wait on a lock a read held, within one sampling
interval. Which other resource it waited on (CPU, memory, I/O) this run does not record. Nothing measured here calls for a shared process (ADR 0086
section 4); recheck if a consumer runs many concurrent sessions against one shared server.

The forced timeouts below ran with the shipped defaults: `grep -c 'open transactions after
timeout: 0'` on this file counts them. The baseline rows show what the discard rule prevents: a
session cancelled inside a transaction with `XACT_ABORT OFF` and kept open still holds one.
Through `query`, a statement that opens a transaction fails with SQL Server's error 266 when
`sp_executesql` returns, so the executor discards the connection on the error path; the
`@@TRANCOUNT` check after the statement is a backstop this run did not reach.

## Results

<!-- measure-read-safety:results:start -->
Run on 2026-11-06 by `scripts/measure-read-safety.mjs` against `mcr.microsoft.com/mssql/server:2025-CU8-ubuntu-24.04`
(`sha256:4bab24f36c1ecd48e85f7d37df26e6bf301641d84c3fe652f9a0dcc947d512e1`), SQL Server 17.0.4075.5 Enterprise Developer Edition (64-bit), in a container capped at 2 GB.
Database `measure`: 200000 rows; READ_COMMITTED_SNAPSHOT off,
accelerated database recovery off, optimized locking off.
Reads run as `measure_reader`, a member of `db_datareader` only.

### Read controls while a writer holds a row lock for 8000 ms

| Reader | Lock timeout (ms) | Request timeout (ms) | Outcome | Blocked (ms) | Lock-wait samples | Open transactions after |
| --- | --- | --- | --- | --- | --- | --- |
| executor, no lock or request timeout | -1 | none | returned | 8012 | 76 | 0 |
| executor, lock timeout only | 500 | none | lock timeout (error 1222) | 579 | 4 | 0 |
| executor, lock timeout only | 1000 | none | lock timeout (error 1222) | 1080 | 9 | 0 |
| executor, lock timeout only | 2000 | none | lock timeout (error 1222) | 2078 | 19 | 0 |
| executor, lock timeout only | 5000 | none | lock timeout (error 1222) | 5079 | 48 | 0 |
| executor, request timeout only | -1 | 1000 | request timeout | 1067 | 9 | 0 |
| executor, request timeout only | -1 | 3000 | request timeout | 3065 | 29 | 0 |
| raw session in BEGIN TRAN, XACT_ABORT OFF, cancelled at 2000 ms, kept open | -1 | 2000 (client cancel) | cancelled | 2004 | - | 1 |
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
| REPEATABLE READ | 3039 |
| SERIALIZABLE | 3013 |

### Row cap: `SELECT id, payload` over 200000 rows, no contention

| Row cap | Rows returned | Truncated | Call (ms) | Open transactions after |
| --- | --- | --- | --- | --- |
| 100 | 100 | true | 56 | 0 |
| 1000 | 1000 | true | 56 | 0 |
| 10000 | 10000 | true | 65 | 0 |
| none | 200000 | false | 224 | 0 |

Guard overhead: a `SELECT 1` averages 1.22 ms through the executor (guard batch, statement,
`@@TRANCOUNT` check) and 0.44 ms on a raw session, over 50 calls on a pooled connection.

### Forced timeouts at the shipped defaults (request 30000 ms, lock 5000 ms, row cap 1000)

- Writer holds a row lock 10000 ms: lock timeout (error 1222) after 5081 ms; open transactions after timeout: 0
- A cross join that runs past the request timeout: request timeout after 30187 ms; open transactions after timeout: 0

### Process topology: N stdio server processes, 4 concurrent `query` calls each, pool max 2, idle close 30000 ms

A writer updates one random row in autocommit every 20 ms throughout. The whole table ran 3 times.

| Run | Processes | Calls | Peak agent sessions | Call median (ms) | Call max (ms) | Wall (ms) | Writer max (ms) | Open transactions after |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 1 | 4 | 2 | 1575 | 1640 | 2101 | 140 | 0 |
| 1 | 2 | 8 | 4 | 2104 | 2528 | 2716 | 332 | 0 |
| 1 | 4 | 16 | 8 | 2110 | 2806 | 2968 | 122 | 0 |
| 1 | 8 | 32 | 16 | 2880 | 4013 | 4169 | 197 | 0 |
| 2 | 1 | 4 | 2 | 1158 | 1158 | 1328 | 197 | 0 |
| 2 | 2 | 8 | 4 | 1832 | 2169 | 2305 | 366 | 0 |
| 2 | 4 | 16 | 8 | 2613 | 3459 | 3612 | 356 | 0 |
| 2 | 8 | 32 | 16 | 3770 | 5094 | 5262 | 230 | 0 |
| 3 | 1 | 4 | 2 | 1063 | 1085 | 1241 | 41 | 0 |
| 3 | 2 | 8 | 4 | 1828 | 1987 | 2131 | 48 | 0 |
| 3 | 4 | 16 | 8 | 3017 | 3823 | 3972 | 66 | 0 |
| 3 | 8 | 32 | 16 | 3705 | 5213 | 5409 | 309 | 0 |

### Waiting tasks in the topology runs, by waiter and blocker

Sampled every 50 ms from `sys.dm_os_waiting_tasks`, for the agent sessions and the writer. A task counts when its
`blocking_session_id` is set and not 0. Longest wait is the largest `wait_duration_ms` a sample saw, so it can
trail the true wait by up to one sampling interval.

| Run | Processes | Waiter | Blocker | Wait class | Wait types | Peak waiting tasks | Longest wait (ms) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 1 | agent | same session | other | CXCONSUMER | 28 | 25 |
| 1 | 1 | agent | agent | lock | LCK_M_S | 14 | 38 |
| 1 | 1 | agent | writer | lock | LCK_M_S | 1 | 77 |
| 1 | 1 | agent | same session | lock | LCK_M_S | 13 | 27 |
| 1 | 2 | agent | same session | other | CXCONSUMER, CXPACKET, CXSYNC_CONSUMER, CXSYNC_PORT | 45 | 429 |
| 1 | 2 | agent | same session | lock | LCK_M_S | 6 | 294 |
| 1 | 2 | agent | writer | lock | LCK_M_S | 1 | 312 |
| 1 | 2 | agent | agent | lock | LCK_M_S | 7 | 15 |
| 1 | 4 | agent | same session | other | CXCONSUMER, CXPACKET, CXSYNC_CONSUMER, CXSYNC_PORT | 71 | 413 |
| 1 | 4 | agent | agent | lock | LCK_M_S | 3 | 39 |
| 1 | 4 | agent | same session | lock | LCK_M_S | 1 | 25 |
| 1 | 4 | agent | writer | lock | LCK_M_S | 1 | 39 |
| 1 | 8 | agent | same session | other | CXCONSUMER, CXPACKET, CXSYNC_CONSUMER, CXSYNC_PORT | 77 | 99 |
| 1 | 8 | agent | agent | lock | LCK_M_S | 9 | 81 |
| 1 | 8 | agent | same session | lock | LCK_M_S | 10 | 102 |
| 1 | 8 | agent | writer | lock | LCK_M_S | 1 | 108 |
| 2 | 1 | agent | same session | lock | LCK_M_S | 9 | 68 |
| 2 | 1 | agent | writer | lock | LCK_M_S | 1 | 69 |
| 2 | 1 | agent | same session | other | CXCONSUMER, CXPACKET, CXSYNC_CONSUMER, CXSYNC_PORT | 27 | 40 |
| 2 | 1 | agent | agent | lock | LCK_M_S | 1 | 12 |
| 2 | 2 | agent | same session | other | CXCONSUMER, CXSYNC_CONSUMER, CXSYNC_PORT | 91 | 176 |
| 2 | 2 | agent | writer | lock | LCK_M_S | 1 | 286 |
| 2 | 2 | agent | agent | lock | LCK_M_S | 43 | 279 |
| 2 | 2 | agent | same session | lock | LCK_M_S | 23 | 271 |
| 2 | 4 | agent | same session | other | CXCONSUMER, CXSYNC_PORT | 91 | 146 |
| 2 | 4 | agent | writer | lock | LCK_M_S | 1 | 299 |
| 2 | 4 | agent | agent | lock | LCK_M_S | 71 | 276 |
| 2 | 4 | agent | same session | lock | LCK_M_S | 23 | 283 |
| 2 | 8 | agent | same session | other | CXCONSUMER, CXPACKET, CXSYNC_PORT | 75 | 129 |
| 2 | 8 | agent | same session | lock | LCK_M_S | 3 | 29 |
| 2 | 8 | agent | agent | lock | LCK_M_S | 5 | 13 |
| 2 | 8 | agent | writer | lock | LCK_M_S | 1 | 32 |
| 3 | 1 | agent | writer | lock | LCK_M_S | 1 | 25 |
| 3 | 1 | agent | same session | other | CXCONSUMER, CXSYNC_PORT | 22 | 22 |
| 3 | 1 | agent | agent | lock | LCK_M_S | 2 | 14 |
| 3 | 1 | agent | same session | lock | LCK_M_S | 5 | 21 |
| 3 | 2 | agent | same session | other | CXCONSUMER, CXSYNC_CONSUMER, CXSYNC_PORT | 49 | 20 |
| 3 | 2 | agent | same session | lock | LCK_M_S | 6 | 14 |
| 3 | 2 | agent | writer | lock | LCK_M_S | 1 | 16 |
| 3 | 4 | agent | same session | other | CXCONSUMER, CXPACKET, CXSYNC_CONSUMER, CXSYNC_PORT | 52 | 65 |
| 3 | 4 | agent | writer | lock | LCK_M_S | 1 | 24 |
| 3 | 4 | agent | agent | lock | LCK_M_S | 7 | 24 |
| 3 | 4 | agent | same session | lock | LCK_M_S | 5 | 22 |
| 3 | 8 | agent | same session | other | CXCONSUMER, CXPACKET, CXSYNC_CONSUMER, CXSYNC_PORT | 88 | 336 |
| 3 | 8 | agent | writer | lock | LCK_M_S | 1 | 24 |
| 3 | 8 | agent | agent | lock | LCK_M_S | 4 | 21 |
| 3 | 8 | agent | same session | lock | LCK_M_S | 1 | 13 |
| 3 | 8 | writer | agent | lock | LCK_M_IX | 1 | 12 |

Worst case over 3 runs: writer max 366 ms; longest wait the writer spent on an agent session
12 ms; longest wait any session spent on an agent session 279 ms; longest agent lock wait
312 ms; open transactions after a topology run 0.

Bounded-blocking check: PASS. Every call returned; no agent lock wait reached the lock timeout, no wait on an agent session reached the request timeout, and no transaction was left open.
<!-- measure-read-safety:results:end -->
