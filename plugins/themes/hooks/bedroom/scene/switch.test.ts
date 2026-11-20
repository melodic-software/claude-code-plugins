import { expect, test } from 'claude-code/testing'

import { bedroomSvg } from '../scene.ts'
import { DEFAULT_STATE } from './lib.ts'

test('drawn whole, the wall switch shows the ceiling light: its toggle up when on, down when off', () => {
  const toggleAt = (y: number): string => `<rect x="1410.5" y="${y}" width="2.6" height="7" fill="url(#room-tg)"`
  const on = bedroomSvg({ ...DEFAULT_STATE, light: true }, 0)
  const off = bedroomSvg({ ...DEFAULT_STATE, light: false }, 0)
  expect(on.includes(toggleAt(485.5))).toBe(true)
  expect(on.includes(toggleAt(493.5))).toBe(false)
  expect(off.includes(toggleAt(493.5))).toBe(true)
  expect(off.includes(toggleAt(485.5))).toBe(false)
})
