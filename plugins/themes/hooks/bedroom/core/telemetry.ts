import type { EngineInterface } from 'claude-code'

/** What /bedroom stats reports. Kept in memory only: the module writes no file. */
export const stats = { renders: 0, roomSends: 0, valueOnly: 0, chars: 0, buildMs: 0, maxBuildMs: 0, askMs: 0 }
/** Lines noted since the last flush, for the debug log. */
const pending: string[] = []
/** Value-only redraws in each of the last 60 minutes, by the minute since the epoch. */
const perMinute = new Map<number, number>()

export function note(line: string): void {
  pending.push(line)
  if (pending.length > 200) pending.shift()
}

/** A piece's hook threw: one line, and the caller carries on. */
export function failed(piece: string, what: string, error: unknown): void {
  note(`the ${piece} piece's ${what} failed: ${error instanceof Error ? error.message : String(error)}`)
}

const failedBefore = new Set<string>()
/** The same, noted only the first time: for a hook that runs at every redraw. */
export function failedOnce(piece: string, what: string, error: unknown): void {
  if (failedBefore.has(`${piece} ${what}`)) return
  failedBefore.add(`${piece} ${what}`)
  failed(piece, what, error)
}

/** Counts a redraw that changed only the shader's values. */
export function countValueOnly(ms: number): void {
  stats.valueOnly += 1
  const minute = Math.floor(ms / 60_000)
  perMinute.set(minute, (perMinute.get(minute) ?? 0) + 1)
  for (const key of perMinute.keys()) if (key < minute - 59) perMinute.delete(key)
}

/** The most value-only redraws in one minute over the last hour. */
export function busiestMinute(ms: number): number {
  const minute = Math.floor(ms / 60_000)
  let most = 0
  for (const [key, count] of perMinute) if (key >= minute - 59) most = Math.max(most, count)
  return most
}

/** Writes the lines noted since the last flush to the debug log. */
export function flush($: EngineInterface): void {
  for (const line of pending.splice(0)) $.ui.log(`bedroom: ${line}`, { to: 'debug' })
}
