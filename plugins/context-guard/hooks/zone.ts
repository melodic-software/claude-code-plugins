// The zone resolver of scripts/context-zone.sh, in TypeScript: the same gates, bands, combination
// rule and malformed-file notices over the same snapshot and zones.json text. The shared fixture
// (scripts/context-zone.fixtures.mjs) holds the two equal; the reader contract is the authority.

export type Word = 'light' | 'moderate' | 'heavy' | 'unknown'
export type Zone = Exclude<Word, 'unknown'>
export type Bands = { light: number; moderate: number; tokens: [number, number, number][] }

export const STALENESS_SECONDS = 600
const TOKEN_SEMANTICS_MIN_VERSION = '2.1.132'
export const DEFAULT_BANDS: Bands = {
  light: 50,
  moderate: 75,
  tokens: [
    [200_000, 100_000, 150_000],
    [1_000_000, 128_000, 500_000],
  ],
}
export const RANK: Record<Zone, number> = { light: 0, moderate: 1, heavy: 2 }
const ZONES: Zone[] = ['light', 'moderate', 'heavy']

type Json = Record<string, unknown>
const isObject = (v: unknown): v is Json => typeof v === 'object' && v !== null && !Array.isArray(v)
const isNumber = (v: unknown): v is number => typeof v === 'number' && Number.isFinite(v)
// jq's `x // null`: false and null both fall through.
const orNull = (v: unknown) => (v === undefined || v === null || v === false ? null : v)

const parse = (text: string): { ok: true; value: unknown } | { ok: false } => {
  try {
    return { ok: true, value: JSON.parse(text) }
  } catch {
    return { ok: false }
  }
}

// Keys an object with no edge keys may hold and still keep the default bands silently; the mod
// reads all but token_bands.
const KNOWN_KEYS = ['token_bands', 'actions', 'approach_margin', 'thresholds']

// An old key name, read for one release as its new name; the new name wins when both are set,
// and the old key is dropped either way.
export const alias = (o: Json, next: string, old: string): Json => {
  const { [old]: was, ...rest } = o
  return orNull(rest[next]) === null && orNull(was) !== null ? { ...rest, [next]: was } : rest
}

// zones.json with the old band key names (smart_max_*, acceptable_max_*) read as the new ones.
const normalize = (z: unknown): unknown => {
  if (!isObject(z)) return z
  const o = alias(alias(z, 'light_max_used_percentage', 'smart_max_used_percentage'), 'moderate_max_used_percentage', 'acceptable_max_used_percentage')
  const tb = orNull(o.token_bands)
  if (!isObject(tb)) return o
  const rows = Object.entries(tb).map(([k, v]) => [k, isObject(v) ? alias(alias(v, 'light_max_tokens', 'smart_max_tokens'), 'moderate_max_tokens', 'acceptable_max_tokens') : v])
  return { ...o, token_bands: Object.fromEntries(rows) }
}

// zones.json: each shape validated on its own, a malformed one falls back with its notice.
export const readBands = (zones: string | null): { bands: Bands; notices: string[] } => {
  if (zones === null) return { bands: DEFAULT_BANDS, notices: [] }
  const parsed = parse(zones)
  if (!parsed.ok) return { bands: DEFAULT_BANDS, notices: ['percent', 'token_bands'] }
  const z = normalize(parsed.value)
  const bands: Bands = { ...DEFAULT_BANDS }
  const notices: string[] = []
  const l = isObject(z) ? orNull(z.light_max_used_percentage) : null
  const m = isObject(z) ? orNull(z.moderate_max_used_percentage) : null
  if (isNumber(l) && isNumber(m) && l > 0 && l < m && m <= 100) {
    bands.light = l
    bands.moderate = m
  } else if (!(isObject(z) && l === null && m === null && Object.keys(z).every(k => KNOWN_KEYS.includes(k)))) {
    notices.push('percent')
  }
  const tb = isObject(z) ? orNull(z.token_bands) : null
  if (tb !== null) {
    const entries = isObject(tb) ? Object.entries(tb) : []
    const valid =
      entries.length > 0 &&
      entries.every(([key, v]) => {
        if (!/^[0-9]+$/.test(key) || !isObject(v)) return false
        const lt = orNull(v.light_max_tokens)
        const mt = orNull(v.moderate_max_tokens)
        return isNumber(lt) && isNumber(mt) && lt > 0 && lt < mt && mt <= Number(key)
      })
    if (valid) {
      bands.tokens = entries
        .map(([key, v]) => [Number(key), (v as Json).light_max_tokens as number, (v as Json).moderate_max_tokens as number] as [number, number, number])
        .sort((x, y) => x[0] - y[0])
    } else {
      notices.push('token_bands')
    }
  }
  return { bands, notices }
}

const versionAtLeast = (candidate: string, min: string) => {
  if (!/^[0-9]+(\.[0-9]+)*$/.test(candidate)) return false
  const c = candidate.split('.').map(Number)
  const m = min.split('.').map(Number)
  const n = Math.max(c.length, m.length)
  for (let i = 0; i < n; i += 1) {
    const x = c[i] ?? 0
    const y = m[i] ?? 0
    if (x !== y) return x > y
  }
  return true
}

