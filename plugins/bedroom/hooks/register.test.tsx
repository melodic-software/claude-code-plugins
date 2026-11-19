import { expect, test } from 'claude-code/testing'

import { hitAt, toViewBox } from './register.tsx'
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
