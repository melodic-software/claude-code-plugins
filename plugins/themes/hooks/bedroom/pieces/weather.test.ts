import { expect, test } from 'claude-code/testing'

import { local } from '../core/clock.js'
import { BUILT } from '../core/signals.gen.js'
import { WEATHERS } from '../core/settings.js'
import { EVENING, QUIET, STORE_KEY, startRoom } from '../core/testing.js'
import { encodeWorld } from '../core/values.js'
import { SHARES, autoKind } from './weather.js'

/** 1,000 days in a row from 2026-01-01, at noon. */
const DAYS = Array.from({ length: 1000 }, (_, i) => local(new Date(2026, 0, 1 + i, 12, 0, 0).getTime()))

test('auto gives the same kind twice for one date and block, and across a block', () => {
  if (!BUILT.includes('weather')) return
  for (const day of DAYS.slice(0, 50)) {
    for (let hours = 0; hours < 24; hours++) {
      const at = { ...day, hours }
      expect(autoKind(at)).toBe(autoKind({ ...at }))
      expect(autoKind(at)).toBe(autoKind({ ...at, hours: hours - (hours % 3), minutes: 59 }))
    }
  }
})

test('over 1,000 dates auto keeps within 5 points of 60, 25, 12 and 3 in 100, in every block, and never gives a storm', () => {
  if (!BUILT.includes('weather')) return
  for (let block = 0; block < 8; block++) {
    const counts = [0, 0, 0, 0, 0]
    for (const day of DAYS) {
      const kind = autoKind({ ...day, hours: block * 3 })
      counts[kind] = (counts[kind] ?? 0) + 1
    }
    counts.forEach((count, kind) => expect(Math.abs(count / 10 - SHARES[kind]!)).toBeLessThanOrEqual(5))
    expect(counts[WEATHERS.indexOf('storm')]).toBe(0)
  }
})

test('each /bedroom weather word sends its kind and stores it; a stored choice survives a reload', { timeoutMs: 30000, options: { ...QUIET, weather: 'auto' } }, async ($, on) => {
  if (!BUILT.includes('weather')) return
  const room = await startRoom($, on, { saved: { weather: 'rain' } })
  const world = (weather: number) => encodeWorld({ sun: 0, weather, work: 0, zone: 0, hall: 0 })
  expect((await room.values())?.world).toBe(world(2))
  expect(await room.run('weather')).toBe('the weather is rain until /bedroom weather auto')
  for (const word of ['storm', 'overcast', 'downpour', 'clear', 'rain'] as const) {
    expect(await room.run(`weather ${word}`)).toBe(`the weather is ${word} until /bedroom weather auto`)
    expect((room.store.get(STORE_KEY) as { weather?: string }).weather).toBe(word)
    await room.clock.advance(6500)
    expect((await room.values())?.world).toBe(world(WEATHERS.indexOf(word)))
  }
  const auto = WEATHERS[autoKind(local(EVENING))]
  expect(await room.run('weather AUTO')).toBe(`the weather is auto, ${auto} now; it changes by itself every three hours, never to a storm`)
  expect((room.store.get(STORE_KEY) as { weather?: string }).weather).toBe('auto')
  await room.clock.advance(6500)
  expect((await room.values())?.world).toBe(world(autoKind(local(EVENING))))
  expect(await room.run('weather snow')).toMatch(/^say auto, clear, overcast, rain, downpour, storm, default, strike or lightning/)
  expect((room.store.get(STORE_KEY) as { weather?: string }).weather).toBe('auto')
  await room.run('weather storm')
  expect(await room.run('weather default')).toBe('weather follows its setting again (now auto)')
  expect((room.store.get(STORE_KEY) as { weather?: string }).weather).toBeUndefined()
  await room.unmount()
})
