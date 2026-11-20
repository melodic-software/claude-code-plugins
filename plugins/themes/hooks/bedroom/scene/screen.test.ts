import { expect, test } from 'claude-code/testing'

import { bedroomSvg } from '../scene.ts'
import { DEFAULT_STATE } from './lib.ts'

test('drawn whole, with the tape in the tape has the screen over the console, as in the shader', () => {
  const card = 'FAR MERIDIAN'
  const tape = 'tv-tr'
  const both = bedroomSvg({ ...DEFAULT_STATE, tv: true, tape: true, console: true, titles: {} }, 0)
  expect(both.includes(tape)).toBe(true)
  expect(both.includes(card)).toBe(false)
  const game = bedroomSvg({ ...DEFAULT_STATE, tv: true, tape: false, console: true, titles: {} }, 0)
  expect(game.includes(tape)).toBe(false)
  expect(game.includes(card)).toBe(true)
})
