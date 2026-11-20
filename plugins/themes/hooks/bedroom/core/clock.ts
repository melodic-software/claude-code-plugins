import type { EngineInterface } from 'claude-code'

import type { Local } from './piece.js'

let cached = 0

/** Reads the engine's clock and keeps the reading. Every time comes from here, read before a redraw is asked; Date only turns it into local hours and minutes. */
export async function readNow($: EngineInterface): Promise<number> {
  cached = await $.clock.now()
  return cached
}

/** The last reading, in milliseconds since the epoch. */
export function nowMs(): number {
  return cached
}

export function local(ms: number): Local {
  const date = new Date(ms)
  const start = new Date(date.getFullYear(), 0, 1)
  const day = Math.floor((new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime() - start.getTime()) / 86_400_000) + 1
  return { hours: date.getHours(), minutes: date.getMinutes(), day, year: date.getFullYear() }
}

/** The minute of the half day, 0 to 719, by local time: what the VCR clock shows. */
export function minuteOfHalfDay(ms: number): number {
  const { hours, minutes } = local(ms)
  return (hours % 12) * 60 + minutes
}

/**
 * Calls onMinute just after each minute turns, with the milliseconds since the last call. A reload leaves the old copy's
 * chain running until it unloads, so each chain has a generation, the time it started, held in $.state: a chain stops
 * at its next tick once a newer one is held. Lost or older, the value is written back and the chain carries on, so the
 * clock never stops for want of it.
 */
export async function startMinuteChain($: EngineInterface, onMinute: (gapMs: number) => void | Promise<void>): Promise<number> {
  const { value } = await $.state.get({ plugin: 'themes', key: 'bedroom-chain' })
  let last = await readNow($)
  const generation = Math.max(last, (value ?? 0) + 1)
  await $.state.set({ plugin: 'themes', key: 'bedroom-chain' }, generation)
  const arm = (from: number): void => {
    $.clock.after(60_050 - (from % 60_000), async () => {
      const held = await $.state.get({ plugin: 'themes', key: 'bedroom-chain' })
      if (held.value !== undefined && held.value > generation) return
      if (held.value !== generation) await $.state.set({ plugin: 'themes', key: 'bedroom-chain' }, generation)
      const now = await readNow($)
      const gap = now - last
      last = now
      arm(now)
      await onMinute(gap)
    })
  }
  arm(last)
  return generation
}
