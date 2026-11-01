import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { describe, it } from 'node:test';
import { APP_NAME, TRANCOUNT_CHECK, createTediousExecutor } from '../src/executor.mjs';

const tick = () => new Promise((resolve) => setImmediate(resolve));
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

const cancelError = () => Object.assign(new Error('Canceled.'), { code: 'ECANCEL' });

// A stand-in for the tedious module. Each statement the agent sends is answered
// by `answer(request, connection)`; the guard batch and the @@TRANCOUNT check
// are answered here, the check with `state.trancount`.
function fakeTedious({ answer = (request, connection) => connection.respond([{ one: 1 }]), connectError } = {}) {
  const state = { trancount: 0, connections: [] };

  class Request extends EventEmitter {
    constructor(sql, callback) {
      super();
      this.sql = sql;
      this.callback = callback;
      this.parameters = {};
    }

    addParameter(name, type, value) {
      this.parameters[name] = { type, value };
    }
  }

  class Connection extends EventEmitter {
    constructor(config) {
      super();
      this.config = config;
      this.log = [];
      this.cancels = 0;
      this.closed = false;
      this.began = false;
      this.current = null;
      state.connections.push(this);
    }

    connect(callback) {
      setImmediate(() => callback(connectError ?? null));
    }

    execSqlBatch(request) {
      this.start(request, 'batch');
    }

    execSql(request) {
      this.start(request, 'execSql');
    }

    start(request, kind) {
      assert.equal(this.current, null, 'tedious runs one request at a time per connection');
      this.log.push({ kind, sql: request.sql, parameters: request.parameters });
      this.current = request;
      setImmediate(() => {
        if (request.sql === TRANCOUNT_CHECK) this.respond([{ trancount: state.trancount }]);
        else if (kind === 'batch') this.finish();
        else answer(request, this);
      });
    }

    // Streams rows as the 'row' events tedious emits, stopping once cancelled.
    respond(rows) {
      const request = this.current;
      const names = Object.keys(rows[0] ?? {});
      request.emit('columnMetadata', names.map((colName) => ({ colName })));
      for (const row of rows) {
        if (request.canceled) return;
        request.emit('row', names.map((colName) => ({ value: row[colName], metadata: { colName } })));
      }
      this.finish();
    }

    finish(error = null) {
      const request = this.current;
      if (!request) return;
      this.current = null;
      request.callback(error, 0);
    }

    cancel() {
      this.cancels += 1;
      if (!this.current) return false;
      this.current.canceled = true;
      setImmediate(() => this.finish(cancelError()));
      return true;
    }

    beginTransaction() {
      this.began = true;
    }

    close() {
      this.closed = true;
      this.emit('end');
    }
  }

  return { driver: { Connection, Request, TYPES: { NVarChar: 'NVarChar' } }, state };
}

function registration(overrides = {}) {
  return {
    environment: 'local',
    server: 'localhost',
    port: 1433,
    databases: ['app', 'reporting'],
    auth: { type: 'sql-login', user: { env: 'SQL_READER_USER' }, password: { env: 'SQL_READER_PASSWORD' } },
    limits: { requestTimeoutMs: 1_000, lockTimeoutMs: 2_500, rowCap: 100 },
    ...overrides,
  };
}

const env = { SQL_READER_USER: 'reader', SQL_READER_PASSWORD: 'secret-value' };

function setup({ fake = fakeTedious(), reg = registration(), ...options } = {}) {
  const executor = createTediousExecutor(reg, { driver: fake.driver, env, ...options });
  return { executor, state: fake.state };
}

const sqlOf = (connection) => connection.log.map((entry) => entry.sql);

