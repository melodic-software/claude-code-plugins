const MAX_PATTERN_LENGTH = 200
const MAX_DEPTH = 64
// A user pattern runs over windows of this many characters, each overlapping the next by half, so
// its cost grows with the text's length, not its square; a match up to half a window is whole in one.
const WINDOW = 1024
// The guard's bound on the lengths a pattern tries at each start: one unbounded quantifier (a
// window) times a small factor.
const MAX_COST = 4 * WINDOW
const QUANTIFIER_BRACE = /^\{(\d+)(?:(,)(\d*))?\}/

// Each built-in is anchored on a run start (a lookbehind) so a long run of word characters is
// scanned once, not once per start position. Open-ended tails (`*`) mask a token still streaming.
const BUILTIN_SOURCES = [
  // An address with its TLD anywhere, or one still streaming at the end of the text.
  '(?<![A-Za-z0-9._%+-])[A-Za-z0-9._%+-]+@(?:[A-Za-z0-9-]+(?:\\.[A-Za-z0-9-]+)*\\.[A-Za-z]{2,}|[A-Za-z0-9-]*(?:\\.[A-Za-z0-9-]*)*(?![\\s\\S]))',
  '(?<![A-Za-z0-9])sk-[\\w-]*',
  '(?<![A-Za-z0-9_])gh[pousr]_\\w*',
  '(?<![A-Za-z0-9_])github_pat_\\w*',
  '(?<![A-Za-z0-9])xox[abprs]-[\\w-]*',
  '(?<![A-Za-z0-9])AKIA[0-9A-Z]*',
  '(?<![A-Za-z0-9_])eyJ[\\w-]*(?:\\.[\\w-]*){0,2}',
  '-----BEGIN [A-Z ]*PRIVATE KEY(?: BLOCK)?-----[\\s\\S]*?(?:-----END [A-Z ]*PRIVATE KEY(?: BLOCK)?-----|(?![\\s\\S]))',
]

// The user patterns, which run per window.
const EXTRA = new WeakSet<RegExp>()

