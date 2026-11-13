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
task that waited on another session, by waiter, blocker, whether the blocker was itself waiting,
and wait class, and the worst-case line under it sums them over the runs. The guarantee it checks
is bounded blocking, not none: Microsoft documents that with `READ_COMMITTED_SNAPSHOT` off a
`READ COMMITTED` read takes shared locks, releasing each row lock before the next row
([SET TRANSACTION ISOLATION LEVEL](https://learn.microsoft.com/en-us/sql/t-sql/statements/set-transaction-isolation-level-transact-sql)),
so a writer can wait on it, and that the lock timeout limits how long a statement waits for a lock
([SET LOCK_TIMEOUT](https://learn.microsoft.com/en-us/sql/t-sql/statements/set-lock-timeout-transact-sql)).
The request timeout, plus the time the server takes to act on the cancel (the forced-timeout line
below shows both), ends the read and any wait it causes. This rests on each read running in
autocommit with `XACT_ABORT ON`, since a cancel ends the batch but not an explicit transaction
([blocking](https://learn.microsoft.com/en-us/troubleshoot/sql/database-engine/performance/understand-resolve-blocking));
the forced-timeout lines and the two raw-session rows of the read-controls table show it here.
The topology check line says less than the tables: a call whose lock wait hits the lock timeout,
or that runs past the request timeout, fails and ends the run before any results are written, so a
written PASS shows no single lock wait reached the lock timeout and every call returned within the
request timeout (the lock timeout limits each lock wait, not a call's length), and the line itself
can fail only on a transaction left open. Whether reads held anyone
up, and for how long, is the waiting-tasks table and the worst-case line; no limit on how long a
writer may wait is set or checked. A
waiting task whose blocker SQL Server cannot identify can show a `blocking_session_id` of 0
([sys.dm_exec_requests](https://learn.microsoft.com/en-us/sql/relational-databases/system-dynamic-management-views/sys-dm-exec-requests-transact-sql)),
so the table does not count it. The table-level lock count in the worst-case line is the
escalation check: the locking guide starts escalation at 5,000 locks taken by one statement on one
table reference and does not say whether locks already released count
([locking guide](https://learn.microsoft.com/en-us/sql/relational-databases/sql-server-transaction-locking-and-row-versioning-guide)),
so this measurement shows escalation did not happen here, not that it cannot. Compare the writer's
slowest update in the topology table with its longest wait on an agent session in the worst-case
line: any part of the slowest update that the waiting-tasks table does not show as a wait on an
agent session was not a wait on a lock a read held, within one sampling interval. Which other
resource it waited on (CPU, memory, I/O) this run does not record. Three runs is a judgment: SPEC
CPU2017 accepts three runs per benchmark ([run rules](https://www.spec.org/cpu2017/Docs/runrules.html)),
and no source read sets a count for a pass-or-fail bound check; three runs show the worst case,
not the spread. Nothing measured here calls for a shared process (ADR 0086 section 4); recheck if
a consumer runs many concurrent sessions against one shared server.

The forced timeouts below ran with the shipped defaults: `grep -c 'open transactions after
timeout: 0'` on this file counts them. The baseline rows show what the discard rule prevents: a
session cancelled inside a transaction with `XACT_ABORT OFF` and kept open still holds one.
Through `query`, a statement that opens a transaction fails with SQL Server's error 266 when
`sp_executesql` returns, so the executor discards the connection on the error path; the
`@@TRANCOUNT` check after the statement is a backstop this run did not reach.

## Results

<!-- BEGIN GENERATED: measure-read-safety-results. Run node plugins/sql-server/scripts/measure-read-safety.mjs -->
Run on 2026-11-06 by `scripts/measure-read-safety.mjs` against `mcr.microsoft.com/mssql/server:2025-CU10-ubuntu-24.04`
(`sha256:245f6b1c8903edae52cb20fa31419cefcde1a49938bb8c3447099011fc871ca3`), SQL Server 17.0.5035.5 Enterprise Developer Edition (64-bit), in a container capped at 2 GB.
Database `measure`: 200000 rows; READ_COMMITTED_SNAPSHOT off,
accelerated database recovery off, optimized locking off.
Reads run as `measure_reader`, a member of `db_datareader` only.

### Read controls while a writer holds a row lock for 8000 ms

| Reader | Lock timeout (ms) | Request timeout (ms) | Outcome | Blocked (ms) | Lock-wait samples | Open transactions after |
| --- | --- | --- | --- | --- | --- | --- |
| executor, no lock or request timeout | -1 | none | returned | 8008 | 75 | 0 |
| executor, lock timeout only | 500 | none | lock timeout (error 1222) | 581 | 4 | 0 |
| executor, lock timeout only | 1000 | none | lock timeout (error 1222) | 1075 | 9 | 0 |
| executor, lock timeout only | 2000 | none | lock timeout (error 1222) | 2077 | 19 | 0 |
| executor, lock timeout only | 5000 | none | lock timeout (error 1222) | 5075 | 47 | 0 |
| executor, request timeout only | -1 | 1000 | request timeout | 1067 | 9 | 0 |
| executor, request timeout only | -1 | 3000 | request timeout | 3066 | 28 | 0 |
| raw session in BEGIN TRAN, XACT_ABORT OFF, cancelled at 2000 ms, kept open | -1 | 2000 (client cancel) | cancelled | 2003 | - | 1 |
| raw session in BEGIN TRAN, XACT_ABORT ON, cancelled at 2000 ms, kept open | -1 | 2000 (client cancel) | cancelled | 2003 | - | 0 |

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
| SERIALIZABLE | 3010 |

### Row cap: `SELECT id, payload` over 200000 rows, no contention

| Row cap | Rows returned | Truncated | Call (ms) | Open transactions after |
| --- | --- | --- | --- | --- |
| 100 | 100 | true | 56 | 0 |
| 1000 | 1000 | true | 55 | 0 |
| 10000 | 10000 | true | 65 | 0 |
| none | 200000 | false | 210 | 0 |

Guard overhead: a `SELECT 1` averages 1.27 ms through the executor (guard batch, statement,
`@@TRANCOUNT` check) and 0.38 ms on a raw session, over 50 calls on a pooled connection.

### Forced timeouts at the shipped defaults (request 30000 ms, lock 5000 ms, row cap 1000)

- Writer holds a row lock 10000 ms: lock timeout (error 1222) after 5076 ms; open transactions after timeout: 0
- A cross join that runs past the request timeout: request timeout after 30150 ms; open transactions after timeout: 0

### Process topology: N stdio server processes, 4 concurrent `query` calls each, pool max 2, idle close 30000 ms

A writer updates one random row in autocommit every 20 ms throughout. The whole table ran 3 times.

| Run | Processes | Calls | Peak agent sessions | Call median (ms) | Call max (ms) | Wall (ms) | Writer max (ms) | Open transactions after |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 1 | 4 | 2 | 1668 | 1677 | 1867 | 57 | 0 |
| 1 | 2 | 8 | 4 | 2418 | 2979 | 3155 | 45 | 0 |
| 1 | 4 | 16 | 8 | 2624 | 3332 | 3489 | 83 | 0 |
| 1 | 8 | 32 | 16 | 3675 | 4869 | 5123 | 148 | 0 |
| 2 | 1 | 4 | 2 | 1471 | 1471 | 1634 | 60 | 0 |
| 2 | 2 | 8 | 4 | 2029 | 2190 | 2345 | 59 | 0 |
| 2 | 4 | 16 | 8 | 2546 | 3512 | 3677 | 91 | 0 |
| 2 | 8 | 32 | 16 | 3268 | 5078 | 5260 | 204 | 0 |
| 3 | 1 | 4 | 2 | 1202 | 1205 | 1377 | 83 | 0 |
| 3 | 2 | 8 | 4 | 1916 | 1974 | 2136 | 94 | 0 |
| 3 | 4 | 16 | 8 | 2384 | 3659 | 3821 | 95 | 0 |
| 3 | 8 | 32 | 16 | 3708 | 5687 | 5901 | 64 | 0 |

### Waiting tasks in the topology runs, by waiter and blocker

Sampled every 50 ms from `sys.dm_os_waiting_tasks`, for the agent sessions and the writer. A task counts when its
`blocking_session_id` is set and not 0. Longest wait is the largest `wait_duration_ms` a sample saw, so it can
trail the true wait by up to one sampling interval. Blocker waiting says whether the blocker was itself waiting on
another session at that sample: a request queued behind a waiting one names it as blocker, so such a wait is
not counted as caused by the blocker. A negative `blocking_session_id` (an owner SQL Server cannot name) and a
session's own parallel tasks are classed apart, not as blocking by another session.

| Run | Processes | Waiter | Blocker | Blocker waiting | Wait class | Wait types | Peak waiting tasks | Longest wait (ms) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 1 | agent | same session | no | other | CXCONSUMER, CXPACKET | 22 | 14 |
| 1 | 1 | agent | writer | no | lock | LCK_M_S | 1 | 4 |
| 1 | 1 | agent | same session | yes | lock | LCK_M_S | 2 | 2 |
| 1 | 2 | agent | same session | no | other | CXCONSUMER, CXSYNC_CONSUMER, CXSYNC_PORT | 29 | 521 |
| 1 | 2 | agent | writer | no | lock | LCK_M_S | 1 | 16 |
| 1 | 2 | agent | same session | yes | other | CXCONSUMER | 16 | 2 |
| 1 | 4 | agent | same session | no | other | CXCONSUMER, CXSYNC_CONSUMER, CXSYNC_PORT | 47 | 76 |
| 1 | 4 | agent | writer | no | lock | LCK_M_S | 1 | 66 |
| 1 | 4 | agent | agent | yes | lock | LCK_M_S | 4 | 54 |
| 1 | 4 | agent | same session | yes | other | CXCONSUMER | 13 | 7 |
| 1 | 4 | agent | same session | yes | lock | LCK_M_S | 4 | 57 |
| 1 | 8 | agent | same session | no | other | CXCONSUMER, CXPACKET, CXSYNC_CONSUMER, CXSYNC_PORT | 77 | 152 |
| 1 | 8 | agent | writer | no | lock | LCK_M_S | 1 | 21 |
| 1 | 8 | agent | same session | yes | other | CXCONSUMER | 19 | 7 |
| 1 | 8 | agent | agent | yes | lock | LCK_M_S | 1 | 7 |
| 1 | 8 | agent | same session | yes | lock | LCK_M_S | 1 | 2 |
| 2 | 1 | agent | same session | yes | lock | LCK_M_S | 3 | 8 |
| 2 | 1 | agent | agent | yes | lock | LCK_M_S | 3 | 10 |
| 2 | 1 | agent | writer | no | lock | LCK_M_S | 1 | 12 |
| 2 | 1 | agent | same session | no | other | CXCONSUMER, CXPACKET | 24 | 18 |
| 2 | 2 | agent | same session | no | other | CXCONSUMER, CXSYNC_CONSUMER, CXSYNC_PORT | 27 | 45 |
| 2 | 2 | agent | writer | no | lock | LCK_M_S | 1 | 23 |
| 2 | 2 | agent | agent | yes | lock | LCK_M_S | 7 | 16 |
| 2 | 2 | agent | same session | yes | lock | LCK_M_S | 3 | 22 |
| 2 | 2 | agent | same session | yes | other | CXCONSUMER | 41 | 1 |
| 2 | 4 | agent | same session | no | other | CXCONSUMER, CXPACKET, CXSYNC_CONSUMER, CXSYNC_PORT | 68 | 207 |
| 2 | 4 | agent | writer | no | lock | LCK_M_S | 1 | 14 |
| 2 | 4 | agent | same session | yes | other | CXCONSUMER | 4 | 13 |
| 2 | 4 | agent | agent | yes | lock | LCK_M_S | 3 | 14 |
| 2 | 4 | agent | same session | yes | lock | LCK_M_S | 1 | 13 |
| 2 | 8 | agent | same session | no | other | CXCONSUMER, CXPACKET, CXSYNC_CONSUMER, CXSYNC_PORT | 82 | 55 |
| 2 | 8 | agent | agent | yes | lock | LCK_M_S | 5 | 18 |
| 2 | 8 | agent | same session | yes | other | CXCONSUMER | 24 | 20 |
| 2 | 8 | agent | agent | no | lock | LCK_M_S | 1 | 16 |
| 2 | 8 | agent | writer | no | lock | LCK_M_S | 1 | 25 |
| 2 | 8 | agent | same session | yes | lock | LCK_M_S | 3 | 24 |
| 3 | 1 | agent | same session | no | other | CXCONSUMER | 18 | 3 |
| 3 | 1 | agent | writer | no | lock | LCK_M_S | 1 | 2 |
| 3 | 2 | agent | same session | no | other | CXCONSUMER, CXPACKET | 27 | 22 |
| 3 | 2 | agent | same session | yes | other | CXCONSUMER | 22 | 3 |
| 3 | 2 | agent | agent | yes | lock | LCK_M_S | 7 | 10 |
| 3 | 2 | agent | same session | yes | lock | LCK_M_S | 6 | 25 |
| 3 | 2 | agent | writer | no | lock | LCK_M_S | 1 | 17 |
| 3 | 2 | agent | agent | no | lock | LCK_M_S | 1 | 0 |
| 3 | 4 | agent | same session | no | other | CXCONSUMER, CXPACKET, CXSYNC_CONSUMER, CXSYNC_PORT | 65 | 66 |
| 3 | 4 | agent | writer | no | lock | LCK_M_S | 1 | 34 |
| 3 | 4 | agent | same session | yes | other | CXCONSUMER, CXPACKET | 13 | 4 |
| 3 | 4 | agent | agent | yes | lock | LCK_M_S | 3 | 8 |
| 3 | 4 | agent | same session | yes | lock | LCK_M_S | 3 | 19 |
| 3 | 8 | agent | same session | no | other | CXCONSUMER, CXPACKET, CXSYNC_CONSUMER, CXSYNC_PORT | 75 | 90 |
| 3 | 8 | agent | writer | no | lock | LCK_M_S | 1 | 19 |
| 3 | 8 | agent | same session | yes | lock | LCK_M_S | 1 | 2 |
| 3 | 8 | agent | same session | yes | other | CXCONSUMER | 3 | 0 |
| 3 | 8 | agent | agent | yes | lock | LCK_M_S | 2 | 12 |

Worst case over 3 runs: writer max 204 ms; longest wait the writer spent on an agent session
0 ms (0 ms on one not itself waiting); longest wait any session spent on an agent
session 54 ms (16 ms on one not itself waiting); longest agent lock wait 66 ms; open
transactions after a topology run 0; table-level locks an agent session held at once
0. Median over the runs of the writer's slowest update, by process count: 1: 60 ms, 2: 59 ms, 4: 91 ms, 8: 148 ms.
3 runs show the worst case; they support no estimate of run-to-run spread.

Topology check: PASS. No agent lock wait reached the lock timeout (5000 ms), every call returned within the request timeout (30000 ms), and no transaction was left open. How long anyone waited is the worst-case line above.
<!-- END GENERATED: measure-read-safety-results -->
