import { test } from 'node:test'
import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { evaluatePromotion, recordAudit, resolveDataDir, retain } from './registry-history.mjs'

const here = path.dirname(fileURLToPath(import.meta.url))
const script = path.join(here, 'registry-history.mjs')
const SETTINGS = { audits: 3, days: 30 }
const ALL_PASS = { live: true, dated: true, error_range: true, current_models: true }

const rec = (date, checks = ALL_PASS, row_id = 'new-board') => ({ row_id, date, checks: { ...checks } })
const input = (date, checks = ALL_PASS, extra = {}) => ({
  row_id: 'new-board', source: 'shipped', status: 'support-only', date, checks: { ...checks }, ...extra,
})

function tmpDir(t) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'registry-history-'))
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }))
  return dir
}

const stored = (dataDir, rowId = 'new-board') =>
  JSON.parse(fs.readFileSync(path.join(dataDir, 'registry-history', `${rowId}.json`), 'utf8'))

test('promotion: two passing audits over 40 days are not enough', () => {
  const v = evaluatePromotion([rec('2026-10-01'), rec('2026-11-10')], SETTINGS)
  assert.equal(v.promote, false)
})

test('promotion: three passing audits spanning 29 days are not enough', () => {
  const v = evaluatePromotion([rec('2026-10-01'), rec('2026-10-15'), rec('2026-10-30')], SETTINGS)
  assert.equal(v.promote, false)
})

test('promotion: three passing audits spanning 30 days propose permanent with their dates', () => {
  const v = evaluatePromotion([rec('2026-10-01'), rec('2026-10-15'), rec('2026-10-31')], SETTINGS)
  assert.equal(v.promote, true)
  assert.deepEqual(v.audits, ['2026-10-01', '2026-10-15', '2026-10-31'])
})

for (const check of ['live', 'dated', 'error_range', 'current_models']) {
  test(`promotion: a failed ${check} check inside the window blocks`, () => {
    const v = evaluatePromotion(
      [rec('2026-10-01'), rec('2026-10-15', { ...ALL_PASS, [check]: false }), rec('2026-10-31')],
      SETTINGS,
    )
    assert.equal(v.promote, false)
    assert.match(v.reason, new RegExp(`failed ${check} on 2026-10-15`))
  })
}

test('promotion: a failure before a full passing run no longer blocks', () => {
  const v = evaluatePromotion(
    [rec('2026-08-01', { ...ALL_PASS, live: false }), rec('2026-09-01'), rec('2026-09-20'), rec('2026-10-01')],
    SETTINGS,
  )
  assert.equal(v.promote, true)
  assert.deepEqual(v.audits, ['2026-09-01', '2026-09-20', '2026-10-01'])
})

test('promotion: the settings change the rule', () => {
  const recs = [rec('2026-10-01'), rec('2026-10-11')]
  assert.equal(evaluatePromotion(recs, { audits: 2, days: 10 }).promote, true)
  assert.equal(evaluatePromotion(recs, { audits: 2, days: 11 }).promote, false)
})

test('retention: keeps the newest records until they number audits + 1 and span days + 7', () => {
  const recs = ['2026-06-01', '2026-07-01', '2026-08-01', '2026-10-01', '2026-10-20', '2026-11-01', '2026-11-10']
    .map(d => rec(d))
  assert.deepEqual(retain(recs, SETTINGS).map(r => r.date), ['2026-10-01', '2026-10-20', '2026-11-01', '2026-11-10'])
})

test('retention: daily audits keep 37 days, not a fixed count', () => {
  const recs = Array.from({ length: 60 }, (_, i) => rec(new Date(Date.UTC(2026, 8, 1 + i)).toISOString().slice(0, 10)))
  const kept = retain(recs, SETTINGS)
  assert.equal(kept.length, 38)
  assert.equal(kept[0].date, '2026-09-23')
  assert.equal(kept[kept.length - 1].date, '2026-10-30')
})

test('retention: keeps everything while too few records exist', () => {
  const recs = [rec('2026-10-01'), rec('2026-11-01')]
  assert.equal(retain(recs, SETTINGS).length, 2)
})

test('record: writes one record per row per audit with date, row id and the four checks', (t) => {
  const dataDir = tmpDir(t)
  const out = recordAudit({ dataDir, input: [input('2026-10-01', { ...ALL_PASS, error_range: false })], ...SETTINGS })
  assert.equal(out.recorded, 1)
  assert.deepEqual(stored(dataDir), {
    row_id: 'new-board',
    records: [{ row_id: 'new-board', date: '2026-10-01', checks: { live: true, dated: true, error_range: false, current_models: true } }],
  })
})

test('record: a second run on the same date replaces that date, a later date appends', (t) => {
  const dataDir = tmpDir(t)
  recordAudit({ dataDir, input: [input('2026-10-01', { ...ALL_PASS, live: false })], ...SETTINGS })
  recordAudit({ dataDir, input: [input('2026-10-01')], ...SETTINGS })
  recordAudit({ dataDir, input: [input('2026-10-08')], ...SETTINGS })
  const records = stored(dataDir).records
  assert.deepEqual(records.map(r => r.date), ['2026-10-01', '2026-10-08'])
  assert.equal(records[0].checks.live, true)
})

