import type { EngineInterface } from 'claude-code'

import { minuteOfHalfDay, readNow } from '../core/clock.js'
import { ctxOf } from '../core/context.js'
import type { Ctx, Local, Piece } from '../core/piece.js'
import { STRIKE_GAP_MS, STRIKE_SHOWS_MS, cueRefusal, noteForcedStrike, strike } from '../core/schedule.js'
import { WEATHERS } from '../core/settings.js'
import { CUES } from '../core/signals.gen.js'
import { cueFree } from '../core/values.js'

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
 * One the shader cannot take yet is not sent, and the answer says when it can.
 */
async function strikeNow(ctx: Ctx): Promise<string> {
  if (kindOf(ctx) !== WEATHERS.indexOf('storm')) return `lightning comes only in a storm, and the weather is ${WEATHERS[kindOf(ctx)]}: say /bedroom weather storm first, then /bedroom weather strike`
  const refused = cueRefusal(ctx.nowMs)
  if (refused !== undefined) return `no strike: ${refused}`
  if (lastAsked !== undefined && ctx.nowMs - lastAsked < STRIKE_GAP_MS) return `one strike at a time: try again in ${Math.ceil((STRIKE_GAP_MS - (ctx.nowMs - lastAsked)) / 1000)} s`
  lastAsked = ctx.nowMs
  lastStrike = ctx.nowMs
  const delay = await ctx.cue(CUES.strike, '/bedroom weather strike')
  noteForcedStrike(ctx.nowMs, delay)
  return `lightning strikes in about ${Math.round((delay + STRIKE_SHOWS_MS) / 1000)} s`
}
let lastAsked: number | undefined
/** When the mod last sent a strike, asked for or its own. */
let lastStrike: number | undefined

/**
 * Lightning beyond the shader's own schedule (about one strike in three minutes), sent by the mod in a storm through
 * the cue a strike asked for takes. A cue holds the world channel CUE_HOLD_MS and the atmosphere then holds it
 * WORLD_GAP_MS (18 s in all), so the channel carries at most one strike each 18 s, about 3.3 a minute, and the
 * hallway's cues share it. Each minute has three slots SLOT_S apart from an offset hashed from the minute, each kept with
 * the setting's chance; a slot within SLOT_S of the last strike, or while the channel is busy, waits and is tried
 * twice more. `normal` comes to about 2 a minute with the shader's own (1.8 extra in ten test minutes), within what
 * the National Weather Service calls occasional (1 to 3 a minute, https://www.weather.gov/mlb/lightning_threat), and
 * `often` to about 2.8 (2.4 extra), the most the channel carries with room left for the hallway and a strike asked for.
 */
export const LIGHTNING = { rare: 0, normal: 0.75, often: 1 } as const
export const SLOT_S = 20
/** A strike is not sent when it would show this close to one the shader's own schedule draws: that one would hide it. */
export const SCHEDULED_CLEAR_MS = 8000

/** The seconds after the minute's tick of its extra strikes: a whole-number hash of the minute, the same in every session. */
export function extraStrikes(minute: number, chance: number): number[] {
  const offset = roll(minute, 0, 7) % SLOT_S
  return [0, 1, 2].filter(k => roll(minute, k + 1, 7) < chance * 100).map(k => offset + k * SLOT_S)
}

/** Whether a strike shown at `at` falls within SCHEDULED_CLEAR_MS of a scheduled one this minute or the next. */
function nearScheduled(at: number): boolean {
  const start = at - (at % 60_000)
  return [start - 60_000, start, start + 60_000].some(from => {
    const second = strike(minuteOfHalfDay(from))
    return second !== undefined && Math.abs(from + 1000 + second * 1000 - at) < SCHEDULED_CLEAR_MS
  })
}

/** One of the mod's own strikes, when it is a storm, the shader takes cues and the channel is free; a busy channel is tried again twice. */
async function extraStrike($: EngineInterface, tries = 0): Promise<void> {
  const now = await readNow($)
  const ctx = ctxOf($)
  if (kindOf(ctx) !== WEATHERS.indexOf('storm') || cueRefusal(now) !== undefined) return
  if (nearScheduled(now + STRIKE_SHOWS_MS)) return
  const wait = lastStrike === undefined ? 0 : lastStrike + SLOT_S * 1000 - now
  if (wait > 0 || !cueFree(now)) {
    if (tries < 2) $.clock.after(Math.max(wait, 0) + 2000 * (tries + 1), () => void extraStrike($, tries + 1))
    return
  }
  lastStrike = now
  noteForcedStrike(now, await ctx.cue(CUES.strike, 'lightning'))
}

/** Each minute, the times of its extra strikes. */
export async function engineTick($: EngineInterface, ctx: Ctx): Promise<void> {
  const chance = LIGHTNING[ctx.setting('lightning') as keyof typeof LIGHTNING] ?? 0
  if (chance === 0 || kindOf(ctx) !== WEATHERS.indexOf('storm')) return
  for (const second of extraStrikes(Math.floor(ctx.nowMs / 60_000), chance)) $.clock.after(second * 1000, () => void extraStrike($))
}

/** /bedroom weather lightning rare|normal|often: how often a storm strikes beyond the shader's own schedule. */
async function lightning(ctx: Ctx, word: string | undefined): Promise<string> {
  const kinds = Object.keys(LIGHTNING)
  if (word === 'default') await ctx.save({ lightning: undefined })
  else if (word !== undefined && word !== '') {
    if (!kinds.includes(word)) return `say ${kinds.join(', ')} or default, as in /bedroom weather lightning often`
    await ctx.save({ lightning: word })
  }
  const now = ctx.setting('lightning')
  return `lightning is ${now}: ${now === 'rare' ? 'about one strike in three minutes' : now === 'often' ? 'about three strikes a minute' : 'about two strikes a minute'} in a storm`
}

/** A command that changes the kind shows within seconds; one that does not sends nothing. */
async function weather(ctx: Ctx, args: readonly string[]): Promise<string> {
  const word = (args[0] ?? '').toLowerCase()
  if (word === '') return told(ctx)
  if (word === 'strike') return strikeNow(ctx)
  if (word === 'lightning') return lightning(ctx, (args[1] ?? '').toLowerCase())
  if (word !== 'auto' && !(WEATHERS as readonly string[]).includes(word)) return `say auto, ${WEATHERS.join(', ')}, default, strike or lightning, as in /bedroom weather rain`
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
