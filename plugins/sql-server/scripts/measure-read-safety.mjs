#!/usr/bin/env node
// Measures the read controls and the process topology of ADR 0086 sections 1
// and 4 against a local SQL Server Linux container it starts and removes, then
// rewrites the results block of reference/read-safety-measurement.md.
//
//   node scripts/measure-read-safety.mjs [--image <tag>] [--doc <path>]
//
// Needs Docker, Node 22 and the plugin's dependencies (npm ci). The SA and
// reader passwords are generated per run and never written or printed. The
// container's certificate is self-signed, so the measurement connects with a
// driver whose Connection sets trustServerCertificate; the shipped executor
// code runs unchanged on top of it.
import { execFileSync, spawn } from 'node:child_process';
import { randomBytes, randomInt } from 'node:crypto';
import { mkdtempSync, readFileSync, rmSync, mkdirSync, writeFileSync } from 'node:fs';
import { createServer } from 'node:net';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';
import { APP_NAME, DEFAULT_LIMITS, IDLE_TIMEOUT_MS, POOL_MAX, createTediousExecutor } from '../src/executor.mjs';

const PLUGIN_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const SELF = fileURLToPath(import.meta.url);
const DEFAULT_IMAGE = 'mcr.microsoft.com/mssql/server:2025-CU8-ubuntu-24.04';
const DEFAULT_DOC = join(PLUGIN_ROOT, 'reference', 'read-safety-measurement.md');
const START = '<!-- measure-read-safety:results:start -->';
const END = '<!-- measure-read-safety:results:end -->';
const DB = 'measure';
const ROWS = 200_000;
const LOCKED_ID = 150_000;
const READER_USER = 'measure_reader';
const BASELINE_APP = 'measure-baseline';
const SCAN = 'SELECT MAX(LEN(payload)) AS longest FROM dbo.items;';

const sleep = (ms) => new Promise((done) => setTimeout(done, ms));
const now = () => performance.now();
const password = () => `Aa1!${randomBytes(18).toString('base64url')}`;

async function tediousModule() {
  const module = await import('tedious');
  return module.default ?? module;
}

// tedious with the one change a self-signed container certificate needs.
async function trustingDriver() {
  const tedious = await tediousModule();
  class Connection extends tedious.Connection {
    constructor(config) {
      super({ ...config, options: { ...config.options, trustServerCertificate: true } });
    }
  }
  return { ...tedious, Connection };
}

function docker(args, env = process.env) {
  return execFileSync('docker', args, { encoding: 'utf8', env, stdio: ['ignore', 'pipe', 'pipe'] }).trim();
}

function freePort() {
  return new Promise((done, fail) => {
    const server = createServer();
    server.once('error', fail);
    server.listen(0, '127.0.0.1', () => {
      const { port } = server.address();
      server.close(() => done(port));
    });
  });
}