const band = (value: number, light: number, moderate: number): Zone => (value <= light ? 'light' : value <= moderate ? 'moderate' : 'heavy')
export const worse = (a: Zone, b: Zone): Zone => (RANK[a] >= RANK[b] ? a : b)

// A strict YYYY-MM-DDTHH:MM:SSZ that names a real instant, refusing values a lenient parser
// would normalize (February 30, second 60, hour 24).
const epochOf = (capturedAt: string): number | undefined => {
  const m = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})Z$/.exec(capturedAt)
  if (!m) return undefined
  const d = new Date(0)
  d.setUTCFullYear(Number(m[1]), Number(m[2]) - 1, Number(m[3]))
  d.setUTCHours(Number(m[4]), Number(m[5]), Number(m[6]), 0)
  const ms = d.getTime()
  if (!Number.isFinite(ms)) return undefined
  const back = d.toISOString().replace(/\.\d{3}Z$/, 'Z')
  return back === capturedAt ? ms / 1000 : undefined
}

export type TokenShape = { used: number; size: number; light: number; moderate: number }

// The token shape of one snapshot body: occupancy, window size and the band row's edges;
// undefined when it is not computable.
export const tokenShape = (w: Json, cliVersion: unknown, bands: Bands): TokenShape | undefined => {
  const input = orNull(w.total_input_tokens)
  const output = orNull(w.total_output_tokens)
  const size = orNull(w.context_window_size)
  if (
    !(isNumber(input) && input >= 0 && isNumber(output) && output >= 0 && isNumber(size) && size > 0) ||
    !versionAtLeast(typeof cliVersion === 'string' ? cliVersion : '', TOKEN_SEMANTICS_MIN_VERSION)
  ) return undefined
  const used = input + output
  const row = bands.tokens.filter(([cls]) => cls <= size).at(-1)
  return used <= size && row !== undefined ? { used, size, light: row[1], moderate: row[2] } : undefined
}

// The zone of one snapshot body, both shapes, worse wins; undefined when neither is computable.
export const zoneOfWindow = (w: Json, cliVersion: unknown, bands: Bands): Zone | undefined => {
  const p = orNull(w.used_percentage)
  const pz = isNumber(p) && p >= 0 && p <= 100 ? band(p, bands.light, bands.moderate) : undefined
  const t = tokenShape(w, cliVersion, bands)
  const tz = t && band(t.used, t.light, t.moderate)
  return pz && tz ? worse(pz, tz) : (pz ?? tz)
}

// A percentage of the auto-compact window as a percentage of the model's window, which
// used_percentage counts against. Unchanged unless the compaction window is the smaller one.
export const ofWindow = (percent: number, window: number, compactWindow: number | undefined) =>
  compactWindow !== undefined && window > 0 && compactWindow > 0 && compactWindow < window ? (percent * compactWindow) / window : percent

// Percentage edges that follow a lowered auto-compact window. The mod passes the window it read
// as `follow`; without one, resolveZone takes the snapshot's bands.auto_compact_window, as the
// shell resolver does.
export const followWindow = (bands: Bands, window: number, compactWindow: number | undefined): Bands => ({
  ...bands,
  light: ofWindow(bands.light, window, compactWindow),
  moderate: ofWindow(bands.moderate, window, compactWindow),
})

const windowSize = (w: Json) => {
  const size = orNull(w.context_window_size)
  return isNumber(size) ? size : 0
}

const publishedWindow = (s: Json) => {
  const b = orNull(s.bands)
  const acw = isObject(b) ? orNull(b.auto_compact_window) : null
  return isNumber(acw) ? acw : undefined
}

export const resolveZone = (args: {
  sid: string
  snapshot: string | null
  zones: string | null
  nowSec: number
  follow?: (bands: Bands) => Bands
}): { word: Word; notices: string[] } => {
  const unknown = (notices: string[] = []) => ({ word: 'unknown' as const, notices })
  if (!/^[A-Za-z0-9_-]+$/.test(args.sid) || args.snapshot === null) return unknown()
  const { bands: read, notices } = readBands(args.zones)
  const parsed = parse(args.snapshot)
  if (!parsed.ok || !isObject(parsed.value)) return unknown(notices)
  const s = parsed.value
  if (typeof orNull(s.captured_at) !== 'string') return unknown(notices)
  if (orNull(s.session_id) !== args.sid) return unknown(notices)
  const w = orNull(s.context_window)
  if (!isObject(w) || orNull(w.current_usage) === null) return unknown(notices)
  const at = epochOf(s.captured_at as string)
  if (at === undefined) return unknown(notices)
  const age = args.nowSec - at
  if (age < -60 || age > STALENESS_SECONDS) return unknown(notices)
  const bands = args.follow ? args.follow(read) : followWindow(read, windowSize(w), publishedWindow(s))
  const zone = zoneOfWindow(w, s.cli_version, bands)
  return zone === undefined ? unknown(notices) : { word: zone, notices }
}

export const isZone = (word: unknown): word is Zone => ZONES.includes(word as Zone)
