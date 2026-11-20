import { minuteOfHalfDay } from '../core/clock.js'
import type { Ctx, Piece } from '../core/piece.js'
import { cueRefusal, scheduledEventShows, shaderStartedAt } from '../core/schedule.js'
import { CUES } from '../core/signals.gen.js'
import { worldMove } from '../core/values.js'

/** How soon a cue shows once it is sent: the app's delay and ease, then the shader's 2.5 s hold. */
const SHOWS_S = 4.5
/** How long the hall light stays on, as the shader holds it. */
export const HALL_LIGHT_MS = 180_000
/** From the minute's tick to the shader turning its own hall light on: the clock taken about 0.9 s in, then 20 s. */
const OWN_LIGHT_MS = 910 + 20_000

/** When the hall light is on, as far as the mod can tell: from the door's presses and the shader's own schedule. */
let lit: { from: number; until: number } | undefined

/** Whether the hall light is on at `now`. A shader that started since it came on starts with it off. */
export function hallLightOn(now: number): boolean {
  if (lit === undefined || now < lit.from || now >= lit.until) return false
  const started = shaderStartedAt()
  return started !== undefined && started <= lit.from
}

/**
 * Whether the shader turns its own hall light on in a minute of the half day, at a sun phase, as its hallway column
 * runs it: a code of the minute hashed, kept in 3 of 211 at dusk and evening and 1 of 211 at night and before dawn.
 */
export function ownHallLight(minute: number, sun: number): boolean {
  const hash = (Math.floor((minute * 1023) / 719 + 0.5005) * 89 + 69.5) % 211
  const late = sun >= 1.5 && sun < 3.5
  return (sun < 1.5 && hash < 3) || (late && hash < 1)
}

/** /bedroom hall pass and /bedroom hall light: the hallway's events at once, while the hallway is on. */
async function now(ctx: Ctx, word: 'pass' | 'light'): Promise<string> {
  if (!ctx.setting('hall')) return 'the hallway is off: say /bedroom hall on first'
  const refused = cueRefusal(ctx.nowMs)
  if (refused !== undefined) return `not now: ${refused}`
  const delay = await ctx.cue(word === 'pass' ? CUES.pass : CUES.light, `/bedroom hall ${word}`)
  const when = `in about ${Math.round(delay / 1000 + SHOWS_S)} s`
  if (word === 'pass') return `someone passes the door ${when}`
  const shows = ctx.nowMs + delay + SHOWS_S * 1000
  const wasOn = hallLightOn(shows)
  lit = wasOn ? undefined : { from: ctx.nowMs, until: shows + HALL_LIGHT_MS }
  return wasOn ? `the hall light turns off ${when}` : `the hall light turns on ${when} and stays on for three minutes`
}

/**
 * The hallway: the hall field is 1 while the hall setting is on, which lets the shader run the hallway's own timed
 * events; /bedroom hall on|off holds a choice in the store; /bedroom hall pass and hall light run one event at once.
 */
export const piece: Piece = {
  name: 'hallway',
  fields: ctx => ({ hall: ctx.setting('hall') ? 1 : 0 }),
  tick: ctx => {
    if (!ctx.setting('hall')) lit = undefined
    const at = ctx.nowMs + OWN_LIGHT_MS
    if (!ctx.setting('hall') || hallLightOn(at) || !ownHallLight(minuteOfHalfDay(ctx.nowMs), ctx.fields().sun)) return
    if (scheduledEventShows(at, worldMove().hurryAt)) lit = { from: at, until: at + HALL_LIGHT_MS }
  },
  commands: {
    hall: async (ctx, args) => {
      const word = (args[0] ?? '').toLowerCase()
      if (word === 'pass' || word === 'light') return now(ctx, word)
      if (word !== 'on' && word !== 'off') {
        return `the hallway's events are ${ctx.setting('hall') ? 'on' : 'off'}. Say /bedroom hall on or off, hall pass or hall light to see one now, or hall default to follow the setting`
      }
      await ctx.save({ hall: word === 'on' })
      if (word === 'off') lit = undefined
      await ctx.send(`/bedroom hall ${word}`)
      return word === 'on'
        ? 'the hallway is on: about once an hour someone passes the door, and now and then the hall light comes on for three minutes'
        : 'the hallway is off: the light in the gap stays as it is'
    },
  },
}
