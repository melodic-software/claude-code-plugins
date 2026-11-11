// The interview surface registry (surfaces/registry.mjs): AC5 (medium never moves the surface),
// AC13 surface part (unset surface with alternatives prints exactly one offer line) and AC15
// (a new surface entry needs no edit to the interview skill).
import { after, test } from 'node:test'
import assert from 'node:assert/strict'
import { execFileSync } from 'node:child_process'
import { chmodSync, cpSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { ENTRIES_DIR, loadEntries, resolveSurface } from '../surfaces/registry.mjs'

const here = dirname(fileURLToPath(import.meta.url))
const REGISTRY = join(here, '..', 'surfaces', 'registry.mjs')
const SKILL = join(here, '..', 'skills', 'interview', 'SKILL.md')
// What an unset userConfig key looks like in skill content: the literal token (lane-page.md).
const UNSET = '${user_config.surface}'
const made = []
const tmp = () => made[made.push(mkdtempSync(join(tmpdir(), 'surface-registry-'))) - 1]
after(() => made.forEach(d => rmSync(d, { recursive: true, force: true })))
const tools = (...names) => ({ has: n => names.includes(n), env: {} })
const PAGE_ONLY = tools('python3', 'curl', 'bash') // page available, no cloudflared
const ALL = tools('python3', 'curl', 'bash', 'cloudflared')
const NONE = tools()
const emptyProject = () => {
  const root = tmp()
  return { root, env: { CLAUDE_PROJECT_DIR: root, HOME: join(root, 'home'), PATH: '' } }
}

test('AC13: surface unset and two surfaces available prints exactly one offer line', async () => {
  const { env } = emptyProject()
  const r = await resolveSurface({ userConfig: { surface: UNSET }, env, context: PAGE_ONLY })
  assert.equal(r.surface, 'terminal') // plugin.json userConfig.surface.default
  assert.equal(r.decidedBy, 'default')
  assert.equal(typeof r.line, 'string')
  assert.equal(r.line.split('\n').length, 1)
  assert.match(r.line, /terminal \(default\)/)
  assert.match(r.line, /\bpage\b/)
  assert.doesNotMatch(r.line, /shared session/, 'an unavailable surface is not offered')
})

test('AC13 through the CLI: one JSON line whose offer line is a single line', () => {
  const { root } = emptyProject()
  const bin = join(root, 'bin')
  mkdirSync(bin)
  for (const name of ['python3', 'curl', 'bash']) {
    writeFileSync(join(bin, name), '#!/bin/sh\n')
    chmodSync(join(bin, name), 0o755)
  }
  const out = execFileSync(process.execPath, [REGISTRY, 'resolve', '--surface', UNSET], {
    env: { PATH: bin, HOME: join(root, 'home') },
    encoding: 'utf8',
  })
  assert.equal(out.trimEnd().split('\n').length, 1)
  const r = JSON.parse(out)
  assert.deepEqual([r.surface, r.alternatives], ['terminal', ['page']])
  assert.equal(r.line.split('\n').length, 1)
})

test('the CLI still prints its JSON line when the plugin path passes through a symlink', () => {
  const { root } = emptyProject()
  const link = join(root, 'planning')
  symlinkSync(join(here, '..'), link)
  const out = execFileSync(process.execPath, [join(link, 'surfaces', 'registry.mjs'), 'resolve', '--surface', 'page'], {
    env: { PATH: '', HOME: join(root, 'home'), CLAUDE_PROJECT_DIR: root },
    encoding: 'utf8',
  })
  assert.equal(JSON.parse(out).surface, 'page')
})

test('no offer line when the surface is set, or when no alternative is available', async () => {
  const { env } = emptyProject()
  const set = await resolveSurface({ userConfig: { surface: 'page' }, env, context: ALL })
  assert.deepEqual([set.surface, set.decidedBy, set.line], ['page', 'userConfig', null])
  const asked = await resolveSurface({ argument: 'page', userConfig: { surface: UNSET }, env, context: ALL })
  assert.deepEqual([asked.surface, asked.decidedBy, asked.line], ['page', 'argument', null])
  const alone = await resolveSurface({ userConfig: { surface: UNSET }, env, context: NONE })
  assert.deepEqual([alone.surface, alone.decidedBy, alone.line], ['terminal', 'default', null])
})

test('an empty or unknown value is unset; an unknown one is named in a notice', async () => {
  const { env } = emptyProject()
  const empty = await resolveSurface({ userConfig: { surface: '' }, env, context: NONE })
  assert.deepEqual([empty.surface, empty.decidedBy, empty.notices], ['terminal', 'default', []])
  const bogus = await resolveSurface({ userConfig: { surface: 'hologram' }, env, context: NONE })
  assert.deepEqual([bogus.surface, bogus.decidedBy], ['terminal', 'default'])
  assert.equal(bogus.notices.length, 1)
  assert.match(bogus.notices[0], /hologram/)
})

test('order: argument, then userConfig, then the default; a repository file never picks the surface', async () => {
  const { root, env } = emptyProject()
  mkdirSync(join(root, '.claude'))
  writeFileSync(join(root, '.claude', 'interview-surface.json'), JSON.stringify({ surface: 'page', port: 0 }))
  const unset = await resolveSurface({ userConfig: { surface: UNSET }, env, context: ALL })
  assert.deepEqual([unset.surface, unset.decidedBy], ['terminal', 'default'])
  const user = await resolveSurface({ userConfig: { surface: 'terminal' }, env, context: ALL })
  assert.deepEqual([user.surface, user.decidedBy], ['terminal', 'userConfig'])
  const arg = await resolveSurface({ argument: 'share', userConfig: { surface: 'terminal' }, env, context: ALL })
  assert.deepEqual([arg.surface, arg.decidedBy], ['shared-session', 'argument'])
})

test('a configured surface that cannot run stays chosen and says why, so its spoke degrades', async () => {
  const { env } = emptyProject()
  const r = await resolveSurface({ userConfig: { surface: 'page' }, env, context: NONE })
  assert.equal(r.surface, 'page')
  assert.equal(r.available.ok, false)
  assert.match(r.available.reason, /Python 3, curl, bash/)
  assert.equal(r.notices.length, 1)
  assert.deepEqual(r.read, ['skills/interview/context/lane-page.md', 'skills/interview/context/surface.md'])
})

test('every surface the offer line names can be asked for by that name', async () => {
  const { env } = emptyProject()
  for (const e of await loadEntries()) {
    const r = await resolveSurface({ argument: e.reportName, userConfig: { surface: UNSET }, env, context: ALL })
    assert.deepEqual([r.surface, r.decidedBy, r.notices], [e.id, 'argument', []], e.reportName)
  }
})

test('the document surface is picked by "document" alone and never offered beside the others', async () => {
  const { env } = emptyProject()
  for (const word of ['document', 'Document']) {
    const r = await resolveSurface({ argument: word, userConfig: { surface: UNSET }, env, context: NONE })
    assert.deepEqual([r.surface, r.decidedBy, r.available.ok], ['document', 'argument', true], word)
  }
  const old = await resolveSurface({ argument: 'questionnaire', userConfig: { surface: UNSET }, env, context: NONE })
  assert.deepEqual([old.surface, old.decidedBy], ['terminal', 'default'], 'the retired name is not an argument word')
  const unset = await resolveSurface({ userConfig: { surface: UNSET }, env, context: ALL })
  assert.ok(!unset.alternatives.includes('document'), 'not an alternative')
  assert.doesNotMatch(unset.line, /\bdocument\b/, 'not named in the offer line')
  const onPage = await resolveSurface({ argument: 'page', env, context: ALL })
  assert.ok(!onPage.alternatives.includes('document'))
  const listed = JSON.parse(execFileSync(process.execPath, [REGISTRY, 'list'], { encoding: 'utf8' }))
  const onRequest = Object.fromEntries(listed.map(e => [e.id, e.onRequest]))
  assert.deepEqual([onRequest.document, onRequest.page, onRequest.terminal], [true, false, false], 'list marks the on-request surface')
})

test('the shared session needs the owner\'s yes unless the user asked for it', async () => {
  const { env } = emptyProject()
  const asked = await resolveSurface({ argument: 'share', env, context: ALL })
  assert.equal(asked.handle.needsYes, false)
  const configured = await resolveSurface({ userConfig: { surface: 'shared-session' }, env, context: ALL })
  assert.equal(configured.handle.needsYes, true)
})

test('AC5: setting medium in every scope never changes the resolved surface', async () => {
  for (const surface of [UNSET, 'page']) {
    const { root, env } = emptyProject()
    const before = await resolveSurface({ userConfig: { surface }, env, context: ALL })
    const medium = 'medium: artifact\n'
    mkdirSync(join(env.HOME, '.claude'), { recursive: true })
    writeFileSync(join(env.HOME, '.claude', 'rendered-views.md'), medium)
    mkdirSync(join(root, '.claude'))
    writeFileSync(join(root, '.claude', 'rendered-views.md'), medium)
    writeFileSync(join(root, '.claude', 'rendered-views.local.md'), medium)
    writeFileSync(join(root, '.claude', 'interview-surface.json'), JSON.stringify({ medium: 'artifact' }))
    mkdirSync(join(root, 'docs', 'conventions'), { recursive: true })
    writeFileSync(join(root, 'docs', 'conventions', 'rendered-views.yaml'), medium)
    writeFileSync(join(root, 'docs', 'conventions', 'rendered-views.local.yaml'), medium)
    for (const m of ['artifact', 'file', 'terminal', 'hosted']) {
      const after = await resolveSurface({ userConfig: { surface, medium: m }, env: { ...env, medium: m }, context: ALL })
      assert.deepEqual(after, before, `medium ${m} moved the surface for surface=${surface}`)
    }
  }
})

test('AC15: a new surface entry is picked up from its own file, with no edit to the skill', async () => {
  const dir = tmp()
  cpSync(ENTRIES_DIR, dir, { recursive: true })
  writeFileSync(
    join(dir, 'kiosk.mjs'),
    `export default {
  id: 'kiosk', reportName: 'kiosk screen',
  available: () => ({ ok: true, reason: 'fixture' }),
  start: () => ({ read: ['skills/interview/context/lane-kiosk.md'] }),
}\n`,
  )
  const entries = await loadEntries(dir)
  const { env } = emptyProject()
  const offered = await resolveSurface({ userConfig: { surface: UNSET }, entries, env, context: NONE })
  assert.match(offered.line, /kiosk screen/)
  const chosen = await resolveSurface({ argument: 'kiosk', entries, env, context: NONE })
  assert.deepEqual([chosen.surface, chosen.read], ['kiosk', ['skills/interview/context/lane-kiosk.md']])

  // The skill's selection paragraph routes through the registry: no lane table, no entry named.
  const skill = readFileSync(SKILL, 'utf8')
  const start = skill.indexOf('**Question lanes.**')
  const section = skill.slice(start, skill.indexOf('## Stance', start))
  assert.ok(start >= 0 && section.includes('surfaces/registry.mjs'))
  assert.doesNotMatch(section, /^\|/m, 'no lane table')
  for (const e of await loadEntries()) {
    for (const word of [e.id, e.reportName]) {
      assert.doesNotMatch(section, new RegExp(`\\b${word}\\b`, 'i'), `selection names ${word}`)
    }
  }
})

test('AC13: an installed planner is named in the one offer line, beside the surfaces, and never required', async () => {
  const { env } = emptyProject()
  const planners = [{ name: 'html-plan', invoke: '/html-plan' }]
  const both = await resolveSurface({ userConfig: { surface: UNSET }, env, context: PAGE_ONLY, planners })
  assert.equal(both.line.split('\n').length, 1)
  assert.match(both.line, /^surface: terminal \(default\)\. Also available: page, html-plan planner \(\/html-plan\)\./)
  assert.equal(both.surface, 'terminal', 'the planner never replaces the surface')
  // The planner alone still earns the line; the eval's line grader still matches it.
  const alone = await resolveSurface({ userConfig: { surface: UNSET }, env, context: NONE, planners })
  assert.match(alone.line, /^\W*surface: \S[^\n]*\(default\)\. Also available: html-plan planner \(\/html-plan\)\.[^\n]*$/m)
  const none = await resolveSurface({ userConfig: { surface: UNSET }, env, context: NONE, planners: [] })
  assert.equal(none.line, null)
})

test('an offer rides the same single line, and a set surface prints no line at all', async () => {
  const { env } = emptyProject()
  const offers = [{ name: 'html-plan', text: 'html-plan, an optional planner, is not installed; say "install html-plan" to add it', install: 'x' }]
  const r = await resolveSurface({ userConfig: { surface: UNSET }, env, context: NONE, offers })
  assert.equal(r.line.split('\n').length, 1)
  assert.match(r.line, /^surface: terminal \(default\)\. html-plan, an optional planner, is not installed; say "install html-plan" to add it\.$/)
  assert.deepEqual(r.offers, offers)
  const set = await resolveSurface({ userConfig: { surface: 'page' }, env, context: PAGE_ONLY, offers, planners: [{ name: 'html-plan', invoke: '/html-plan' }] })
  assert.equal(set.line, null)
})

test('the CLI takes --data-dir and --unattended and stays offline without the claude CLI', () => {
  const { root } = emptyProject()
  const bin = join(root, 'bin')
  mkdirSync(bin)
  const out = execFileSync(
    process.execPath,
    [REGISTRY, 'resolve', '--surface', UNSET, '--data-dir', join(root, 'data'), '--unattended'],
    { env: { PATH: bin, HOME: join(root, 'home') }, encoding: 'utf8' },
  )
  const r = JSON.parse(out)
  assert.deepEqual([r.planners, r.offers, r.line], [[], [], null])
})

test('the gate sections name no surface value: each lane\'s part lives in its spoke', async () => {
  const lines = readFileSync(SKILL, 'utf8').split('\n')
  const section = (open, close) => lines.slice(lines.indexOf(open) + 1, lines.indexOf(close)).join('\n')
  const gated = [
    ['## Gates', '## Action Router'],
    ['## Action Router', '## Stance: supportive, depth-first, opinionated'],
    ['### Step 2. Drive the frontier-rounds loop', '### Step 3. Recognize the stop condition'],
    ['### Step 3. Recognize the stop condition', '### Step 4. Persist the Brief'],
    ['### Step 4. Persist the Brief', '### Step 5. Hand off'],
  ]
  for (const [open, close] of gated) {
    assert.ok(lines.indexOf(open) >= 0 && lines.indexOf(close) > lines.indexOf(open), `${open} is a section`)
    for (const e of await loadEntries()) {
      assert.doesNotMatch(section(open, close), new RegExp(`\\b${e.id}\\b`, 'i'), `${open} names ${e.id}`)
    }
  }
  assert.ok(!lines.some(l => /^#+ .*\bpage\b/i.test(l)), 'no heading names a surface')
})

test('a malformed or duplicate entry is refused at load', async () => {
  const dir = tmp()
  writeFileSync(join(dir, 'a.mjs'), "export default { id: 'a', reportName: 'a', available: () => ({ ok: true }) }\n")
  await assert.rejects(loadEntries(dir), /not a SurfaceEntry/)
  const dup = tmp()
  cpSync(join(ENTRIES_DIR, 'terminal.mjs'), join(dup, 'one.mjs'))
  cpSync(join(ENTRIES_DIR, 'terminal.mjs'), join(dup, 'two.mjs'))
  await assert.rejects(loadEntries(dup), /duplicate surface id terminal/)
})