async function measure() {
  const { values } = parseArgs({ options: { image: { type: 'string' }, doc: { type: 'string' } } });
  const image = values.image ?? DEFAULT_IMAGE;
  const docPath = resolve(values.doc ?? DEFAULT_DOC);
  const doc = readFileSync(docPath, 'utf8');
  if (!doc.includes(START) || !doc.includes(END)) throw new Error(`${docPath} has no results markers`);

  const name = `sql-server-measure-${randomBytes(4).toString('hex')}`;
  const work = mkdtempSync(join(tmpdir(), 'sql-server-measure-'));
  let started = false;
  const cleanup = () => {
    if (started) {
      try {
        docker(['rm', '-f', name]);
      } catch {}
      started = false;
    }
    rmSync(work, { recursive: true, force: true });
  };
  for (const signal of ['SIGINT', 'SIGTERM']) {
    process.once(signal, () => {
      cleanup();
      process.exit(130);
    });
  }

  try {
    const sa = password();
    const reader = password();
    const port = await freePort();
    console.error(`starting ${name} from ${image} on 127.0.0.1:${port}`);
    // Before the run: `docker run -d` creates the container before it starts it,
    // so a failed start still leaves one for cleanup to remove.
    started = true;
    docker(
      ['run', '-d', '--name', name, '--memory', '2g', '-e', 'ACCEPT_EULA=Y', '-e', 'MSSQL_SA_PASSWORD', '-e', 'MSSQL_MEMORY_LIMIT_MB=1536',
        '-p', `127.0.0.1:${port}:1433`, image],
      { ...process.env, MSSQL_SA_PASSWORD: sa },
    );
    const digest = docker(['image', 'inspect', '--format', '{{index .RepoDigests 0}}', image]);
    const lab = await Lab.open({ port, sa, reader });
    const lines = await runAll(lab, { image, digest, port, reader, work });
    await lab.close();

    const block = `${START}\n${lines.join('\n')}\n${END}`;
    const updated = doc.slice(0, doc.indexOf(START)) + block + doc.slice(doc.indexOf(END) + END.length);
    writeFileSync(docPath, updated);
    console.log(lines.join('\n'));
    console.error(`wrote the results to ${docPath}`);
    return 0;
  } catch (error) {
    console.error(`measure-read-safety: ${error.stack ?? error}`);
    return 1;
  } finally {
    cleanup();
  }
}

// Raw tedious sessions for setup, the writer, the sampler and the baselines.
class Lab {
  static async open({ port, sa, reader }) {
    const lab = new Lab(await tediousModule(), port, sa, reader);
    const deadline = Date.now() + 180_000;
    for (;;) {
      try {
        lab.admin = await lab.connect({ appName: 'measure-admin' });
        break;
      } catch (error) {
        if (Date.now() > deadline) throw new Error(`SQL Server did not accept a login within 180 s: ${error.message}`);
        await sleep(2_000);
      }
    }
    return lab;
  }

  constructor(tedious, port, sa, reader) {
    Object.assign(this, { tedious, port, sa, reader });
  }

  connect({ appName, database = 'master', user = 'sa', pass = this.sa } = {}) {
    const connection = new this.tedious.Connection({
      server: '127.0.0.1',
      authentication: { type: 'default', options: { userName: user, password: pass } },
      options: { port: this.port, database, appName, encrypt: true, trustServerCertificate: true, requestTimeout: 0,
        rowCollectionOnRequestCompletion: false, useColumnNames: false },
    });
    return new Promise((done, fail) => connection.connect((error) => (error ? fail(error) : done(connection))));
  }

  run(connection, sql) {
    return new Promise((done, fail) => {
      const rows = [];
      const request = new this.tedious.Request(sql, (error) => (error ? fail(error) : done(rows)));
      request.on('row', (columns) => rows.push(columns.map((column) => column.value)));
      connection.execSqlBatch(request);
    });
  }

  sql(sql) {
    return this.run(this.admin, sql);
  }

  // Open transactions held by sessions with this program name, after giving
  // a closed session time to end.
  async openTransactions(program) {
    let count;
    for (let i = 0; i < 20; i += 1) {
      [[count]] = await this.sql(`SELECT COUNT(*) FROM sys.dm_tran_session_transactions AS t
        JOIN sys.dm_exec_sessions AS s ON s.session_id = t.session_id WHERE s.program_name = N'${program}';`);
      if (count === 0) break;
      await sleep(100);
    }
    return count;
  }

  // Holds an exclusive row lock from a writer session until released.
  async holdRowLock(id = LOCKED_ID) {
    const writer = await this.connect({ appName: 'measure-writer', database: DB });
    await this.run(writer, `BEGIN TRAN; UPDATE dbo.items SET payload = REPLICATE(N'y', 100) WHERE id = ${id};`);
    let released = false;
    return async () => {
      if (released) return;
      released = true;
      await this.run(writer, 'ROLLBACK;');
      writer.close();
    };
  }

