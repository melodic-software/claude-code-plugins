import type { EngineInterface, ThemeSetArgs } from 'claude-code'

import { makeColors } from '../../make-colors.js'
import { bedroomSvg } from '../scene.ts'
import { minuteOfHalfDay, nowMs } from './clock.js'
import { builtPieces } from './context.js'
import type { Ctx, Piece } from './piece.js'
import { noteShaderStart } from './schedule.js'
import { countValueOnly, failedOnce, flush, note, stats } from './telemetry.js'
import { REASK_MS, ask, lastCause, nextValues, startShader } from './values.js'

export const SCENE = 'bedroom'
/**
 * How long a changed room shows alone, without the shader, before the shader starts over it again: the app takes five
 * or six seconds to show a changed room, and stopped a shader that ran through that swap for being too slow. The room
 * shown alone is the room as it stands, the ceiling light off included, so nothing on screen goes back to the lit room
 * while it waits.
 */
export const SETTLE_MS = 7000

const { theme, problems } = makeColors({
  label: 'Bedroom',
  only: 'dark',
  roles: { accent: '#5b8cff', danger: '#e0564a', success: '#6fbf6a', warning: '#e8a23c', pro: '#b48be0' },
  dark: {
    gray: {
      anchors: {
        'surface-0': '#0f1120',
        'surface-1': '#15182a',
        'surface-2': '#1a1e33',
        'surface-3': '#1e223a',
        'text-primary': '#efe9db',
        'text-secondary': '#c9c3b6',
        'text-muted': '#a39fa8',
      },
    },
  },
})
/** The color problems makeColors reports, for a toast at load. */
export const colorProblems = problems

/** The theme: the colors and the backdrop with its glass. */
export function lookOf(ctx: Ctx): ThemeSetArgs {
  return { colors: theme, backdrop: { scene: SCENE, glass: { blur: ctx.saved.blur, tint: '#0b0d18', opacity: ctx.saved.glass } } }
}

let isThemeSet = false
let coveredBy: string | undefined
/** Whether the theme is set: the card's theme button shows it. A set stands for the session whether or not a surface draws it. */
export function isThemeOn(): boolean {
  return isThemeSet
}

/** The plugin whose theme replaced the room's while the room was on, until the room is set or cleared again. */
export function coveringPlugin(): string | undefined {
  return isThemeSet ? coveredBy : undefined
}

/** Another plugin set its theme over the room's: the session has one theme, so the room no longer shows. */
export function markCovered(plugin: string): void {
  coveredBy = plugin
}

/** Sets the bedroom's look and notes that the theme is on. */
export async function setLook($: EngineInterface, ctx: Ctx): Promise<Awaited<ReturnType<EngineInterface['theme']['set']>>> {
  const set = await $.theme.set(lookOf(ctx))
  isThemeSet = true
  coveredBy = undefined
  return set
}

/** Clears the theme and notes that it is off. */
export async function clearLook($: EngineInterface): Promise<Awaited<ReturnType<EngineInterface['theme']['clear']>>> {
  const cleared = await $.theme.clear()
  isThemeSet = false
  coveredBy = undefined
  return cleared
}

/** The room the running shader was started over; empty while no shader runs or a hold is due. */
let shaderSource = ''
let lastSource = ''
let holdUntil = 0
let holdTimer: { cancel: () => void } | undefined
let isShaderShown = false
let isReasking = false
let askedAt: number | undefined

let isStarted = false
/**
 * Notes that session.start has read the clock and the saved room. A backdrop drawn before it shows the room alone with
 * no hold, which would be timed from nothing; session.start then asks the redraw that holds and starts the shader.
 */
export function markStarted(): void {
  isStarted = true
}

/** Whether the shader runs now, every value seeded: a switch order before then is left to the seeding. */
export function isShaderRunning(): boolean {
  return isShaderShown
}

/** Notes when a change asked for a redraw, for /bedroom stats. */
export function noteAsked(): void {
  askedAt = performance.now()
}