test('record: the third passing audit over 30 days proposes the promotion with evidence and a diff', (t) => {
  const dataDir = tmpDir(t)
  assert.equal(recordAudit({ dataDir, input: [input('2026-10-01')], ...SETTINGS }).promotions.length, 0)
  const second = recordAudit({ dataDir, input: [input('2026-10-15')], ...SETTINGS })
  assert.deepEqual(second.pending, [{ source_id: 'new-board', reason: '2 passing audits over 14 days; needs 3 over 30' }])
  const third = recordAudit({ dataDir, input: [input('2026-10-31')], ...SETTINGS })
  assert.deepEqual(third.promotions, [{
    source_id: 'new-board',
    field: 'status',
    from: 'support-only',
    to: 'permanent',
    reason: 'passed every check in 3 audits from 2026-10-01 to 2026-10-31',
    audits: ['2026-10-01', '2026-10-15', '2026-10-31'],
  }])
  assert.equal(third.diff, [
    '--- a/reference/benchmarks.json',
    '+++ b/reference/benchmarks.json',
    '@@ row new-board @@',
    '-  "status": "support-only"',
    '+  "status": "permanent"',
  ].join('\n'))
})

test('record: permanent and team rows are recorded but never proposed', (t) => {
  const dataDir = tmpDir(t)
  for (const date of ['2026-10-01', '2026-10-15', '2026-10-31']) {
    const out = recordAudit({
      dataDir,
      input: [
        input(date, ALL_PASS, { row_id: 'kept-board', status: 'permanent' }),
        input(date, ALL_PASS, { row_id: 'team-board', source: 'team' }),
      ],
      ...SETTINGS,
    })
    assert.deepEqual(out.promotions, [])
    assert.equal(out.diff, null)
  }
  assert.equal(stored(dataDir, 'kept-board').records.length, 3)
  assert.equal(stored(dataDir, 'team-board').records.length, 3)
})

test('record: invalid records are skipped with a note and written nowhere', (t) => {
  const dataDir = tmpDir(t)
  const out = recordAudit({
    dataDir,
    input: [
      { row_id: '../escape', date: '2026-10-01', checks: ALL_PASS },
      { row_id: 'ok-board', date: '2026-02-30', checks: ALL_PASS },
      { row_id: 'ok-board', date: '2026-10-01', checks: { live: 'yes' } },
    ],
    ...SETTINGS,
  })
  assert.equal(out.recorded, 0)
  assert.equal(out.notes.length, 3)
  assert.deepEqual(fs.readdirSync(path.join(dataDir, 'registry-history')), [])
})

test('record: prunes old records on write and deletes a row file idle for over a year', (t) => {
  const dataDir = tmpDir(t)
  const dir = path.join(dataDir, 'registry-history')
  for (const date of ['2026-06-01', '2026-09-01', '2026-10-01', '2026-10-20', '2026-11-01']) {
    recordAudit({ dataDir, input: [input(date)], ...SETTINGS })
  }
  fs.writeFileSync(path.join(dir, 'gone-board.json'), JSON.stringify({ row_id: 'gone-board', records: [rec('2025-11-09', ALL_PASS, 'gone-board')] }))
  fs.writeFileSync(path.join(dir, 'idle-board.json'), JSON.stringify({ row_id: 'idle-board', records: [rec('2025-11-10', ALL_PASS, 'idle-board')] }))
  const out = recordAudit({ dataDir, input: [input('2026-11-10')], ...SETTINGS })
  assert.deepEqual(stored(dataDir).records.map(r => r.date), ['2026-10-01', '2026-10-20', '2026-11-01', '2026-11-10'])
  assert.equal(out.removed_rows, 1)
  assert.deepEqual(fs.readdirSync(dir).sort(), ['idle-board.json', 'new-board.json'])
})

test('data dir: an explicit dir wins, an own CLAUDE_PLUGIN_DATA is used, a foreign one is refused', () => {
  const root = path.join(os.tmpdir(), 'not-installed', 'multi-agent')
  assert.equal(resolveDataDir('/x/y', {}, root), path.resolve('/x/y'))
  const own = path.join(os.tmpdir(), 'multi-agent-market')
  assert.equal(resolveDataDir(null, { CLAUDE_PLUGIN_DATA: own }, root), path.resolve(own))
  assert.throws(() => resolveDataDir(null, { CLAUDE_PLUGIN_DATA: path.join(os.tmpdir(), 'other-plugin') }, root), /nowhere to keep registry history/)
})

test('cli: resolves vendors.promotion_audits and promotion_days to the bundled 3 and 30', (t) => {
  const dataDir = tmpDir(t)
  const file = path.join(dataDir, 'in.json')
  fs.writeFileSync(file, JSON.stringify({ historyRecords: [input('2026-10-01')] }))
  const res = spawnSync(process.execPath, [script, 'record', '--input', file, '--data-dir', dataDir], {
    encoding: 'utf8',
    cwd: dataDir,
    env: { ...process.env, CLAUDE_PROJECT_DIR: dataDir, HOME: dataDir },
  })
  assert.equal(res.status, 0, res.stderr)
  const out = JSON.parse(res.stdout)
  assert.deepEqual(out.settings, { audits: 3, days: 30 })
  assert.equal(out.recorded, 1)
})

test('cli: --audits and --days override, and a bad value exits 2', (t) => {
  const dataDir = tmpDir(t)
  const file = path.join(dataDir, 'in.json')
  fs.writeFileSync(file, JSON.stringify([input('2026-10-01'), input('2026-10-03', ALL_PASS, { row_id: 'b-board' })]))
  const ok = spawnSync(process.execPath, [script, 'record', '--input', file, '--data-dir', dataDir, '--audits', '1', '--days', '1'], { encoding: 'utf8' })
  assert.equal(ok.status, 0, ok.stderr)
  assert.deepEqual(JSON.parse(ok.stdout).settings, { audits: 1, days: 1 })
  const bad = spawnSync(process.execPath, [script, 'record', '--input', file, '--data-dir', dataDir, '--audits', '0', '--days', '30'], { encoding: 'utf8' })
  assert.equal(bad.status, 2)
  assert.match(bad.stderr, /--audits must be an integer >= 1/)
})