  // Samples requests and sessions of the given programs every interval until stopped.
  sampler(programs, intervalMs = 100) {
    const list = programs.map((program) => `N'${program}'`).join(', ');
    const samples = [];
    let stop = false;
    const done = (async () => {
      const connection = await this.connect({ appName: 'measure-sampler' });
      while (!stop) {
        const [[sessions, lockWaits, blocked]] = await this.run(connection, `SELECT
          (SELECT COUNT(*) FROM sys.dm_exec_sessions WHERE program_name = N'${APP_NAME}'),
          (SELECT COUNT(*) FROM sys.dm_exec_requests AS r JOIN sys.dm_exec_sessions AS s ON s.session_id = r.session_id
             WHERE s.program_name IN (${list}) AND r.wait_type LIKE N'LCK%'),
          (SELECT COUNT(*) FROM sys.dm_exec_requests AS r JOIN sys.dm_exec_sessions AS s ON s.session_id = r.session_id
             WHERE s.program_name IN (${list}) AND r.blocking_session_id <> 0);`);
        samples.push({ sessions, lockWaits, blocked });
        await sleep(intervalMs);
      }
      connection.close();
    })().catch((error) => error);
    return async () => {
      stop = true;
      const failure = await done;
      if (failure) throw failure;
      return {
        sessions: Math.max(0, ...samples.map((s) => s.sessions)),
        lockWaits: samples.filter((s) => s.lockWaits > 0).length,
        blocked: Math.max(0, ...samples.map((s) => s.blocked)),
      };
    };
  }

  close() {
    this.admin.close();
  }
}

function registration(lab, limits) {
  return {
    environment: 'local',
    server: '127.0.0.1',
    port: lab.port,
    databases: [DB],
    auth: { type: 'sql-login', user: { env: 'MEASURE_SQL_USER' }, password: { env: 'MEASURE_SQL_PASSWORD' } },
    limits,
  };
}

async function executorFor(lab, limits, options = {}) {
  return createTediousExecutor(registration(lab, limits), {
    driver: await trustingDriver(),
    env: { MEASURE_SQL_USER: READER_USER, MEASURE_SQL_PASSWORD: lab.reader },
    ...options,
  });
}

const outcome = (error) => {
  if (!error) return 'returned';
  if (error.number === 1222) return 'lock timeout (error 1222)';
  if (/request timeout/.test(error.message)) return 'request timeout';
  if (error.code === 'ECANCEL') return 'cancelled';
  return `error: ${String(error.message).split('\n')[0]}`;
};

// Runs a read through the executor while a writer holds a row lock it scans.
async function blockedRead(lab, limits, holdMs) {
  const release = await lab.holdRowLock();
  const stopSampler = lab.sampler([APP_NAME]);
  const releaser = setTimeout(release, holdMs);
  const executor = await executorFor(lab, limits);
  const began = now();
  let error;
  try {
    await executor.query({ database: DB, sql: SCAN });
  } catch (caught) {
    error = caught;
  }
  const blockedMs = Math.round(now() - began);
  clearTimeout(releaser);
  await release();
  // Sampled before close, so a connection wrongly kept in the pool still counts.
  const open = await lab.openTransactions(APP_NAME);
  await executor.close();
  const sample = await stopSampler();
  return { blockedMs, outcome: outcome(error), lockWaits: sample.lockWaits, open };
}

// A raw reader session inside a transaction, cancelled on the client side and
// kept open: what the discard rule guards against.
async function keptOpenAfterCancel(lab, xactAbort) {
  const release = await lab.holdRowLock();
  const connection = await lab.connect({ appName: BASELINE_APP, database: DB, user: READER_USER, pass: lab.reader });
  const cancel = setTimeout(() => connection.cancel(), 2_000);
  const began = now();
  let error;
  try {
    await lab.run(connection, `SET XACT_ABORT ${xactAbort ? 'ON' : 'OFF'}; BEGIN TRAN; ${SCAN}`);
  } catch (caught) {
    error = caught;
  }
  const blockedMs = Math.round(now() - began);
  clearTimeout(cancel);
  await release();
  const open = await lab.openTransactions(BASELINE_APP);
  connection.close();
  return { blockedMs, outcome: outcome(error), open };
}

