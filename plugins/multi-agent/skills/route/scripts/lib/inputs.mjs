import { spawnSync } from 'node:child_process'
import fs from 'node:fs'
import path from 'node:path'
import {
  DATE_RE,
  ID_RE,
  READ_STATES,
  ROW_STATUSES,
  SAFE_FIELD_RE,
  TIEBREAK_STEPS,
  VERDICTS,
  WORK_TYPES,
  die,
} from './common.mjs'

const SAFE_RECORD_FIELDS = ['model', 'version', 'effort']

const REGISTRY_TOP_KEYS = new Set(['version', 'note', 'rows'])
const REGISTRY_ROW_KEYS = new Set([
  'id',
  'workloads',
  'link',
  'publisher',
  'provider_own',
  'status',
  'task_set',
  'expect',
  'freshness_seconds',
  'enabled',
])
const VERDICT_RECORD_KEYS = new Set([
  'source_id',
  'workload',
  'vendor',
  'model',
  'version',
  'effort',
  'verdict',
  'error_range',
  'page_date',
  'read',
  'tokens',
])
const VERDICT_REQUIRED_KEYS = [
  'source_id',
  'workload',
  'vendor',
  'model',
  'version',
  'effort',
  'verdict',
  'error_range',
  'page_date',
  'read',
]
const TOKENS_KEYS = new Set(['value', 'unit', 'source'])
const WRAPPER_KEYS = new Set(['records', 'findings'])
const SETTINGS_KEYS = new Set([
  'routing',
  'trials',
  'auto_delegation',
  'tiebreak',
  'trials_prove',
  'trials_fail',
  'promotion_audits',
  'promotion_days',
  'claude',
  'codex',
  'antigravity',
  'sources',
  'source',
])
const VENDOR_ENTRY_KEYS = new Set(['in_use', 'rank'])
const SOURCE_ENTRY_KEYS = new Set(['enabled'])

export function readJson(filePath, label) {
  let raw
  try {
    raw = fs.readFileSync(filePath, 'utf8')
  } catch (err) {
    die(`cannot read ${label} (${filePath}): ${err.message}`)
  }
  try {
    return JSON.parse(raw)
  } catch (err) {
    die(`invalid JSON in ${label} (${filePath}): ${err.message}`)
  }
}

