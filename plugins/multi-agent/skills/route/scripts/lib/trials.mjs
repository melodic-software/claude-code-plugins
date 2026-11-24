import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { resolveEffort } from './common.mjs'

const DEFAULT_PLUGIN_ROOT = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  '..',
  '..',
  '..',
  '..',
)

export function installedDataDir(root) {
  const resolved = path.resolve(root)
  const parts = resolved.split(path.sep)
  const cache = parts.lastIndexOf('cache')
  if (cache < 1 || parts[cache - 1] !== 'plugins' || parts.length !== cache + 4) return null
  const [marketplace, plugin] = parts.slice(cache + 1)
  if (plugin !== 'multi-agent') return null
  return path.join(
    parts.slice(0, cache).join(path.sep),
    'data',
    `${plugin}@${marketplace}`.replace(/[^A-Za-z0-9_-]/g, '-'),
  )
}

export function resolveOutcomesDir(explicitStateDir, env = process.env, root = DEFAULT_PLUGIN_ROOT) {
  if (explicitStateDir) {
    const resolved = path.resolve(explicitStateDir)
    const direct = path.join(resolved, 'outcomes')
    if (fs.existsSync(direct)) return direct
    const nested = path.join(resolved, 'vendor-state', 'outcomes')
    if (fs.existsSync(nested)) return nested
    return null
  }
  const installed = installedDataDir(root)
  let dataDir = installed
  if (!dataDir) {
    const given = env.CLAUDE_PLUGIN_DATA
    if (given && /^multi-agent-/.test(path.win32.basename(given))) {
      dataDir = path.resolve(given)
    }
  }
  if (!dataDir) return null
  const outcomes = path.join(dataDir, 'vendor-state', 'outcomes')
  return fs.existsSync(outcomes) ? outcomes : null
}

export function loadOutcomesForWorkType(outcomesDir, workType) {
  const proven = []
  const failed = []
  if (!outcomesDir) return { proven, failed }
  let entries
  try {
    entries = fs.readdirSync(outcomesDir).filter((f) => f.endsWith('.json'))
  } catch {
    return { proven, failed }
  }
  for (const name of entries) {
    try {
      const doc = JSON.parse(fs.readFileSync(path.join(outcomesDir, name), 'utf8'))
      if (!doc || typeof doc !== 'object' || !doc.key || typeof doc.key !== 'object') continue
      if (doc.key.work_type !== workType) continue
      if (doc.result === 'proven') proven.push(doc)
      else if (doc.result === 'failed') failed.push(doc)
    } catch {
    }
  }
  return { proven, failed }
}

export function versionMatches(outcomeVersion, candidateVersion) {
  if (!candidateVersion) return true
  return outcomeVersion === candidateVersion
}

export function isPairFailed(failedOutcomes, cand) {
  if (!cand || !cand.vendor || !cand.model) return false
  const v = cand.vendor.toLowerCase()
  const m = cand.model.toLowerCase()
  const e = (cand.effort || 'default').toLowerCase()
  return failedOutcomes.some(
    (o) =>
      o.key.vendor === v &&
      o.key.model.toLowerCase() === m &&
      o.key.effort === e &&
      versionMatches(o.key.version, cand.version || null),
  )
}

export function isProvenEligible(
  outcome,
  modelsByVendor,
  skippedSilentVendors,
  unavailableInUseVendors,
  taskType,
  gatedVendors = new Set(),
) {
  const { vendor, model, version, effort } = outcome.key
  if (skippedSilentVendors.has(vendor) || unavailableInUseVendors.has(vendor) || gatedVendors.has(vendor)) {
    return false
  }
  const vInfo = modelsByVendor.get(vendor)
  if (!vInfo || vInfo.status !== 'ok' || vInfo.ids.length === 0) return false
  if (!vInfo.idSet.has(model.toLowerCase())) return false
  const currentVersion = vInfo.versionByModel.get(model.toLowerCase()) || null
  if (!versionMatches(version, currentVersion)) return false
  if (taskType === 'image' && vInfo.image !== true) return false
  if (effort && effort !== 'default') {
    const allowed = vInfo.effortsByModel.get(model.toLowerCase()) || vInfo.topEfforts
    if (!allowed || allowed.length === 0 || !allowed.includes(effort)) return false
  }
  return true
}

export function selectProvenOutcome({
  provenOutcomes,
  modelsByVendor,
  skippedSilentVendors,
  unavailableInUseVendors,
  gatedVendors = new Set(),
  effectiveVendorOrder,
  taskType,
  notes,
}) {
  const eligibleProven = provenOutcomes.filter((o) =>
    isProvenEligible(o, modelsByVendor, skippedSilentVendors, unavailableInUseVendors, taskType, gatedVendors),
  )
  if (eligibleProven.length === 0) return null

  const orderIdx = (v) => {
    const i = effectiveVendorOrder.indexOf(v)
    return i >= 0 ? i : effectiveVendorOrder.length
  }
  eligibleProven.sort((a, b) => {
    const nonClaudeDiff = (a.key.vendor === 'claude' ? 1 : 0) - (b.key.vendor === 'claude' ? 1 : 0)
    if (nonClaudeDiff !== 0) return nonClaudeDiff
    const ord = orderIdx(a.key.vendor) - orderIdx(b.key.vendor)
    if (ord !== 0) return ord
    return String(b.at || '').localeCompare(String(a.at || ''))
  })
  const best = eligibleProven[0]
  const vInfo = modelsByVendor.get(best.key.vendor)
  const vendor = best.key.vendor
  const model =
    (vInfo && vInfo.idCanonical.get(best.key.model.toLowerCase())) || best.key.model
  const version = best.key.version
  const effort = best.key.effort
  notes.push(`proven on this machine for ${taskType}: ${vendor} ${model} @ ${effort}`)
  return { vendor, model, version, effort, basis: 'proven' }
}

export function selectActiveTrial({
  modelsByVendor,
  skippedSilentVendors,
  unavailableInUseVendors,
  gatedVendors = new Set(),
  effectiveVendorOrder,
  failedOutcomes,
  taskType,
  notes,
}) {
  const seen = new Set()
  let skippedFailedTrial = 0
  for (const vName of [...effectiveVendorOrder, ...modelsByVendor.keys()]) {
    if (
      seen.has(vName) ||
      vName === 'claude' ||
      skippedSilentVendors.has(vName) ||
      unavailableInUseVendors.has(vName) ||
      gatedVendors.has(vName)
    ) {
      continue
    }
    seen.add(vName)
    const vInfo = modelsByVendor.get(vName)
    if (!vInfo || vInfo.status !== 'ok' || vInfo.ids.length === 0) continue
    if (taskType === 'image' && vInfo.image !== true) continue
    const model = vInfo.defaultModel || vInfo.ids[0]
    if (!vInfo.idSet.has(model.toLowerCase())) continue
    const cand = {
      vendor: vName,
      model,
      version: vInfo.versionByModel.get(model.toLowerCase()) || null,
      effort: resolveEffort(vInfo, model, null),
    }
    if (isPairFailed(failedOutcomes, cand)) {
      skippedFailedTrial++
      continue
    }
    notes.push(`active trial selected ${cand.vendor} ${cand.model} @ ${cand.effort} for ${taskType}`)
    return { ...cand, basis: 'trial' }
  }
  if (skippedFailedTrial > 0) {
    notes.push(`all candidate pairs failed trial for ${taskType}; keeping default claude`)
  }
  return null
}
