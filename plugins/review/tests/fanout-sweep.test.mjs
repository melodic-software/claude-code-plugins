// Runs workflows/fanout-sweep.js against stubbed workflow hooks (agent,
// parallel, pipeline, phase, log, args) and asserts what it dispatches.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const source = readFileSync(join(here, '..', 'workflows', 'fanout-sweep.js'), 'utf8')
const AsyncFunction = Object.getPrototypeOf(async () => {}).constructor
const body = source.replace(/^export const meta\b/m, 'const meta')

// Banned by the bundled /workflow-authoring skill's determinism rules; the test enforces the same list.
for (const banned of ['Date.now(', 'Math.random(', 'new Date()']) {
  test(`script does not call ${banned}`, () => assert.ok(!source.includes(banned)))
}

async function run(args, { reply } = {}) {
  const calls = []
  const logs = []
  const agent = async (prompt, opts = {}) => {
    calls.push({ prompt, opts })
    if (reply) return reply(prompt, opts)
    if (opts.schema) return { records: [{ surface: 'x', category: 'c', raw_text: 'r' }] }
    return `findings from ${opts.label}`
  }
  const parallel = async thunks => Promise.all(thunks.map(t => t().catch(() => null)))
  const pipeline = async () => { throw new Error('not used') }
  const fn = new AsyncFunction('agent', 'parallel', 'pipeline', 'phase', 'log', 'args', 'budget', 'workflow', body)
  const result = await fn(agent, parallel, pipeline, () => {}, m => logs.push(m), args, { total: null }, null)
  return { result, calls, logs }
}

const slices = c => c.filter(x => x.opts.label && x.opts.label.startsWith('slice:'))
const extract = c => c.find(x => x.opts.label === 'stage0-extract')

test('missing diffBase returns an error and dispatches nothing', async () => {
  const { result, calls } = await run({ slices: ['a.md'] })
  assert.equal(result.error, 'missing-diff-base')
  assert.equal(calls.length, 0)
})

test('bare invocation (no args) dispatches nothing', async () => {
  const { result, calls } = await run(undefined)
  assert.equal(result.error, 'missing-diff-base')
  assert.equal(calls.length, 0)
})

test('a diffBase that is not a ref is refused', async () => {
  const { result, calls } = await run({ diffBase: 'main; rm -rf /' })
  assert.equal(result.error, 'bad-diff-base')
  assert.equal(calls.length, 0)
})

test('the extractor runs as routed', async () => {
  const roles = { retrieval: { single: { model: 'haiku', effort: 'medium' }, fanout: { model: 'sonnet', effort: 'low' } } }
  const { calls } = await run({ diffBase: 'origin/main', slices: ['a.md'], roles })
  assert.equal(extract(calls).opts.model, 'haiku')
  assert.equal(extract(calls).opts.effort, 'medium')
})

test('the single judge may inherit: an inherit single variant omits model', async () => {
  const roles = {
    verifier: { single: { model: 'inherit', effort: 'high' }, fanout: { model: 'opus', effort: 'high' } },
    retrieval: { single: { model: 'inherit', effort: 'high' }, fanout: { model: 'opus', effort: 'low' } },
  }
  const { calls } = await run({ diffBase: 'origin/main', roles })
  const x = extract(calls)
  assert.ok(!('model' in x.opts), 'extractor carries no model option')
  assert.equal(x.opts.effort, 'high')
})

test('session model unknown (no roles passed): the extractor falls back to sonnet at medium', async () => {
  const { calls, logs } = await run({ diffBase: 'origin/main', slices: ['a.md'] })
  assert.equal(extract(calls).opts.model, 'sonnet')
  assert.equal(extract(calls).opts.effort, 'medium')
  assert.ok(logs.some(l => l.includes('built-in fallbacks')))
})

test('a malformed role variant falls back and is logged', async () => {
  const roles = { retrieval: { single: { model: 'claude-opus-5-5', effort: 'low' } } }
  const { calls, logs } = await run({ diffBase: 'origin/main', slices: ['a.md'], roles })
  assert.equal(extract(calls).opts.model, 'sonnet')
  assert.ok(logs.some(l => l.includes('roles.retrieval.single')))
})

test('every slice runs as review:brief-reviewer and the extractor as review:stage-normalizer', async () => {
  const { calls } = await run({ diffBase: 'origin/main', slices: ['a.md', 'b.md'] })
  assert.equal(slices(calls).length, 2)
  for (const s of slices(calls)) assert.equal(s.opts.agentType, 'review:brief-reviewer')
  assert.equal(extract(calls).opts.agentType, 'review:stage-normalizer')
})

