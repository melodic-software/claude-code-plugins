import type { EngineInterface } from 'claude-code'

export type Tiers = [number, number, number]
export const DEFAULT_TIERS: Tiers = [50, 75, 90]
export const LEVELS_FILE = 'levels.json'

export const validTiers = (value: unknown): value is Tiers =>
  Array.isArray(value) &&
  value.length === 3 &&
  value.every(n => Number.isInteger(n) && n >= 1 && n <= 100) &&
  value[0] < value[1] &&
  value[1] < value[2]

export async function readTiers($: EngineInterface, home: string | undefined): Promise<Tiers> {
  if (!home) return DEFAULT_TIERS
  const text = await $.fs.read(`${home}/.claude/rate-limits/${LEVELS_FILE}`).catch(() => undefined)
  if (typeof text !== 'string') return DEFAULT_TIERS
  try {
    const tiers = (JSON.parse(text) as { tiers?: unknown }).tiers
    return validTiers(tiers) ? tiers : DEFAULT_TIERS
  } catch {
    return DEFAULT_TIERS
  }
}

export const tierColor = (percent: number, [mid, highMid, high]: Tiers) =>
  percent >= high ? 'error' : percent >= highMid ? '#ff8700' : percent >= mid ? 'warning' : 'success'
