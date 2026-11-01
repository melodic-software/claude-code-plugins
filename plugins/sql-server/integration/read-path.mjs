// Proves the read path against a real SQL Server: starts a local SQL Server
// Linux container (Developer edition), creates a read-only login and a second
// database, runs the plugin's stdio server on a registration confined to one
// database, and checks #5940's S1/S2, S5, S6 and S7. Prints one PASS or FAIL
// line per check on stdout, progress on stderr. Without Docker it prints
// "SKIP: docker not available" and exits 0.
//
// usage: node plugins/sql-server/integration/read-path.mjs
// needs: Docker, openssl, and the plugin's dependencies (npm ci --prefix plugins/sql-server)
import { spawn, spawnSync } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createInterface } from 'node:readline';
import { fileURLToPath } from 'node:url';
import { APP_NAME } from '../src/executor.mjs';
import { checkStatement } from '../src/statement.mjs';

const PLUGIN_ROOT = fileURLToPath(new URL('..', import.meta.url));
const IMAGE = 'mcr.microsoft.com/mssql/server:2022-latest';
const READER = 'mcp_reader';
const LOCK_TIMEOUT_MS = 4321;
const ROUNDS = 2;
const READY_TIMEOUT_MS = 240_000;
const CALL_TIMEOUT_MS = 60_000;

const log = (line) => process.stderr.write(`read-path: ${line}\n`);

// Each is sent through the query tool and must be refused, on every round. A
// write is also sent straight to the server as the read-only login, past the
// reject list, and the login must refuse it with a permission error.
const write = (label, sql) => ({ label, sql, write: true });
const setting = (label, sql) => ({ label, sql, write: false });
const ATTEMPTS = [
  write('INSERT', "INSERT INTO dbo.items (id, name) VALUES (99, N'x')"),
  write('UPDATE', "UPDATE dbo.items SET name = N'x'"),
  write('DELETE', 'DELETE FROM dbo.items'),
  write('MERGE', "MERGE dbo.items AS t USING (SELECT 99 AS id) AS s ON t.id = s.id WHEN NOT MATCHED THEN INSERT (id, name) VALUES (s.id, N'x');"),
  write('TRUNCATE', 'TRUNCATE TABLE dbo.items'),
  write('SELECT INTO', 'SELECT * INTO dbo.items_copy FROM dbo.items'),
  write('CREATE TABLE', 'CREATE TABLE dbo.made (id int)'),
  write('ALTER TABLE', 'ALTER TABLE dbo.items ADD extra int NULL'),
  write('DROP TABLE', 'DROP TABLE dbo.items'),
  write('DISABLE TRIGGER', 'DISABLE TRIGGER dbo.items_audit ON dbo.items'),
  write('CREATE USER', 'CREATE USER intruder WITHOUT LOGIN'),
  write('GRANT', 'GRANT INSERT ON dbo.items TO public'),
  write('EXEC', "EXEC sp_executesql N'DELETE FROM dbo.items'"),
  write('batch', 'SELECT 1 AS a; DELETE FROM dbo.items'),
  write('batch without a semicolon', 'SELECT 1 AS a DELETE FROM dbo.items'),
  write('batch behind a comment', 'SELECT 1 AS a /* x */; DROP TABLE dbo.items'),
  // A SELECT that writes: the reject list lets it through, so the login must refuse it.
  write('NEXT VALUE FOR', 'SELECT NEXT VALUE FOR dbo.counter AS n'),
  write('DBCC', 'DBCC FREEPROCCACHE'),
  setting('SET XACT_ABORT', 'SET XACT_ABORT OFF'),
  setting('SET LOCK_TIMEOUT', 'SET LOCK_TIMEOUT -1'),
  setting('SET TRANSACTION ISOLATION LEVEL', 'SET TRANSACTION ISOLATION LEVEL SERIALIZABLE'),
  setting('SET IMPLICIT_TRANSACTIONS', 'SET IMPLICIT_TRANSACTIONS ON'),
  setting('BEGIN TRANSACTION', 'BEGIN TRANSACTION'),
  setting('USE', 'USE other'),
  setting('lock hint', 'SELECT * FROM dbo.items WITH (TABLOCKX, HOLDLOCK)'),
  setting('OPTION clause', 'SELECT * FROM dbo.items OPTION (MAXDOP 1)'),
  setting('WAITFOR', "WAITFOR DELAY '00:00:01'"),
];