// A statement that opens a transaction, sent past the reject list.
async function openedTransaction(lab, viaExecutor) {
  const sql = 'BEGIN TRAN; SELECT TOP (1) id FROM dbo.items;';
  if (!viaExecutor) {
    const connection = await lab.connect({ appName: BASELINE_APP, database: DB, user: READER_USER, pass: lab.reader });
    let error;
    try {
      await lab.run(connection, sql);
    } catch (caught) {
      error = caught;
    }
    const open = await lab.openTransactions(BASELINE_APP);
    connection.close();
    await lab.openTransactions(BASELINE_APP);
    return { outcome: outcome(error), open };
  }
  const executor = await executorFor(lab, DEFAULT_LIMITS);
  let error;
  try {
    await executor.query({ database: DB, sql });
  } catch (caught) {
    error = caught;
  }
  const open = await lab.openTransactions(APP_NAME);
  await executor.close();
  return { outcome: outcome(error), open };
}

// How long a writer waits on a reader transaction under each isolation level.
async function writerWaitUnder(lab, level, holdMs) {
  const reader = await lab.connect({ appName: BASELINE_APP, database: DB, user: READER_USER, pass: lab.reader });
  await lab.run(reader, `SET TRANSACTION ISOLATION LEVEL ${level}; BEGIN TRAN; SELECT COUNT(*) FROM dbo.items WHERE id <= 1000;`);
  const writer = await lab.connect({ appName: 'measure-writer', database: DB });
  let committed;
  const commit = setTimeout(() => {
    committed = lab.run(reader, 'COMMIT;');
  }, holdMs);
  const began = now();
  await lab.run(writer, `SET LOCK_TIMEOUT -1; UPDATE dbo.items SET payload = payload + N'' WHERE id = 500;`);
  const waitedMs = Math.round(now() - began);
  clearTimeout(commit);
  await (committed ?? lab.run(reader, 'COMMIT;'));
  reader.close();
  writer.close();
  return waitedMs;
}

async function cappedRead(lab, rowCap) {
  const executor = await executorFor(lab, { ...DEFAULT_LIMITS, requestTimeoutMs: 600_000, rowCap });
  const began = now();
  const result = await executor.query({ database: DB, sql: 'SELECT id, payload FROM dbo.items ORDER BY id;' });
  const ms = Math.round(now() - began);
  const open = await lab.openTransactions(APP_NAME);
  await executor.close();
  return { ms, rows: result.rowCount, truncated: result.truncated, open };
}

async function guardOverhead(lab) {
  const executor = await executorFor(lab, DEFAULT_LIMITS);
  const raw = await lab.connect({ appName: BASELINE_APP, database: DB, user: READER_USER, pass: lab.reader });
  const time = async (fn, n = 50) => {
    await fn();
    const began = now();
    for (let i = 0; i < n; i += 1) await fn();
    return (now() - began) / n;
  };
  const viaExecutor = await time(() => executor.query({ database: DB, sql: 'SELECT 1 AS one;' }));
  const viaRaw = await time(() => lab.run(raw, 'SELECT 1 AS one;'));
  await executor.close();
  raw.close();
  return { viaExecutor: viaExecutor.toFixed(2), viaRaw: viaRaw.toFixed(2) };
}

