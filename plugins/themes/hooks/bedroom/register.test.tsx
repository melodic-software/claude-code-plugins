import { expect, test } from 'claude-code/testing'

import { TITLE_CAPS, aspectFrom, hitAt, moves, switchesAt, toViewBox, withTitle } from './register.tsx'
import { bedroomSvg } from './scene.ts'
import { DEFAULT_STATE } from './scene/lib.ts'

test('a click maps to the scene by the window shape', () => {
  expect(toViewBox(0.5, 0.5, 1.6)).toEqual({ x: 800, y: 500 })
  expect(toViewBox(0, 1, 1.6)).toEqual({ x: 0, y: 1000 })
})

test('a click lands on the thing under it, or on nothing', () => {
  expect(hitAt(1200, 480)).toBe('tv')
  expect(hitAt(1345, 560)).toBe('spine')
  expect(hitAt(10, 10)).toBeUndefined()
})

test('the room draws the made-up titles and pennant by default', () => {
  const svg = bedroomSvg({ ...DEFAULT_STATE, titles: {}, underShader: true }, 0)

  expect(DEFAULT_STATE.posters).toBe('plain')
  expect(svg.includes('FAR MERIDIAN')).toBe(true)
  expect(svg.includes('ROOFTOP')).toBe(true)
  expect(svg.includes('LANTERN HILL')).toBe(true)
})

test('a title set with /bedroom title replaces the default', () => {
  const svg = bedroomSvg({ ...DEFAULT_STATE, titles: { console: 'MY GAME', tape: 'MY TAPE' }, underShader: true }, 0)

  expect(svg.includes('MY GAME')).toBe(true)
  expect(svg.includes('MY TAPE')).toBe(true)
  expect(svg.includes('FAR MERIDIAN')).toBe(false)
})

test('a click where two things overlap flips both, as the shader does', () => {
  expect(switchesAt(1340, 560)).toEqual(['console', 'tape'])
  expect(switchesAt(1399, 500)).toEqual(['light', 'lava'])
  expect(switchesAt(1200, 480)).toEqual(['tv'])
  expect(switchesAt(10, 10)).toEqual([])
})

test('/bedroom title pennant sets the pennant in capitals, capped, and no text puts the default back', () => {
  const set = withTitle({}, 'pennant', 'silver foxes of the far north')

  expect(set.pennant).toBe('SILVER FOXES')
  expect(set.pennant?.length).toBe(TITLE_CAPS.pennant)
  expect(withTitle(set, 'pennant-top', 'pine hollow')['pennant-top']).toBe('PINE HOLLOW')
  expect(withTitle(set, 'pennant', '')).toEqual({})
  expect(withTitle({}, 'console', 'My Game').console).toBe('My Game')

  const svg = bedroomSvg({ ...DEFAULT_STATE, titles: withTitle(withTitle({}, 'pennant', 'silver foxes'), 'pennant-top', 'pine hollow') }, 0)

  expect(svg.includes('>SILVER FOXES</text>')).toBe(true)
  expect(svg.includes('>PINE HOLLOW</text>')).toBe(true)
  expect(svg.includes('NIGHTJARS')).toBe(false)
  expect(svg.includes('LANTERN HILL')).toBe(false)
  expect(bedroomSvg({ ...DEFAULT_STATE, titles: {} }, 0).includes('textLength="128" lengthAdjust="spacingAndGlyphs">NIGHTJARS</text>')).toBe(true)
})

test('every title is escaped for the SVG', () => {
  const svg = bedroomSvg({ ...DEFAULT_STATE, titles: { console: 'A<B', tape: 'C&D', pennant: 'E"F', 'pennant-top': 'G>H' }, underShader: true }, 0)

  expect(svg.includes('A&lt;B')).toBe(true)
  expect(svg.includes('C&amp;D')).toBe(true)
  expect(svg.includes('E&quot;F')).toBe(true)
  expect(svg.includes('G&gt;H')).toBe(true)
  expect(svg.includes('A<B')).toBe(false)
})

test('a $ in a title is written as typed, not read as a replacement pattern', () => {
  const svg = bedroomSvg({ ...DEFAULT_STATE, titles: { console: 'X$&Y', tape: "P$'Q" }, underShader: true }, 0)

  expect(svg.includes('X$&amp;Y')).toBe(true)
  expect(svg.includes("P$'Q")).toBe(true)
  expect(svg.includes('@TITLE@')).toBe(false)
  expect(svg.includes('@TAPE@')).toBe(false)
})

test('drawn whole, with no shader, the console title card shows only on the console\'s own screen', () => {
  const card = 'FAR MERIDIAN'

  expect(bedroomSvg({ ...DEFAULT_STATE, tv: true, console: false, titles: {} }, 0).includes(card)).toBe(false)
  expect(bedroomSvg({ ...DEFAULT_STATE, tv: true, tape: true, titles: {} }, 0).includes(card)).toBe(false)
  expect(bedroomSvg({ ...DEFAULT_STATE, tv: false, console: true, titles: {} }, 0).includes(card)).toBe(false)
  expect(bedroomSvg({ ...DEFAULT_STATE, tv: true, console: true, titles: {} }, 0).includes(card)).toBe(true)
  expect(bedroomSvg({ ...DEFAULT_STATE, tv: true, console: false, titles: {}, underShader: true }, 0).includes(card)).toBe(true)
})

test('a switch order is one move to the end, or, when the number already sits on that side, the middle first', () => {
  expect(moves(1, false)).toEqual([0])
  expect(moves(0, true)).toEqual([1])
  expect(moves(0.5, false)).toEqual([0])
  expect(moves(1, true)).toEqual([0.5, 1])
  expect(moves(0, false)).toEqual([0.5, 0])
  expect(moves(0.5, true)).toEqual([0.5, 1])
})

test('a calibration click on the dresser corner gives the window shape', () => {
  expect(aspectFrom(0.7, 0.9).toFixed(2)).toBe('1.55')
  expect(aspectFrom(0.5, 0.5)).toBe(1.6)
  expect(aspectFrom(0.51, 0.95).toFixed(2)).toBe('1.77')
})