describe('the per-call guards', () => {
  it('opens each call with IF @@TRANCOUNT > 0 ROLLBACK, before the statement', async () => {
    const { executor, state } = setup();
    await executor.query({ database: 'app', sql: 'SELECT 1 AS one' });
    const [guard, statement] = state.connections[0].log;
    assert.equal(guard.kind, 'batch');
    assert.match(guard.sql, /^IF @@TRANCOUNT > 0 ROLLBACK;/);
    assert.equal(statement.sql, 'SELECT 1 AS one');
  });

  it('sets XACT_ABORT ON, READ COMMITTED and the configured LOCK_TIMEOUT in a plain batch', async () => {
    const { executor, state } = setup();
    await executor.query({ database: 'app', sql: 'SELECT 1 AS one' });
    const [guard] = state.connections[0].log;
    assert.equal(guard.kind, 'batch', 'a SET inside sp_executesql would revert when it returns');
    assert.match(guard.sql, /^SET XACT_ABORT ON;$/m);
    assert.match(guard.sql, /^SET TRANSACTION ISOLATION LEVEL READ COMMITTED;$/m);
    assert.match(guard.sql, /^SET LOCK_TIMEOUT 2500;$/m);
  });

  it('runs the statement in autocommit: no transaction opened and implicit transactions off', async () => {
    const { executor, state } = setup();
    await executor.query({ database: 'app', sql: 'SELECT 1 AS one' });
    const [connection] = state.connections;
    assert.equal(connection.began, false);
    assert.equal(connection.config.options.enableImplicitTransactions, false);
    assert.match(connection.log[0].sql, /^SET IMPLICIT_TRANSACTIONS OFF;$/m);
    assert.ok(sqlOf(connection).every((sql) => !/BEGIN\s+TRAN/i.test(sql)));
    assert.deepEqual(
      connection.log.map((entry) => entry.kind),
      ['batch', 'execSql', 'batch'],
    );
  });

  it('checks @@TRANCOUNT after the statement and reuses the connection when it is 0', async () => {
    const { executor, state } = setup();
    await executor.query({ database: 'app', sql: 'SELECT 1 AS one' });
    await executor.query({ database: 'app', sql: 'SELECT 2 AS two' });
    assert.equal(state.connections.length, 1);
    assert.equal(sqlOf(state.connections[0])[2], TRANCOUNT_CHECK);
    assert.equal(state.connections[0].closed, false);
  });

  it('discards the connection when @@TRANCOUNT is above 0 after the call', async () => {
    const { executor, state } = setup();
    state.trancount = 1;
    const result = await executor.query({ database: 'app', sql: 'SELECT 1 AS one' });
    assert.deepEqual(result.rows, [[1]]);
    assert.equal(state.connections[0].closed, true);
    state.trancount = 0;
    await executor.query({ database: 'app', sql: 'SELECT 1 AS one' });
    assert.equal(state.connections.length, 2);
  });
});

describe('the discard rule', () => {
  it('discards the connection after a timeout', async () => {
    const fake = fakeTedious({ answer: () => {} });
    const { executor, state } = setup({ fake, reg: registration({ limits: { requestTimeoutMs: 20, lockTimeoutMs: 0, rowCap: 10 } }) });
    await assert.rejects(executor.query({ database: 'app', sql: 'SELECT 1 AS one' }), /ran past the 20 ms request timeout/);
    assert.equal(state.connections[0].cancels, 1);
    assert.equal(state.connections[0].closed, true);
  });

  it('discards the connection after a cancel', async () => {
    const fake = fakeTedious({ answer: (request, connection) => connection.finish(cancelError()) });
    const { executor, state } = setup({ fake });
    await assert.rejects(executor.query({ database: 'app', sql: 'SELECT 1 AS one' }), { code: 'ECANCEL' });
    assert.equal(state.connections[0].closed, true);
  });

  it('discards the connection after an error, and the next call opens a fresh one', async () => {
    let fail = true;
    const fake = fakeTedious({
      answer: (request, connection) => (fail ? connection.finish(new Error("Invalid object name 'nope'.")) : connection.respond([{ one: 1 }])),
    });
    const { executor, state } = setup({ fake });
    await assert.rejects(executor.query({ database: 'app', sql: 'SELECT * FROM nope' }), /Invalid object name/);
    assert.equal(state.connections[0].closed, true);
    assert.ok(!sqlOf(state.connections[0]).includes(TRANCOUNT_CHECK));
    fail = false;
    await executor.query({ database: 'app', sql: 'SELECT 1 AS one' });
    assert.equal(state.connections.length, 2);
    assert.equal(state.connections[1].closed, false);
  });

  it('discards a connection the driver reported an error on, even after a clean call', async () => {
    const fake = fakeTedious({
      answer: (request, connection) => {
        connection.emit('error', new Error('socket hang up'));
        connection.respond([{ one: 1 }]);
      },
    });
    const { executor, state } = setup({ fake });
    await executor.query({ database: 'app', sql: 'SELECT 1 AS one' });
    assert.equal(state.connections[0].closed, true);
  });
});

