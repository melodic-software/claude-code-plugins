import type { Ctx, Piece } from '../core/piece.js'
import { PHASES, minutesOf } from '../core/settings.js'

/**
 * The time of day: the sun field from the local time, the sunrise and sunset settings and a stored /bedroom time, and
 * the command that holds a phase. The VCR clock always shows the real time.
 */
const DAY = 24 * 60
/** Other words for a phase. */
const ALIASES: Record<string, (typeof PHASES)[number]> = { late: 'night', midday: 'noon', afternoon: 'noon' }

/** Where each row starts, in minutes of the day, in row order: dusk at sunset, evening, night, predawn, dawn, morning, noon at 11:00, golden. */
export function rowStarts(sunrise: number, sunset: number): number[] {
  return [sunset, sunset + 75, sunset + 150, sunrise - 75, sunrise - 20, sunrise + 40, 11 * 60, sunset - 90].map(start => (start + DAY) % DAY)
}

/** The row at a minute of the day: the one that started last, round midnight. */
export function rowAt(minute: number, sunrise: number, sunset: number): number {
  const since = rowStarts(sunrise, sunset).map(start => (minute - start + DAY) % DAY)
  return since.indexOf(Math.min(...since))
}

/** A word of /bedroom time as the phase it holds: auto, a phase or its alias, or HH:MM read with these settings. */
export function phaseOf(word: string, sunrise: number, sunset: number): string | undefined {
  if (word === 'auto' || (PHASES as readonly string[]).includes(word)) return word
  if (word in ALIASES) return ALIASES[word]
  const clock = /^(\d{1,2}):(\d\d)$/.exec(word)
  if (clock === null || Number(clock[1]) > 23 || Number(clock[2]) > 59) return undefined
  return PHASES[rowAt(Number(clock[1]) * 60 + Number(clock[2]), sunrise, sunset)]
}

const settings = (ctx: Ctx): [number, number] => [minutesOf(ctx.setting('sunrise')), minutesOf(ctx.setting('sunset'))]

/** The row now: the phase held, or the one the clock gives. */
export function sunOf(ctx: Ctx): number {
  const held = ctx.setting('time')
  if (held !== 'auto') return PHASES.indexOf(held as (typeof PHASES)[number])
  const { hours, minutes } = ctx.local()
  return rowAt(hours * 60 + minutes, ...settings(ctx))
}

async function time(ctx: Ctx, args: readonly string[]): Promise<string> {
  const word = (args[0] ?? '').toLowerCase()
  if (word === '') {
    const held = ctx.setting('time')
    const now = PHASES[sunOf(ctx)]
    return `${held === 'auto' ? `the room follows the clock, ${now} now` : `the room holds ${now}`}; sunrise ${ctx.setting('sunrise')}, sunset ${ctx.setting('sunset')}. Say /bedroom time auto, a phase (${PHASES.join(', ')}) or a time as HH:MM`
  }
  const phase = phaseOf(word, ...settings(ctx))
  if (phase === undefined) return `say auto, a phase (${PHASES.join(', ')}, or late, midday, afternoon) or a time as HH:MM, as in /bedroom time noon or /bedroom time 14:30`
  await ctx.save({ time: phase })
  await ctx.send(`/bedroom time ${word}`, { hurry: true })
  if (phase === 'auto') return `the room follows the clock: ${PHASES[sunOf(ctx)]} now`
  return `the room holds ${phase}${word === phase ? '' : ` (${word})`} until /bedroom time auto; the VCR still shows the real time`
}

export const piece: Piece = {
  name: 'time',
  fields: ctx => ({ sun: sunOf(ctx) }),
  commands: { time },
}
