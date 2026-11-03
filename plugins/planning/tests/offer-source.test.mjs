// Optional plugin offers (offers/offer-source.mjs): AC10 (freshness by the newest commit on the
// plugin's source path; no offer when renamed, unlisted, a lookup fails or the run is unattended;
// the install command carries user scope) and the 24-hour lookup cache.
//
// Canned responses are recorded, never written from the code's guess: fixtures/offers/catalog.json
// is GET repos/anthropics/claude-plugins-community/contents/.claude-plugin/marketplace.json
// (raw) on 2026-11-03, trimmed to two of its entries, and commits-html-plan.json is
// GET repos/anthropics/claude-plugins-community/commits?path=html-plan&per_page=1 on 2026-11-03,
// trimmed to the fields read. Commit ages are set by replacing that one date.
import { after, test } from 'node:test'
import assert from 'node:assert/strict'
import { mkdtempSync, readFileSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { findOffers, installCommand, loadOfferable } from '../offers/offer-source.mjs'

const here = dirname(fileURLToPath(import.meta.url))
const fixture = name => JSON.parse(readFileSync(join(here, 'fixtures', 'offers', name), 'utf8'))
const made = []
const dataDir = () => made[made.push(mkdtempSync(join(tmpdir(), 'offer-source-'))) - 1]
after(() => made.forEach(d => rmSync(d, { recursive: true, force: true })))

// Hand-computed: 2026-11-03 is day 307 of 2026, so 30, 120 and 200 days earlier are
// 2026-10-04, 2026-07-06 and 2026-04-17.
const NOW = new Date('2026-11-03T00:00:00Z')
const HTML_PLAN = {
  name: 'html-plan',
  marketplace: 'claude-community',
  repo: 'anthropics/claude-plugins-community',
  kind: 'planner',
  invoke: '/html-plan',
}

function commitsOn(date) {
  const [c] = fixture('commits-html-plan.json')
  return [{ ...c, commit: { ...c.commit, committer: { ...c.commit.committer, date }, author: { ...c.commit.author, date } } }]
}

// A fake GitHub API answering the two lookups; it records every path it was asked for.
function github({ catalog = fixture('catalog.json'), commits = fixture('commits-html-plan.json'), fail } = {}) {
  const calls = []
  const fetchJson = async path => {
    calls.push(path)
    if (fail) throw fail
    if (path === 'repos/anthropics/claude-plugins-community/contents/.claude-plugin/marketplace.json') return catalog
    if (path === 'repos/anthropics/claude-plugins-community/commits?path=html-plan&per_page=1') return commits
    throw new Error(`GitHub 404 for ${path}`)
  }
  return { calls, fetchJson }
}

const run = (gh, extra = {}) =>
  findOffers({ entries: [HTML_PLAN], installed: new Set(), dataDir: dataDir(), now: NOW, fetchJson: gh.fetchJson, ...extra })

test('AC10: a source path last committed 30 days ago gives a plain offer', async () => {
  const r = await run(github({ commits: commitsOn('2026-10-04T12:00:00Z') }))
  assert.equal(r.offers.length, 1)
  assert.equal(r.offers[0].name, 'html-plan')
  assert.equal(r.offers[0].freshness, 'plain')
  assert.equal(r.offers[0].date, null)
  assert.doesNotMatch(r.offers[0].text, /2026-10-04/)
})

test('AC10: 120 days gives an offer that shows the date', async () => {
  const r = await run(github({ commits: commitsOn('2026-07-06T12:00:00Z') }))
  assert.equal(r.offers.length, 1)
  assert.equal(r.offers[0].freshness, 'dated')
  assert.equal(r.offers[0].date, '2026-07-06')
  assert.match(r.offers[0].text, /2026-07-06/)
})

test('AC10: 200 days gives no offer', async () => {
  const r = await run(github({ commits: commitsOn('2026-04-17T12:00:00Z') }))
  assert.deepEqual(r.offers, [])
})

test('the recorded html-plan commit (2026-10-05) is a plain offer on 2026-11-03', async () => {
  const r = await run(github())
  assert.equal(r.offers[0]?.freshness, 'plain')
})

test('AC10: no offer for a renamed plugin (its source now listed under another name)', async () => {
  const catalog = fixture('catalog.json')
  catalog.plugins = catalog.plugins.map(p => (p.name === 'html-plan' ? { ...p, name: 'claim-plan' } : p))
  const r = await run(github({ catalog }))
  assert.deepEqual(r.offers, [])
})

test('AC10: no offer for an unlisted plugin', async () => {
  const catalog = fixture('catalog.json')
  catalog.plugins = catalog.plugins.filter(p => p.name !== 'html-plan')
  const r = await run(github({ catalog }))
  assert.deepEqual(r.offers, [])
})

test('AC10: no offer when a lookup fails (a thrown error, a 403, a 404, a malformed reply)', async () => {
  for (const gh of [
    github({ fail: new Error('getaddrinfo ENOTFOUND api.github.com') }),
    github({ fail: new Error('GitHub 403 for repos/anthropics/claude-plugins-community/commits') }),
    github({ commits: [] }),
    github({ commits: { message: 'Not Found' } }),
    github({ catalog: { plugins: 'not a list' } }),
  ]) {
    assert.deepEqual((await run(gh)).offers, [])
  }
})

test('AC10: no offer, and no lookup, on the unattended path', async () => {
  const gh = github()
  const r = await run(gh, { unattended: true })
  assert.deepEqual(r.offers, [])
  assert.deepEqual(gh.calls, [])
})

test('no offer, and no lookup, without a plugin data directory to cache in', async () => {
  for (const dir of [undefined, '', '${CLAUDE_PLUGIN_DATA}']) {
    const gh = github()
    const r = await run(gh, { dataDir: dir })
    assert.deepEqual([r.offers, gh.calls], [[], []])
  }
})

test('no offer when the installed list is unknown (no claude CLI to install with)', async () => {
  const gh = github()
  const r = await run(gh, { installed: null })
  assert.deepEqual([r.offers, r.planners, gh.calls], [[], [], []])
})

test('AC13: an installed planner is named, never offered and never looked up', async () => {
  const gh = github()
  const r = await run(gh, { installed: new Set(['html-plan']) })
  assert.deepEqual(r.offers, [])
  assert.deepEqual(r.planners, [{ name: 'html-plan', invoke: '/html-plan' }])
  assert.deepEqual(gh.calls, [])
})

test('AC10: the install command carries user scope', async () => {
  const cmd = installCommand(HTML_PLAN)
  assert.match(cmd, /^claude plugin install html-plan /)
  assert.match(cmd, /(^| )--scope user( |$)/)
  assert.match(cmd, /--marketplace anthropics\/claude-plugins-community/)
  const r = await run(github())
  assert.equal(r.offers[0].install, cmd)
})

test('one lookup per plugin per 24 hours: a second run within the day makes no request', async () => {
  const dir = dataDir()
  const gh = github()
  await findOffers({ entries: [HTML_PLAN], installed: new Set(), dataDir: dir, now: NOW, fetchJson: gh.fetchJson })
  const first = gh.calls.length
  assert.ok(first > 0)
  const later = new Date(NOW.getTime() + 23 * 3600e3)
  const again = await findOffers({ entries: [HTML_PLAN], installed: new Set(), dataDir: dir, now: later, fetchJson: gh.fetchJson })
  assert.equal(gh.calls.length, first)
  assert.equal(again.offers[0]?.freshness, 'plain')
  const nextDay = new Date(NOW.getTime() + 25 * 3600e3)
  await findOffers({ entries: [HTML_PLAN], installed: new Set(), dataDir: dir, now: nextDay, fetchJson: gh.fetchJson })
  assert.equal(gh.calls.length, first * 2)
})

test('a failed lookup is cached too, so a failing network is not asked again within the day', async () => {
  const dir = dataDir()
  const gh = github({ fail: new Error('GitHub 403 rate limit') })
  const args = { entries: [HTML_PLAN], installed: new Set(), dataDir: dir, fetchJson: gh.fetchJson }
  await findOffers({ ...args, now: NOW })
  const first = gh.calls.length
  const r = await findOffers({ ...args, now: new Date(NOW.getTime() + 3600e3) })
  assert.deepEqual([r.offers, gh.calls.length], [[], first])
})

// cant-fail-ok: decision Q35 names html-plan, from its marketplace, as the optional planner.
test('the shipped offer list holds html-plan as an optional planner from its marketplace', () => {
  const entries = loadOfferable()
  const h = entries.find(e => e.name === 'html-plan')
  assert.deepEqual(
    [h.marketplace, h.repo, h.kind],
    ['claude-community', 'anthropics/claude-plugins-community', 'planner'],
  )
})
