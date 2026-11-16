// test-scope: plugins/planning/hooks/hooks.json
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { spawnSync } from 'node:child_process'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { decide, isVagueBuild, NUDGE } from './vague-build-nudge.mjs'

const here = dirname(fileURLToPath(import.meta.url))
const probes = JSON.parse(readFileSync(join(dirname(here), 'probes', 'interview-bare.json'), 'utf8')).queries

for (const q of probes) {
  test(`probe ${q.id} ${q.expect_trigger ? 'is' : 'is not'} a vague build request`, () => {
    assert.equal(isVagueBuild(q.request), q.expect_trigger)
  })
}

const quiet = [
  ['the explore eval prompt', 'what does the retry code in src/ do?'],
  ['a slash command', '/planning:interview notifications'],
  ['a request that states its scope', 'Add email notifications when an order ships, so customers know.'],
  ['a long request', 'Add notifications to the app for every order event that staff and customers care about today'],
  ['a request naming a file', 'Add a retry to `fetch_status`'],
  ['an empty prompt', '   '],
]
for (const [label, prompt] of quiet) {
  test(`quiet on ${label}`, () => {
    assert.equal(decide({ hook_event_name: 'UserPromptSubmit', prompt }), null)
  })
}

test('the build eval prompt gets the nudge as UserPromptSubmit additionalContext', () => {
  assert.deepEqual(decide({ hook_event_name: 'UserPromptSubmit', prompt: 'Add notifications to the app.' }), {
    hookSpecificOutput: { hookEventName: 'UserPromptSubmit', additionalContext: NUDGE },
  })
})

test('the nudge names the hook and states facts, not orders', () => {
  assert.match(NUDGE, /^planning vague-build check: /)
  assert.match(NUDGE, /\/planning:interview/)
  assert.doesNotMatch(NUDGE, /\b(must|always|never|you should)\b/i)
})

test('a payload with no string prompt is quiet', () => {
  assert.equal(decide({ hook_event_name: 'UserPromptSubmit' }), null)
  assert.equal(decide(null), null)
})

function fire(stdin) {
  return spawnSync(process.execPath, [join(here, 'vague-build-nudge.mjs')], { input: stdin, encoding: 'utf8', timeout: 5000 })
}

test('the script prints the JSON answer for a vague build prompt and exits 0', () => {
  const r = fire(JSON.stringify({ hook_event_name: 'UserPromptSubmit', prompt: 'Add notifications to the app.' }))
  assert.equal(r.status, 0)
  assert.equal(JSON.parse(r.stdout).hookSpecificOutput.additionalContext, NUDGE)
})

test('the script prints nothing for other prompts and for bad input, and exits 0', () => {
  for (const input of [JSON.stringify({ prompt: 'what does the retry code in src/ do?' }), 'not json', '']) {
    const r = fire(input)
    assert.equal(r.status, 0)
    assert.equal(r.stdout, '')
  }
})

test('hooks.json runs the script in exec form on UserPromptSubmit with a short timeout', () => {
  const rows = JSON.parse(readFileSync(join(here, 'hooks.json'), 'utf8')).hooks.UserPromptSubmit
  assert.equal(rows.length, 1)
  const [h] = rows[0].hooks
  assert.equal(h.type, 'command')
  assert.equal(h.command, 'node')
  assert.deepEqual(h.args, ['${CLAUDE_PLUGIN_ROOT}/hooks/vague-build-nudge.mjs'])
  assert.ok(h.timeout <= 5)
})