// A general-purpose agent holds Agent and Skill, so every call must name a plugin agent, and each
// named definition must withhold both. docs/plugin-philosophy.md "Named agents keep their pins":
// a definition that pins effort gets neither option; one that inherits and pins none gets the route.
const agentsDir = join(here, '..', 'agents')
const frontmatter = type => readFileSync(join(agentsDir, type.replace(/^review:/, '') + '.md'), 'utf8').split('\n---')[0]

test('every call names a plugin agent whose tools exclude Agent and Skill', async () => {
  const roles = { retrieval: { single: { model: 'sonnet', effort: 'low' } } }
  const { calls } = await run({ diffBase: 'origin/main', slices: ['a.md'], roles })
  for (const c of calls) {
    assert.match(c.opts.agentType || '', /^review:/, `${c.opts.label} names an agent`)
    const tools = /^tools:\s*"([^"]*)"/m.exec(frontmatter(c.opts.agentType))[1].split(/,\s*/)
    assert.ok(!tools.includes('Agent') && !tools.includes('Skill'), `${c.opts.agentType} withholds Agent and Skill`)
  }
})

// The fan-out frontier guard (docs/plugin-philosophy.md): a stage running several agents never
// runs them on the session's model, which may be the frontier one.
const NON_FRONTIER = ['opus', 'sonnet', 'haiku']
test('every fan-out (Review stage) agent pins a non-frontier model, or its call passes one', async () => {
  const roles = { retrieval: { single: { model: 'sonnet', effort: 'low' } } }
  const { calls } = await run({ diffBase: 'origin/main', slices: ['a.md', 'b.md'], roles })
  const fanout = calls.filter(c => c.opts.phase === 'Review')
  assert.equal(fanout.length, 6)
  for (const c of fanout) {
    const pinned = /^model:\s*([^\s#]+)/m.exec(frontmatter(c.opts.agentType))
    const model = pinned && pinned[1] !== 'inherit' ? pinned[1] : c.opts.model
    assert.ok(NON_FRONTIER.includes(model), `${c.opts.label} runs on ${model}, not a non-frontier model`)
  }
})

test('named agents that pin effort pass neither model nor effort; an inheriting unpinned one passes the route', async () => {
  const roles = { retrieval: { single: { model: 'sonnet', effort: 'low' } } }
  const { calls } = await run({ diffBase: 'origin/main', slices: ['a.md'], roles })
  for (const c of calls) {
    if (/^effort:/m.test(frontmatter(c.opts.agentType))) {
      assert.ok(!('model' in c.opts) && !('effort' in c.opts), `${c.opts.label} keeps its pins`)
    } else {
      assert.equal(c.opts.effort, 'low', `${c.opts.label} passes the routed effort`)
    }
  }
})

test('roster, diff base in prompts, and the returned shape', async () => {
  const { result, calls } = await run({ diffBase: 'abc123', slices: ['docs/review/sec.md'] })
  assert.deepEqual(result.ran, ['security-reviewer', 'architecture-guardian', 'code-reviewer', 'doc-drift-detector', 'slice:docs/review/sec.md'])
  assert.deepEqual(result.nulls, [])
  assert.equal(result.records.length, 1)
  assert.equal(result.raw.length, 5)
  for (const c of calls.filter(x => x.opts.phase === 'Review')) assert.ok(c.prompt.includes('git diff abc123'))
})

test('a null leaf is named in nulls and never extracted', async () => {
  const { result } = await run({ diffBase: 'abc123' }, {
    reply: (p, o) => (o.label === 'code-reviewer' ? null : o.schema ? { records: [] } : 'ok'),
  })
  assert.deepEqual(result.nulls, ['code-reviewer'])
  assert.ok(!result.raw.some(r => r.label === 'code-reviewer'))
})

test('maxConcurrent caps each wave', async () => {
  let live = 0
  let peak = 0
  const { calls } = await run({ diffBase: 'abc', slices: ['1', '2', '3', '4', '5'], maxConcurrent: 2 }, {
    reply: async (p, o) => {
      live++
      peak = Math.max(peak, live)
      await new Promise(r => setImmediate(r))
      live--
      return o.schema ? { records: [] } : 'ok'
    },
  })
  assert.equal(slices(calls).length, 5)
  assert.ok(peak <= 2, `peak concurrency ${peak}`)
})

test('a thrown dispatch is retried once', async () => {
  let thrown = 0
  const { result } = await run({ diffBase: 'abc' }, {
    reply: (p, o) => {
      if (o.label === 'security-reviewer' && thrown === 0) {
        thrown++
        throw new Error('transient')
      }
      return o.schema ? { records: [] } : 'ok'
    },
  })
  assert.equal(thrown, 1)
  assert.deepEqual(result.nulls, [])
})

test('string args are parsed as JSON', async () => {
  const { result } = await run(JSON.stringify({ diffBase: 'abc' }))
  assert.equal(result.diffBase, 'abc')
})

// Diversity: `lens` (the default) runs one agent per concern; `model` sends one prompt to each
// distinct fan-out model in the role map. Expected labels and agent come from the /review:fanout
// run-everything contract, not from the script's output.
const review = c => c.filter(x => x.opts.phase === 'Review')
const LENS_RAN = ['security-reviewer', 'architecture-guardian', 'code-reviewer', 'doc-drift-detector', 'slice:a.md']
const routed = (o, w, v, r) => ({
  orchestrator: { single: { model: 'inherit', effort: 'high' }, fanout: o },
  worker: { single: { model: 'inherit', effort: 'high' }, fanout: w },
  verifier: { single: { model: 'inherit', effort: 'high' }, fanout: v },
  retrieval: { single: { model: 'sonnet', effort: 'low' }, fanout: r },
})
// Two explicit tiers. `inherit` is the session model, which these runs pass no args.session
// for, so an inherit fan-out variant names no known tier and cannot stand for one here.
const TWO_TIERS = routed(
  { model: 'opus', effort: 'high' },
  { model: 'opus', effort: 'xhigh' },
  { model: 'opus', effort: 'medium' },
  { model: 'sonnet', effort: 'low' },
)

test('diversity absent, null and "lens" dispatch the same lens roster and report lens', async () => {
  const base = await run({ diffBase: 'abc', slices: ['a.md'], roles: TWO_TIERS })
  for (const diversity of [undefined, null, 'lens', ' lens ']) {
    const got = await run({ diffBase: 'abc', slices: ['a.md'], roles: TWO_TIERS, diversity })
    assert.deepEqual(got.calls, base.calls, `diversity ${JSON.stringify(diversity)} dispatches the lens calls`)
    assert.deepEqual(got.result.ran, LENS_RAN)
    assert.equal(got.result.diversity, 'lens')
    assert.ok(!('tiers' in got.result), 'lens returns no tiers')
  }
})

test('model sends the one review prompt to each distinct fan-out tier and runs no lens leaf', async () => {
  const { result, calls } = await run({ diffBase: 'abc', slices: ['a.md'], roles: TWO_TIERS, diversity: 'model' })
  const leaves = review(calls)
  assert.deepEqual(leaves.map(c => c.opts.label), ['model:opus', 'model:sonnet'])
  for (const c of leaves) {
    assert.equal(c.opts.agentType, 'review:lane-verifier')
    assert.equal(c.opts.effort, 'medium', 'effort comes from the verifier fan-out variant')
    assert.ok(c.prompt.includes('git diff abc'))
    assert.ok(c.prompt.includes('it is better to surface a finding that later gets filtered out'), 'coverage clause kept')
  }
  assert.equal(leaves[0].opts.model, 'opus')
  assert.equal(leaves[1].opts.model, 'sonnet')
  assert.equal(slices(calls).length, 0)
  assert.equal(result.diversity, 'model')
  assert.deepEqual(result.tiers, ['opus', 'sonnet'])
  assert.deepEqual(result.ran, ['model:opus', 'model:sonnet'])
  assert.ok(extract(calls), 'the extractor still runs')
})

test('inherit is the session model: it dedupes with the same explicit alias', async () => {
  const roles = routed(
    { model: 'inherit', effort: 'high' },
    { model: 'opus', effort: 'high' },
    { model: 'inherit', effort: 'medium' },
    { model: 'opus', effort: 'low' },
  )
  const { result, calls } = await run({ diffBase: 'abc', slices: ['a.md'], roles, session: 'opus', diversity: 'model' })
  assert.equal(result.diversity, 'lens', 'inherit under an opus session and opus are one tier, fewer than two')
  assert.deepEqual(result.ran, LENS_RAN)
  assert.ok(!calls.some(c => (c.opts.label || '').startsWith('model:')))
})

test('inherit resolves to the session alias and its leaf omits model', async () => {
  const roles = routed(
    { model: 'inherit', effort: 'high' },
    { model: 'opus', effort: 'high' },
    { model: 'sonnet', effort: 'medium' },
    undefined,
  )
  const { result, calls } = await run({ diffBase: 'abc', roles, session: 'sonnet', diversity: 'model' })
  assert.deepEqual(result.tiers, ['sonnet', 'opus'])
  const leaves = review(calls)
  assert.deepEqual(leaves.map(c => c.opts.label), ['model:sonnet', 'model:opus'])
  assert.ok(!('model' in leaves[0].opts), 'the session tier runs on the session model')
  assert.equal(leaves[1].opts.model, 'opus')
})

test('inherit under an unknown or frontier session is left out of model diversity with a log', async () => {
  const roles = routed(
    { model: 'inherit', effort: 'high' },
    { model: 'opus', effort: 'high' },
    { model: 'sonnet', effort: 'medium' },
    undefined,
  )
  for (const session of [undefined, 'fable', 'best', 'gpt', 'inherit']) {
    const { result, logs } = await run({ diffBase: 'abc', roles, session, diversity: 'model' })
    assert.deepEqual(result.tiers, ['opus', 'sonnet'], `session ${session}: inherit is no non-frontier tier`)
    assert.ok(logs.some(l => l.includes('roles.orchestrator.fanout')), `session ${session}: the dropped inherit is logged`)
  }
  const one = routed({ model: 'inherit', effort: 'high' }, { model: 'sonnet', effort: 'high' }, undefined, undefined)
  const { result } = await run({ diffBase: 'abc', roles: one, diversity: 'model' })
  assert.equal(result.diversity, 'lens', 'inherit plus one explicit tier, session unknown, is fewer than two')
})

test('model tiers keep first-seen order over orchestrator, worker, verifier, retrieval', async () => {
  const roles = routed(
    { model: 'sonnet', effort: 'high' },
    { model: 'opus', effort: 'high' },
    { model: 'sonnet', effort: 'low' },
    { model: 'haiku', effort: 'low' },
  )
  const { result, calls } = await run({ diffBase: 'abc', roles, diversity: 'model' })
  assert.deepEqual(result.tiers, ['sonnet', 'opus', 'haiku'])
  assert.deepEqual(review(calls).map(c => c.opts.model), ['sonnet', 'opus', 'haiku'])
})

test('model leaves run at high effort when the verifier fan-out variant has none', async () => {
  const roles = routed({ model: 'opus', effort: 'high' }, { model: 'sonnet', effort: 'low' }, undefined, undefined)
  const { calls } = await run({ diffBase: 'abc', roles, diversity: ' model ' })
  assert.equal(review(calls).length, 2)
  for (const c of review(calls)) assert.equal(c.opts.effort, 'high')
})

test('fable and best tiers are dropped from model diversity with a log', async () => {
  const roles = routed(
    { model: 'fable', effort: 'high' },
    { model: 'best', effort: 'high' },
    { model: 'opus', effort: 'high' },
    { model: 'sonnet', effort: 'low' },
  )
  const { result, calls, logs } = await run({ diffBase: 'abc', roles, diversity: 'model' })
  assert.deepEqual(result.tiers, ['opus', 'sonnet'])
  for (const c of calls) assert.ok(!['fable', 'best'].includes(c.opts.model), `${c.opts.label} stays off the frontier`)
  assert.ok(logs.some(l => l.includes('fable')), 'the fable tier is logged')
  assert.ok(logs.some(l => l.includes('best')), 'the best tier is logged')
})

test('model with fewer than two tiers runs the lens roster, logs it and reports lens', async () => {
  const one = routed(
    { model: 'opus', effort: 'high' },
    { model: 'opus', effort: 'high' },
    { model: 'fable', effort: 'high' },
    { model: 'opus', effort: 'low' },
  )
  for (const roles of [one, undefined]) {
    const lens = await run({ diffBase: 'abc', slices: ['a.md'], roles })
    const got = await run({ diffBase: 'abc', slices: ['a.md'], roles, diversity: 'model' })
    assert.deepEqual(got.calls, lens.calls)
    assert.deepEqual(got.result.ran, LENS_RAN)
    assert.equal(got.result.diversity, 'lens')
    assert.ok(got.logs.some(l => /tier/.test(l) && /lens/.test(l)), 'the fallback to lens is logged')
  }
})

test('an unknown diversity value is refused before any dispatch', async () => {
  for (const diversity of ['models', '', 7, {}, ['model'], true]) {
    const { result, calls } = await run({ diffBase: 'abc', slices: ['a.md'], roles: TWO_TIERS, diversity })
    assert.equal(result.error, 'bad-diversity', `diversity ${JSON.stringify(diversity)} is refused`)
    assert.equal(typeof result.next, 'string')
    assert.equal(calls.length, 0)
  }
})

test('every model-mode call names a plugin agent whose tools exclude Agent and Skill', async () => {
  const { calls } = await run({ diffBase: 'abc', slices: ['a.md'], roles: TWO_TIERS, diversity: 'model' })
  assert.equal(review(calls).filter(c => c.opts.label.startsWith('model:')).length, 2, 'the model leaves ran')
  for (const c of calls) {
    assert.match(c.opts.agentType || '', /^review:/, `${c.opts.label} names an agent`)
    const tools = /^tools:\s*"([^"]*)"/m.exec(frontmatter(c.opts.agentType))[1].split(/,\s*/)
    assert.ok(!tools.includes('Agent') && !tools.includes('Skill'), `${c.opts.agentType} withholds Agent and Skill`)
  }
})
