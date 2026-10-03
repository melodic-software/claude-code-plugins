// Tests for the drift-checker WebFetch gate: decide() directly, the hook as
// registered (stdin in, deny JSON out), and that the workflow drops sources
// on the same hosts the gate allows.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { spawnSync } from 'node:child_process'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { decide, FETCH_HOSTS } from './drift-checker-fetch-gate.mjs'

const here = dirname(fileURLToPath(import.meta.url))
const fetch = (url, agent = 'multi-agent:drift-checker') => ({ agent_type: agent, tool_name: 'WebFetch', tool_input: { url } })

test('a first-party docs page passes', () => {
  assert.equal(decide(fetch('https://code.claude.com/docs/en/workflows#cost')), null)
  assert.equal(decide(fetch('https://platform.claude.com/docs/en/about-claude/models/overview')), null)
})

test('an off-host, query-carrying, userinfo or non-https fetch is denied', () => {
  for (const url of [
    'https://attacker.example/c',
    'https://code.claude.com/docs?d=secret',
    'https://user:pw@code.claude.com/docs',
    'http://code.claude.com/docs',
    'https://code.claude.com.attacker.example/x',
    'not a url',
  ]) assert.match(decide(fetch(url)), /denied/, url)
})

test('other agents and the main thread pass through', () => {
  assert.equal(decide(fetch('https://attacker.example/?d=x', 'Explore')), null)
  assert.equal(decide({ tool_name: 'WebFetch', tool_input: { url: 'https://attacker.example/' } }), null)
  assert.equal(decide(fetch('https://attacker.example/', 'drift-checker-ish')), null)
})

test('a bare drift-checker agent type is gated too', () => {
  assert.match(decide(fetch('https://attacker.example/', 'drift-checker')), /denied/)
})

test('the hook as registered prints a deny decision and stays silent on an allowed fetch', () => {
  const hook = join(here, 'drift-checker-fetch-gate.mjs')
  const denied = spawnSync('node', [hook], { input: JSON.stringify(fetch('https://attacker.example/')), encoding: 'utf8' })
  assert.equal(denied.status, 0)
  assert.equal(JSON.parse(denied.stdout).hookSpecificOutput.permissionDecision, 'deny')
  const allowed = spawnSync('node', [hook], { input: JSON.stringify(fetch('https://code.claude.com/docs/en/hooks')), encoding: 'utf8' })
  assert.equal(allowed.stdout, '')
  const garbage = spawnSync('node', [hook], { input: 'not json', encoding: 'utf8' })
  assert.equal(garbage.status, 0)
  assert.equal(garbage.stdout, '')
})

test('the workflow drops sources on the same hosts the gate allows', () => {
  const wf = readFileSync(join(here, '..', 'workflows', 'drift-audit.js'), 'utf8')
  const hosts = JSON.parse(wf.match(/const FETCH_HOSTS = (\[[^\]]*\])/)[1].replace(/'/g, '"'))
  assert.deepEqual(hosts, FETCH_HOSTS)
})

test('hooks.json registers the gate on WebFetch in exec form', () => {
  const cfg = JSON.parse(readFileSync(join(here, 'hooks.json'), 'utf8'))
  const entry = cfg.hooks.PreToolUse[0]
  assert.equal(entry.matcher, 'WebFetch')
  assert.deepEqual(entry.hooks[0].args, ['${CLAUDE_PLUGIN_ROOT}/hooks/drift-checker-fetch-gate.mjs'])
})
