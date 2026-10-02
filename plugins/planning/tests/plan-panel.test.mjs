// Runs workflows/plan-panel.js against stubbed workflow hooks (agent,
// parallel, pipeline, phase, log, args) and asserts what it dispatches.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const source = readFileSync(join(here, '..', 'workflows', 'plan-panel.js'), 'utf8')
const AsyncFunction = Object.getPrototypeOf(async () => {}).constructor
const body = source.replace(/^export const meta\b/m, 'const meta')

// Banned by the bundled /workflow-authoring skill's determinism rules; the test enforces the same list.
for (const banned of ['Date.now(', 'Math.random(', 'new Date()']) {
  test(`script does not call ${banned}`, () => assert.ok(!source.includes(banned)))
}

const score = (draft, n) => ({ draft, goal_fit: n, blast_radius: n, test_strategy: n, reversibility: n, rationale: 'r' })

// Default replies: every draft returns, judges prefer draft B, synthesis grafts from A.
function defaultReply(prompt, opts) {
  if (opts.label.startsWith('draft:')) return { plan: 'plan from ' + opts.label, key_ideas: ['idea ' + opts.label] }
  if (opts.label.startsWith('judge:')) {
    const letters = [...prompt.matchAll(/^### Draft ([A-Z])$/gm)].map(m => m[1])
    return { scores: letters.map(l => score(l, l === 'B' ? 5 : 3)), dissent: 'concern from ' + opts.label }
  }
  if (opts.label === 'synthesize') return { plan: 'final plan', grafted: [{ idea: 'x', from: 'A' }], dissent: ['open trade-off'] }
  throw new Error('unexpected label ' + opts.label)
}

async function run(args, { reply = defaultReply } = {}) {
  const calls = []
  const logs = []
  const agent = async (prompt, opts = {}) => {
    calls.push({ prompt, opts })
    return reply(prompt, opts)
  }
  const parallel = async thunks => Promise.all(thunks.map(t => t().catch(() => null)))
  const pipeline = async () => { throw new Error('not used') }
  const fn = new AsyncFunction('agent', 'parallel', 'pipeline', 'phase', 'log', 'args', 'budget', 'workflow', body)
  const result = await fn(agent, parallel, pipeline, () => {}, m => logs.push(m), args, { total: null }, null)
  return { result, calls, logs }
}

const drafters = c => c.filter(x => x.opts.label.startsWith('draft:'))
const judges = c => c.filter(x => x.opts.label.startsWith('judge:'))
const fanout = c => [...drafters(c), ...judges(c)]
const synth = c => c.find(x => x.opts.label === 'synthesize')

const FRONTIER = {
  worker: { single: { model: 'inherit', effort: 'medium' }, fanout: { model: 'opus', effort: 'medium' } },
  verifier: { single: { model: 'inherit', effort: 'high' }, fanout: { model: 'opus', effort: 'high' } },
  orchestrator: { single: { model: 'inherit', effort: 'high' }, fanout: { model: 'opus', effort: 'high' } },
}
const NON_FRONTIER = {
  worker: { single: { model: 'inherit', effort: 'medium' }, fanout: { model: 'inherit', effort: 'medium' } },
  verifier: { single: { model: 'inherit', effort: 'high' }, fanout: { model: 'inherit', effort: 'high' } },
  orchestrator: { single: { model: 'inherit', effort: 'high' }, fanout: { model: 'inherit', effort: 'high' } },
}

test('missing task returns an error and dispatches nothing', async () => {
  const { result, calls } = await run({ context: 'c' })
  assert.equal(result.error, 'missing-task')
  assert.equal(calls.length, 0)
})

test('bare invocation (no args) dispatches nothing', async () => {
  const { result, calls } = await run(undefined)
  assert.equal(result.error, 'missing-task')
  assert.equal(calls.length, 0)
})

test('frontier session: every drafter and judge gets opus; the synthesizer inherits', async () => {
  const { calls } = await run({ task: 't', roles: FRONTIER })
  assert.equal(drafters(calls).length, 4)
  assert.equal(judges(calls).length, 3)
  for (const c of fanout(calls)) assert.equal(c.opts.model, 'opus', c.opts.label)
  assert.ok(!('model' in synth(calls).opts), 'synthesizer carries no model option')
})

test('non-frontier session: fan-out agents omit model', async () => {
  const { calls } = await run({ task: 't', roles: NON_FRONTIER })
  for (const c of fanout(calls)) assert.ok(!('model' in c.opts), c.opts.label + ' carries no model option')
})

test('unknown session (no roles passed): fan-out agents get opus and the fallback is logged', async () => {
  const { calls, logs } = await run({ task: 't' })
  for (const c of fanout(calls)) assert.equal(c.opts.model, 'opus', c.opts.label)
  assert.ok(!('model' in synth(calls).opts))
  assert.ok(logs.some(l => l.includes('built-in fallbacks')))
})

test('effort is explicit everywhere: drafters medium, judges high, synthesis high', async () => {
  const { calls } = await run({ task: 't' })
  for (const c of drafters(calls)) assert.equal(c.opts.effort, 'medium')
  for (const c of judges(calls)) assert.equal(c.opts.effort, 'high')
  assert.equal(synth(calls).opts.effort, 'high')
})

test('a malformed role variant falls back and is logged', async () => {
  const { calls, logs } = await run({ task: 't', roles: { verifier: { fanout: { model: 'claude-opus-5-5', effort: 'high' } } } })
  for (const c of judges(calls)) assert.equal(c.opts.model, 'opus')
  assert.ok(logs.some(l => l.includes('roles.verifier.fanout')))
})

test('the judges pick the winner and the result carries scores, grafts and dissent', async () => {
  const { result, calls } = await run({ task: 'add caching', context: 'ctx' })
  assert.deepEqual(result.winner, { id: 'B', angle: 'risk-first' })
  assert.equal(result.plan, 'final plan')
  assert.equal(result.synthesized, true)
  assert.equal(result.scores.find(s => s.draft === 'B').total, 20)
  assert.equal(result.scores.find(s => s.draft === 'A').judges, 3)
  assert.deepEqual(result.grafted, [{ idea: 'x', from: 'A' }])
  assert.ok(result.dissent.includes('open trade-off'))
  assert.ok(result.dissent.includes('concern from judge:1'))
  for (const c of calls) assert.ok(c.prompt.includes('add caching') && c.prompt.includes('ctx'))
  assert.ok(synth(calls).prompt.includes('### Winning draft B'))
})

test('null drafts are filtered and named', async () => {
  const { result, calls } = await run({ task: 't' }, {
    reply: (p, o) => (o.label === 'draft:reuse-first' ? null : defaultReply(p, o)),
  })
  assert.deepEqual(result.nulls.drafts, ['reuse-first'])
  assert.deepEqual(result.drafts.map(d => d.angle), ['mvp-first', 'risk-first', 'testability-first'])
  assert.ok(!judges(calls)[0].prompt.includes('### Draft D'))
})

test('every draft null returns an error and runs no judge', async () => {
  const { result, calls } = await run({ task: 't' }, { reply: (p, o) => (o.label.startsWith('draft:') ? null : defaultReply(p, o)) })
  assert.equal(result.error, 'no-drafts')
  assert.equal(judges(calls).length, 0)
  assert.equal(synth(calls), undefined)
})

test('every judge null returns an error carrying the drafts', async () => {
  const { result, calls } = await run({ task: 't' }, { reply: (p, o) => (o.label.startsWith('judge:') ? null : defaultReply(p, o)) })
  assert.equal(result.error, 'no-judges')
  assert.equal(result.drafts.length, 4)
  assert.equal(synth(calls), undefined)
})

test('the concurrency cap holds', async () => {
  let live = 0
  let peak = 0
  const { calls } = await run({ task: 't', angles: ['a', 'b', 'c', 'd', 'e'], judges: 4, maxConcurrent: 2 }, {
    reply: async (p, o) => {
      live++
      peak = Math.max(peak, live)
      await new Promise(r => setImmediate(r))
      live--
      return defaultReply(p, o)
    },
  })
  assert.equal(drafters(calls).length, 5)
  assert.equal(judges(calls).length, 4)
  assert.ok(peak <= 2, `peak concurrency ${peak}`)
})

test('custom angles replace the defaults; one angle falls back to the defaults', async () => {
  const custom = await run({ task: 't', angles: [{ name: 'perf-first', focus: 'latency' }, 'security-first'] })
  assert.deepEqual(drafters(custom.calls).map(c => c.opts.label), ['draft:perf-first', 'draft:security-first'])
  const one = await run({ task: 't', angles: ['solo'] })
  assert.equal(drafters(one.calls).length, 4)
})

test('a thrown dispatch is retried once', async () => {
  let thrown = 0
  const { result } = await run({ task: 't' }, {
    reply: (p, o) => {
      if (o.label === 'draft:mvp-first' && thrown === 0) {
        thrown++
        throw new Error('transient')
      }
      return defaultReply(p, o)
    },
  })
  assert.equal(thrown, 1)
  assert.deepEqual(result.nulls.drafts, [])
})

test('a null synthesis returns the winning draft unsynthesized', async () => {
  const { result } = await run({ task: 't' }, { reply: (p, o) => (o.label === 'synthesize' ? null : defaultReply(p, o)) })
  assert.equal(result.synthesized, false)
  assert.equal(result.plan, 'plan from draft:risk-first')
})

test('string args are parsed as JSON', async () => {
  const { result } = await run(JSON.stringify({ task: 'from a string' }))
  assert.equal(result.task, 'from a string')
})
