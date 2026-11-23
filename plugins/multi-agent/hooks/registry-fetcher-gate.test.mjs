import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { decide, judge } from '../lib/docs-fetcher-gate.mjs'

const here = dirname(fileURLToPath(import.meta.url))
const plugin = join(here, '..')
const hooksCfg = JSON.parse(readFileSync(join(plugin, 'hooks', 'hooks.json'), 'utf8'))
const benchmarks = JSON.parse(readFileSync(join(plugin, 'reference', 'benchmarks.json'), 'utf8'))

const EXPECTED_DOCS_HOSTS = [
  'code.claude.com',
  'platform.claude.com',
  'docs.claude.com',
  'docs.anthropic.com',
  'www.anthropic.com',
]

function findBashGate(agentType) {
  for (const entry of hooksCfg.hooks.PreToolUse) {
    if (entry.matcher !== 'Bash') continue
    for (const h of entry.hooks || []) {
      if (
        h.type === 'command' &&
        h.command === 'node' &&
        Array.isArray(h.args) &&
        h.args[0] === '${CLAUDE_PLUGIN_ROOT}/lib/docs-fetcher-gate.mjs' &&
        h.args[1] === agentType
      ) {
        return h
      }
    }
  }
  return null
}

const benchmarkHosts = [...new Set(benchmarks.rows.map(r => new URL(r.link).hostname.toLowerCase()))].sort()

test('docs-fetcher Bash gate entry and host list stay unchanged', () => {
  const h = findBashGate('multi-agent:docs-fetcher')
  assert.ok(h, 'multi-agent:docs-fetcher Bash hook must be registered')
  assert.equal(h.onFailure, 'block')
  assert.deepEqual(h.args.slice(2), EXPECTED_DOCS_HOSTS)
})

test('registry-fetcher Bash gate host list equals reference/benchmarks.json hosts exactly', () => {
  const h = findBashGate('multi-agent:registry-fetcher')
  assert.ok(h, 'multi-agent:registry-fetcher Bash hook must be registered')
  assert.equal(h.onFailure, 'block')
  const hookHosts = h.args.slice(2).map(s => s.toLowerCase())
  assert.equal(hookHosts.length, new Set(hookHosts).size, 'hook host list has no duplicates')
  assert.deepEqual([...hookHosts].sort(), benchmarkHosts)
})

test('registry-audit workflow uses the same host list as reference/benchmarks.json', () => {
  const wf = readFileSync(join(plugin, 'workflows', 'registry-audit.js'), 'utf8')
  const wfHosts = JSON.parse(wf.match(/const REGISTRY_HOSTS = (\[[^\]]*\])/)[1].replace(/'/g, '"'))
  assert.deepEqual([...wfHosts].sort(), benchmarkHosts)
})

test('docs-fetcher-gate allows each benchmark row URL for registry-fetcher and denies off-host or malformed calls', () => {
  const h = findBashGate('multi-agent:registry-fetcher')
  const hosts = h.args.slice(2).map(s => s.toLowerCase())
  const root = '/opt/plugins/multi-agent'
  const call = (cmd, agentType = 'multi-agent:registry-fetcher', agentId = 'a1') => ({
    agent_type: agentType,
    agent_id: agentId,
    tool_name: 'Bash',
    tool_input: { command: cmd },
  })

  for (const row of benchmarks.rows) {
    const cmd = `bash "${root}/scripts/docs-raw.sh" '${row.link}'`
    assert.equal(decide(call(cmd), { agentType: 'multi-agent:registry-fetcher', root, hosts }), null, row.id)
  }

  for (const bad of [
    `bash "${root}/scripts/docs-raw.sh" 'https://attacker.example/board'`,
    `bash "${root}/scripts/docs-raw.sh" 'https://code.claude.com/docs/en/workflows'`,
    `bash "${root}/scripts/docs-raw.sh" '${benchmarks.rows[0].link}?q=secret'`,
    `bash "${root}/scripts/docs-raw.sh" '${benchmarks.rows[0].link}' | cat`,
    `curl '${benchmarks.rows[0].link}'`,
  ]) {
    assert.match(
      decide(call(bad), { agentType: 'multi-agent:registry-fetcher', root, hosts }),
      /denied/,
      bad,
    )
  }

  assert.equal(
    decide(call('echo ok', 'Explore'), { agentType: 'multi-agent:registry-fetcher', root, hosts }),
    null,
  )
  assert.equal(
    decide(call('echo ok', ''), { agentType: 'multi-agent:registry-fetcher', root, hosts }),
    null,
  )
})

test('registry-fetcher gate allows docs-raw.sh only once per agent run', () => {
  const h = findBashGate('multi-agent:registry-fetcher')
  const hosts = h.args.slice(2).map(s => s.toLowerCase())
  const root = '/opt/plugins/multi-agent'
  const payload = JSON.stringify({
    agent_type: 'multi-agent:registry-fetcher',
    agent_id: 'reg-run-1',
    tool_name: 'Bash',
    tool_input: { command: `bash "${root}/scripts/docs-raw.sh" '${benchmarks.rows[0].link}'` },
  })
  let seen = false
  const claim = () => (seen ? false : ((seen = true), true))
  assert.equal(judge(payload, { agentType: 'multi-agent:registry-fetcher', root, hosts, claim }), null)
  assert.match(
    judge(payload, { agentType: 'multi-agent:registry-fetcher', root, hosts, claim }),
    /already run docs-raw\.sh once/,
  )
})
