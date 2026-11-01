import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { after, describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';

const pluginFile = (path) => fileURLToPath(new URL(`../${path}`, import.meta.url));
const SCRIPT = pluginFile('skills/setup/scripts/check-setup.mjs');
const { version } = JSON.parse(readFileSync(pluginFile('.claude-plugin/plugin.json'), 'utf8'));

const projectDir = mkdtempSync(join(tmpdir(), 'sql-server-setup-project-'));
const outside = mkdtempSync(join(tmpdir(), 'sql-server-setup-config-'));
after(() => {
  rmSync(projectDir, { recursive: true, force: true });
  rmSync(outside, { recursive: true, force: true });
});

const writeConfig = (name, text) => {
  const file = join(outside, name);
  writeFileSync(file, text);
  return file;
};
const check = (...args) =>
  spawnSync(process.execPath, [SCRIPT, ...args], {
    cwd: projectDir,
    encoding: 'utf8',
    env: { PATH: process.env.PATH, SQL_READER_USER: 'reader' },
  });

// Every config example the docs show, so a doc edit that breaks one fails here.
const DOCS = ['README.md', 'reference/azure-sql-database.md'];
const examples = DOCS.flatMap((doc) =>
  [...readFileSync(pluginFile(doc), 'utf8').matchAll(/```json\n([\s\S]*?)```/g)]
    .map((match) => match[1])
    .filter((text) => text.includes('"schemaVersion"'))
    .map((text, i) => ({ doc, i, text })),
);

describe('check-setup.mjs', () => {
  it('finds a config example in each doc', () => {
    assert.deepEqual([...new Set(examples.map((e) => e.doc))], DOCS);
  });

  for (const { doc, i, text } of examples) {
    it(`passes the config example ${i + 1} in ${doc}`, () => {
      const result = check('--config', writeConfig(`example-${i}-${doc.replaceAll('/', '-')}`, text));
      assert.equal(result.status, 0, result.stdout + result.stderr);
      assert.match(result.stdout, /^PASS {2}config: /m);
      assert.match(result.stdout, /^PASS {2}environment /m);
    });
  }

  it('fails a config with a literal password, without printing it', () => {
    const fixture = readFileSync(pluginFile('test/fixtures/literal-password.json'), 'utf8');
    const result = check('--config', writeConfig('literal-password.json', fixture));
    assert.equal(result.status, 1);
    assert.match(result.stdout, /^FAIL {2}config: .*literal password/m);
    assert.ok(!result.stdout.includes('not-a-real-secret'));
  });

  it('fails an environment the config does not name', () => {
    const file = writeConfig('valid.json', examples[0].text);
    const result = check('--config', file, '--environment', 'missing');
    assert.equal(result.status, 1);
    assert.match(result.stdout, /^FAIL {2}environment missing: /m);
  });

  it('prints a registration that names credentials by reference', () => {
    const fixture = readFileSync(pluginFile('test/fixtures/valid-sql-login.json'), 'utf8');
    const dataDir = mkdtempSync(join(tmpdir(), 'sql-server-setup-data-'));
    try {
      const result = check('--config', writeConfig('sql-login.json', fixture), '--data-dir', dataDir);
      assert.equal(result.status, 0, result.stdout + result.stderr);
      assert.match(result.stdout, /^INFO {2}server copy: none in /m);
      assert.match(result.stdout, /^INFO {2}auth local: SQL_READER_USER is set/m);
      assert.match(result.stdout, /^INFO {2}auth local: SQL_READER_PASSWORD is not set/m);
      const command = /^INFO {2}register local: (.*)$/m.exec(result.stdout)?.[1];
      assert.ok(command?.startsWith('claude mcp add '), result.stdout);
      assert.ok(command.includes("--env 'SQL_READER_PASSWORD=${SQL_READER_PASSWORD}'"));
      assert.ok(command.includes('--transport stdio --scope user sql-local -- node '));
      assert.ok(command.includes(join(dataDir, 'server', 'src', 'launch.mjs')));
      assert.ok(!/=reader\b/.test(command), 'a variable value reached the command');
    } finally {
      rmSync(dataDir, { recursive: true, force: true });
    }
  });

  it('fails a server copy of another version, and one missing its dependencies', () => {
    const dataDir = mkdtempSync(join(tmpdir(), 'sql-server-setup-data-'));
    const manifest = join(dataDir, 'server', '.claude-plugin');
    mkdirSync(manifest, { recursive: true });
    const file = writeConfig('copy.json', examples[0].text);
    try {
      writeFileSync(join(manifest, 'plugin.json'), JSON.stringify({ version: '0.0.1' }));
      let result = check('--config', file, '--data-dir', dataDir);
      assert.equal(result.status, 1);
      assert.match(result.stdout, /^FAIL {2}server copy: .* holds 0\.0\.1, the plugin is /m);

      writeFileSync(join(manifest, 'plugin.json'), JSON.stringify({ version }));
      result = check('--config', file, '--data-dir', dataDir);
      assert.equal(result.status, 1);
      assert.match(result.stdout, /^FAIL {2}server dependencies: tedious, @azure\/identity not installed/m);
    } finally {
      rmSync(dataDir, { recursive: true, force: true });
    }
  });

  it('refuses a missing --config or an empty --data-dir as a usage error', () => {
    assert.equal(check().status, 2);
    assert.equal(check('--config', writeConfig('usage.json', examples[0].text), '--data-dir', '').status, 2);
  });
});
