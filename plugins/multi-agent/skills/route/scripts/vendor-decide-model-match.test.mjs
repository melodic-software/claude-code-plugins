import { test } from 'node:test'
import assert from 'node:assert/strict'
import { devNull } from 'node:os'
import { MODELS, rec, twoBoards } from './lib/test-fixtures.mjs'

process.env.GIT_CONFIG_GLOBAL ??= devNull
process.env.GIT_CONFIG_NOSYSTEM = '1'

const EFFORT_SUFFIXED_MODELS = {
  ...MODELS,
  gemini: {
    status: 'ok',
    models: [
      { id: 'finch-2-neon-high' },
      { id: 'finch-2-neon-xhigh' },
      { id: 'finch-2-neon-medium' },
      { id: 'finch-2-neon-low' },
    ],
  },
}

function geminiLeadsOnBoth(t, model, effort, models = EFFORT_SUFFIXED_MODELS) {
  return twoBoards(
    t,
    [
      rec('board-a', 'gemini', model, 'lead', { effort }),
      rec('board-a', 'claude', 'kestrel-1', 'behind'),
      rec('board-b', 'gemini', model, 'lead', { effort }),
      rec('board-b', 'claude', 'kestrel-1', 'behind'),
    ],
    { models },
  )
}

test('AC14: a board missing a vendor current model id abstains for that vendor', (t) => {
  const res = twoBoards(t, [
    rec('board-a', 'codex', 'sparrow-1', 'lead'),
    rec('board-a', 'claude', 'kestrel-1', 'behind'),
    rec('board-b', 'codex', 'sparrow-1', 'lead'),
    rec('board-b', 'claude', 'kestrel-0', 'behind'),
  ])
  assert.equal(res.code, 0, res.stderr)
  assert.equal(res.json.vendor, 'claude')
  assert.equal(res.json.basis, 'default')
  assert.equal(res.json.sources.find((s) => s.source_id === 'board-b').role, 'abstains')
  assert.ok(res.json.notes.some((n) => /abstain/i.test(n) && /claude/i.test(n)))
})

test('AC14: a base-name record matches effort-suffixed ids and canonicalizes to the record effort', (t) => {
  const res = geminiLeadsOnBoth(t, 'Finch-2-Neon', 'medium')
  assert.equal(res.code, 0, res.stderr)
  assert.equal(res.json.vendor, 'gemini')
  assert.equal(res.json.model, 'finch-2-neon-medium')
  assert.equal(res.json.basis, 'consensus')
  assert.ok(!res.json.notes.some((n) => /not in current models/.test(n)), JSON.stringify(res.json.notes))
})

test('AC14: a base-name record whose effort has no suffixed id takes the first listed id', (t) => {
  const res = geminiLeadsOnBoth(t, 'finch-2-neon', 'max')
  assert.equal(res.code, 0, res.stderr)
  assert.equal(res.json.vendor, 'gemini')
  assert.equal(res.json.model, 'finch-2-neon-high')
})

test('AC14: a prefix that is not a whole hyphen token does not match and abstains', (t) => {
  const res = geminiLeadsOnBoth(t, 'finch-2', 'high')
  assert.equal(res.code, 0, res.stderr)
  assert.equal(res.json.vendor, 'claude')
  assert.equal(res.json.basis, 'default')
  assert.ok(res.json.notes.some((n) => n.includes("model 'finch-2' is not in current models")))
})

test('AC14: a base-name record whose only current id ends in a non-effort token abstains', (t) => {
  const res = geminiLeadsOnBoth(t, 'finch-2-neon', 'high', {
    ...MODELS,
    gemini: { status: 'ok', models: [{ id: 'finch-2-neon-1' }] },
  })
  assert.equal(res.code, 0, res.stderr)
  assert.equal(res.json.vendor, 'claude')
  assert.equal(res.json.basis, 'default')
  assert.ok(res.json.notes.some((n) => n.includes("model 'finch-2-neon' is not in current models")))
})

test('AC14: an older model version does not count for the current version id', (t) => {
  const res = twoBoards(
    t,
    [
      rec('board-a', 'codex', 'sparrow-1', 'lead'),
      rec('board-a', 'claude', 'claude-opus-5', 'behind'),
      rec('board-b', 'codex', 'sparrow-1', 'lead'),
      rec('board-b', 'claude', 'claude-opus-5', 'behind'),
    ],
    {
      models: {
        ...MODELS,
        claude: {
          ...MODELS.claude,
          models: [{ id: 'claude-opus-5-5', efforts: ['medium', 'high', 'max'], default_effort: 'medium' }],
        },
      },
    },
  )
  assert.equal(res.code, 0, res.stderr)
  assert.equal(res.json.vendor, 'claude')
  assert.equal(res.json.basis, 'default')
  assert.ok(res.json.notes.some((n) => n.includes("model 'claude-opus-5' is not in current models")))
})

test('AC14: an exact current id keeps that id whatever the record effort', (t) => {
  const res = geminiLeadsOnBoth(t, 'finch-2-neon-xhigh', 'low')
  assert.equal(res.code, 0, res.stderr)
  assert.equal(res.json.vendor, 'gemini')
  assert.equal(res.json.model, 'finch-2-neon-xhigh')
})
