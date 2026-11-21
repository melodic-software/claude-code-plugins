import type { EngineInterface } from 'claude-code'
import { expect, test } from 'claude-code/testing'

import { readNow } from '../core/clock.js'
import { ctxOf, usePieces } from '../core/context.js'
import type { Piece } from '../core/piece.js'
import { draw, markStarted } from '../core/render.js'
import { load, save } from '../core/saved.js'
import { stats } from '../core/telemetry.js'
import { QUIET, startRoom } from '../core/testing.js'
import { bedroomSvg } from '../scene.ts'
import { DEFAULT_STATE, type State } from '../scene/lib.ts'
import { part as roomPart } from '../scene/parts/room.js'
import { part as tvPart } from '../scene/parts/tv.js'
import { part as windowPart } from '../scene/parts/window.js'
import { BUILT } from './index.js'
import { piece } from './no-shader.js'

/** The console's title card on the screen, and the default title in it. */
const CARD = '<rect x="1164" y="472" width="88" height="16" fill="#04050b"/>'
const SWITCHES = ['tv', 'tape', 'console', 'pc', 'light', 'lamp', 'lava'] as const

test('with the shader off the backdrop is the hand-drawn room alone, and the idle screen holds no title card', { timeoutMs: 20000, options: QUIET }, async ($, on) => {
  if (!BUILT.includes('no-shader')) return
  const room = await startRoom($, on)
  expect(await room.values()).toBeDefined()
  expect(await room.source()).toContain(CARD)

  expect(await room.run('shader off')).toMatch(/^the shader is off/)
  await room.clock.advance(7300)
  expect(await room.values()).toBeUndefined()
  const idle = await room.source()
  expect(idle).not.toContain(CARD)
  expect(idle).not.toContain('FAR MERIDIAN')

  await room.run('console on')
  expect(await room.source()).toContain(CARD)
  expect(await room.values()).toBeUndefined()
  await room.run('console off')
  expect(await room.source()).toBe(idle)

  await room.clock.advance(61_000)
  expect(await room.source()).toBe(idle)
  expect(await room.values()).toBeUndefined()
  await room.unmount()
})

/** A hook's `$` with the calls drawing makes: the store, a redraw, the clock and the debug log. */
function engine(): EngineInterface {
  const store = new Map<string, unknown>()
  return {
    plugin: { root: '/bedroom' },
    store: {
      get: async (key: string) => store.get(key),
      set: async (key: string, value: unknown) => void store.set(key, value),
    },
    ui: { toast: () => undefined, invalidate: () => undefined, log: () => undefined },
    clock: { now: async () => 120_000, after: () => ({ cancel: () => undefined }) },
  } as unknown as EngineInterface
}

test('a change of row or weather sends the hand-drawn room again, and an unchanged one does not', async () => {
  if (!BUILT.includes('no-shader')) return
  const $ = engine()
  await load($)
  await readNow($)
  markStarted()
  const given = { sun: 0, weather: 0 }
  const sky: Piece = { name: 'stand-in', fields: () => ({ ...given }) }
  usePieces([sky, piece])
  await save($, { shader: false })

  const sends = (): number => stats.roomSends
  const dusk = draw($, ctxOf($))
  expect(dusk.values).toBeUndefined()
  expect(dusk.source).not.toContain(CARD)
  const before = sends()
  expect(draw($, ctxOf($)).source).toBe(dusk.source)
  expect(sends()).toBe(before)

  given.sun = 6
  const noon = draw($, ctxOf($))
  expect(sends()).toBe(before + 1)
  expect(noon.values).toBeUndefined()
  expect(noon.source).toContain('stop-color="#5c8cd1"')
  expect(noon.source).not.toContain('window-tw')

  given.weather = 2
  const rain = draw($, ctxOf($))
  expect(sends()).toBe(before + 2)
  expect(rain.source).toContain('url(#window-rp)')

  await save($, { shader: true })
  const waiting = draw($, ctxOf($))
  expect(waiting.values).toBeUndefined()
  expect(waiting.source).toBe(bedroomSvg({ ...DEFAULT_STATE, titles: {} }, 0))
})

test('with no look, or dusk in clear weather, the window and the room shell draw as they always did', { timeoutMs: 20000 }, () => {
  if (!BUILT.includes('no-shader')) return
  for (let bits = 0; bits < 128; bits++) {
    const state: State = { ...DEFAULT_STATE }
    SWITCHES.forEach((name, i) => (state[name] = ((bits >> i) & 1) === 1))
    const dusk = { ...state, look: { sun: 0, weather: 0 } }
    expect(windowPart(dusk), `window ${bits}`).toEqual(windowPart(state))
    expect(roomPart(dusk), `room ${bits}`).toEqual(roomPart(state))
    const card = state.tv && state.console && !state.tape
    expect(tvPart(dusk).body?.includes(CARD), `tv ${bits}`).toBe(card)
    expect(tvPart(state).body?.includes(CARD), `tv ${bits}`).toBe(card)
    expect(tvPart({ ...state, underShader: true }).body?.includes(CARD), `tv ${bits}`).toBe(true)
  }
})

test('the room asks for the row and the weather the other pieces give', () => {
  if (!BUILT.includes('no-shader')) return
  const ctx = { fields: () => ({ sun: 5, weather: 3, work: 1, zone: 2, hall: 1 }) } as unknown as Parameters<NonNullable<Piece['room']>>[0]
  expect(piece.room?.(ctx)).toEqual({ sun: 5, weather: 3 })
})