// One stdio server process: initialize, then `calls` concurrent query calls.
function serverProcess({ config, cwd, reader, calls, sql, children }) {
  const child = spawn(process.execPath, [SELF, '--serve', '--config', config, '--environment', 'local'], {
    cwd,
    env: { ...process.env, MEASURE_SQL_USER: READER_USER, MEASURE_SQL_PASSWORD: reader },
    stdio: ['pipe', 'pipe', 'pipe'],
  });
  children.push(child);
  let stderr = '';
  child.stderr.on('data', (chunk) => {
    stderr += chunk;
  });
  const pending = new Map();
  let buffer = '';
  child.stdout.on('data', (chunk) => {
    buffer += chunk;
    let newline;
    while ((newline = buffer.indexOf('\n')) >= 0) {
      const message = JSON.parse(buffer.slice(0, newline));
      buffer = buffer.slice(newline + 1);
      pending.get(message.id)?.(message);
    }
  });
  const exited = new Promise((done) => child.once('exit', done));
  const send = (id, method, params) =>
    new Promise((done) => {
      pending.set(id, done);
      child.stdin.write(`${JSON.stringify({ jsonrpc: '2.0', id, method, params })}\n`);
    });
  return (async () => {
    await send(0, 'initialize', { protocolVersion: '2025-06-18', capabilities: {}, clientInfo: { name: 'measure', version: '1' } });
    const latencies = await Promise.all(
      Array.from({ length: calls }, async (_, i) => {
        const began = now();
        const response = await send(i + 1, 'tools/call', { name: 'query', arguments: { sql } });
        if (response.error || response.result?.isError) {
          throw new Error(`a query call failed: ${JSON.stringify(response.error ?? response.result.content)} ${stderr}`);
        }
        return now() - began;
      }),
    );
    child.stdin.end();
    await exited;
    return latencies;
  })();
}

async function topology(lab, { work, reader }, processes) {
  const cwd = join(work, 'cwd');
  const configDir = join(work, 'config');
  mkdirSync(cwd, { recursive: true });
  mkdirSync(configDir, { recursive: true });
  const config = join(configDir, 'config.json');
  writeFileSync(config, JSON.stringify({
    schemaVersion: 1,
    environments: {
      local: {
        server: '127.0.0.1',
        port: lab.port,
        databases: [DB],
        auth: { type: 'sql-login', user: { env: 'MEASURE_SQL_USER' }, password: { env: 'MEASURE_SQL_PASSWORD' } },
      },
    },
  }));
  const sql = 'SELECT COUNT_BIG(*) AS n FROM dbo.items AS a CROSS JOIN (SELECT TOP (40) id FROM dbo.items) AS b WHERE (a.id + b.id) % 7 = 0;';

  // A writer updating single rows in autocommit throughout, timing each.
  const writer = await lab.connect({ appName: 'measure-writer', database: DB });
  let writing = true;
  const writes = [];
  let writerError;
  const writerLoop = (async () => {
    while (writing) {
      const began = now();
      await lab.run(writer, `UPDATE dbo.items SET payload = payload + N'' WHERE id = ${randomInt(1, ROWS + 1)};`);
      writes.push(now() - began);
      await sleep(20);
    }
  })().catch((error) => {
    writerError = error;
  });
  const stopSampler = lab.sampler([APP_NAME, 'measure-writer'], 50);
  const children = [];
  const began = now();
  let latencies;
  let wallMs;
  let sample;
  // A failed call must not leave server processes, the writer or the sampler running.
  try {
    latencies = (
      await Promise.all(Array.from({ length: processes }, () => serverProcess({ config, cwd, reader, calls: 4, sql, children })))
    ).flat();
    wallMs = Math.round(now() - began);
  } finally {
    for (const child of children) if (child.exitCode === null && child.signalCode === null) child.kill();
    writing = false;
    sample = await stopSampler();
    await writerLoop;
    writer.close();
  }
  if (writerError) throw writerError;
  latencies.sort((a, b) => a - b);
  return {
    processes,
    calls: latencies.length,
    peakSessions: sample.sessions,
    peakBlocked: sample.blocked,
    medianMs: Math.round(latencies[Math.floor(latencies.length / 2)]),
    maxMs: Math.round(latencies.at(-1)),
    wallMs,
    writerMaxMs: Math.round(Math.max(...writes)),
  };
}