describe('the pool', () => {
  it('opens at most two connections and queues a third call until one is free', async () => {
    const pending = [];
    const fake = fakeTedious({ answer: (request, connection) => pending.push(() => connection.respond([{ one: 1 }])) });
    const { executor, state } = setup({ fake });
    const calls = [1, 2, 3].map(() => executor.query({ database: 'app', sql: 'SELECT 1 AS one' }));
    while (pending.length < 2) await tick();
    await tick();
    assert.equal(state.connections.length, 2);
    pending.shift()();
    while (pending.length < 2) await tick();
    pending.splice(0).forEach((respond) => respond());
    await Promise.all(calls);
    assert.equal(state.connections.length, 2);
  });

  it('never hands out an idle connection the server has since ended', async () => {
    const { executor, state } = setup();
    await executor.query({ database: 'app', sql: 'SELECT 1 AS one' });
    state.connections[0].emit('end');
    await executor.query({ database: 'app', sql: 'SELECT 1 AS one' });
    assert.equal(state.connections.length, 2);
    assert.equal(state.connections[0].log.length, 3, 'the ended connection ran nothing more');
  });

  it('closes a connection once it has sat idle', async () => {
    const { executor, state } = setup({ idleTimeoutMs: 10 });
    await executor.query({ database: 'app', sql: 'SELECT 1 AS one' });
    assert.equal(state.connections[0].closed, false);
    await sleep(40);
    assert.equal(state.connections[0].closed, true);
  });

  it('opens a connection per database and closes every idle one on close', async () => {
    const { executor, state } = setup();
    await executor.query({ database: 'app', sql: 'SELECT 1 AS one' });
    await executor.query({ database: 'reporting', sql: 'SELECT 1 AS one' });
    assert.deepEqual(
      state.connections.map((connection) => connection.config.options.database),
      ['app', 'reporting'],
    );
    await executor.close();
    assert.ok(state.connections.every((connection) => connection.closed));
  });

  it('marks every session with the agent application name', async () => {
    const { executor, state } = setup();
    await executor.query({ database: 'app', sql: 'SELECT 1 AS one' });
    assert.equal(state.connections[0].config.options.appName, APP_NAME);
    assert.match(APP_NAME, /agent/);
  });
});

describe('auth', () => {
  it('sql-login reads the user and password from the named environment variables', async () => {
    const { executor, state } = setup();
    await executor.query({ database: 'app', sql: 'SELECT 1 AS one' });
    assert.deepEqual(state.connections[0].config.authentication, {
      type: 'default',
      options: { userName: 'reader', password: 'secret-value' },
    });
    assert.equal(state.connections[0].config.server, 'localhost');
    assert.equal(state.connections[0].config.options.port, 1433);
  });

  it('passes a named instance as instanceName, without the port', async () => {
    const { executor, state } = setup({ reg: registration({ server: 'db-host\\READER' }) });
    await executor.query({ database: 'app', sql: 'SELECT 1 AS one' });
    const { config } = state.connections[0];
    assert.equal(config.server, 'db-host');
    assert.equal(config.options.instanceName, 'READER');
    assert.equal(Object.hasOwn(config.options, 'port'), false);
  });

  it('sql-login names a missing variable, never a value, and opens no connection', async () => {
    const fake = fakeTedious();
    const executor = createTediousExecutor(registration(), { driver: fake.driver, env: { SQL_READER_USER: 'reader' } });
    await assert.rejects(executor.query({ database: 'app', sql: 'SELECT 1 AS one' }), /SQL_READER_PASSWORD is not set/);
    assert.equal(fake.state.connections.length, 0);
  });

  it('entra-default passes one token credential, built with the client id, to every connection', async () => {
    const built = [];
    const credential = { getToken: async () => ({ token: 't', expiresOnTimestamp: 0 }) };
    const { executor, state } = setup({
      reg: registration({ auth: { type: 'entra-default', clientId: '00000000-0000-0000-0000-000000000001' } }),
      createCredential: (clientId) => {
        built.push(clientId);
        return credential;
      },
    });
    await executor.query({ database: 'app', sql: 'SELECT 1 AS one' });
    await executor.query({ database: 'reporting', sql: 'SELECT 1 AS one' });
    assert.deepEqual(built, ['00000000-0000-0000-0000-000000000001']);
    for (const connection of state.connections) {
      assert.deepEqual(connection.config.authentication, { type: 'token-credential', options: { credential } });
    }
  });
});

