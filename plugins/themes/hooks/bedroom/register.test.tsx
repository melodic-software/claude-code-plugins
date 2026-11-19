import { expect, test } from 'claude-code/testing'

import { TITLE_CAPS, hitAt, switchesAt, toViewBox, withTitle } from './register.tsx'
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
  const svg = bedroomSvg({ ...DEFAULT_STATE, titles: {} }, 0)

  expect(DEFAULT_STATE.posters).toBe('plain')
  expect(svg.includes('FAR MERIDIAN')).toBe(true)
  expect(svg.includes('ROOFTOP')).toBe(true)
  expect(svg.includes('LANTERN HILL')).toBe(true)
})

test('a title set with /bedroom title replaces the default', () => {
  const svg = bedroomSvg({ ...DEFAULT_STATE, titles: { console: 'MY GAME', tape: 'MY TAPE' } }, 0)

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
  const svg = bedroomSvg({ ...DEFAULT_STATE, titles: { console: 'A<B', tape: 'C&D', pennant: 'E"F', 'pennant-top': 'G>H' } }, 0)

  expect(svg.includes('A&lt;B')).toBe(true)
  expect(svg.includes('C&amp;D')).toBe(true)
  expect(svg.includes('E&quot;F')).toBe(true)
  expect(svg.includes('G&gt;H')).toBe(true)
  expect(svg.includes('A<B')).toBe(false)
})

test('a $ in a title is written as typed, not read as a replacement pattern', () => {
  const svg = bedroomSvg({ ...DEFAULT_STATE, titles: { console: 'X$&Y', tape: "P$'Q" } }, 0)

  expect(svg.includes('X$&amp;Y')).toBe(true)
  expect(svg.includes("P$'Q")).toBe(true)
  expect(svg.includes('@TITLE@')).toBe(false)
  expect(svg.includes('@TAPE@')).toBe(false)
})
