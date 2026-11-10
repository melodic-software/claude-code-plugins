// Offer source for optional plugins (offerable.json): the one module that asks a marketplace
// whether it still lists a plugin and when the plugin's source path last changed. Every lookup is
// cached in plugin data for 24 hours, a failed one included, and any failure means no offer.
//
// Freshness, by the newest commit touching the plugin's source path: under 3 months a plain
// offer, 3 to 6 months an offer with that date, older than 6 months no offer. A name the
// catalog no longer lists (renamed or removed) gets no offer. An installed plugin is never
// offered; an installed planner is returned so the caller can name it.
import { execFileSync } from 'node:child_process'
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

export const OFFERABLE = join(dirname(fileURLToPath(import.meta.url)), 'offerable.json')
export const CACHE_MS = 24 * 3600e3
const CATALOG = '.claude-plugin/marketplace.json'
const TIMEOUT_MS = 5000

export const loadOfferable = (file = OFFERABLE) => JSON.parse(readFileSync(file, 'utf8')).plugins

export const installCommand = e => `claude plugin install ${e.name} --marketplace ${e.repo} --scope user`

// A data dir still shown as its `${...}` token was never substituted: there is nowhere to cache.
const usable = dir => typeof dir === 'string' && dir.trim() !== '' && !/^\$\{[\w.]+\}$/.test(dir.trim())

export async function githubJson(path) {
  const raw = path.includes('/contents/')
  const res = await fetch(`https://api.github.com/${path}`, {
    headers: {
      Accept: raw ? 'application/vnd.github.raw+json' : 'application/vnd.github+json',
      'User-Agent': 'planning-offer-source',
    },
    signal: AbortSignal.timeout(TIMEOUT_MS),
  })
  if (!res.ok) throw new Error(`GitHub ${res.status} for ${path}`)
  return JSON.parse(await res.text())
}

// Installed plugin names from `claude plugin list --json`; null when that cannot run, which
// also means nothing can be installed from here.
export function installedPlugins(
  list = () =>
    execFileSync('claude', ['plugin', 'list', '--json'], { encoding: 'utf8', timeout: 15000, stdio: ['ignore', 'pipe', 'ignore'] }),
) {
  try {
    return new Set(JSON.parse(list()).map(p => String(p.id).split('@')[0]))
  } catch {
    return null
  }
}

function sourceOf(entry, listed) {
  const s = listed.source
  if (typeof s === 'string' && s.startsWith('./')) return { repo: entry.repo, path: s.slice(2).replace(/\/+$/, '') }
  if (s?.source === 'github' && typeof s.repo === 'string') return { repo: s.repo, path: s.path ?? '' }
  return null
}

async function ask(entry, fetchJson) {
  const catalog = await fetchJson(`repos/${entry.repo}/contents/${CATALOG}`)
  if (!Array.isArray(catalog?.plugins)) throw new Error('the catalog has no plugins list')
  const listed = catalog.plugins.find(p => p?.name === entry.name)
  if (!listed) return { listed: false }
  const src = sourceOf(entry, listed)
  if (!src) throw new Error('unsupported source shape')
  const query = `${src.path ? `path=${encodeURIComponent(src.path)}&` : ''}per_page=1`
  const commits = await fetchJson(`repos/${src.repo}/commits?${query}`)
  const date = Array.isArray(commits) ? commits[0]?.commit?.committer?.date : undefined
  if (!date || Number.isNaN(Date.parse(date))) throw new Error('no commit on the source path')
  return { listed: true, repo: src.repo, path: src.path, lastCommit: date }
}

async function lookup(entry, { dataDir, now, fetchJson }) {
  const file = join(dataDir, 'offer-cache', `${entry.marketplace}--${entry.name}.json`)
  try {
    const cached = JSON.parse(readFileSync(file, 'utf8'))
    const age = now - Date.parse(cached.checkedAt)
    if (age >= 0 && age < CACHE_MS) return cached
  } catch {}
  const checkedAt = now.toISOString()
  const save = rec => writeFileSync(file, `${JSON.stringify({ checkedAt, ...rec })}\n`)
  // Claim the slot before asking: a cache that cannot be written means no lookup at all.
  try {
    mkdirSync(dirname(file), { recursive: true })
    save({ error: 'lookup in progress' })
  } catch {
    return { error: 'plugin data is not writable' }
  }
  const rec = await ask(entry, fetchJson).catch(e => ({ error: String(e?.message ?? e) }))
  try {
    save(rec)
  } catch {}
  return { checkedAt, ...rec }
}

const addMonths = (date, n) => {
  const d = new Date(date)
  d.setUTCMonth(d.getUTCMonth() + n)
  return d
}

export function freshness(lastCommit, now) {
  if (now < addMonths(lastCommit, 3)) return 'plain'
  if (now < addMonths(lastCommit, 6)) return 'dated'
  return 'stale'
}

const offerText = (e, date) =>
  `${e.name}, an optional ${e.kind} that ${e.helps}${date ? `, last updated ${date}` : ''}, is not installed; say "install ${e.name}" to add it`

export async function findOffers({
  entries = loadOfferable(),
  installed,
  unattended = false,
  dataDir,
  now = new Date(),
  fetchJson = githubJson,
} = {}) {
  if (!installed) return { planners: [], offers: [] }
  const planners = entries
    .filter(e => e.kind === 'planner' && installed.has(e.name))
    .map(e => ({ name: e.name, invoke: e.invoke }))
  const offers = []
  if (unattended || !usable(dataDir)) return { planners, offers }
  for (const e of entries.filter(x => !installed.has(x.name))) {
    const rec = await lookup(e, { dataDir, now, fetchJson })
    if (rec.error || !rec.listed) continue
    const f = freshness(rec.lastCommit, now)
    if (f === 'stale') continue
    const date = f === 'dated' ? rec.lastCommit.slice(0, 10) : null
    offers.push({ name: e.name, kind: e.kind, freshness: f, date, text: offerText(e, date), install: installCommand(e) })
  }
  return { planners, offers }
}