describe('the request timeout and the row cap', () => {
  it('the request timeout cancels the request', async () => {
    const fake = fakeTedious({ answer: () => {} });
    const { executor, state } = setup({ fake, reg: registration({ limits: { requestTimeoutMs: 20, lockTimeoutMs: 0, rowCap: 10 } }) });
    await assert.rejects(executor.query({ database: 'app', sql: 'SELECT 1 AS one' }));
    assert.equal(state.connections[0].cancels, 1);
    assert.equal(state.connections[0].config.options.requestTimeout, 0, "the executor's timer owns the timeout");
  });

  it('the row cap cancels the request at the first row past it and returns the capped rows', async () => {
    const fake = fakeTedious({ answer: (request, connection) => connection.respond([1, 2, 3, 4, 5].map((n) => ({ n }))) });
    const { executor, state } = setup({ fake, reg: registration({ limits: { requestTimeoutMs: 1_000, lockTimeoutMs: 0, rowCap: 3 } }) });
    const result = await executor.query({ database: 'app', sql: 'SELECT n FROM t' });
    assert.deepEqual(result, { columns: ['n'], rows: [[1], [2], [3]], rowCount: 3, truncated: true });
    assert.equal(state.connections[0].cancels, 1);
    assert.equal(state.connections[0].closed, true, 'a cancelled connection is not reused');
  });

  it('a result of exactly the row cap is complete and cancels nothing', async () => {
    const fake = fakeTedious({ answer: (request, connection) => connection.respond([1, 2, 3].map((n) => ({ n }))) });
    const { executor, state } = setup({ fake, reg: registration({ limits: { requestTimeoutMs: 1_000, lockTimeoutMs: 0, rowCap: 3 } }) });
    const result = await executor.query({ database: 'app', sql: 'SELECT n FROM t' });
    assert.equal(result.truncated, false);
    assert.equal(state.connections[0].cancels, 0);
    assert.equal(state.connections[0].closed, false);
  });
});

describe('list_objects and describe_object', () => {
  it('list_objects passes the schema as a parameter and runs inside the same guards', async () => {
    const fake = fakeTedious({
      answer: (request, connection) =>
        connection.respond(/SCHEMATA/.test(request.sql) ? [{ schema: 'dbo' }] : [{ schema: 'dbo', name: 'orders', type: 'BASE TABLE' }]),
    });
    const { executor, state } = setup({ fake });
    const result = await executor.listObjects({ database: 'app', schema: 'dbo' });
    assert.deepEqual(result, { schemas: ['dbo'], objects: [{ schema: 'dbo', name: 'orders', type: 'BASE TABLE' }], truncated: false });
    const { log } = state.connections[0];
    assert.match(log[0].sql, /^IF @@TRANCOUNT > 0 ROLLBACK;/);
    assert.deepEqual(log[1].parameters, { schema: { type: 'NVarChar', value: 'dbo' } });
    assert.equal(log.at(-1).sql, TRANCOUNT_CHECK);
  });

  it('describe_object returns columns, keys and indexes, with a null schema when none is given', async () => {
    const fake = fakeTedious({
      answer: (request, connection) => {
        if (/INFORMATION_SCHEMA\.COLUMNS/.test(request.sql)) connection.respond([{ name: 'id', type: 'int' }]);
        else if (/TABLE_CONSTRAINTS/.test(request.sql)) connection.respond([{ name: 'pk_orders', type: 'PRIMARY KEY', column: 'id' }]);
        else connection.respond([{ name: 'pk_orders', type: 'CLUSTERED', unique: true, column: 'id', included: false }]);
      },
    });
    const { executor, state } = setup({ fake });
    const result = await executor.describeObject({ database: 'app', name: 'orders' });
    assert.deepEqual(result.columns, [{ name: 'id', type: 'int' }]);
    assert.equal(result.keys[0].type, 'PRIMARY KEY');
    assert.equal(result.indexes[0].type, 'CLUSTERED');
    assert.deepEqual(state.connections[0].log[1].parameters, {
      schema: { type: 'NVarChar', value: null },
      name: { type: 'NVarChar', value: 'orders' },
    });
  });

  it('describe_object refuses an object it cannot see', async () => {
    const fake = fakeTedious({ answer: (request, connection) => connection.respond([]) });
    const { executor } = setup({ fake });
    await assert.rejects(executor.describeObject({ database: 'app', schema: 'dbo', name: 'missing' }), /no table or view named dbo\.missing/);
  });
});
