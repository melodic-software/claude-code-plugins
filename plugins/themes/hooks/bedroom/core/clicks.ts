import type { EngineInterface } from 'claude-code'

import { purr } from '../pieces/sound.js'
import { HITS } from '../scene/lib.ts'
import { readNow } from './clock.js'
import { ctxOf } from './context.js'
import type { Switch } from './piece.js'
import { isHolding } from './render.js'
import { switched } from './switched.js'
import { note } from './telemetry.js'
import { ask, clickScreen } from './values.js'

const CALIBRATION_POINT = { x: 1110, y: 906 }
let isCalibrating = false

/** The next click sets the window's shape for click mapping. */
export function calibrateNext(): void {
  isCalibrating = true
}

/** A click, given as fractions of the window, in the scene's own viewBox units. The scene is 1600 by 1000, cropped to fill. */
export function toViewBox(x: number, y: number, aspect: number): { x: number; y: number } {
  const width = Math.min(1600, 1000 * aspect)
  const height = Math.min(1000, 1600 / aspect)

  return { x: 800 + (x - 0.5) * width, y: 500 + (y - 0.5) * height }
}

/** Every thing a viewBox point lands on: the shader flips each switch whose rectangle holds a click, so where rectangles overlap a click lands on more than one. */
export function hitsAt(x: number, y: number): string[] {
  return Object.entries(HITS)
    .filter(([, [left, top, width, height]]) => x >= left && x <= left + width && y >= top && y <= top + height)
    .map(([name]) => name)
}

/** The first thing a viewBox point lands on, if any. */
export function hitAt(x: number, y: number): string | undefined {
  return hitsAt(x, y)[0]
}

/** The switches a viewBox point flips, as the shader flips them: the tape's spine is the tape. */
export function switchesAt(x: number, y: number): string[] {
  return [...new Set(hitsAt(x, y).filter(name => name !== 'cat').map(name => (name === 'spine' ? 'tape' : name)))]
}

/** The window's shape from a click, given as fractions of the window, on the bottom-left corner of the dresser's front. */
export function aspectFrom(x: number, y: number): number {
  const across = x - 0.5
  const down = y - 0.5
  const width = across > 0.02 ? (CALIBRATION_POINT.x - 800) / across : 1600
  const height = down > 0.02 ? (CALIBRATION_POINT.y - 500) / down : 1000
  const aspect = width < 1590 ? width / 1000 : height < 990 ? 1600 / height : 1.6

  return Math.min(4, Math.max(0.5, aspect))
}

/**
 * Handles a click at window fractions point (x right, y down). The shader answers a click on a switch it draws by
 * itself, so while it runs the mod only records it: nothing is sent and nothing is drawn again. A click on the tape or
 * the console while an earlier change for it may still be on its way has its state sent once more later. Returns what
 * it struck (a switch, `cat`, `calibrated`), or undefined for bare backdrop. The test kit cannot raise ui.pointer, so
 * the handler is a function of its own.
 */
export async function handleClick($: EngineInterface, point: { readonly x: number; readonly y: number }): Promise<string | undefined> {
  await readNow($)
  const ctx = ctxOf($)
  if (isCalibrating) {
    isCalibrating = false
    await ctx.save({ aspect: aspectFrom(point.x, point.y) })
    $.ui.toast(`bedroom: clicks calibrated (window shape ${ctx.saved.aspect.toFixed(2)})`)
    return 'calibrated'
  }
  const at = toViewBox(point.x, point.y, ctx.saved.aspect)
  const struck = hitsAt(at.x, at.y)
  const keys = switchesAt(at.x, at.y) as Switch[]
  note(`click at ${point.x.toFixed(3)},${point.y.toFixed(3)} (room ${at.x.toFixed(0)},${at.y.toFixed(0)}) on ${struck.length === 0 ? 'nothing' : struck.join(' and ')}`)
  if (keys.length === 0) {
    if (!struck.includes('cat')) return undefined
    $.ui.toast('the cat purrs')
    purr($)
    return 'cat'
  }
  const state = { ...ctx.saved.state }
  for (const key of keys) state[key] = !state[key]
  const saving = ctx.save({ state })
  for (const key of keys) {
    const isOn = state[key]
    note(`${key} is now ${isOn ? 'on' : 'off'}`)
    switched($, ctx, key, isOn, 'click')
    if (ctx.setting('shader') && (key === 'tape' || key === 'console')) clickScreen($, key, isOn, ctx.nowMs)
  }
  if (!ctx.setting('shader') || isHolding()) void ask($, `a click on ${keys.join(' and ')}`)
  void saving.catch(() => undefined)
  return keys[0]
}
