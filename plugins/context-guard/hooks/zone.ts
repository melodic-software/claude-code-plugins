// The zone resolver of scripts/context-zone.sh, in TypeScript: the same gates, bands, combination
// rule and malformed-file notices over the same snapshot and zones.json text. The shared fixture
// (scripts/context-zone.fixtures.mjs) holds the two equal; the reader contract is the authority.

export type Word = 'smart' | 'acceptable' | 'dumb' | 'unknown'
export type Zone = Exclude<Word, 'unknown'>
export type Bands = { smart: number; acceptable: number; tokens: [number, number, number][] }

export const STALENESS_SECONDS = 600
const TOKEN_SEMANTICS_MIN_VERSION = '2.1.132'
export const DEFAULT_BANDS: Bands = {
  smart: 50,
  acceptable: 75,
  tokens: [
    [200_000, 100_000, 150_000],
    [1_000_000, 128_000, 250_000],
  ],
}
export const RANK: Record<Zone, number> = { smart: 0, acceptable: 1, dumb: 2 }
const ZONES: Zone[] = ['smart', 'acceptable', 'dumb']

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

// zones.json: each shape validated on its own, a malformed one falls back with its notice.
export const readBands = (zones: string | null): { bands: Bands; notices: string[] } => {
  if (zones === null) return { bands: DEFAULT_BANDS, notices: [] }
  const parsed = parse(zones)
  if (!parsed.ok) return { bands: DEFAULT_BANDS, notices: ['percent', 'token_bands'] }
  const z = parsed.value
  const bands: Bands = { ...DEFAULT_BANDS }
  const notices: string[] = []
  const s = isObject(z) ? orNull(z.smart_max_used_percentage) : null
  const a = isObject(z) ? orNull(z.acceptable_max_used_percentage) : null
  if (isNumber(s) && isNumber(a) && s > 0 && s < a && a <= 100) {
    bands.smart = s
    bands.acceptable = a
  } else if (!(isObject(z) && s === null && a === null && Object.keys(z).every(k => KNOWN_KEYS.includes(k)))) {
    notices.push('percent')
  }
  const tb = isObject(z) ? orNull(z.token_bands) : null
  if (tb !== null) {
    const entries = isObject(tb) ? Object.entries(tb) : []
    const valid =
      entries.length > 0 &&
      entries.every(([key, v]) => {
        if (!/^[0-9]+$/.test(key) || !isObject(v)) return false
        const sm = orNull(v.smart_max_tokens)
        const am = orNull(v.acceptable_max_tokens)
        return isNumber(sm) && isNumber(am) && sm > 0 && sm < am && am <= Number(key)
      })
    if (valid) {
      bands.tokens = entries
        .map(([key, v]) => [Number(key), (v as Json).smart_max_tokens as number, (v as Json).acceptable_max_tokens as number] as [number, number, number])
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

const band = (value: number, smart: number, acceptable: number): Zone => (value <= smart ? 'smart' : value <= acceptable ? 'acceptable' : 'dumb')
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

export type TokenShape = { used: number; size: number; smart: number; acceptable: number }

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
  return used <= size && row !== undefined ? { used, size, smart: row[1], acceptable: row[2] } : undefined
}

// The zone of one snapshot body, both shapes, worse wins; undefined when neither is computable.
export const zoneOfWindow = (w: Json, cliVersion: unknown, bands: Bands): Zone | undefined => {
  const p = orNull(w.used_percentage)
  const pz = isNumber(p) && p >= 0 && p <= 100 ? band(p, bands.smart, bands.acceptable) : undefined
  const t = tokenShape(w, cliVersion, bands)
  const tz = t && band(t.used, t.smart, t.acceptable)
  return pz && tz ? worse(pz, tz) : (pz ?? tz)
}

export const resolveZone = (args: { sid: string; snapshot: string | null; zones: string | null; nowSec: number }): { word: Word; notices: string[] } => {
  const unknown = (notices: string[] = []) => ({ word: 'unknown' as const, notices })
  if (!/^[A-Za-z0-9_-]+$/.test(args.sid) || args.snapshot === null) return unknown()
  const { bands, notices } = readBands(args.zones)
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
  const zone = zoneOfWindow(w, s.cli_version, bands)
  return zone === undefined ? unknown(notices) : { word: zone, notices }
}

export const isZone = (word: unknown): word is Zone => ZONES.includes(word as Zone)
