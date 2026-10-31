import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { describe, it } from 'node:test';
import { DEFAULT_LIMITS, IDLE_TIMEOUT_MS, POOL_MAX, guardBatch } from '../src/executor.mjs';

// The shipped defaults must be the row the measurement doc chose.
const doc = readFileSync(new URL('../reference/read-safety-measurement.md', import.meta.url), 'utf8');
const section = doc.slice(doc.indexOf('## Chosen defaults'), doc.indexOf('\n## ', doc.indexOf('## Chosen defaults') + 1));
const chosen = Object.fromEntries(
  [...section.matchAll(/^\| `(\w+)` \| ([^|]+?) \|/gm)].map(([, name, value]) => [name, value.trim()]),
);

describe('defaults match the chosen row of reference/read-safety-measurement.md', () => {
  it('has a chosen row for every default', () => {
    assert.deepEqual(Object.keys(chosen).sort(), ['IDLE_TIMEOUT_MS', 'POOL_MAX', 'isolation', 'lockTimeoutMs', 'requestTimeoutMs', 'rowCap']);
  });

  it('requestTimeoutMs', () => assert.equal(DEFAULT_LIMITS.requestTimeoutMs, Number(chosen.requestTimeoutMs)));
  it('lockTimeoutMs', () => assert.equal(DEFAULT_LIMITS.lockTimeoutMs, Number(chosen.lockTimeoutMs)));
  it('rowCap', () => assert.equal(DEFAULT_LIMITS.rowCap, Number(chosen.rowCap)));
  it('POOL_MAX', () => assert.equal(POOL_MAX, Number(chosen.POOL_MAX)));
  it('IDLE_TIMEOUT_MS', () => assert.equal(IDLE_TIMEOUT_MS, Number(chosen.IDLE_TIMEOUT_MS)));
  it('isolation', () => assert.match(guardBatch(DEFAULT_LIMITS.lockTimeoutMs), new RegExp(`SET TRANSACTION ISOLATION LEVEL ${chosen.isolation};`)));
});
