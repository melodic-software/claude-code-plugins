import { test } from 'node:test'
import assert from 'node:assert/strict'
import { createHash } from 'node:crypto'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const plugin = join(dirname(fileURLToPath(import.meta.url)), '..')
const source = readFileSync(join(plugin, 'workflows', 'registry-audit.js'), 'utf8')
const body = source.replace(/^export const meta\b/m, 'const meta')
const AsyncFunction = Object.getPrototypeOf(async () => {}).constructor

const data = (prompt, name) => {
  const m = prompt.match(new RegExp('<data name="' + name + '">\\n([\\s\\S]*?)\\n</data>'))
  return m ? JSON.parse(m[1]) : undefined
}
const rawPage = (url, text = 'Board 2026-11-15') =>
  'docs-raw: url=' + url + ' state=read format=markdown validated=yes sha256=' + 'a'.repeat(64) +
  ' kind=page bytes=' + Buffer.byteLength(text) + ' body_sha256=' + createHash('sha256').update(text).digest('hex') + '\n' + text

const row = (id, workloads, status = 'support-only', extra = {}) => ({
  id, workloads, link: 'https://www.vals.ai/' + id, publisher: 'vals', provider_own: false,
  status, task_set: id, expect: 'Board', source: 'shipped', ...extra,
})

const VERDICT = { reachable: true, page_date: '2026-11-15', tests_current_models: 'yes', error_range: 'yes', notes: [] }

async function run(args, verdict = () => ({})) {
  const calls = []
  const agent = async (prompt, o) => {
    calls.push({ prompt, opts: o })
    if (o.label.startsWith('fetch:')) return { output: rawPage(data(prompt, 'url')) }
    const r = data(prompt, 'row')
    return { source_id: r.id, covers_work_types: r.workloads, ...VERDICT, ...verdict(r) }
  }
  const parallel = async thunks => Promise.all(thunks.map(t => t().catch(() => null)))
  const fn = new AsyncFunction('agent', 'parallel', 'pipeline', 'phase', 'log', 'args', 'budget', 'workflow', body)
  const result = await fn(agent, parallel, async () => {}, () => {}, () => {}, args, { total: null }, null)
  return { result, calls }
}

const CURRENT = { claude: ['claude-x'], codex: ['gpt-x'], gemini: ['gemini-x'] }
const PASS = { live: true, dated: true, error_range: true, current_models: true }

test('judge schema requires a closed error_range field and the prompt asks for it', async () => {
  const { calls } = await run({ rows: [row('a-board', ['coding'])], asOf: '2026-11-23', currentModels: CURRENT })
  const judge = calls.find(c => c.opts.label === 'judge:a-board')
  assert.deepEqual(judge.opts.schema.properties.error_range, { type: 'string', enum: ['yes', 'no', 'unclear'] })
  assert.ok(judge.opts.schema.required.includes('error_range'))
  assert.match(judge.prompt, /error_range/)
  const judgeMd = readFileSync(join(plugin, 'agents', 'registry-judge.md'), 'utf8')
  assert.match(judgeMd, /"error_range": "yes"/)
})

test('error_range is copied from the judge, and a missing or invalid value is unclear', async () => {
  const values = { 'a-board': 'no', 'b-board': undefined, 'c-board': 'maybe' }
  const { result } = await run(
    { rows: Object.keys(values).map(id => row(id, ['coding'])), asOf: '2026-11-23', currentModels: CURRENT },
    r => ({ error_range: values[r.id] }),
  )
  assert.deepEqual(result.rows.map(r => r.error_range), ['no', 'unclear', 'unclear'])
})

test('a row passing all four checks gets a history record with the audit date', async () => {
  const { result } = await run({ rows: [row('a-board', ['coding'])], asOf: '2026-11-23', currentModels: CURRENT })
  assert.deepEqual(result.historyRecords, [
    { row_id: 'a-board', source: 'shipped', status: 'support-only', date: '2026-11-23', checks: PASS },
  ])
})

test('each failed check is recorded false', async () => {
  const cases = {
    'live-board': { reachable: false },
    'dated-board': { page_date: '2026-04-01' },
    'range-board': { error_range: 'no' },
    'models-board': { tests_current_models: 'unclear' },
  }
  const { result } = await run(
    { rows: Object.keys(cases).map(id => row(id, ['coding'])), asOf: '2026-11-23', currentModels: CURRENT },
    r => cases[r.id],
  )
  const checks = Object.fromEntries(result.historyRecords.map(h => [h.row_id, h.checks]))
  assert.deepEqual(checks['live-board'], { live: false, dated: false, error_range: false, current_models: false })
  assert.deepEqual(checks['dated-board'], { ...PASS, dated: false })
  assert.deepEqual(checks['range-board'], { ...PASS, error_range: false })
  assert.deepEqual(checks['models-board'], { ...PASS, current_models: false })
})

test('current_models needs the vendor list: without currentModels the check fails', async () => {
  const { result } = await run({ rows: [row('a-board', ['coding'])], asOf: '2026-11-23' })
  assert.equal(result.historyRecords[0].checks.current_models, false)
})

test('an image-only row requires only imageVendors; a mixed row requires every vendor', async () => {
  const { calls, result } = await run({
    rows: [row('img-board', ['image']), row('mix-board', ['image', 'coding'])],
    asOf: '2026-11-23',
    currentModels: CURRENT,
    imageVendors: ['codex', 'gemini', 'unknown'],
  })
  const required = id => data(calls.find(c => c.opts.label === 'judge:' + id).prompt, 'required_vendors')
  assert.deepEqual(required('img-board'), ['codex', 'gemini'])
  assert.deepEqual(required('mix-board'), ['claude', 'codex', 'gemini'])
  assert.ok(result.historyRecords.every(h => h.checks.current_models))
})

test('an image-only row with no imageVendors fails current_models', async () => {
  const { result } = await run({ rows: [row('img-board', ['image'])], asOf: '2026-11-23', currentModels: CURRENT })
  assert.equal(result.historyRecords[0].checks.current_models, false)
})

test('no asOf means no history records', async () => {
  const { result } = await run({ rows: [row('a-board', ['coding'])], currentModels: CURRENT })
  assert.deepEqual(result.historyRecords, [])
})