async function setup(lab) {
  await lab.sql(`CREATE DATABASE ${DB};`);
  await lab.sql(`CREATE LOGIN ${READER_USER} WITH PASSWORD = N'${lab.reader}', CHECK_POLICY = OFF;`);
  await lab.sql(`USE ${DB};
    CREATE TABLE dbo.items (id int NOT NULL PRIMARY KEY, payload nvarchar(400) NOT NULL);
    WITH n AS (SELECT TOP (${ROWS}) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS id FROM sys.all_objects AS a CROSS JOIN sys.all_objects AS b)
    INSERT dbo.items (id, payload) SELECT id, REPLICATE(N'x', 100) FROM n;
    CREATE USER ${READER_USER} FOR LOGIN ${READER_USER};
    ALTER ROLE db_datareader ADD MEMBER ${READER_USER};
    USE master;`);
  const [[version]] = await lab.sql("SELECT CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(64)) + N' ' + CAST(SERVERPROPERTY('Edition') AS nvarchar(128));");
  const [[rcsi, adr, optimized]] = await lab.sql(`SELECT is_read_committed_snapshot_on, is_accelerated_database_recovery_on,
    CAST(DATABASEPROPERTYEX(N'${DB}', 'IsOptimizedLockingOn') AS int) FROM sys.databases WHERE name = N'${DB}';`);
  return { version, rcsi: Number(rcsi), adr: Number(adr), optimized: Number(optimized ?? 0) };
}