// A refusal for a missing grant names a permission; any other error (a parse
// error, a dropped connection) does not count as the login refusing.
const PERMISSION_REFUSAL = /permission/i;
const DATABASE_REFUSAL = /not able to access the database/i;

const SESSION_PROBE = `SELECT s.transaction_isolation_level AS isolation, s.lock_timeout AS lockTimeout,
  @@TRANCOUNT AS openTransactions, CAST(@@OPTIONS & 16384 AS int) AS xactAbort,
  CAST(@@OPTIONS & 2 AS int) AS implicitTransactions, DB_NAME() AS db, s.program_name AS app
FROM sys.dm_exec_sessions AS s WHERE s.session_id = @@SPID`;

const EXPECTED_SESSION = {
  isolation: 2, // READ COMMITTED
  lockTimeout: LOCK_TIMEOUT_MS,
  openTransactions: 0,
  xactAbort: 16384,
  implicitTransactions: 0,
  db: 'app',
  app: APP_NAME,
};

// Read as sa: what any write, DDL or grant would change.
const FINGERPRINT = `SELECT
  (SELECT COUNT(*) FROM app.sys.objects WHERE is_ms_shipped = 0) AS appObjects,
  (SELECT COUNT(*) FROM app.sys.columns AS c JOIN app.sys.objects AS o ON o.object_id = c.object_id WHERE o.is_ms_shipped = 0) AS appColumns,
  (SELECT COUNT(*) FROM app.dbo.items) AS itemRows,
  (SELECT CHECKSUM_AGG(CHECKSUM(id, name)) FROM app.dbo.items) AS itemChecksum,
  (SELECT CAST(current_value AS bigint) FROM app.sys.sequences WHERE name = N'counter') AS counter,
  (SELECT CAST(is_disabled AS int) FROM app.sys.triggers WHERE name = N'items_audit') AS triggerDisabled,
  (SELECT COUNT(*) FROM app.sys.database_principals) AS appPrincipals,
  (SELECT COUNT(*) FROM app.sys.database_role_members) AS appRoleMembers,
  (SELECT COUNT(*) FROM app.sys.database_permissions) AS appPermissions,
  (SELECT COUNT(*) FROM other.sys.objects WHERE is_ms_shipped = 0) AS otherObjects,
  (SELECT COUNT(*) FROM other.dbo.ledger) AS ledgerRows,
  (SELECT CHECKSUM_AGG(CHECKSUM(id, amount)) FROM other.dbo.ledger) AS ledgerChecksum,
  (SELECT COUNT(*) FROM sys.databases) AS databases,
  (SELECT COUNT(*) FROM sys.server_principals) AS logins;`;

class SetupError extends Error {}

function dockerAvailable() {
  const probe = spawnSync('docker', ['info', '--format', '{{.ServerVersion}}'], { stdio: 'ignore' });
  return probe.error === undefined && probe.status === 0;
}

function run(command, args, { env = process.env, quiet = false } = {}) {
  const result = spawnSync(command, args, { encoding: 'utf8', env, stdio: ['ignore', quiet ? 'pipe' : 2, 'pipe'] });
  if (result.error) throw new SetupError(`${command} could not start: ${result.error.message}`);
  if (result.status !== 0) throw new SetupError(`${command} ${args[0]} exited ${result.status}: ${result.stderr.trim()}`);
  return (result.stdout ?? '').trim();
}

// Meets SQL Server's default password policy: upper, lower, digit and symbol.
const newPassword = () => `${randomBytes(16).toString('hex')}Aa1!`;

