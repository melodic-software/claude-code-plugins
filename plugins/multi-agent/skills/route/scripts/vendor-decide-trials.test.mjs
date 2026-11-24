import { test } from 'node:test'
import assert from 'node:assert/strict'
import { devNull } from 'node:os'
import { MODELS, boardEntry, makeFixture, rec, row, seedOutcome } from './lib/test-fixtures.mjs'

process.env.GIT_CONFIG_GLOBAL ??= devNull
process.env.GIT_CONFIG_NOSYSTEM = '1'

test('AC10: trials on with either count unset emits one note saying trials stay inactive', (t) => {
  for (const s of [
    { routing: true, trials: true },
    { routing: true, trials: true, trials_prove: 3, trials_fail: null },
    { routing: true, trials: true, trials_prove: null, trials_fail: 2 },
  ]) {
    const res = makeFixture(t, {
      registry: { version: 1, rows: [row('board-a')] },
      manifest: { boards: [boardEntry('board-a')] },
      records: [],
      settings: s,
      extraArgs: ['--task-type', 'coding'],
    })
    assert.equal(res.code, 0, res.stderr)
    const trialNotes = res.json.notes.filter((n) => /trials stay inactive/i.test(n))
    assert.equal(trialNotes.length, 1, `expected 1 inactive note for ${JSON.stringify(s)}`)
  }

  const resBoth = makeFixture(t, {
    registry: { version: 1, rows: [row('board-a')] },
    manifest: { boards: [boardEntry('board-a')] },
    records: [],
    settings: { routing: true, trials: true, trials_prove: 3, trials_fail: 2 },
    extraArgs: ['--task-type', 'coding'],
  })
  assert.equal(resBoth.code, 0, resBoth.stderr)
  assert.equal(resBoth.json.notes.some((n) => /trials stay inactive/i.test(n)), false)
})

test('a trial runs the first listed model at its default effort, not the model a board record leads with', (t) => {
  const models = {
    ...MODELS,
    codex: {
      status: 'ok',
      unset_model: 'cli-default',
      models: [
        { id: 'sparrow-1', efforts: ['low', 'medium', 'high'], default_effort: 'medium' },
        { id: 'sparrow-2', efforts: ['low', 'medium', 'high'], default_effort: 'medium' },
      ],
    },
  }
  const res = makeFixture(t, {
    registry: { version: 1, rows: [row('board-a')] },
    manifest: { boards: [boardEntry('board-a')] },
    records: [rec('board-a', 'codex', 'sparrow-2', 'lead', { effort: 'high' })],
    models,
    settings: { routing: true, trials: true, trials_prove: 3, trials_fail: 2 },
    extraArgs: ['--task-type', 'coding'],
  })
  assert.equal(res.code, 0, res.stderr)
  assert.equal(res.json.basis, 'trial')
  assert.equal(res.json.vendor, 'codex')
  assert.equal(res.json.model, 'sparrow-1')
  assert.equal(res.json.effort, 'medium')
})

test('a heavy trial runs one step above the default, or the level --heavy-effort names when the CLI accepts it and it is not below the default', (t) => {
  const trial = (extraArgs) =>
    makeFixture(t, {
      registry: { version: 1, rows: [row('board-a')] },
      manifest: { boards: [boardEntry('board-a')] },
      records: [],
      settings: { routing: true, trials: true, trials_prove: 3, trials_fail: 2 },
      extraArgs: ['--task-type', 'coding', ...extraArgs],
    }).json
  const everyday = trial([])
  assert.equal(everyday.basis, 'trial')
  assert.equal(everyday.effort, 'medium')
  assert.equal(trial(['--task-class', 'heavy']).effort, 'high')
  assert.equal(trial(['--task-class', 'heavy', '--heavy-effort', 'codex=xhigh']).effort, 'xhigh')
  assert.equal(trial(['--task-class', 'heavy', '--heavy-effort', 'codex=max']).effort, 'high', 'a level the CLI does not list falls back')
  assert.equal(trial(['--task-class', 'heavy', '--heavy-effort', 'codex=low']).effort, 'high', 'a level below the default falls back')
  assert.equal(trial(['--heavy-effort', 'codex=xhigh']).effort, 'medium', 'an everyday trial ignores --heavy-effort')
})

test('a pair proven at the everyday effort routes everyday tasks but not heavy ones, which trial at the heavy effort', (t) => {
  const stateDir = seedOutcome(t, [
    {
      key: { vendor: 'codex', model: 'sparrow-1', version: null, effort: 'medium', work_type: 'coding' },
      result: 'proven',
      at: '2026-11-22T00:00:00.000Z',
    },
  ])
  const decide = (extraArgs) =>
    makeFixture(t, {
      registry: { version: 1, rows: [row('board-a')] },
      manifest: { boards: [boardEntry('board-a')] },
      records: [],
      stateDir,
      settings: { routing: true, trials: true, trials_prove: 3, trials_fail: 2 },
      extraArgs: ['--task-type', 'coding', ...extraArgs],
    }).json
  const everyday = decide([])
  assert.equal(everyday.basis, 'proven')
  assert.equal(everyday.effort, 'medium')
  const heavy = decide(['--task-class', 'heavy'])
  assert.equal(heavy.basis, 'trial')
  assert.equal(heavy.effort, 'high')
})