async function runAll(lab, { image, digest, reader, work }) {
  const env = await setup(lab);
  const out = [];
  const date = new Date().toISOString().slice(0, 10);
  const row = (...cells) => out.push(`| ${cells.join(' | ')} |`);
  const NO_TIMEOUT = 600_000;
  const HOLD = 8_000;

  out.push(`Run on ${date} by \`scripts/measure-read-safety.mjs\` against \`${image}\``);
  out.push(`(\`${digest.split('@')[1] ?? digest}\`), SQL Server ${env.version}, in a container capped at 2 GB.`);
  out.push(`Database \`${DB}\`: ${ROWS} rows; READ_COMMITTED_SNAPSHOT ${env.rcsi ? 'on' : 'off'},`);
  out.push(`accelerated database recovery ${env.adr ? 'on' : 'off'}, optimized locking ${env.optimized ? 'on' : 'off'}.`);
  out.push(`Reads run as \`${READER_USER}\`, a member of \`db_datareader\` only.`);

  console.error('read controls under a held row lock');
  out.push('', `### Read controls while a writer holds a row lock for ${HOLD} ms`, '');
  row('Reader', 'Lock timeout (ms)', 'Request timeout (ms)', 'Outcome', 'Blocked (ms)', 'Lock-wait samples', 'Open transactions after');
  row('---', '---', '---', '---', '---', '---', '---');
  const none = await blockedRead(lab, { ...DEFAULT_LIMITS, lockTimeoutMs: -1, requestTimeoutMs: NO_TIMEOUT }, HOLD);
  row('executor, no lock or request timeout', '-1', 'none', none.outcome, none.blockedMs, none.lockWaits, none.open);
  for (const lockTimeoutMs of [500, 1_000, 2_000, 5_000]) {
    const r = await blockedRead(lab, { ...DEFAULT_LIMITS, lockTimeoutMs, requestTimeoutMs: NO_TIMEOUT }, HOLD);
    row('executor, lock timeout only', lockTimeoutMs, 'none', r.outcome, r.blockedMs, r.lockWaits, r.open);
  }
  for (const requestTimeoutMs of [1_000, 3_000]) {
    const r = await blockedRead(lab, { ...DEFAULT_LIMITS, lockTimeoutMs: -1, requestTimeoutMs }, HOLD);
    row('executor, request timeout only', '-1', requestTimeoutMs, r.outcome, r.blockedMs, r.lockWaits, r.open);
  }
  for (const xactAbort of [false, true]) {
    const r = await keptOpenAfterCancel(lab, xactAbort);
    row(`raw session in BEGIN TRAN, XACT_ABORT ${xactAbort ? 'ON' : 'OFF'}, cancelled at 2000 ms, kept open`, '-1', '2000 (client cancel)', r.outcome, r.blockedMs, '-', r.open);
  }

  console.error('transaction left open by the statement');
  out.push('', '### A statement that opens a transaction (sent past the reject list)', '');
  row('Reader', 'Outcome', 'Open transactions after');
  row('---', '---', '---');
  const rawOpen = await openedTransaction(lab, false);
  row('raw session, connection kept', rawOpen.outcome, rawOpen.open);
  const execOpen = await openedTransaction(lab, true);
  row('executor (statement fails with error 266, connection discarded)', execOpen.outcome, execOpen.open);

  console.error('isolation');
  out.push('', '### Pinned isolation: writer wait on a reader transaction held 3000 ms', '');
  row('Reader isolation', 'Writer waited (ms)');
  row('---', '---');
  for (const level of ['READ COMMITTED', 'REPEATABLE READ', 'SERIALIZABLE']) row(level, await writerWaitUnder(lab, level, 3_000));

  console.error('row cap');
  out.push('', `### Row cap: \`SELECT id, payload\` over ${ROWS} rows, no contention`, '');
  row('Row cap', 'Rows returned', 'Truncated', 'Call (ms)', 'Open transactions after');
  row('---', '---', '---', '---', '---');
  for (const rowCap of [100, 1_000, 10_000, ROWS + 1]) {
    const r = await cappedRead(lab, rowCap);
    row(rowCap > ROWS ? 'none' : rowCap, r.rows, r.truncated, r.ms, r.open);
  }

  const overhead = await guardOverhead(lab);
  out.push('', `Guard overhead: a \`SELECT 1\` averages ${overhead.viaExecutor} ms through the executor (guard batch, statement,`);
  out.push(`\`@@TRANCOUNT\` check) and ${overhead.viaRaw} ms on a raw session, over 50 calls on a pooled connection.`);

  console.error('forced timeouts at the shipped defaults');
  const d = DEFAULT_LIMITS;
  out.push('', `### Forced timeouts at the shipped defaults (request ${d.requestTimeoutMs} ms, lock ${d.lockTimeoutMs} ms, row cap ${d.rowCap})`, '');
  const lockForced = await blockedRead(lab, d, d.lockTimeoutMs + 5_000);
  out.push(`- Writer holds a row lock ${d.lockTimeoutMs + 5_000} ms: ${lockForced.outcome} after ${lockForced.blockedMs} ms; open transactions after timeout: ${lockForced.open}`);
  const slow = await executorFor(lab, d);
  const began = now();
  let slowError;
  try {
    await slow.query({ database: DB, sql: 'SELECT COUNT_BIG(*) AS n FROM dbo.items AS a CROSS JOIN dbo.items AS b WHERE (a.id + b.id) % 7 = 0;' });
  } catch (caught) {
    slowError = caught;
  }
  const slowMs = Math.round(now() - began);
  const slowOpen = await lab.openTransactions(APP_NAME);
  await slow.close();
  out.push(`- A cross join that runs past the request timeout: ${outcome(slowError)} after ${slowMs} ms; open transactions after timeout: ${slowOpen}`);

  console.error('process topology');
  out.push('', `### Process topology: N stdio server processes, 4 concurrent \`query\` calls each, pool max ${POOL_MAX}, idle close ${IDLE_TIMEOUT_MS} ms`, '');
  out.push('A writer updates one random row in autocommit every 20 ms throughout.', '');
  row('Processes', 'Calls', 'Peak agent sessions', 'Peak blocked requests', 'Call median (ms)', 'Call max (ms)', 'Wall (ms)', 'Writer max (ms)');
  row('---', '---', '---', '---', '---', '---', '---', '---');
  for (const processes of [1, 2, 4, 8]) {
    const t = await topology(lab, { work, reader }, processes);
    row(t.processes, t.calls, t.peakSessions, t.peakBlocked, t.medianMs, t.maxMs, t.wallMs, t.writerMaxMs);
  }
  return out;
}

// Child mode: one stdio server process, as a registration launches it.
if (process.argv[2] === '--serve') {
  const { main } = await import('../src/main.mjs');
  const driver = await trustingDriver();
  process.exitCode = await main({ argv: process.argv.slice(3), createExecutor: (reg) => createTediousExecutor(reg, { driver }) });
} else {
  process.exitCode = await measure();
}
