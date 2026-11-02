import assert from 'node:assert/strict';
import { copyFileSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { after, describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';
import { ConfigError, loadConfig } from '../src/config.mjs';
import { compileSchema } from '../src/schema-validate.mjs';

const fixture = (name) => fileURLToPath(new URL(`./fixtures/${name}`, import.meta.url));
const projectDir = mkdtempSync(join(tmpdir(), 'sql-server-project-'));
after(() => rmSync(projectDir, { recursive: true, force: true }));

const load = (name) => loadConfig(fixture(name), { projectDir });
const refuses = (name, message) => assert.throws(() => load(name), (e) => e instanceof ConfigError && message.test(e.message));

describe('loadConfig accepts', () => {
  it('a sql-login environment whose credentials are named by environment variable', () => {
    const config = load('valid-sql-login.json');
    assert.deepEqual(config.environments.local.auth.password, { env: 'SQL_READER_PASSWORD' });
  });

  it('an entra-default environment with limit overrides', () => {
    assert.equal(load('valid-entra.json').environments['shared-dev'].limits.rowCap, 200);
  });

  it('a write block naming a separate write principal by reference', () => {
    assert.deepEqual(load('valid-write.json').environments.local.write.auth.password, { env: 'SQL_WRITER_PASSWORD' });
  });
});

describe('loadConfig refuses', () => {
  it('a literal password in place of an environment variable reference', () => {
    refuses('literal-password.json', /literal password/);
  });

  it('a password key=value pair inside any value', () => {
    refuses('literal-password-pair.json', /literal password/);
  });

  it('a literal connection string as a value', () => {
    refuses('literal-connection-string.json', /literal connection string/);
  });

  it('a connection string property', () => {
    refuses('connection-string-property.json', /literal connection string/);
  });

  it('an unknown schemaVersion', () => {
    refuses('unknown-schema-version.json', /unknown schemaVersion 2/);
  });

  it('an unknown property', () => {
    refuses('unknown-property.json', /\/environments\/local\/readOnly: unknown property/);
  });

  it('a --config path inside the project directory', () => {
    const nested = join(projectDir, 'config');
    mkdirSync(nested, { recursive: true });
    const inside = join(nested, 'sql-server.json');
    copyFileSync(fixture('valid-sql-login.json'), inside);
    assert.throws(
      () => loadConfig(inside, { projectDir }),
      (e) => e instanceof ConfigError && /inside the project directory/.test(e.message),
    );
  });

  it('a --config path that is the project directory itself', () => {
    assert.throws(() => loadConfig(projectDir, { projectDir }), /inside the project directory/);
  });

  it('a missing --config', () => {
    assert.throws(() => loadConfig('', { projectDir }), /--config <path> is required/);
  });

  it('malformed JSON, without quoting the file text', () => {
    const outside = mkdtempSync(join(tmpdir(), 'sql-server-config-'));
    try {
      const file = join(outside, 'broken.json');
      writeFileSync(file, '{ "auth": { "pwd": not-a-real-secret } }');
      assert.throws(
        () => loadConfig(file, { projectDir }),
        (e) => e instanceof ConfigError && /not valid JSON/.test(e.message) && !e.message.includes('not-a-real-secret'),
      );
    } finally {
      rmSync(outside, { recursive: true, force: true });
    }
  });
});

describe('compileSchema', () => {
  it('refuses a keyword it does not implement', () => {
    assert.throws(() => compileSchema({ type: 'object', if: { type: 'object' } }), /keyword if/);
  });

  it('does not treat inherited object members as declared properties', () => {
    const validate = compileSchema({ type: 'object', additionalProperties: false, properties: {} });
    assert.deepEqual(validate(JSON.parse('{"constructor": 1}')), ['/constructor: unknown property']);
  });
});