// A CSI sequence (colors, erase-line) or a two-character escape; OSC text such as a hyperlink
// target is matched like any other text.
const ANSI = /\u001b(?:\[[0-?]*[ -/]*[@-~]|[@-Z\\^_])/g

const NOREPLY = /^noreply@/i
const GITHUB_NOREPLY = /^\d+\+[^@]+@users\.noreply\.github\.com$/i

const isAllowed = (match: string, offset: number, text: string): boolean =>
  NOREPLY.test(match) || GITHUB_NOREPLY.test(match) || (/^git@/i.test(match) && text[offset + match.length] === ':')

// How many lengths a pattern can try at one start: the product of its quantifiers' ranges, an
// unbounded one counted as a window. Infinity for a shape that backtracks without bound: a
// quantified group holding a quantifier or an alternation.
const backtrackCost = (source: string): number => {
  const groups: { quantified: boolean; alternates: boolean }[] = [{ quantified: false, alternates: false }]
  let cost = 1
  let inClass = false
  // The range of the quantifier at `i`, its length, and whether it repeats without a small bound.
  const quantifierAt = (i: number): { range: number; length: number; repeats: boolean } | undefined => {
    const c = source[i]
    let q: { range: number; length: number; repeats: boolean } | undefined
    if (c === '*' || c === '+') q = { range: WINDOW, length: 1, repeats: true }
    else if (c === '?') q = { range: 2, length: 1, repeats: false }
    else if (c === '{') {
      const m = QUANTIFIER_BRACE.exec(source.slice(i))
      if (!m) return undefined
      const min = Number(m[1])
      const max = m[2] === undefined ? min : m[3] === '' ? Infinity : Number(m[3])
      q = { range: Math.min(max - min + 1, WINDOW), length: m[0].length, repeats: true }
    }
    // A lazy marker belongs to the quantifier.
    if (q && source[i + q.length] === '?') q.length++
    return q
  }
  for (let i = 0; i < source.length; i++) {
    const c = source[i]
    const top = groups[groups.length - 1] as { quantified: boolean; alternates: boolean }
    if (c === '\\') {
      i++
    } else if (inClass) {
      if (c === ']') inClass = false
    } else if (c === '[') {
      inClass = true
    } else if (c === '(') {
      groups.push({ quantified: false, alternates: false })
      if (source[i + 1] === '?') i++
    } else if (c === ')') {
      const inner = groups.pop() ?? { quantified: false, alternates: false }
      const q = quantifierAt(i + 1)
      if (q?.repeats && (inner.quantified || inner.alternates)) return Infinity
      const parent = groups[groups.length - 1] ?? top
      parent.quantified ||= inner.quantified || q !== undefined
      parent.alternates ||= inner.alternates
      if (q) {
        cost *= q.range
        i += q.length
      }
    } else if (c === '|') {
      top.alternates = true
    } else {
      const q = quantifierAt(i)
      if (q) {
        top.quantified = true
        cost *= q.range
        i += q.length - 1
      }
    }
  }
  return cost
}

const compileExtra = (source: string): RegExp | undefined => {
  if (typeof source !== 'string' || source.length === 0 || source.length > MAX_PATTERN_LENGTH) return undefined
  if (backtrackCost(source) > MAX_COST) return undefined
  try {
    if (new RegExp(source).test('')) return undefined
    const re = new RegExp(source, 'g')
    EXTRA.add(re)
    return re
  } catch {
    return undefined
  }
}

export function compilePatterns(extra: readonly string[]): { patterns: RegExp[]; invalid: string[] } {
  const patterns = BUILTIN_SOURCES.map((s) => new RegExp(s, 'g'))
  const invalid: string[] = []
  for (const source of extra) {
    const re = compileExtra(source)
    if (re) patterns.push(re)
    else invalid.push(source)
  }
  return { patterns, invalid }
}

type Range = [number, number]

// The spans every pattern matches, overlapping or touching ones joined, sorted. Patterns run over
// the text with each escape sequence replaced by as many NUL characters, so a token right after a
// color code starts a match and no escape becomes part of one.
function findRanges(text: string, patterns: readonly RegExp[]): Range[] {
  const view = text.replace(ANSI, (s) => '\u0000'.repeat(s.length))
  const ranges: Range[] = []
  const collect = (pattern: RegExp, from: number, to: number) => {
    for (const m of view.slice(from, to).matchAll(pattern)) {
      const at = from + m.index
      if (m[0] !== '' && !isAllowed(m[0], at, view)) ranges.push([at, at + m[0].length])
    }
  }
  for (const pattern of patterns) {
    if (!EXTRA.has(pattern)) {
      collect(pattern, 0, view.length)
      continue
    }
    for (let from = 0; ; from += WINDOW / 2) {
      collect(pattern, from, from + WINDOW)
      if (from + WINDOW >= view.length) break
    }
  }
  ranges.sort((a, b) => a[0] - b[0])
  const merged: Range[] = []
  for (const [start, end] of ranges) {
    const last = merged[merged.length - 1]
    if (last && start <= last[1]) last[1] = Math.max(last[1], end)
    else merged.push([start, end])
  }
  return merged
}

export function maskText(text: string, patterns: readonly RegExp[], mask: string): string {
  const ranges = findRanges(text, patterns)
  if (ranges.length === 0) return text
  // Escape sequences inside a match are kept, so the colors after it stay as the text set them.
  const escapes = [...text.matchAll(ANSI)].map((m): Range => [m.index, m.index + m[0].length])
  let out = ''
  let at = 0
  let j = 0
  for (const [start, end] of ranges) {
    out += text.slice(at, start)
    let masked = false
    let i = start
    while (j < escapes.length && (escapes[j] as Range)[1] <= start) j++
    for (let k = j; k < escapes.length && (escapes[k] as Range)[0] < end; k++) {
      const s = Math.max((escapes[k] as Range)[0], start)
      const e = Math.min((escapes[k] as Range)[1], end)
      if (s > i && !masked) {
        out += mask
        masked = true
      }
      out += text.slice(s, e)
      i = e
    }
    if (i < end && !masked) out += mask
    at = end
  }
  return out + text.slice(at)
}

// The text around each range and the ranges, as `text.split(re)` and `text.match(re)` give them.
const cut = (text: string, ranges: readonly Range[]): { parts: string[]; hidden: string[] } => {
  const parts: string[] = []
  let at = 0
  for (const [start, end] of ranges) {
    parts.push(text.slice(at, start))
    at = end
  }
  parts.push(text.slice(at))
  return { parts, hidden: ranges.map(([start, end]) => text.slice(start, end)) }
}

// The text around each match and the matches: `parts` has one more entry than `hidden`.
// Overlapping or touching matches join into one.
export function splitMatches(text: string, patterns: readonly RegExp[]): { parts: string[]; hidden: string[] } {
  return cut(text, findRanges(text, patterns))
}

const FENCE = /^ {0,3}(```|~~~)/
const BLANK = /^[ \t]*$/

// Markdown blocks as [start, end) offsets: runs of lines split at blank lines, a fenced block kept
// whole (to the end of the text when it is not closed).
function blockSpans(text: string): Range[] {
  const out: Range[] = []
  let start = -1
  let end = 0
  let at = 0
  let fence: string | undefined
  for (const line of text.split('\n')) {
    if (fence === undefined && BLANK.test(line)) {
      if (start >= 0) out.push([start, end])
      start = -1
    } else {
      const marker = FENCE.exec(line)?.[1]
      if (marker !== undefined) fence = fence === undefined ? marker : fence === marker ? undefined : fence
      if (start < 0) start = at
      end = at + line.length
    }
    at += line.length + 1
  }
  if (start >= 0) out.push([start, end])
  return out
}

export function blocks(text: string): string[] {
  return blockSpans(text).map(([start, end]) => text.slice(start, end))
}

// Each block with the text around its matches and the matches. Matching runs over the whole text,
// so a match that crosses a blank line is hidden in every block it reaches.
export function splitBlocks(
  text: string,
  patterns: readonly RegExp[],
): { block: string; parts: string[]; hidden: string[] }[] {
  const ranges = findRanges(text, patterns)
  return blockSpans(text).map(([start, end]) => {
    const inside = ranges
      .filter(([s, e]) => s < end && e > start)
      .map(([s, e]): Range => [Math.max(s, start) - start, Math.min(e, end) - start])
    const block = text.slice(start, end)
    return { block, ...cut(block, inside) }
  })
}

const isPlain = (value: object): boolean => {
  const proto = Object.getPrototypeOf(value)
  return proto === null || proto === Object.prototype
}

// Every string in `value` passed through `str` and every object key through `key`; arrays and plain
// objects are walked (their keys kept distinct), any other object is replaced whole by the mask, so
// nothing in it draws.
const walk = (
  value: unknown,
  str: (s: string) => string,
  key: (k: string) => string,
  mask: string,
  depth: number,
): unknown => {
  if (typeof value === 'string') return str(value)
  if (value === null || typeof value !== 'object') return value
  if (depth >= MAX_DEPTH || !(Array.isArray(value) || isPlain(value))) return mask
  if (Array.isArray(value)) return value.map((v) => walk(v, str, key, mask, depth + 1))
  const entries = Object.entries(value)
  const keys = distinct(entries.map(([k]) => key(k)), mask)
  return Object.fromEntries(entries.map(([, v], i) => [keys[i], walk(v, str, key, mask, depth + 1)]))
}

// Keeps values distinct where a schema requires it: when masking made two equal, each value's masks
// are numbered by its position, and if that is not enough the position is appended to every value.
export function distinct(values: readonly string[], mask: string): string[] {
  const isDistinct = (list: readonly string[]) => new Set(list).size === list.length
  if (isDistinct(values)) return [...values]
  const token = (n: number) => (mask.endsWith(']') ? `${mask.slice(0, -1)} ${n}]` : `${mask} ${n}`)
  const numbered = values.map((v, i) => v.split(mask).join(token(i + 1)))
  return isDistinct(numbered) ? numbered : numbered.map((v, i) => `${v} (${i + 1})`)
}

const mapProps = <P extends object>(
  props: P,
  keys: readonly (keyof P)[],
  str: (s: string) => string,
  mask: string,
  key: (k: string) => string = str,
): P => {
  const out = { ...props }
  for (const k of keys) {
    if (Object.prototype.hasOwnProperty.call(props, k)) {
      out[k] = walk(props[k], str, key, mask, 0) as P[keyof P]
    }
  }
  return out
}

export function maskProps<P extends object>(
  props: P,
  keys: readonly (keyof P)[],
  patterns: readonly RegExp[],
  mask: string,
): P {
  return mapProps(props, keys, (s) => maskText(s, patterns, mask), mask)
}

const FIELD_NAME = /^[A-Za-z_][A-Za-z0-9_]{0,63}$/

// The fail-closed rendering: every string under the named keys replaced whole by the mask, no user
// pattern run, so it finishes in time whatever they cost. An object key stays when it reads as a
// field name the built-ins find nothing in (a schema needs it); any other key is masked.
export function blankProps<P extends object>(
  props: P,
  keys: readonly (keyof P)[],
  patterns: readonly RegExp[],
  mask: string,
): P {
  const builtins = patterns.filter((p) => !EXTRA.has(p))
  return mapProps(props, keys, () => mask, mask, (k) =>
    FIELD_NAME.test(k) && findRanges(k, builtins).length === 0 ? k : mask)
}
