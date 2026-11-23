export const WORK_TYPES = new Set(['coding', 'web-ui', 'knowledge', 'image'])
export const VERDICTS = new Set(['lead', 'tie', 'behind', 'abstain'])
export const READ_STATES = new Set(['live', 'cached-stale', 'unread'])
export const ROW_STATUSES = new Set(['permanent', 'support-only'])
export const TIEBREAK_STEPS = new Set(['vendor-order', 'fewest-tokens', 'most-usage-left'])
export const TASK_CLASSES = new Set(['everyday', 'heavy'])
export const EFFORT_LADDER = ['low', 'medium', 'high', 'xhigh', 'max']

export const ID_RE = /^[a-z0-9][a-z0-9-]*$/
export const DATE_RE = /^[0-9]{4}-[0-9]{2}-[0-9]{2}$/

export function die(msg) {
  process.stderr.write(`vendor-decide: ${msg}\n`)
  process.exit(2)
}

export function parseUtcDate(str) {
  if (typeof str !== 'string' || !DATE_RE.test(str)) return null
  const [y, m, d] = str.split('-').map(Number)
  const dt = new Date(Date.UTC(y, m - 1, d))
  if (dt.getUTCFullYear() !== y || dt.getUTCMonth() !== m - 1 || dt.getUTCDate() !== d) return null
  return dt
}

export function raiseEffort(effort) {
  const idx = EFFORT_LADDER.indexOf(effort)
  if (idx < 0) return 'high'
  return EFFORT_LADDER[Math.min(idx + 1, EFFORT_LADDER.length - 1)]
}

export function resolveEffort(vendorInfo, modelId, requested) {
  if (!requested) return 'default'
  if (!vendorInfo) return requested
  const allowed =
    (modelId && vendorInfo.effortsByModel.get(modelId.toLowerCase())) || vendorInfo.topEfforts
  if (!allowed || allowed.length === 0) return requested
  return allowed.includes(requested) ? requested : 'default'
}

export function pickMode(values) {
  const counts = new Map()
  for (const v of values) {
    if (v == null) continue
    counts.set(v, (counts.get(v) || 0) + 1)
  }
  let best = null
  let bestCount = -1
  for (const [k, c] of counts.entries()) {
    if (c > bestCount) {
      best = k
      bestCount = c
    }
  }
  return best
}