async function loadTedious() {
  try {
    const module = await import('tedious');
    return module.default ?? module;
  } catch (error) {
    throw new SetupError(`cannot load tedious; run npm ci --prefix plugins/sql-server first (${error.message})`);
  }
}

// The container's certificate is self-signed for localhost, so the client
// trusts it explicitly: the sa connection through ca, the server through
// NODE_EXTRA_CA_CERTS. The plugin's executor keeps certificate checks on.
function writeTls(dir) {
  const tls = join(dir, 'tls');
  mkdirSync(tls);
  const cert = join(tls, 'cert.pem');
  const key = join(tls, 'key.pem');
  run('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048', '-subj', '/CN=localhost', '-addext', 'subjectAltName=DNS:localhost',
    '-keyout', key, '-out', cert, '-days', '1'], { quiet: true });
  const conf = join(tls, 'mssql.conf');
  writeFileSync(conf, '[network]\ntlscert = /opt/mssql-tls/cert.pem\ntlskey = /opt/mssql-tls/key.pem\ntlsprotocols = 1.2\nforceencryption = 1\n');
  // The container runs as the mssql user (uid 10001), not the host user; the
  // 0700 temp directory above keeps other host users out.
  chmodSync(tls, 0o755);
  for (const file of [cert, key, conf]) chmodSync(file, 0o444);
  return { tls, cert, conf };
}

function connect(tedious, { port, userName, password, ca, database = 'master' }) {
  const connection = new tedious.Connection({
    server: 'localhost',
    authentication: { type: 'default', options: { userName, password } },
    options: { port, database, encrypt: true, cryptoCredentialsDetails: { ca }, connectTimeout: 10_000, rowCollectionOnRequestCompletion: false },
  });
  connection.on('error', () => {});
  return new Promise((resolve, reject) => {
    connection.connect((error) => {
      if (error) {
        connection.close();
        reject(error);
      } else {
        resolve(connection);
      }
    });
  });
}

function batch(connection, tedious, sql) {
  return new Promise((resolve, reject) => {
    const result = { columns: [], rows: [] };
    const request = new tedious.Request(sql, (error) => (error ? reject(error) : resolve(result)));
    request.on('columnMetadata', (columns) => {
      result.columns = columns.map((column) => column.colName);
    });
    request.on('row', (row) => result.rows.push(row.map((column) => column.value)));
    connection.execSqlBatch(request);
  });
}

function containerLogs(container) {
  const logs = spawnSync('docker', ['logs', '--tail', '30', container], { encoding: 'utf8' });
  return `${logs.stdout ?? ''}${logs.stderr ?? ''}`.trim();
}

async function waitForServer(tedious, container, options) {
  const deadline = Date.now() + READY_TIMEOUT_MS;
  for (;;) {
    try {
      return await connect(tedious, options);
    } catch (error) {
      const state = spawnSync('docker', ['inspect', '--format', '{{.State.Running}}', container], { encoding: 'utf8' });
      if (state.stdout?.trim() !== 'true') throw new SetupError(`the container stopped:\n${containerLogs(container)}`);
      if (Date.now() > deadline) {
        throw new SetupError(`SQL Server did not accept the sa login within ${READY_TIMEOUT_MS / 1000} s: ${error.message}\n${containerLogs(container)}`);
      }
      await new Promise((resolve) => setTimeout(resolve, 2_000));
    }
  }
}

