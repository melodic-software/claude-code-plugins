import type { EngineInterface, Timer } from 'claude-code'

import { ctxOf } from '../core/context.js'
import type { Ctx, On, Piece } from '../core/piece.js'
import { hasStarted } from '../core/render.js'
import { failed } from '../core/telemetry.js'

/**
 * The television reacting to Claude. work is 1 from the main turn's turn.start until 4 s after its turn.complete (a
 * subagent's turn, which carries agentId, is passed over), and 0 at a Stop. zone is the context fill from
 * session.measure, and from one $.session.usage() at load: 1 from 50%, 2 from 75%, each falling back once the fill is
 * down 2 points from where it starts (48%, 73%). With the signal setting off both are 0.
 */
/** work stays 1 this long after the main turn ends, so turns a moment apart read as one stretch of work. */
export const HOLD_MS = 4000
/** The context percent at which zone 1 and zone 2 start (the context-usage plugin's moderate and heavy). */
export const ZONE_FROM = [50, 75] as const
/** A zone falls back once the fill is down this many points from where it starts. */
export const FALL = 2

/** The zone for a fill, given the zone it was in. */
export function zoneOf(percent: number, was: number): number {
  let at = was
  while (at < ZONE_FROM.length && percent >= ZONE_FROM[at]!) at += 1
  while (at > 0 && percent <= ZONE_FROM[at - 1]! - FALL) at -= 1
  return at
}

let working = false
let turn: string | undefined
let hold: Timer | undefined
let zone = 0

function resend($: EngineInterface, why: string): Promise<void> {
  if (!hasStarted()) return Promise.resolve()
  return ctxOf($)
    .send(why)
    .catch(error => failed('claude-tv', why, error))
}

function turnStarted($: EngineInterface, id: string): void {
  hold?.cancel()
  hold = undefined
  turn = id
  if (working) return
  working = true
  void resend($, 'a turn starting')
}

function turnEnded($: EngineInterface, id: string): void {
  if (id !== turn) return
  turn = undefined
  hold?.cancel()
  hold = $.clock.after(HOLD_MS, () => {
    hold = undefined
    if (turn !== undefined || !working) return
    working = false
    void resend($, 'a turn ended')
  })
}

function stopped($: EngineInterface): void {
  hold?.cancel()
  hold = undefined
  turn = undefined
  if (!working) return
  working = false
  void resend($, 'a Stop')
}

function measured($: EngineInterface, percent: number | undefined): void {
  if (percent === undefined) return
  const next = zoneOf(percent, zone)
  if (next === zone) return
  zone = next
  void resend($, 'the context filling')
}

/** Its hooks wait on nothing: the turn's first model call comes after them, and a Stop is noted before any await. */
export function hooks(on: On): void {
  on('turn.start', ($, e, next) => {
    if (e.agentId === undefined) turnStarted($, e.turnId)
    return next(e)
  })
  on('turn.complete', ($, e, next) => {
    if (e.agentId === undefined) turnEnded($, e.turnId)
    return next(e)
  })
  on('session.stop', ($, e, next) => {
    stopped($)
    return next(e)
  })
  on('session.measure', ($, e, next) => {
    measured($, e.context.percent)
    return next(e)
  })
}

/** The fill at load; the shader's start carries it, so nothing is sent here. */
export async function engineStart($: EngineInterface, ctx: Ctx): Promise<void> {
  const usage = await $.session.usage()
  const percent = usage.context.percent
  if (percent !== undefined) zone = zoneOf(percent, zone)
  ctx.note(`claude-tv: the context ${percent ?? 'unknown'}% full, zone ${zone}`)
}

async function signal(ctx: Ctx, args: readonly string[]): Promise<string> {
  const value = (args[0] ?? '').toLowerCase()
  if (value !== '' && value !== 'on' && value !== 'off') return 'say on or off, as in /bedroom signal off; with neither, it flips'
  const isOn = value === '' ? !ctx.setting('signal') : value === 'on'
  await ctx.save({ signal: isOn })
  await ctx.send(`/bedroom signal ${isOn ? 'on' : 'off'}`)
  return isOn
    ? 'the television reacts to Claude: a soft flicker while a turn runs. It shows 3 to 5 seconds after a change'
    : 'the television no longer reacts to Claude'
}

export const piece: Piece = {
  name: 'claude-tv',
  fields: ctx => (ctx.setting('signal') ? { work: working ? 1 : 0, zone } : { work: 0, zone: 0 }),
  commands: { signal },
}