/** Shows the room alone for SETTLE_MS, then brings the shader back with every value at its target. */
export function holdShader($: EngineInterface, why: string): void {
  holdUntil = nowMs() + SETTLE_MS
  isShaderShown = false
  noteShaderStart(holdUntil)
  note(`${why}: drawing the room alone for ${SETTLE_MS} ms`)
  holdTimer?.cancel()
  holdTimer = $.clock.after(SETTLE_MS, () => {
    holdTimer = undefined
    void ask($, 'the room settling')
  })
}

/** Whether the room shows alone now, waiting for the shader: a click in the wait is drawn into the room. */
export function isHolding(): boolean {
  return nowMs() < holdUntil || shaderSource === ''
}

/** What a piece says the hand-drawn room should show; one whose room() throws says nothing. */
function roomOfPiece(piece: Piece, ctx: Ctx): { sun: number; weather: number } | undefined {
  try {
    return piece.room?.(ctx)
  } catch (error) {
    failedOnce(piece.name, 'room', error)
    return undefined
  }
}

/** The room under the shader: the ceiling light on and the things the shader draws switched as it expects, so a switch never sends it again. */
export function shaderRoom(ctx: Ctx): string {
  const saved = ctx.saved
  return bedroomSvg({ ...saved.state, tv: true, lava: false, pc: true, lamp: false, tape: false, console: false, light: true, titles: saved.titles, underShader: true }, saved.dim)
}

/** The room as it stands, drawn whole: what shows when no shader runs. With the shader setting off, the hour and weather the pieces give. */
export function wholeRoom(ctx: Ctx): string {
  const saved = ctx.saved
  const look = ctx.setting('shader') ? undefined : builtPieces().map(piece => roomOfPiece(piece, ctx)).find(given => given !== undefined)
  return bedroomSvg({ ...saved.state, titles: saved.titles, ...(look === undefined ? {} : { look }) }, saved.dim)
}

/** Counts a drawing for /bedroom stats. */
function counted(source: string, startedAt: number): void {
  const buildMs = performance.now() - startedAt
  stats.renders += 1
  stats.buildMs = buildMs
  stats.maxBuildMs = Math.max(stats.maxBuildMs, buildMs)
  stats.chars = source.length
  if (askedAt !== undefined) {
    stats.askMs = startedAt - askedAt
    askedAt = undefined
  }
  if (source !== lastSource) {
    stats.roomSends += 1
    lastSource = source
  }
}

/**
 * What to draw now: the room's source, and the shader's values while it plays. A changed room under the shader starts
 * a hold: the room shows as it stands for SETTLE_MS, then the shader starts over the lit room with every value seeded
 * from what is saved, so clicks made before it are kept.
 */
export function draw($: EngineInterface, ctx: Ctx): { source: string; values?: Readonly<Record<string, number>> } {
  const startedAt = performance.now()
  const now = nowMs()
  if (!ctx.setting('shader')) {
    shaderSource = ''
    isShaderShown = false
    noteShaderStart(undefined)
    const source = wholeRoom(ctx)
    counted(source, startedAt)
    note(`render ${stats.renders} after ${lastCause()}: shader off`)
    flush($)
    return { source }
  }
  const lit = shaderRoom(ctx)
  if (!isStarted) return { source: wholeRoom(ctx) }
  if (lit !== shaderSource) {
    shaderSource = lit
    holdShader($, 'the room changed')
  }
  if (now < holdUntil) {
    isShaderShown = false
    const source = wholeRoom(ctx)
    counted(source, startedAt)
    note(`render ${stats.renders} after ${lastCause()}: the room alone`)
    flush($)
    return { source }
  }
  const isNewRoom = lit !== lastSource
  counted(lit, startedAt)
  if (!isShaderShown) {
    isShaderShown = true
    startShader(ctx.saved.state, ctx.fields(), minuteOfHalfDay(now), now)
    noteShaderStart(now)
    note('the shader starts, every value at its target')
  } else if (!isNewRoom) {
    countValueOnly(now)
  }
  const { values, moved, waits } = nextValues(now)
  note(`render ${stats.renders} after ${lastCause()}: ${moved.length > 0 ? `values moved: ${moved.join(', ')}` : 'numbers only'}`)
  flush($)
  if (waits && !isReasking) {
    isReasking = true
    $.clock.after(REASK_MS, () => {
      isReasking = false
      void ask($, 'values still waiting')
    })
  }
  return { source: lit, values }
}
