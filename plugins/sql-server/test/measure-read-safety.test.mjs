import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';

const script = fileURLToPath(new URL('../scripts/measure-read-safety.mjs', import.meta.url));
const doc = readFileSync(new URL('../reference/read-safety-measurement.md', import.meta.url), 'utf8');
const START = '<!-- BEGIN GENERATED: measure-read-safety-results. Run node plugins/sql-server/scripts/measure-read-safety.mjs -->';
const END = '<!-- END GENERATED: measure-read-safety-results -->';
const resultsBlock = () => doc.slice(doc.indexOf(START), doc.indexOf(END));

// Runs the script on a doc holding text; an empty PATH means a docker call would fail with
// ENOENT, not start a container.
function runOn(t, text) {
  const dir = mkdtempSync(join(tmpdir(), 'sql-server-measure-test-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const target = join(dir, 'doc.md');
  writeFileSync(target, text);
  return spawnSync(process.execPath, [script, '--doc', target], { encoding: 'utf8', env: { PATH: '' } });
}

describe('scripts/measure-read-safety.mjs', () => {
  it('refuses a doc without the results markers before it starts any container', (t) => {
    const run = runOn(t, '# no markers\n');
    assert.equal(run.status, 1);
    assert.match(run.stderr, /has no results markers/);
    assert.doesNotMatch(run.stderr, /starting sql-server-measure-/);
  });

  it('refuses a doc carrying the retired start/end markers, naming them and the two expected lines', (t) => {
    const run = runOn(t, '# old\n<!-- measure-read-safety:results:start -->\n<!-- measure-read-safety:results:end -->\n');
    assert.equal(run.status, 1);
    assert.doesNotMatch(run.stderr, /has no results markers/);
    assert.match(run.stderr, /carries the retired results markers <!-- measure-read-safety:results:start -->/);
    assert.ok(run.stderr.includes(`replace them with ${START} and ${END}`), run.stderr);
    assert.doesNotMatch(run.stderr, /starting sql-server-measure-/);
  });

  it('the committed doc carries exactly one results marker pair, start first', () => {
    assert.equal(doc.split(START).length, 2);
    assert.equal(doc.split(END).length, 2);
    assert.ok(doc.indexOf(START) < doc.indexOf(END));
  });

  it('refuses a --runs value that is not a whole number of at least 1 before it starts any container', () => {
    for (const runs of ['0', '1.5', 'x']) {
      const run = spawnSync(process.execPath, [script, '--runs', runs], { encoding: 'utf8', env: { PATH: '' } });
      assert.notEqual(run.status, 0);
      assert.match(run.stderr, /--runs takes a whole number of at least 1/);
      assert.doesNotMatch(run.stderr, /starting sql-server-measure-/);
    }
  });

  it('the committed doc holds one results block with a forced-timeout line at zero', () => {
    const block = resultsBlock();
    assert.ok(block.length > 0);
    assert.match(block, /open transactions after timeout: 0/);
    assert.doesNotMatch(block, /open transactions after timeout: [1-9]/);
  });

  it('the committed doc records a passing topology check over the attributed topology runs', () => {
    const block = resultsBlock();
    assert.match(block, /### Waiting tasks in the topology runs, by waiter and blocker/);
    assert.match(block, /Topology check: PASS\./);
  });
});
