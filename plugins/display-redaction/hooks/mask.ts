const MAX_PATTERN_LENGTH = 200
const MAX_DEPTH = 64
const QUANTIFIER_BRACE = /^\{\d/

// Each built-in is anchored on a run start (a lookbehind) so a long run of word characters is
// scanned once, not once per start position. Open-ended tails (`*`) mask a token still streaming.
const BUILTIN_SOURCES = [
  // An address with its TLD anywhere, or one still streaming at the end of the text.
  '(?<![A-Za-z0-9._%+-])[A-Za-z0-9._%+-]+@(?:[A-Za-z0-9-]+(?:\\.[A-Za-z0-9-]+)*\\.[A-Za-z]{2,}|[A-Za-z0-9-]*(?:\\.[A-Za-z0-9-]*)*(?![\\s\\S]))',
  '(?<![A-Za-z0-9])sk-[\\w-]*',
  '(?<![A-Za-z0-9_])ghp_\\w*',
  '(?<![A-Za-z0-9_])github_pat_\\w*',
  '(?<![A-Za-z0-9])xox[abprs]-[\\w-]*',
  '(?<![A-Za-z0-9])AKIA[0-9A-Z]*',
  '(?<![A-Za-z0-9_])eyJ[\\w-]*(?:\\.[\\w-]*){0,2}',
  '-----BEGIN [A-Z ]*PRIVATE KEY-----[\\s\\S]*?(?:-----END [A-Z ]*PRIVATE KEY-----|(?![\\s\\S]))',
]

const NOREPLY = /^noreply@/i
const GITHUB_NOREPLY = /^\d+\+[^@]+@users\.noreply\.github\.com$/i

const isAllowed = (match: string, offset: number, text: string): boolean =>
  NOREPLY.test(match) || GITHUB_NOREPLY.test(match) || (/^git@/i.test(match) && text[offset + match.length] === ':')

// A group that holds a quantifier and is itself quantified can backtrack without bound.
const hasNestedQuantifier = (source: string): boolean => {
  const groups: boolean[] = [false]
  let inClass = false
  for (let i = 0; i < source.length; i++) {
    const c = source[i]
    if (c === '\\') {
      i++
    } else if (inClass) {
      if (c === ']') inClass = false
    } else if (c === '[') {
      inClass = true
    } else if (c === '(') {
      groups.push(false)
    } else if (c === ')') {
      const inner = groups.pop() ?? false
      const next = source.slice(i + 1, i + 3)
      const quantified = next[0] === '*' || next[0] === '+' || QUANTIFIER_BRACE.test(next)
      if (inner && quantified) return true
      groups[groups.length - 1] ||= inner || quantified
    } else if (c === '*' || c === '+' || (c === '{' && QUANTIFIER_BRACE.test(source.slice(i, i + 2)))) {
      groups[groups.length - 1] = true
    }
  }
  return false
}

const compileExtra = (source: string): RegExp | undefined => {
  if (typeof source !== 'string' || source.length === 0 || source.length > MAX_PATTERN_LENGTH) return undefined
  if (hasNestedQuantifier(source)) return undefined
  try {
    if (new RegExp(source).test('')) return undefined
    return new RegExp(source, 'g')
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

export function maskText(text: string, patterns: readonly RegExp[], mask: string): string {
  let out = text
  for (const pattern of patterns) {
    out = out.replace(pattern, (match: string, ...rest: unknown[]) => {
      const last = rest[rest.length - 1]
      const offset = (typeof last === 'object' ? rest[rest.length - 3] : rest[rest.length - 2]) as number
      return isAllowed(match, offset, out) ? match : mask
    })
  }
  return out
}

const walk = (value: unknown, patterns: readonly RegExp[], mask: string, depth: number): unknown => {
  if (typeof value === 'string') return maskText(value, patterns, mask)
  // Past the depth limit a structure is replaced whole, so nothing in it draws unmasked.
  if (depth >= MAX_DEPTH) return value !== null && typeof value === 'object' ? mask : value
  if (Array.isArray(value)) return value.map((v) => walk(v, patterns, mask, depth + 1))
  if (value !== null && typeof value === 'object' && Object.getPrototypeOf(value) === Object.prototype) {
    const entries = Object.entries(value)
    const keys = distinct(entries.map(([k]) => maskText(k, patterns, mask)), mask)
    return Object.fromEntries(entries.map(([, v], i) => [keys[i], walk(v, patterns, mask, depth + 1)]))
  }
  return value
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

export function maskProps<P extends object>(
  props: P,
  keys: readonly (keyof P)[],
  patterns: readonly RegExp[],
  mask: string,
): P {
  const out = { ...props }
  for (const key of keys) {
    if (Object.prototype.hasOwnProperty.call(props, key)) {
      out[key] = walk(props[key], patterns, mask, 0) as P[keyof P]
    }
  }
  return out
}
