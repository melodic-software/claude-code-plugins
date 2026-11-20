import { expect, test } from 'claude-code/testing'

import { HITS } from '../scene/lib.ts'
import { hitAt, toViewBox } from './clicks.js'
import { encodeScreen, encodeWorld } from './values.js'

/** A viewBox point as fractions of a window of this shape (the inverse of toViewBox). */
function inWindow(x: number, y: number, aspect: number): { x: number; y: number } {
  const width = Math.min(1600, 1000 * aspect)
  const height = Math.min(1000, 1600 / aspect)
  return { x: (x - 800) / width + 0.5, y: (y - 500) / height + 0.5 }
}

test('a window corner maps to the room as the scene is cropped: the sides cut below 1.6, the top and bottom above it', () => {
  expect(toViewBox(0, 0, 1.2)).toEqual({ x: 200, y: 0 })
  expect(toViewBox(1, 1, 1.2)).toEqual({ x: 1400, y: 1000 })
  expect(toViewBox(0, 0, 1.6)).toEqual({ x: 0, y: 0 })
  expect(toViewBox(0, 0, 2.5)).toEqual({ x: 0, y: 180 })
  expect(toViewBox(1, 1, 2.5)).toEqual({ x: 1600, y: 820 })
})

test('a click on the middle of each thing lands on it, at window shapes 1.2, 1.6, 1.88 and 2.48', () => {
  for (const aspect of [1.2, 1.6, 1.88, 2.48]) {
    for (const [name, [left, top, width, height]] of Object.entries(HITS)) {
      const at = inWindow(left + width / 2, top + height / 2, aspect)
      const back = toViewBox(at.x, at.y, aspect)
      expect(hitAt(back.x, back.y), `${name} at ${aspect}`).toBe(name)
    }
    const wall = toViewBox(0.5, 0.5, aspect)
    expect(wall).toEqual({ x: 800, y: 500 })
    expect(hitAt(wall.x, wall.y)).toBeUndefined()
  }
})

test('screen codes are hurry + 2 hall + 4 tape + 8 tape sequence + 16 console + 32 console sequence', () => {
  for (let code = 0; code <= 63; code++) {
    const fields = { hurry: code % 2, hall: (code >> 1) % 2, tape: (code >> 2) % 2, tapeSeq: (code >> 3) % 2, console: (code >> 4) % 2, consoleSeq: (code >> 5) % 2 }
    expect(encodeScreen(fields), `screen ${code}`).toBe(code)
  }
})

test('world codes are sun + 8 (weather + 5 (work + 2 zone)), 0 to 239', () => {
  for (let code = 0; code <= 239; code++) {
    const r = Math.floor(code / 8)
    const q = Math.floor(r / 5)
    const fields = { sun: code % 8, weather: r % 5, work: q % 2, zone: Math.floor(q / 2), hall: 0 }
    expect(fields.zone, `world ${code}`).toBeLessThanOrEqual(2)
    expect(encodeWorld(fields), `world ${code}`).toBe(code)
  }
})
