// test-scope: plugins/disk-hygiene/hooks/hooks.json
// Contract tests for the resume notice (#9853): a resumed session hears that the
// clean skill's guard is gone only when /disk-hygiene:clean ran in that session,
// and every other session start stays quiet.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync, existsSync } from 'node:fs'
import { spawnSync } from 'node:child_process'
import { tmpdir } from 'node:os'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { decide, markerCandidates, NOTICE, SUBDIR } from './resume-notice.mjs'

const here = dirname(fileURLToPath(import.meta.url))
const pluginRoot = dirname(here)
const hooksJson = JSON.parse(readFileSync(join(here, 'hooks.json'), 'utf8'))

function scratch(t) {
  const dir = mkdtempSync(join(tmpdir(), 'dh-resume-notice-'))
  t.after(() => rmSync(dir, { recursive: true, force: true }))
  return dir
}

function mark(root, session) {
  mkdirSync(join(root, SUBDIR), { recursive: true })
  writeFileSync(join(root, SUBDIR, `${session}.launched`), '')
}

const ctxFor = (markerRoot, extra = {}) => ({
  markerRoot,
  env: { TMPDIR: join(markerRoot, 'no-such-tmp') },
  platform: 'linux',
  ...extra,
})

test('a resume with the clean marker for this session gets the notice', (t) => {
  const root = scratch(t)
  mark(root, 'sess-1')
  const out = decide({ session_id: 'sess-1', source: 'resume' }, ctxFor(root))
  assert.deepEqual(out, { hookSpecificOutput: { hookEventName: 'SessionStart', additionalContext: NOTICE } })
  assert.match(NOTICE, /\/disk-hygiene:clean again/)
})

test('a resume without the marker stays quiet', (t) => {
  const root = scratch(t)
  assert.equal(decide({ session_id: 'sess-1', source: 'resume' }, ctxFor(root)), null)
  mark(root, 'other-session')
  assert.equal(decide({ session_id: 'sess-1', source: 'resume' }, ctxFor(root)), null)
})

test('startup, clear and fork stay quiet even with the marker', (t) => {
  const root = scratch(t)
  mark(root, 'sess-1')
  for (const source of ['startup', 'clear', 'fork', 'compact', undefined]) {
    assert.equal(decide({ session_id: 'sess-1', source }, ctxFor(root)), null, String(source))
  }
})

test('a missing or non-ASCII session id stays quiet', (t) => {
  const root = scratch(t)
  mark(root, '_')
  assert.equal(decide({ source: 'resume' }, ctxFor(root)), null)
  assert.equal(decide({ session_id: 'é', source: 'resume' }, ctxFor(root)), null)
})

test('an unexpanded data placeholder falls back to the tmp candidate off Windows only', () => {
  const env = { TMPDIR: '/t' }
  assert.deepEqual(markerCandidates('s', { markerRoot: '${CLAUDE_PLUGIN_DATA}', env, platform: 'linux' }), [
    join('/t', `disk-hygiene-${SUBDIR}`, 's.launched'),
  ])
  assert.deepEqual(markerCandidates('s', { markerRoot: '${CLAUDE_PLUGIN_DATA}', env, platform: 'win32' }), [])
  assert.deepEqual(markerCandidates('a/b', { markerRoot: '/d', env, platform: 'win32' }), [
    join('/d', SUBDIR, 'a_b.launched'),
  ])
})

// End to end through the registered rows: the UserPromptExpansion row writes the
// marker through the real launcher, and the SessionStart row reads it.
function registered(event, needle) {
  const rows = hooksJson.hooks[event].flatMap((group) => group.hooks)
  const row = rows.find((h) => (h.args ?? []).join(' ').includes(needle))
  assert.ok(row, `${event} has a row naming ${needle}`)
  return row
}

function run(row, dataRoot, payload, env = {}) {
  const args = row.args.map((a) =>
    a.replaceAll('${CLAUDE_PLUGIN_ROOT}', pluginRoot).replaceAll('${CLAUDE_PLUGIN_DATA}', dataRoot),
  )
  return spawnSync(row.command, args, {
    input: JSON.stringify(payload),
    encoding: 'utf8',
    env: { ...process.env, ...env },
    timeout: 30000,
  })
}

test('the registered rows: the notice fires only after /disk-hygiene:clean expanded in that session', (t) => {
  const data = scratch(t)
  const tmp = join(data, 'tmp')
  mkdirSync(tmp)
  const env = { TMPDIR: tmp }
  const expansion = registered('UserPromptExpansion', 'engine_context.py')
  const resume = registered('SessionStart', 'resume-notice.mjs')
  assert.equal(resume.command, 'node')

  const before = run(resume, data, { session_id: 'sess-9', source: 'resume' }, env)
  assert.equal(before.status, 0, before.stderr)
  assert.equal(before.stdout, '', 'no marker yet: quiet')

  const expanded = run(
    expansion,
    data,
    { session_id: 'sess-9', hook_event_name: 'UserPromptExpansion', command_name: 'disk-hygiene:clean' },
    env,
  )
  assert.equal(expanded.status, 0, expanded.stderr)
  assert.ok(existsSync(join(data, SUBDIR, 'sess-9.launched')), 'the expansion row wrote the marker')

  const after = run(resume, data, { session_id: 'sess-9', source: 'resume' }, env)
  assert.equal(after.status, 0, after.stderr)
  assert.equal(JSON.parse(after.stdout).hookSpecificOutput.additionalContext, NOTICE)

  for (const payload of [
    { session_id: 'sess-9', source: 'startup' },
    { session_id: 'sess-other', source: 'resume' },
  ]) {
    const quiet = run(resume, data, payload, env)
    assert.equal(quiet.status, 0, quiet.stderr)
    assert.equal(quiet.stdout, '', JSON.stringify(payload))
  }
})

test('a malformed payload exits 0 and prints nothing', () => {
  const r = spawnSync('node', [join(here, 'resume-notice.mjs'), '--marker-root', '/nonexistent'], {
    input: 'not json',
    encoding: 'utf8',
  })
  assert.equal(r.status, 0)
  assert.equal(r.stdout, '')
})
