import { expect, test } from 'claude-code/testing'

import { TITLE_CAPS, aspectFrom, hitAt, switchesAt, toViewBox, withTitle } from './register.tsx'
import { SECOND_STEP_MS, commandSwitch, nextValues, startShader } from './core/values.js'
import { bedroomSvg } from './scene.ts'
import { DEFAULT_STATE, HITS } from './scene/lib.ts'

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

test('no two click rectangles meet, edges included, so one click flips one switch', () => {
  const names = Object.keys(HITS)
  const meeting: string[] = []
  for (const [i, a] of names.entries()) {
    for (const b of names.slice(i + 1)) {
      const [ax, ay, aw, ah] = HITS[a]!
      const [bx, by, bw, bh] = HITS[b]!
      if (ax <= bx + bw && bx <= ax + aw && ay <= by + bh && by <= ay + ah) meeting.push(`${a} and ${b}`)
    }
  }
  expect(meeting, 'rectangles that share a point').toEqual([])
})

test('a click on either side of each border between neighbors flips the one thing on that side', () => {
  expect(switchesAt(1336, 560)).toEqual(['console'])
  expect(switchesAt(1337, 560)).toEqual(['tape'])
  expect(switchesAt(1340, 560)).toEqual(['tape'])
  expect(switchesAt(1357, 560)).toEqual(['tape'])
  expect(switchesAt(1358, 560)).toEqual(['lava'])
  expect(switchesAt(1397, 500)).toEqual(['lava'])
  expect(switchesAt(1398, 500)).toEqual(['light'])
  expect(switchesAt(1399, 500)).toEqual(['light'])
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

test('a switch order is one move to the end, or, when a click turned the switch since the number last moved, the middle first', () => {
  const lit = { ...DEFAULT_STATE, tv: true }
  const quiet = { sun: 0, weather: 0, work: 0, zone: 0, hall: 0 }

  startShader(lit, quiet, 0, 0)
  expect(commandSwitch('tv', 1, true)).toBe('already')
  expect(commandSwitch('tv', 0, true)).toBe('sent')
  expect(nextValues(0).values.tv).toBe(0)
  expect(commandSwitch('tv', 0, true)).toBe('turned')
  expect(nextValues(10).values.tv).toBe(0.5)
  expect(nextValues(10 + SECOND_STEP_MS - 1).values.tv).toBe(0.5)
  expect(nextValues(10 + SECOND_STEP_MS).values.tv).toBe(0)
  expect(commandSwitch('lamp', 1, false)).toBe('sent')
  expect(nextValues(5000).values.lamp).toBe(1)
})

test('a calibration click on the dresser corner gives the window shape', () => {
  expect(aspectFrom(0.7, 0.9).toFixed(2)).toBe('1.55')
  expect(aspectFrom(0.5, 0.5)).toBe(1.6)
  expect(aspectFrom(0.51, 0.95).toFixed(2)).toBe('1.77')
})
