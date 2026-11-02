import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { PassThrough } from 'node:stream';
import { after, describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';
import { ConfigError, loadConfig } from '../src/config.mjs';
import { main } from '../src/main.mjs';
import { UsageError, bindRegistration, parseRegistrationArgs } from '../src/registration.mjs';
import { ERROR_CODES, LEGACY_PROTOCOL_VERSION, PROTOCOL_VERSION, createServer, serveStdio } from '../src/server.mjs';
import { REQUIRES_USER_INTERACTION, WRITE_NOT_OPTED_IN } from '../src/tools.mjs';

const FIXED_TOOLS = ['query', 'list_objects', 'describe_object', 'preview_write', 'write'];
const DATABASES = ['app', 'reporting'];

function fakeExecutor() {
  const calls = [];
  const record = (method) => async (request) => {
    calls.push({ method, request });
    return { rows: [] };
  };
  return {
    calls,
    query: record('query'),
    listObjects: record('listObjects'),
    describeObject: record('describeObject'),
    previewWrite: record('previewWrite'),
    write: record('write'),
  };
}

// A stream may deliver a written chunk on a later tick; wait one turn.
const settle = () => new Promise((resolve) => setImmediate(resolve));

const modernMeta = { 'io.modelcontextprotocol/protocolVersion': PROTOCOL_VERSION, 'io.modelcontextprotocol/clientCapabilities': {} };

function setup({ writeExecutor } = {}) {
  const executor = fakeExecutor();
  const server = createServer({ databases: DATABASES, executor, writeExecutor });
  let nextId = 1;
  const request = (method, params, { modern = true } = {}) =>
    server.handle({ jsonrpc: '2.0', id: nextId++, method, params: modern ? { ...params, _meta: modernMeta } : params });
  const call = async (name, args, options) => (await request('tools/call', { name, arguments: args }, options)).result;
  return { executor, server, request, call };
}

describe('tools/list', () => {
  for (const modern of [true, false]) {
    it(`returns exactly the five fixed tools (${modern ? PROTOCOL_VERSION : LEGACY_PROTOCOL_VERSION})`, async () => {
      const { request } = setup();
      const { result } = await request('tools/list', {}, { modern });
      assert.deepEqual(
        result.tools.map((tool) => tool.name),
        FIXED_TOOLS,
      );
    });
  }

  it('returns the same list on repeated calls, before and after a tool call', async () => {
    const { request, call } = setup();
    const first = (await request('tools/list', {})).result.tools;
    await call('query', { sql: 'SELECT 1 AS one' });
    await call('query', { sql: 'DROP TABLE t' });
    const second = (await request('tools/list', {})).result.tools;
    const third = (await request('tools/list', {}, { modern: false })).result.tools;
    assert.deepEqual(second, first);
    assert.deepEqual(third, first);
  });

  it('gives every tool an object input schema that refuses unknown arguments', async () => {
    const { request } = setup();
    for (const tool of (await request('tools/list', {})).result.tools) {
      assert.equal(tool.inputSchema.type, 'object');
      assert.equal(tool.inputSchema.additionalProperties, false);
      assert.ok(tool.inputSchema.properties.database, `${tool.name} takes a database argument`);
    }
  });

  it('lists the same tools whether or not the registration opted in to writes', async () => {
    const readOnly = (await setup().request('tools/list', {})).result.tools;
    const optedIn = (await setup({ writeExecutor: fakeExecutor() }).request('tools/list', {})).result.tools;
    assert.deepEqual(optedIn, readOnly);
  });
});

describe('the per-call approval flag', () => {
  const listed = async () => (await setup().request('tools/list', {})).result.tools;

  it('marks the write tool requiresUserInteraction with the JSON Boolean true', async () => {
    const write = (await listed()).find((tool) => tool.name === 'write');
    assert.equal(write._meta[REQUIRES_USER_INTERACTION], true);
  });

  for (const name of ['query', 'list_objects', 'describe_object', 'preview_write']) {
    it(`leaves the read tool ${name} unflagged`, async () => {
      const tool = (await listed()).find((candidate) => candidate.name === name);
      assert.equal(tool._meta?.[REQUIRES_USER_INTERACTION], undefined);
    });
  }
});

describe('the write tool', () => {
  it('is refused without opt-in, before any executor is called', async () => {
    const { executor, call } = setup();
    for (const modern of [true, false]) {
      const result = await call('write', { sql: 'DELETE FROM orders WHERE id = 1', expectedRows: 1 }, { modern });
      assert.equal(result.isError, true);
      assert.equal(result.content[0].text, WRITE_NOT_OPTED_IN);
    }
    assert.deepEqual(executor.calls, []);
  });

  it('is refused without opt-in even when its arguments are wrong', async () => {
    const { call } = setup();
    const result = await call('write', { sql: 'DROP TABLE orders' });
    assert.equal(result.content[0].text, WRITE_NOT_OPTED_IN);
  });

  it('runs on the write executor, never the read one, with a terminated statement', async () => {
    const writeExecutor = fakeExecutor();
    const { executor, call } = setup({ writeExecutor });
    const result = await call('write', { sql: 'UPDATE orders SET status = 1 WHERE id = 7', expectedRows: 1, database: 'reporting' });
    assert.equal(result.isError, false);
    assert.deepEqual(executor.calls, []);
    assert.deepEqual(writeExecutor.calls, [
      { method: 'write', request: { database: 'reporting', sql: 'UPDATE orders SET status = 1 WHERE id = 7\n;', expectedRows: 1 } },
    ]);
  });

  it('passes a statement that already ends in a semicolon through unchanged', async () => {
    const writeExecutor = fakeExecutor();
    const { call } = setup({ writeExecutor });
    await call('write', { sql: 'DELETE FROM orders WHERE id = 7;', expectedRows: 0 });
    assert.equal(writeExecutor.calls[0].request.sql, 'DELETE FROM orders WHERE id = 7;');
  });

  for (const sql of ['SELECT 1 AS one', 'DELETE FROM a; DELETE FROM b', 'UPDATE t SET a = 1 COMMIT', 'TRUNCATE TABLE orders']) {
    it(`refuses through the write reject list: ${sql}`, async () => {
      const writeExecutor = fakeExecutor();
      const { call } = setup({ writeExecutor });
      const result = await call('write', { sql, expectedRows: 1 });
      assert.equal(result.isError, true);
      assert.match(result.content[0].text, /^the write reject list refused the statement: \S/);
      assert.deepEqual(writeExecutor.calls, []);
    });
  }

  for (const expectedRows of [-1, 1.5, '1', 2_147_483_648]) {
    it(`refuses expectedRows ${JSON.stringify(expectedRows)}`, async () => {
      const writeExecutor = fakeExecutor();
      const { call } = setup({ writeExecutor });
      const result = await call('write', { sql: 'DELETE FROM orders', expectedRows });
      assert.equal(result.isError, true);
      assert.match(result.content[0].text, /expectedRows must be a non-negative integer/);
      assert.deepEqual(writeExecutor.calls, []);
    });
  }

  it('refuses a database outside the allow-list', async () => {
    const writeExecutor = fakeExecutor();
    const { call } = setup({ writeExecutor });
    const result = await call('write', { sql: 'DELETE FROM orders', expectedRows: 1, database: 'master' });
    assert.match(result.content[0].text, /"master" is not in this registration's allow-list/);
    assert.deepEqual(writeExecutor.calls, []);
  });

  it('reports a rolled-back batch as a tool error', async () => {
    const writeExecutor = fakeExecutor();
    writeExecutor.write = async () => {
      throw new Error('rolled back: the statement affected 3 rows, not the expected 1');
    };
    const { call } = setup({ writeExecutor });
    const result = await call('write', { sql: 'DELETE FROM orders', expectedRows: 1 });
    assert.equal(result.isError, true);
    assert.equal(result.content[0].text, 'the write call failed: rolled back: the statement affected 3 rows, not the expected 1');
  });
});

describe('the preview_write tool', () => {
  it('runs on the read executor, opted in or not', async () => {
    const { executor, call } = setup();
    const result = await call('preview_write', { schema: 'sales', name: 'orders' });
    assert.equal(result.isError, false);
    assert.deepEqual(executor.calls, [{ method: 'previewWrite', request: { database: 'app', schema: 'sales', name: 'orders' } }]);
  });
});

describe('the tools capability', () => {
  it('declares listChanged false in server/discover', async () => {
    const { request } = setup();
    const { result } = await request('server/discover', {});
    assert.equal(result.resultType, 'complete');
    assert.deepEqual(result.capabilities.tools, { listChanged: false });
    assert.ok(result.supportedVersions.includes(PROTOCOL_VERSION));
  });

  it('declares listChanged false in the legacy initialize result', async () => {
    const { request } = setup();
    const { result } = await request('initialize', { protocolVersion: LEGACY_PROTOCOL_VERSION, capabilities: {} }, { modern: false });
    assert.equal(result.protocolVersion, LEGACY_PROTOCOL_VERSION);
    assert.deepEqual(result.capabilities.tools, { listChanged: false });
  });
});

describe('the database allow-list', () => {
  const calls = [
    ['query', { sql: 'SELECT 1 AS one' }],
    ['list_objects', {}],
    ['describe_object', { name: 'orders' }],
  ];

  for (const [name, args] of calls) {
    it(`refuses a database outside the list before the executor is called (${name})`, async () => {
      const { executor, call } = setup();
      const result = await call(name, { ...args, database: 'master' });
      assert.equal(result.isError, true);
      assert.match(result.content[0].text, /"master" is not in this registration's allow-list/);
      assert.deepEqual(executor.calls, []);
    });

    it(`uses the first allowed database when database is omitted (${name})`, async () => {
      const { executor, call } = setup();
      const result = await call(name, args);
      assert.equal(result.isError, false);
      assert.equal(executor.calls.length, 1);
      assert.equal(executor.calls[0].request.database, 'app');
    });
  }

  it('passes an allowed database through', async () => {
    const { executor, call } = setup();
    await call('describe_object', { database: 'reporting', schema: 'sales', name: 'orders' });
    assert.deepEqual(executor.calls, [
      { method: 'describeObject', request: { database: 'reporting', schema: 'sales', name: 'orders' } },
    ]);
  });
});

describe('the reject list on query', () => {
  for (const sql of ['DELETE FROM orders', 'SELECT 1 AS a; SELECT 2 AS b', 'SELECT * INTO copy FROM orders', 'SELECT * FROM t WITH (TABLOCKX)']) {
    it(`reaches the client as a tool error: ${sql}`, async () => {
      const { executor, call } = setup();
      const result = await call('query', { sql });
      assert.equal(result.isError, true);
      assert.match(result.content[0].text, /^the reject list refused the statement: \S/);
      assert.deepEqual(executor.calls, []);
    });
  }

  it('reaches a legacy client as a tool error too', async () => {
    const { call } = setup();
    const result = await call('query', { sql: 'EXEC sp_who' }, { modern: false });
    assert.equal(result.isError, true);
    assert.match(result.content[0].text, /EXEC is not allowed|only a SELECT/);
  });

  it('lets one SELECT through to the executor and returns its result', async () => {
    const { executor, call } = setup();
    const result = await call('query', { sql: 'WITH c AS (SELECT 1 AS n) SELECT n FROM c' });
    assert.equal(result.resultType, 'complete');
    assert.equal(result.isError, false);
    assert.deepEqual(result.structuredContent, { rows: [] });
    assert.deepEqual(JSON.parse(result.content[0].text), { rows: [] });
    assert.deepEqual(executor.calls, [{ method: 'query', request: { database: 'app', sql: 'WITH c AS (SELECT 1 AS n) SELECT n FROM c' } }]);
  });
});

describe('tool argument and protocol errors', () => {
  it('refuses an unknown tool as a protocol error', async () => {
    const { request } = setup();
    const response = await request('tools/call', { name: 'connect', arguments: {} });
    assert.equal(response.error.code, ERROR_CODES.invalidParams);
    assert.match(response.error.message, /Unknown tool: connect/);
  });

  it('refuses an argument no tool declares, such as a server name', async () => {
    const { executor, call } = setup();
    const result = await call('query', { sql: 'SELECT 1 AS one', server: 'other-host' });
    assert.equal(result.isError, true);
    assert.match(result.content[0].text, /takes no argument named server/);
    assert.deepEqual(executor.calls, []);
  });

  it('refuses a missing required argument', async () => {
    const { call } = setup();
    const result = await call('describe_object', {});
    assert.equal(result.isError, true);
    assert.match(result.content[0].text, /needs the name argument/);
  });

  it('reports an executor failure as a tool error', async () => {
    const executor = fakeExecutor();
    executor.query = async () => {
      throw new Error('login failed');
    };
    const server = createServer({ databases: DATABASES, executor });
    const { result } = await server.handle({
      jsonrpc: '2.0',
      id: 1,
      method: 'tools/call',
      params: { name: 'query', arguments: { sql: 'SELECT 1 AS one' }, _meta: modernMeta },
    });
    assert.equal(result.isError, true);
    assert.equal(result.content[0].text, 'the query call failed: login failed');
  });

  it('answers an unsupported protocol version with the versions it supports', async () => {
    const { server } = setup();
    const response = await server.handle({
      jsonrpc: '2.0',
      id: 1,
      method: 'tools/list',
      params: { _meta: { ...modernMeta, 'io.modelcontextprotocol/protocolVersion': '1900-01-01' } },
    });
    assert.equal(response.error.code, ERROR_CODES.unsupportedProtocolVersion);
    assert.deepEqual(response.error.data, { supported: [PROTOCOL_VERSION, LEGACY_PROTOCOL_VERSION], requested: '1900-01-01' });
  });

  it('refuses a modern request whose _meta lacks clientCapabilities', async () => {
    const { server } = setup();
    const response = await server.handle({
      jsonrpc: '2.0',
      id: 1,
      method: 'tools/list',
      params: { _meta: { 'io.modelcontextprotocol/protocolVersion': PROTOCOL_VERSION } },
    });
    assert.equal(response.error.code, ERROR_CODES.invalidParams);
  });

  it('sends no response to a notification', async () => {
    const { server } = setup();
    assert.equal(await server.handle({ jsonrpc: '2.0', method: 'notifications/initialized' }), null);
  });

  it('answers an unknown method with method not found', async () => {
    const { request } = setup();
    assert.equal((await request('resources/list', {})).error.code, ERROR_CODES.methodNotFound);
  });
});

describe('serveStdio', () => {
  it('answers one line per request and none for a notification, then resolves when input ends', async () => {
    const { server } = setup();
    const input = new PassThrough();
    const output = new PassThrough();
    const chunks = [];
    output.on('data', (chunk) => chunks.push(chunk));
    const done = serveStdio(server, { input, output });
    input.write(`${JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: LEGACY_PROTOCOL_VERSION } })}\n`);
    input.write(`${JSON.stringify({ jsonrpc: '2.0', method: 'notifications/initialized' })}\n`);
    input.write(`${JSON.stringify({ jsonrpc: '2.0', id: 2, method: 'tools/list' })}\n`);
    input.write('not json\n');
    input.end();
    await done;
    await settle();
    const responses = Buffer.concat(chunks)
      .toString('utf8')
      .trimEnd()
      .split('\n')
      .map((line) => JSON.parse(line));
    assert.equal(responses.length, 3);
    const byId = new Map(responses.map((response) => [response.id, response]));
    assert.equal(byId.get(1).result.protocolVersion, LEGACY_PROTOCOL_VERSION);
    assert.deepEqual(
      byId.get(2).result.tools.map((tool) => tool.name),
      FIXED_TOOLS,
    );
    assert.equal(byId.get(null).error.code, ERROR_CODES.parse);
  });
});

describe('the registration', () => {
  const fixture = (name) => fileURLToPath(new URL(`./fixtures/${name}`, import.meta.url));
  const projectDir = mkdtempSync(join(tmpdir(), 'sql-server-project-'));
  after(() => rmSync(projectDir, { recursive: true, force: true }));

  it('reads --config and --environment', () => {
    assert.deepEqual(parseRegistrationArgs(['--config', '/etc/sql.json', '--environment', 'local']), {
      configPath: '/etc/sql.json',
      environment: 'local',
      write: false,
    });
  });

  it('reads --write as the opt-in to writes', () => {
    assert.equal(parseRegistrationArgs(['--config', '/etc/sql.json', '--environment', 'local', '--write']).write, true);
    assert.throws(() => parseRegistrationArgs(['--config', 'a', '--environment', 'b', '--write=yes']), UsageError);
  });

  it('binds the write principal only with --write', () => {
    const config = loadConfig(fixture('valid-write.json'), { projectDir });
    assert.equal(bindRegistration(config, 'local').write, undefined);
    const registration = bindRegistration(config, 'local', { write: true });
    assert.deepEqual(registration.write.auth.user, { env: 'SQL_WRITER_USER' });
    assert.deepEqual(registration.auth.user, { env: 'SQL_READER_USER' });
  });

  it('refuses --write on an environment with no write principal, or one that reuses the read principal', () => {
    const config = loadConfig(fixture('valid-write.json'), { projectDir });
    assert.throws(() => bindRegistration(config, 'read-only', { write: true }), (e) => e instanceof ConfigError && /--write needs a write principal/.test(e.message));
    assert.throws(() => bindRegistration(config, 'same-principal', { write: true }), (e) => e instanceof ConfigError && /must be a separate login/.test(e.message));
  });

  it('gives a --write registration a second executor bound to the write principal', async () => {
    const created = [];
    const input = new PassThrough();
    const output = new PassThrough();
    const running = main({
      argv: ['--config', fixture('valid-write.json'), '--environment', 'local', '--write'],
      createExecutor: (registration) => {
        const executor = fakeExecutor();
        created.push({ registration, executor });
        return executor;
      },
      input,
      output,
      projectDir,
    });
    const params = { name: 'write', arguments: { sql: 'DELETE FROM orders WHERE id = 1', expectedRows: 1 } };
    input.end(`${JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'tools/call', params })}\n`);
    assert.equal(await running, 0);
    assert.deepEqual(
      created.map(({ registration }) => registration.auth.user.env),
      ['SQL_READER_USER', 'SQL_WRITER_USER'],
    );
    assert.deepEqual(created[0].executor.calls, []);
    assert.equal(created[1].executor.calls[0].method, 'write');
  });

  it('gives a registration without --write no write executor, so its write tool refuses', async () => {
    const created = [];
    const input = new PassThrough();
    const output = new PassThrough();
    const chunks = [];
    output.on('data', (chunk) => chunks.push(chunk));
    const running = main({
      argv: ['--config', fixture('valid-write.json'), '--environment', 'local'],
      createExecutor: (registration) => {
        created.push(registration);
        return fakeExecutor();
      },
      input,
      output,
      projectDir,
    });
    const params = { name: 'write', arguments: { sql: 'DELETE FROM orders WHERE id = 1', expectedRows: 1 } };
    input.end(`${JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'tools/call', params })}\n`);
    assert.equal(await running, 0);
    await settle();
    assert.equal(created.length, 1);
    assert.equal(JSON.parse(Buffer.concat(chunks).toString('utf8')).result.content[0].text, WRITE_NOT_OPTED_IN);
  });

  it('refuses a missing --environment and any other argument', () => {
    assert.throws(() => parseRegistrationArgs(['--config', '/etc/sql.json']), (e) => e instanceof UsageError && /--environment is required/.test(e.message));
    assert.throws(() => parseRegistrationArgs(['--config', 'a', '--environment', 'b', '--server', 'c']), UsageError);
    assert.throws(() => parseRegistrationArgs(['--config', 'a', '--environment', 'b', 'extra']), UsageError);
  });

  it('binds one environment, its database allow-list and its limits', () => {
    const registration = bindRegistration(loadConfig(fixture('valid-entra.json'), { projectDir }), 'shared-dev');
    assert.deepEqual(registration.databases, ['app']);
    assert.equal(registration.server, 'example-dev.database.windows.net');
    assert.equal(registration.limits.rowCap, 200);
  });

  it('refuses an environment the config does not name', () => {
    const config = loadConfig(fixture('valid-entra.json'), { projectDir });
    assert.throws(() => bindRegistration(config, 'prod'), (e) => e instanceof ConfigError && /it names: shared-dev/.test(e.message));
  });

  it('exits 2 with the reason on stderr when the registration cannot bind', async () => {
    const stderr = new PassThrough();
    let text = '';
    stderr.on('data', (chunk) => {
      text += chunk;
    });
    const code = await main({ argv: ['--config', fixture('valid-entra.json'), '--environment', 'prod'], stderr, projectDir });
    await settle();
    assert.equal(code, 2);
    assert.match(text, /--environment prod is not in the config/);
  });

  it('serves the bound allow-list over stdio and closes the executor when input ends', async () => {
    const executor = fakeExecutor();
    let closed = false;
    executor.close = async () => {
      closed = true;
    };
    const input = new PassThrough();
    const output = new PassThrough();
    const chunks = [];
    output.on('data', (chunk) => chunks.push(chunk));
    const running = main({
      argv: ['--config', fixture('valid-entra.json'), '--environment', 'shared-dev'],
      createExecutor: () => executor,
      input,
      output,
      projectDir,
    });
    input.end(`${JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'tools/call', params: { name: 'list_objects', arguments: {} } })}\n`);
    assert.equal(await running, 0);
    await settle();
    assert.equal(closed, true);
    assert.deepEqual(executor.calls, [{ method: 'listObjects', request: { database: 'app' } }]);
    assert.equal(JSON.parse(Buffer.concat(chunks).toString('utf8')).result.isError, false);
  });
});