async function createFixtures(sa, tedious, readerPassword) {
  for (const sql of [
    `CREATE LOGIN [${READER}] WITH PASSWORD = N'${readerPassword}';`,
    'CREATE DATABASE [app];',
    'CREATE DATABASE [other];',
    'USE [app];',
    'CREATE TABLE dbo.items (id int NOT NULL PRIMARY KEY, name nvarchar(50) NOT NULL);',
    "INSERT INTO dbo.items (id, name) VALUES (1, N'one'), (2, N'two'), (3, N'three');",
    'CREATE SEQUENCE dbo.counter AS int START WITH 1 INCREMENT BY 1;',
    // After one use, current_value moves on any further NEXT VALUE FOR.
    'SELECT NEXT VALUE FOR dbo.counter;',
    'CREATE TRIGGER dbo.items_audit ON dbo.items AFTER INSERT AS SET NOCOUNT ON;',
    `CREATE USER [${READER}] FOR LOGIN [${READER}];`,
    `ALTER ROLE db_datareader ADD MEMBER [${READER}];`,
    'USE [other];',
    'CREATE TABLE dbo.ledger (id int NOT NULL PRIMARY KEY, amount int NOT NULL);',
    'INSERT INTO dbo.ledger (id, amount) VALUES (1, 100);',
    'USE [master];',
  ]) {
    await batch(sa, tedious, sql);
  }
}

// Read as sa between calls: a plugin session left holding a transaction.
const OPEN_PLUGIN_TRANSACTIONS = `SELECT COUNT(*) FROM sys.dm_exec_sessions
WHERE program_name = N'${APP_NAME.replaceAll("'", "''")}' AND open_transaction_count > 0;`;

async function openPluginTransactions(sa, tedious) {
  const { rows } = await batch(sa, tedious, OPEN_PLUGIN_TRANSACTIONS);
  return rows[0][0];
}

async function fingerprint(sa, tedious) {
  const { columns, rows } = await batch(sa, tedious, FINGERPRINT);
  return Object.fromEntries(columns.map((column, i) => [column, rows[0][i]]));
}

function changed(before, after) {
  return Object.keys(before)
    .filter((key) => before[key] !== after[key])
    .map((key) => `${key} ${JSON.stringify(before[key])} -> ${JSON.stringify(after[key])}`);
}

function startServer(registration, env) {
  const child = spawn(registration.command, registration.args, { cwd: PLUGIN_ROOT, env, stdio: ['pipe', 'pipe', 'pipe'] });
  const transcript = { stdout: '', stderr: '' };
  const pending = new Map();
  let nextId = 1;
  let gone;
  const exited = new Promise((resolve) => {
    child.once('close', (code) => {
      gone = new Error(`the server exited with code ${code}: ${transcript.stderr.trim()}`);
      for (const waiter of pending.values()) waiter.reject(gone);
      pending.clear();
      resolve();
    });
  });
  child.once('error', (error) => {
    gone = error;
  });
  child.stdin.on('error', () => {});
  child.stderr.setEncoding('utf8').on('data', (chunk) => {
    transcript.stderr += chunk;
  });
  createInterface({ input: child.stdout, crlfDelay: Infinity }).on('line', (line) => {
    transcript.stdout += `${line}\n`;
    let message;
    try {
      message = JSON.parse(line);
    } catch {
      return;
    }
    pending.get(message.id)?.resolve(message);
    pending.delete(message.id);
  });

  const send = (message) => child.stdin.write(`${JSON.stringify({ jsonrpc: '2.0', ...message })}\n`);

  function request(method, params = {}) {
    if (gone) return Promise.reject(gone);
    const id = nextId;
    nextId += 1;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        pending.delete(id);
        reject(new Error(`${method} got no answer within ${CALL_TIMEOUT_MS / 1000} s`));
      }, CALL_TIMEOUT_MS);
      const settle = (fn) => (value) => {
        clearTimeout(timer);
        fn(value);
      };
      pending.set(id, { resolve: settle(resolve), reject: settle(reject) });
      send({ id, method, params });
    });
  }

  async function stop() {
    child.stdin.end();
    const timer = setTimeout(() => child.kill('SIGKILL'), 10_000);
    await exited;
    clearTimeout(timer);
  }

  return { request, notify: (method, params = {}) => send({ method, params }), stop, transcript };
}

function pluginFiles(dir) {
  return readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    if (entry.name === 'node_modules') return [];
    const path = join(dir, entry.name);
    return entry.isDirectory() ? pluginFiles(path) : entry.isFile() ? [path] : [];
  });
}

