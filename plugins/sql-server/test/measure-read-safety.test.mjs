import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';

const script = fileURLToPath(new URL('../scripts/measure-read-safety.mjs', import.meta.url));
const doc = readFileSync(new URL('../reference/read-safety-measurement.md', import.meta.url), 'utf8');

describe('scripts/measure-read-safety.mjs', () => {
  it('refuses a doc without the results markers before it starts any container', (t) => {
    const dir = mkdtempSync(join(tmpdir(), 'sql-server-measure-test-'));
    t.after(() => rmSync(dir, { recursive: true, force: true }));
    const target = join(dir, 'doc.md');
    writeFileSync(target, '# no markers\n');
    // An empty PATH means a docker call would fail with ENOENT, not start a container.
    const run = spawnSync(process.execPath, [script, '--doc', target], { encoding: 'utf8', env: { PATH: '' } });
    assert.equal(run.status, 1);
    assert.match(run.stderr, /has no results markers/);
    assert.doesNotMatch(run.stderr, /starting sql-server-measure-/);
  });

  it('the committed doc holds one results block with a forced-timeout line at zero', () => {
    const block = doc.slice(doc.indexOf('<!-- measure-read-safety:results:start -->'), doc.indexOf('<!-- measure-read-safety:results:end -->'));
    assert.ok(block.length > 0);
    assert.match(block, /open transactions after timeout: 0/);
    assert.doesNotMatch(block, /open transactions after timeout: [1-9]/);
  });
});