export function readDefaults(filePath) {
  const out = {
    model: 'inherit',
    effort: 'medium',
    vendors: { routing: true, trials: false, auto_delegation: false },
  }
  let raw
  try {
    raw = fs.readFileSync(filePath, 'utf8')
  } catch (err) {
    die(`cannot read defaults (${filePath}): ${err.message}`)
  }
  const stack = []
  for (const line of raw.split(/\r?\n/)) {
    if (!line.trim() || /^\s*#/.test(line)) continue
    const m = line.match(/^(\s*)([A-Za-z0-9_-]+):\s*(.*)$/)
    if (!m) continue
    const indent = m[1].length
    const key = m[2]
    let val = m[3].trim()
    while (stack.length > 0 && stack[stack.length - 1].indent >= indent) stack.pop()
    if (val === '') {
      stack.push({ indent, key })
      continue
    }
    const commentIdx = val.indexOf(' #')
    if (commentIdx >= 0) val = val.slice(0, commentIdx).trim()
    val = val.replace(/^['"]|['"]$/g, '')
    const dotted = [...stack.map((s) => s.key), key].join('.')
    if (dotted === 'roles.worker.model') out.model = val
    if (dotted === 'roles.worker.effort') out.effort = val
    if (dotted === 'vendors.routing' && (val === 'true' || val === 'false')) {
      out.vendors.routing = val === 'true'
    }
    if (dotted === 'vendors.trials' && (val === 'true' || val === 'false')) {
      out.vendors.trials = val === 'true'
    }
    if (dotted === 'vendors.auto_delegation' && (val === 'true' || val === 'false')) {
      out.vendors.auto_delegation = val === 'true'
    }
  }
  return out
}

export function loadSettings(filePath, defaults) {
  const base = {
    routing: defaults.vendors.routing,
    trials: defaults.vendors.trials,
    auto_delegation: defaults.vendors.auto_delegation,
    tiebreak: [],
    trials_prove: null,
    trials_fail: null,
    vendors: {
      claude: { in_use: null, rank: null },
      codex: { in_use: null, rank: null },
      gemini: { in_use: null, rank: null },
    },
    sources: {},
    worker: { model: null, effort: null },
  }
  if (!filePath) return base

  const raw = readJson(filePath, 'settings')
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) {
    die('settings must be a JSON object')
  }
  const hasVendors = 'vendors' in raw && raw.vendors !== null && raw.vendors !== undefined
  if (hasVendors && (typeof raw.vendors !== 'object' || Array.isArray(raw.vendors))) {
    die('settings.vendors must be an object')
  }
  const hasRoles = 'roles' in raw && raw.roles !== null && raw.roles !== undefined
  if (hasRoles && (typeof raw.roles !== 'object' || Array.isArray(raw.roles))) {
    die('settings.roles must be an object')
  }
  if (hasRoles) {
    const workerSingle =
      raw.roles.worker &&
      typeof raw.roles.worker === 'object' &&
      !Array.isArray(raw.roles.worker) &&
      raw.roles.worker.single &&
      typeof raw.roles.worker.single === 'object' &&
      !Array.isArray(raw.roles.worker.single)
        ? raw.roles.worker.single
        : null
    if (workerSingle) {
      if (typeof workerSingle.model === 'string' && workerSingle.model.trim()) {
        base.worker.model = workerSingle.model.trim()
      }
      if (typeof workerSingle.effort === 'string' && workerSingle.effort.trim()) {
        base.worker.effort = workerSingle.effort.trim()
      }
    }
  }
  const doc = hasVendors ? raw.vendors : hasRoles ? {} : raw

  for (const k of Object.keys(doc)) {
    if (!SETTINGS_KEYS.has(k)) die(`settings has unknown field '${k}'`)
  }
  for (const b of ['routing', 'trials', 'auto_delegation']) {
    if (b in doc && doc[b] !== null) {
      if (typeof doc[b] !== 'boolean') die(`settings.${b} must be a boolean`)
      base[b] = doc[b]
    }
  }
  if ('tiebreak' in doc && doc.tiebreak !== null) {
    if (!Array.isArray(doc.tiebreak)) die('settings.tiebreak must be an array')
    const seen = new Set()
    for (const step of doc.tiebreak) {
      if (typeof step !== 'string' || !TIEBREAK_STEPS.has(step)) {
        die(`settings.tiebreak has unknown step '${step}'`)
      }
      if (seen.has(step)) die(`settings.tiebreak has duplicate step '${step}'`)
      seen.add(step)
    }
    base.tiebreak = [...doc.tiebreak]
  }
  if ('trials_prove' in doc && doc.trials_prove !== null) {
    if (!Number.isInteger(doc.trials_prove) || doc.trials_prove < 1) {
      die('settings.trials_prove must be an integer >= 1')
    }
    base.trials_prove = doc.trials_prove
  }
  if ('trials_fail' in doc && doc.trials_fail !== null) {
    if (!Number.isInteger(doc.trials_fail) || doc.trials_fail < 2) {
      die('settings.trials_fail must be an integer >= 2')
    }
    base.trials_fail = doc.trials_fail
  }
  const vendorKeyMap = [
    ['claude', 'claude'],
    ['codex', 'codex'],
    ['antigravity', 'gemini'],
  ]
  for (const [cfgKey, vName] of vendorKeyMap) {
    if (!(cfgKey in doc) || doc[cfgKey] === null) continue
    const entry = doc[cfgKey]
    if (!entry || typeof entry !== 'object' || Array.isArray(entry)) {
      die(`settings.${cfgKey} must be an object`)
    }
    for (const k of Object.keys(entry)) {
      if (!VENDOR_ENTRY_KEYS.has(k)) die(`settings.${cfgKey} has unknown field '${k}'`)
    }
    if ('in_use' in entry && entry.in_use !== null) {
      if (typeof entry.in_use !== 'boolean') die(`settings.${cfgKey}.in_use must be a boolean`)
      base.vendors[vName].in_use = entry.in_use
    }
    if ('rank' in entry && entry.rank !== null) {
      if (!Number.isInteger(entry.rank)) die(`settings.${cfgKey}.rank must be an integer`)
      base.vendors[vName].rank = entry.rank
    }
  }
  if ('sources' in doc && doc.sources !== null) {
    if (!doc.sources || typeof doc.sources !== 'object' || Array.isArray(doc.sources)) {
      die('settings.sources must be an object')
    }
    for (const [sid, entry] of Object.entries(doc.sources)) {
      if (!ID_RE.test(sid)) die(`settings.sources has invalid id '${sid}'`)
      if (!entry || typeof entry !== 'object' || Array.isArray(entry)) {
        die(`settings.sources.${sid} must be an object`)
      }
      for (const k of Object.keys(entry)) {
        if (!SOURCE_ENTRY_KEYS.has(k)) die(`settings.sources.${sid} has unknown field '${k}'`)
      }
      if ('enabled' in entry && entry.enabled !== null) {
        if (typeof entry.enabled !== 'boolean') {
          die(`settings.sources.${sid}.enabled must be a boolean`)
        }
        base.sources[sid] = { enabled: entry.enabled }
      }
    }
  }
  return base
}

export function resolveRepoRoot() {
  const res = spawnSync('git', ['rev-parse', '--show-toplevel'], { encoding: 'utf8' })
  if (res.status !== 0 || !res.stdout) return null
  const root = res.stdout.trim()
  return root || null
}

export function validateRegistry(doc) {
  if (!doc || typeof doc !== 'object' || Array.isArray(doc)) {
    die('registry must be a JSON object')
  }
  for (const k of Object.keys(doc)) {
    if (!REGISTRY_TOP_KEYS.has(k)) die(`registry has unknown field '${k}'`)
  }
  if (doc.version !== 1) die(`registry version must be 1, got ${JSON.stringify(doc.version)}`)
  if ('note' in doc && (typeof doc.note !== 'string' || doc.note.length === 0)) {
    die('registry note must be a non-empty string')
  }
  if (!Array.isArray(doc.rows)) die('registry rows must be an array')

  const seenIds = new Set()
  for (let i = 0; i < doc.rows.length; i++) {
    const r = doc.rows[i]
    const ctx = `registry.rows[${i}]`
    if (!r || typeof r !== 'object' || Array.isArray(r)) die(`${ctx} must be an object`)
    for (const k of Object.keys(r)) {
      if (!REGISTRY_ROW_KEYS.has(k)) die(`${ctx} has unknown field '${k}'`)
    }
    if (typeof r.id !== 'string' || !ID_RE.test(r.id)) die(`${ctx}.id is invalid`)
    if (seenIds.has(r.id)) die(`duplicate registry row id '${r.id}'`)
    seenIds.add(r.id)
    if (!Array.isArray(r.workloads) || r.workloads.length === 0) die(`${ctx}.workloads must be a non-empty array`)
    const wlSeen = new Set()
    for (const w of r.workloads) {
      if (!WORK_TYPES.has(w) || wlSeen.has(w)) die(`${ctx}.workloads has invalid or duplicate entry '${w}'`)
      wlSeen.add(w)
    }
    if (typeof r.link !== 'string' || !r.link.startsWith('https://')) die(`${ctx}.link must be an https URL`)
    if (typeof r.publisher !== 'string' || r.publisher.length === 0) die(`${ctx}.publisher must be a non-empty string`)
    if (typeof r.provider_own !== 'boolean') die(`${ctx}.provider_own must be a boolean`)
    if (!ROW_STATUSES.has(r.status)) die(`${ctx}.status must be permanent or support-only`)
    if (typeof r.task_set !== 'string' || r.task_set.length === 0) die(`${ctx}.task_set must be a non-empty string`)
    if (typeof r.expect !== 'string' || r.expect.length === 0) die(`${ctx}.expect must be a non-empty string`)
    if ('freshness_seconds' in r && (!Number.isInteger(r.freshness_seconds) || r.freshness_seconds < 1)) {
      die(`${ctx}.freshness_seconds must be a positive integer`)
    }
    if ('enabled' in r && typeof r.enabled !== 'boolean') die(`${ctx}.enabled must be a boolean`)
  }
  return doc
}

export function validateVerdictRecord(rec, ctx) {
  if (!rec || typeof rec !== 'object' || Array.isArray(rec)) die(`${ctx} must be an object`)
  for (const k of Object.keys(rec)) {
    if (!VERDICT_RECORD_KEYS.has(k)) die(`${ctx} has unknown field '${k}'`)
  }
  for (const k of VERDICT_REQUIRED_KEYS) {
    if (!(k in rec)) die(`${ctx} is missing required field '${k}'`)
  }
  if (typeof rec.source_id !== 'string' || !ID_RE.test(rec.source_id)) die(`${ctx}.source_id is invalid`)
  if (!WORK_TYPES.has(rec.workload)) die(`${ctx}.workload is invalid`)
  if (typeof rec.vendor !== 'string' || !ID_RE.test(rec.vendor)) die(`${ctx}.vendor is invalid`)
  if (rec.model !== null && typeof rec.model !== 'string') die(`${ctx}.model must be string or null`)
  if (rec.version !== null && typeof rec.version !== 'string') die(`${ctx}.version must be string or null`)
  if (rec.effort !== null && typeof rec.effort !== 'string') die(`${ctx}.effort must be string or null`)
  if (!VERDICTS.has(rec.verdict)) die(`${ctx}.verdict is invalid`)
  if (typeof rec.error_range !== 'boolean') die(`${ctx}.error_range must be boolean`)
  if (rec.page_date !== null && (typeof rec.page_date !== 'string' || !DATE_RE.test(rec.page_date))) {
    die(`${ctx}.page_date must be YYYY-MM-DD or null`)
  }
  if (!READ_STATES.has(rec.read)) die(`${ctx}.read is invalid`)
  if ('tokens' in rec) {
    const t = rec.tokens
    if (!t || typeof t !== 'object' || Array.isArray(t)) die(`${ctx}.tokens must be an object`)
    for (const k of Object.keys(t)) {
      if (!TOKENS_KEYS.has(k)) die(`${ctx}.tokens has unknown field '${k}'`)
    }
    if (typeof t.value !== 'number' || !Number.isFinite(t.value) || t.value < 0) {
      die(`${ctx}.tokens.value must be a non-negative number`)
    }
    if (typeof t.unit !== 'string' || t.unit.length === 0) die(`${ctx}.tokens.unit must be a non-empty string`)
    if (typeof t.source !== 'string' || t.source.length === 0) die(`${ctx}.tokens.source must be a non-empty string`)
  }
}

export function loadRecordsArg(spec) {
  let boundSourceId = null
  let filePath = spec
  const eq = spec.indexOf('=')
  if (eq > 0 && ID_RE.test(spec.slice(0, eq))) {
    boundSourceId = spec.slice(0, eq)
    filePath = spec.slice(eq + 1)
  }
  const raw = readJson(filePath, `records (${filePath})`)
  let records
  let findings = []
  if (Array.isArray(raw)) {
    records = raw
  } else if (raw && typeof raw === 'object') {
    for (const k of Object.keys(raw)) {
      if (!WRAPPER_KEYS.has(k)) die(`records wrapper (${filePath}) has unknown field '${k}'`)
    }
    if (!Array.isArray(raw.records)) die(`records wrapper (${filePath}) must contain a 'records' array`)
    records = raw.records
    if ('findings' in raw) {
      if (!Array.isArray(raw.findings) || !raw.findings.every((f) => typeof f === 'string')) {
        die(`records wrapper (${filePath}) 'findings' must be an array of strings`)
      }
      findings = raw.findings
    }
  } else {
    die(`records (${filePath}) must be an array or {records, findings} object`)
  }
  records.forEach((r, idx) => validateVerdictRecord(r, `${filePath}[${idx}]`))
  return { boundSourceId, records, findings }
}

export function normalizeModels(doc) {
  if (!doc || typeof doc !== 'object' || Array.isArray(doc)) die('--models must be a JSON object')
  const byVendor = new Map()
  for (const [rawKey, entry] of Object.entries(doc)) {
    const vendor = rawKey.toLowerCase() === 'antigravity' ? 'gemini' : rawKey.toLowerCase()
    if (Array.isArray(entry)) {
      const ids = entry.filter((x) => typeof x === 'string' && x.length > 0)
      byVendor.set(vendor, {
        status: ids.length > 0 ? 'ok' : 'unavailable',
        reason: null,
        ids,
        idSet: new Set(ids.map((s) => s.toLowerCase())),
        idCanonical: new Map(ids.map((s) => [s.toLowerCase(), s])),
        effortsByModel: new Map(),
        defaultEffortByModel: new Map(),
        versionByModel: new Map(),
        contextWindowByModel: new Map(),
        topContextWindow: null,
        topEfforts: null,
        defaultModel: null,
        defaultEffort: null,
        tools: null,
        toolSet: null,
        image: null,
        breaker: { open: false, reason: null, reset_at: null },
        skippedModels: new Set(),
      })
      continue
    }
    if (!entry || typeof entry !== 'object') continue
    const status = entry.status ?? 'ok'
    const modelsArr = Array.isArray(entry.models) ? entry.models : []
    const ids = []
    const effortsByModel = new Map()
    const defaultEffortByModel = new Map()
    const versionByModel = new Map()
    const contextWindowByModel = new Map()
    for (const m of modelsArr) {
      const id = typeof m === 'string' ? m : m && typeof m.id === 'string' ? m.id : null
      if (!id) continue
      ids.push(id)
      if (m && typeof m === 'object' && Array.isArray(m.efforts)) {
        effortsByModel.set(id.toLowerCase(), m.efforts)
      }
      if (m && typeof m === 'object' && typeof m.default_effort === 'string' && m.default_effort.trim()) {
        defaultEffortByModel.set(id.toLowerCase(), m.default_effort.trim())
      }
      if (m && typeof m === 'object' && typeof m.version === 'string' && m.version.trim()) {
        versionByModel.set(id.toLowerCase(), m.version.trim())
      }
      if (
        m &&
        typeof m === 'object' &&
        typeof m.context_window === 'number' &&
        Number.isFinite(m.context_window) &&
        m.context_window > 0
      ) {
        contextWindowByModel.set(id.toLowerCase(), m.context_window)
      }
    }
    const topContextWindow =
      typeof entry.context_window === 'number' &&
      Number.isFinite(entry.context_window) &&
      entry.context_window > 0
        ? entry.context_window
        : null
    const tools = Array.isArray(entry.tools)
      ? entry.tools
          .filter((x) => typeof x === 'string' && x.trim().length > 0)
          .map((x) => x.trim().toLowerCase())
      : null
    const rawBreaker = entry.breaker && typeof entry.breaker === 'object' && !Array.isArray(entry.breaker)
      ? entry.breaker
      : null
    const breaker = {
      open: Boolean(rawBreaker && rawBreaker.open === true),
      reason:
        rawBreaker && typeof rawBreaker.reason === 'string' && rawBreaker.reason.trim()
          ? rawBreaker.reason.trim()
          : null,
      reset_at:
        rawBreaker && typeof rawBreaker.reset_at === 'string' && rawBreaker.reset_at.trim()
          ? rawBreaker.reset_at.trim()
          : null,
    }
    byVendor.set(vendor, {
      status,
      reason: typeof entry.reason === 'string' ? entry.reason : null,
      ids,
      idSet: new Set(ids.map((s) => s.toLowerCase())),
      idCanonical: new Map(ids.map((s) => [s.toLowerCase(), s])),
      effortsByModel,
      defaultEffortByModel,
      versionByModel,
      contextWindowByModel,
      topContextWindow,
      topEfforts: Array.isArray(entry.efforts) ? entry.efforts : null,
      defaultModel: typeof entry.default_model === 'string' ? entry.default_model : null,
      defaultEffort: typeof entry.default_effort === 'string' ? entry.default_effort : null,
      tools,
      toolSet: tools ? new Set(tools) : null,
      image: typeof entry.image === 'boolean' ? entry.image : null,
      breaker,
      skippedModels: new Set(),
    })
  }
  return byVendor
}

export function loadUsage(filePath) {
  const byVendor = new Map()
  if (!filePath) return byVendor
  const doc = readJson(filePath, 'usage')
  if (!doc || typeof doc !== 'object' || Array.isArray(doc)) {
    die('--usage must be a JSON object')
  }
  for (const [rawKey, entry] of Object.entries(doc)) {
    const vendor = rawKey.toLowerCase() === 'antigravity' ? 'gemini' : rawKey.toLowerCase()
    if (!entry || typeof entry !== 'object' || Array.isArray(entry)) {
      byVendor.set(vendor, { status: 'unavailable', remaining: null, reason: 'invalid usage reading' })
      continue
    }
    if (
      entry.status === 'ok' &&
      typeof entry.remaining === 'number' &&
      Number.isFinite(entry.remaining) &&
      entry.remaining >= 0 &&
      entry.remaining <= 1
    ) {
      byVendor.set(vendor, {
        status: 'ok',
        remaining: entry.remaining,
        window: typeof entry.window === 'string' ? entry.window : null,
        resets_at: typeof entry.resets_at === 'string' ? entry.resets_at : null,
        source: typeof entry.source === 'string' ? entry.source : null,
      })
    } else {
      const reason =
        typeof entry.reason === 'string' && entry.reason.trim()
          ? entry.reason.trim()
          : entry.status === 'ok'
            ? 'missing valid remaining fraction'
            : `status ${String(entry.status ?? 'unavailable')}`
      byVendor.set(vendor, { status: 'unavailable', remaining: null, reason })
    }
  }
  return byVendor
}

export function loadManifest(filePath) {
  const manifestDoc = readJson(filePath, 'manifest')
  const manifestBoards = Array.isArray(manifestDoc.boards)
    ? manifestDoc.boards
    : Array.isArray(manifestDoc.pages)
      ? manifestDoc.pages
      : die('manifest must contain a boards array')

  const manifestById = new Map()
  for (const entry of manifestBoards) {
    if (entry && typeof entry.source_id === 'string') {
      manifestById.set(entry.source_id, entry)
    }
  }
  return manifestById
}

export function mergeTeamRegistryRows(registry, registryPath, notes) {
  const mergedRows = [...registry.rows]
  const shippedIds = new Set(registry.rows.map((r) => r.id))
  const repoRoot = resolveRepoRoot()
  if (repoRoot) {
    const teamPath = path.join(repoRoot, 'docs', 'conventions', 'multi-agent', 'benchmarks.json')
    if (fs.existsSync(teamPath) && path.resolve(teamPath) !== path.resolve(registryPath)) {
      const teamReg = validateRegistry(readJson(teamPath, 'team registry'))
      for (const teamRow of teamReg.rows) {
        if (shippedIds.has(teamRow.id)) {
          notes.push(`team registry row '${teamRow.id}' refused: duplicates shipped row id`)
          continue
        }
        mergedRows.push(teamRow)
      }
    }
  }
  return mergedRows
}

export function loadBoundRecords(recordSpecs, disabledRows, manifestById, rowById, taskType, notes) {
  const recordsBySource = new Map()
  const findingsCountBySource = new Map()
  for (const spec of recordSpecs) {
    const { boundSourceId, records, findings } = loadRecordsArg(spec)
    if (findings.length > 0) {
      const recSources = new Set(records.map((r) => r.source_id))
      const sourceLabel =
        boundSourceId || (recSources.size === 1 ? [...recSources][0] : 'unknown-source')
      findingsCountBySource.set(
        sourceLabel,
        (findingsCountBySource.get(sourceLabel) || 0) + findings.length,
      )
    }
    for (const r of records) {
      if (boundSourceId && r.source_id !== boundSourceId) {
        notes.push(
          `dropped record claiming source_id '${r.source_id}' inside manifest-bound records for '${boundSourceId}'`,
        )
        continue
      }
      const sid = boundSourceId || r.source_id
      if (disabledRows.has(sid)) continue
      const mEntry = manifestById.get(sid)
      if (!mEntry) {
        notes.push(`dropped record for '${sid}': absent from fetch manifest`)
        continue
      }
      if (!rowById.has(sid)) {
        notes.push(`dropped record for '${sid}': absent from registry`)
        continue
      }
      const badFields = SAFE_RECORD_FIELDS.filter(
        (f) => r[f] !== null && !SAFE_FIELD_RE.test(r[f]),
      )
      if (badFields.length > 0) {
        notes.push(`dropped record for '${sid}': invalid ${badFields.join(', ')} value`)
        continue
      }
      const stampedRead =
        mEntry.state !== 'read' ? 'unread' : mEntry.stale === true ? 'cached-stale' : 'live'
      const stampedDate =
        typeof mEntry.page_date === 'string' && DATE_RE.test(mEntry.page_date)
          ? mEntry.page_date
          : null
      const stamped = {
        ...r,
        source_id: sid,
        page_date: stampedDate,
        read: stampedRead,
      }
      if (stamped.workload !== taskType) continue
      if (!recordsBySource.has(sid)) recordsBySource.set(sid, [])
      recordsBySource.get(sid).push(stamped)
    }
  }
  for (const [sid, count] of findingsCountBySource.entries()) {
    notes.push(
      `${sid}: the page holds content the reader flagged as instructions (${count} item(s)); not relayed`,
    )
  }
  return recordsBySource
}