async function main() {
  if (!dockerAvailable()) {
    console.log('SKIP: docker not available');
    return 0;
  }
  const failures = { 'S1/S2': [], S5: [], S6: [], S7: [] };
  const passes = {};
  const saPassword = newPassword();
  const readerPassword = newPassword();
  const container = `sql-server-read-path-${randomBytes(4).toString('hex')}`;
  const dir = mkdtempSync(join(tmpdir(), 'sql-server-read-path-'));
  let sa;
  let client;
  let tedious;
  const cleanup = () => {
    spawnSync('docker', ['rm', '--force', '--volumes', container], { stdio: 'ignore' });
    rmSync(dir, { recursive: true, force: true });
  };
  const interrupted = () => {
    cleanup();
    process.exit(130);
  };
  process.once('SIGINT', interrupted);
  process.once('SIGTERM', interrupted);

  try {
    tedious = await loadTedious();
    const { tls, cert, conf } = writeTls(dir);
    const ca = readFileSync(cert, 'utf8');

    if (spawnSync('docker', ['image', 'inspect', IMAGE], { stdio: 'ignore' }).status !== 0) {
      log(`pulling ${IMAGE}`);
      run('docker', ['pull', IMAGE]);
    }
    log(`starting ${container}`);
    // The sa password reaches docker through its environment, never its argv.
    run('docker', ['run', '--detach', '--name', container, '-e', 'ACCEPT_EULA=Y', '-e', 'MSSQL_PID=Developer', '-e', 'MSSQL_SA_PASSWORD',
      '-p', '127.0.0.1::1433', '-v', `${tls}:/opt/mssql-tls:ro`, '-v', `${conf}:/var/opt/mssql/mssql.conf`, IMAGE],
    { env: { ...process.env, MSSQL_SA_PASSWORD: saPassword }, quiet: true });
    const port = Number(run('docker', ['port', container, '1433/tcp'], { quiet: true }).split('\n')[0].split(':').at(-1));
    if (!Number.isInteger(port) || port <= 0) throw new SetupError(`cannot read the container's published port`);

    log(`waiting for SQL Server on 127.0.0.1:${port}`);
    sa = await waitForServer(tedious, container, { port, userName: 'sa', password: saPassword, ca });
    await createFixtures(sa, tedious, readerPassword);
    const before = await fingerprint(sa, tedious);
    if (before.itemRows !== 3 || before.ledgerRows !== 1) throw new SetupError(`the fixtures are not in place: ${JSON.stringify(before)}`);

    const configPath = join(dir, 'config.json');
    writeFileSync(configPath, `${JSON.stringify({
      schemaVersion: 1,
      defaults: { requestTimeoutMs: 20_000, lockTimeoutMs: LOCK_TIMEOUT_MS },
      environments: {
        local: {
          server: 'localhost',
          port,
          databases: ['app'],
          auth: { type: 'sql-login', user: { env: 'SQL_READ_PATH_USER' }, password: { env: 'SQL_READ_PATH_PASSWORD' } },
        },
      },
    }, null, 2)}\n`);
    // What a stdio registration stores: the command line, with credentials
    // left to the environment the client starts the server in.
    const registrationPath = join(dir, 'registration.json');
    const registration = {
      type: 'stdio',
      command: process.execPath,
      args: [join(PLUGIN_ROOT, 'src', 'launch.mjs'), '--config', configPath, '--environment', 'local'],
    };
    writeFileSync(registrationPath, `${JSON.stringify({ mcpServers: { 'sql-server-read-path': registration } }, null, 2)}\n`);

    client = startServer(registration, {
      ...process.env,
      SQL_READ_PATH_USER: READER,
      SQL_READ_PATH_PASSWORD: readerPassword,
      NODE_EXTRA_CA_CERTS: cert,
    });
    const init = await client.request('initialize', {
      protocolVersion: '2025-11-25',
      capabilities: {},
      clientInfo: { name: 'sql-server-read-path', version: '1.0.0' },
    });
    if (init.error) throw new SetupError(`initialize failed: ${init.error.message}`);
    client.notify('notifications/initialized');
    if (init.result.capabilities?.tools?.listChanged !== false) failures.S7.push('the tools capability does not declare listChanged false');

    const firstList = await client.request('tools/list');
    if (firstList.error) throw new SetupError(`tools/list failed: ${firstList.error.message}`);
    const baseline = JSON.stringify(firstList.result);
    const toolNames = firstList.result.tools.map((tool) => tool.name).join(', ');
    let toolCalls = 0;

    async function call(name, args) {
      const response = await client.request('tools/call', { name, arguments: args });
      toolCalls += 1;
      const listed = await client.request('tools/list');
      if (JSON.stringify(listed.result) !== baseline) failures.S7.push(`tools/list changed after ${name} ${JSON.stringify(args)}`);
      if (response.error) throw new Error(`tools/call ${name} returned a JSON-RPC error: ${response.error.message}`);
      return { isError: response.result.isError === true, text: response.result.content?.[0]?.text ?? '', data: response.result.structuredContent };
    }

    const rowsOf = ({ data }) => data.rows.map((row) => Object.fromEntries(data.columns.map((column, i) => [column, row[i]])));

    async function sessionDrift(after) {
      const probe = await call('query', { sql: SESSION_PROBE });
      if (probe.isError) return `the session probe failed after ${after}: ${probe.text}`;
      const [session] = rowsOf(probe);
      const wrong = Object.keys(EXPECTED_SESSION).filter((key) => session[key] !== EXPECTED_SESSION[key]);
      if (wrong.length === 0) return null;
      return `after ${after} the session had ${wrong.map((key) => `${key} ${JSON.stringify(session[key])}, not ${JSON.stringify(EXPECTED_SESSION[key])}`).join('; ')}`;
    }

    // A plain read must work, or every refusal below could be a broken connection.
    const read = await call('query', { sql: 'SELECT id, name FROM dbo.items ORDER BY id' });
    if (read.isError || read.data.rowCount !== 3) throw new SetupError(`the read-only login cannot run a plain SELECT: ${read.text}`);

    // S1/S2
    let byList = 0;
    let byLogin = 0;
    for (let round = 1; round <= ROUNDS; round += 1) {
      for (const { label, sql } of ATTEMPTS) {
        const outcome = await call('query', { sql });
        if (!outcome.isError) {
          failures['S1/S2'].push(`round ${round}: ${label} was not refused`);
        } else if (!checkStatement(sql).ok) {
          byList += 1;
        } else if (PERMISSION_REFUSAL.test(outcome.text)) {
          byLogin += 1;
        } else {
          failures['S1/S2'].push(`round ${round}: ${label} passed the reject list and failed without a permission refusal: ${outcome.text}`);
        }
        const drift = await sessionDrift(`${label} (round ${round})`);
        if (drift) failures['S1/S2'].push(drift);
        const open = await openPluginTransactions(sa, tedious);
        if (open !== 0) failures['S1/S2'].push(`after ${label} (round ${round}) ${open} plugin session(s) held an open transaction`);
      }
    }
    // The guarantee does not rest on the reject list: each write sent past it
    // must meet a permission refusal from the login itself.
    const writes = ATTEMPTS.filter((attempt) => attempt.write);
    const reader = await connect(tedious, { port, userName: READER, password: readerPassword, ca, database: 'app' });
    try {
      for (let round = 1; round <= ROUNDS; round += 1) {
        for (const { label, sql } of writes) {
          const error = await batch(reader, tedious, sql).then(() => undefined, (failure) => failure);
          if (error === undefined) {
            failures['S1/S2'].push(`round ${round}: ${label} ran for the read-only login past the reject list`);
          } else if (!PERMISSION_REFUSAL.test(error.message)) {
            failures['S1/S2'].push(`round ${round}: ${label}, sent past the reject list, failed without a permission refusal: ${error.message}`);
          }
        }
      }
    } finally {
      reader.close();
    }
    const afterWrites = await fingerprint(sa, tedious);
    for (const change of changed(before, afterWrites)) failures['S1/S2'].push(`the database changed: ${change}`);
    passes['S1/S2'] = `each of ${ATTEMPTS.length} write, DDL and session-state attempts through query was refused on all ${ROUNDS} rounds ` +
      `(${byList} by the reject list, ${byLogin} by a permission refusal), each of ${writes.length} writes sent past the reject list ` +
      `met a permission refusal, the data and schema are unchanged, every call ran with READ COMMITTED, XACT_ABORT ON and ` +
      `LOCK_TIMEOUT ${LOCK_TIMEOUT_MS}, and no plugin session held a transaction between calls`;

    // S5
    for (const [name, args] of [
      ['query', { sql: 'SELECT id FROM dbo.ledger', database: 'other' }],
      ['list_objects', { database: 'other' }],
      ['describe_object', { name: 'ledger', schema: 'dbo', database: 'other' }],
    ]) {
      const outcome = await call(name, args);
      if (!outcome.isError || !outcome.text.includes('allow-list')) {
        failures.S5.push(`${name} with database "other" was not refused by the allow-list: ${outcome.text}`);
      }
    }
    for (const sql of ['SELECT id, amount FROM other.dbo.ledger', 'SELECT name FROM other.sys.tables']) {
      const outcome = await call('query', { sql });
      if (!outcome.isError) failures.S5.push(`${sql} reached the second database`);
      else if (!DATABASE_REFUSAL.test(outcome.text)) failures.S5.push(`${sql} failed without the login being refused the database: ${outcome.text}`);
    }
    const listed = await call('list_objects', {});
    if (listed.isError) {
      failures.S5.push(`list_objects failed: ${listed.text}`);
    } else {
      const names = listed.data.objects.map((object) => object.name);
      if (!names.includes('items') || names.includes('ledger')) failures.S5.push(`list_objects returned ${names.join(', ')}`);
    }
    const afterScope = await fingerprint(sa, tedious);
    for (const change of changed(before, afterScope)) failures.S5.push(`the database changed: ${change}`);
    passes.S5 = 'the registration confined to app was refused the second database by the allow-list on every tool, ' +
      'and by the read-only login on three-part names';

    const { transcript } = client;
    await client.stop();
    client = undefined;

    // S6
    const secrets = [saPassword, readerPassword];
    const scanned = [configPath, registrationPath, conf, ...pluginFiles(PLUGIN_ROOT)];
    for (const file of scanned) {
      const text = readFileSync(file, 'utf8');
      if (secrets.some((secret) => text.includes(secret))) failures.S6.push(`${file} holds a password`);
    }
    for (const [stream, text] of Object.entries(transcript)) {
      if (secrets.some((secret) => text.includes(secret))) failures.S6.push(`the server's ${stream} holds a password`);
    }
    passes.S6 = `no password appears in the ${scanned.length} plugin, config and registration files or in the server's output`;

    // S7
    passes.S7 = `tools/list returned the same tools (${toolNames}) before and after each of ${toolCalls} tool calls, with listChanged false`;
  } catch (error) {
    console.log(`FAIL: ${error instanceof SetupError ? 'setup' : 'run'}: ${error.message}`);
    return 1;
  } finally {
    await client?.stop().catch(() => {});
    sa?.close();
    cleanup();
    process.off('SIGINT', interrupted);
    process.off('SIGTERM', interrupted);
  }

  let failed = false;
  for (const [check, problems] of Object.entries(failures)) {
    if (problems.length === 0) {
      console.log(`PASS: ${check} ${passes[check]}`);
    } else {
      failed = true;
      for (const problem of problems) console.log(`FAIL: ${check} ${problem}`);
    }
  }
  return failed ? 1 : 0;
}

process.exitCode = await main();
