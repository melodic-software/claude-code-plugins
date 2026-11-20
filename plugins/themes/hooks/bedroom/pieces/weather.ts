import type { Ctx, Local, Piece } from '../core/piece.js'
import { STRIKE_GAP_MS, STRIKE_SHOWS_MS, noteForcedStrike } from '../core/schedule.js'
import { WEATHERS } from '../core/settings.js'
import { CUES } from '../core/signals.gen.js'

/**
 * The weather: the weather field from the stored choice or the setting, and /bedroom weather. `auto` changes by itself
 * without asking any service: the kind is a whole-number hash of the local date and its 3-hour block, so every session
 * gives the same weather at the same hour without writing anything, and it is never a storm.
 */
/** How many in 100 blocks `auto` gives each kind, in the order of WEATHERS: clear, overcast, rain, downpour, storm. */
export const SHARES = [60, 25, 12, 3, 0] as const

/** A whole number from 0 to 99 for a year, a day of the year and a 3-hour block of it. */
export function roll(year: number, day: number, block: number): number {
  let h = Math.imul(year, 0x9e3779b1) ^ Math.imul(day, 0x85ebca6b) ^ Math.imul(block + 1, 0xc2b2ae35)
  h = Math.imul(h ^ (h >>> 16), 0x7feb352d)
  h = Math.imul(h ^ (h >>> 15), 0x846ca68b)
  return ((h ^ (h >>> 16)) >>> 0) % 100
}

/** The kind `auto` gives at a local time, as an index of WEATHERS. */
export function autoKind(at: Local): number {
  let left = roll(at.year, at.day, Math.floor(at.hours / 3))
  let kind = 0
  while (left >= SHARES[kind]!) left -= SHARES[kind++]!
  return kind
}

function kindOf(ctx: Ctx): number {
  const chosen = ctx.setting('weather')
  return chosen === 'auto' ? autoKind(ctx.local()) : WEATHERS.indexOf(chosen as (typeof WEATHERS)[number])
}

function told(ctx: Ctx): string {
  const chosen = ctx.setting('weather')
  const now = WEATHERS[kindOf(ctx)]
  return chosen === 'auto' ? `the weather is auto, ${now} now; it changes by itself every three hours, never to a storm` : `the weather is ${now} until /bedroom weather auto`
}

/**
 * /bedroom weather strike: one lightning strike now, in a storm only, as the scheduled ones are (the shader's pulse
 * rises with the storm's lane, and a strike from a clear sky would read as a fault). At most one each STRIKE_GAP_MS.
 */
async function strikeNow(ctx: Ctx): Promise<string> {
  if (kindOf(ctx) !== WEATHERS.indexOf('storm')) return 'lightning comes only in a storm: say /bedroom weather storm first, then /bedroom weather strike'
  if (lastAsked !== undefined && ctx.nowMs - lastAsked < STRIKE_GAP_MS) return `one strike at a time: try again in ${Math.ceil((STRIKE_GAP_MS - (ctx.nowMs - lastAsked)) / 1000)} s`
  lastAsked = ctx.nowMs
  const delay = await ctx.cue(CUES.strike, '/bedroom weather strike')
  noteForcedStrike(ctx.nowMs, delay)
  return `lightning strikes in about ${Math.round((delay + STRIKE_SHOWS_MS) / 1000)} s`
}
let lastAsked: number | undefined

/** A command that changes the kind shows within seconds; one that does not sends nothing. */
async function weather(ctx: Ctx, args: readonly string[]): Promise<string> {
  const word = (args[0] ?? '').toLowerCase()
  if (word === '') return told(ctx)
  if (word === 'strike') return strikeNow(ctx)
  if (word !== 'auto' && !(WEATHERS as readonly string[]).includes(word)) return `say auto, ${WEATHERS.join(', ')}, default or strike, as in /bedroom weather rain`
  const was = kindOf(ctx)
  await ctx.save({ weather: word })
  if (kindOf(ctx) !== was) await ctx.send('/bedroom weather', { hurry: true })
  return told(ctx)
}

export const piece: Piece = {
  name: 'weather',
  fields: ctx => ({ weather: kindOf(ctx) }),
  commands: { weather },
}
