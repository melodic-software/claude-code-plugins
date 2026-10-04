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

test('session model unknown (no roles passed): the extractor falls back to sonnet at low', async () => {
  const { calls, logs } = await run({ diffBase: 'origin/main', slices: ['a.md'] })
  assert.equal(extract(calls).opts.model, 'sonnet')
  assert.equal(extract(calls).opts.effort, 'low')
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
