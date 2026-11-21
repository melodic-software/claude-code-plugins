import { expect, test } from 'claude-code/testing'

import { DEFAULT_STATE } from '../scene/lib.ts'
import { QUIET, startRoom } from './testing.js'
import { REASK_MS, commandSwitch, encodeWorld, nextValues, pumpScreen, rebuild, startShader, want } from './values.js'

test('a minute tick, a hurry flip and two switch commands asked together move at most three names a redraw', () => {
  const quiet = { sun: 0, weather: 0, work: 0, zone: 0, hall: 0 }
  startShader(DEFAULT_STATE, quiet, 480, -60_000)
  let now = 1000
  want('clock', 481)
  const noon = { ...quiet, sun: 6, weather: 2 }
  rebuild(noon, now, { hurry: true })
  expect(commandSwitch('tv', 0, true)).toBe('sent')
  expect(commandSwitch('lava', 1, false)).toBe('sent')
  const seen: string[][] = []
  let values = {} as Record<string, number>
  for (let step = 0; step < 40; step++) {
    rebuild(noon, now)
    pumpScreen(now)
    const redraw = nextValues(now)
    seen.push(redraw.moved)
    values = redraw.values
    now += REASK_MS
  }
  expect(seen[0]).toEqual(['tv', 'lava', 'screen'])
  expect(seen[1]).toEqual(['world', 'clock'])
  for (const moved of seen) expect(moved.length).toBeLessThanOrEqual(3)
  expect(values.tv).toBe(0)
  expect(values.lava).toBe(1)
  expect(values.clock).toBe(481)
  expect(values.world).toBe(encodeWorld(noon))
  expect(values.screen).toBe(1)
})

test('in the plugin, redraws asked together move at most three names each', { timeoutMs: 20000, options: QUIET }, async ($, on) => {
  const room = await startRoom($, on)
  await room.clock.advance(59_900 - (room.clock.now() % 60_000))
  await Promise.all([room.run('tv off'), room.run('lava on'), room.run('pc off'), room.run('lamp on'), room.run('console on'), room.clock.advance(300)])
  await room.clock.advance(8000)
  const moves = room.events().filter(line => line.includes('values moved:'))
  expect(moves.length).toBeGreaterThan(0)
  for (const line of moves) expect(line.split('values moved: ')[1]!.split(', ').length, line).toBeLessThanOrEqual(3)
  expect(await room.values()).toMatchObject({ tv: 0, lava: 1, pc: 0, lamp: 1, clock: 481 })
  expect(Math.floor(((await room.values())?.screen ?? 0) / 16) % 2).toBe(1)
  await room.unmount()
})
