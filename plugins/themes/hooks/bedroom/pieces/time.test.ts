import { expect, test } from 'claude-code/testing'

import { PHASES, minutesOf } from '../core/settings.js'
import { STORE_KEY, startRoom } from '../core/testing.js'
import { BUILT } from './index.js'
import { phaseOf, rowAt, rowStarts } from './time.js'

const hhmm = (minute: number): string => `${String(Math.floor(minute / 60)).padStart(2, '0')}:${String(minute % 60).padStart(2, '0')}`

test('the row changes exactly at each row start, one minute each side, for two pairs of settings', () => {
  if (!BUILT.includes('time')) return
  for (const [sunrise, sunset, starts] of [
    ['06:30', '20:30', ['20:30', '21:45', '23:00', '05:15', '06:10', '07:10', '11:00', '19:00']],
    ['05:45', '21:15', ['21:15', '22:30', '23:45', '04:30', '05:25', '06:25', '11:00', '19:45']],
  ] as const) {
    const R = minutesOf(sunrise)
    const S = minutesOf(sunset)
    expect(rowStarts(R, S).map(hhmm)).toEqual([...starts])
    starts.forEach((start, row) => {
      const at = minutesOf(start)
      expect(rowAt((at - 1 + 1440) % 1440, R, S)).toBe((row + 7) % 8)
      expect(rowAt(at, R, S)).toBe(row)
      expect(rowAt((at + 1) % 1440, R, S)).toBe(row)
    })
    expect(rowAt(0, R, S)).toBe(2)
    expect(rowAt(1439, R, S)).toBe(2)
  }
})

test('/bedroom time takes auto, each phase, its other words and HH:MM, and nothing else', () => {
  if (!BUILT.includes('time')) return
  const R = minutesOf('06:30')
  const S = minutesOf('20:30')
  expect(phaseOf('auto', R, S)).toBe('auto')
  for (const phase of PHASES) expect(phaseOf(phase, R, S)).toBe(phase)
  expect(phaseOf('late', R, S)).toBe('night')
  expect(phaseOf('midday', R, S)).toBe('noon')
  expect(phaseOf('afternoon', R, S)).toBe('noon')
  expect(phaseOf('14:30', R, S)).toBe('noon')
  expect(phaseOf('3:00', R, S)).toBe('night')
  expect(phaseOf('05:15', R, S)).toBe('predawn')
  expect(phaseOf('20:29', R, S)).toBe('golden')
  expect(phaseOf('20:30', R, S)).toBe('dusk')
  for (const word of ['', 'sunny', '24:00', '12:60', '1230', 'noon2']) expect(phaseOf(word, R, S)).toBeUndefined()
})

/** 21:00 local on 2026-11-19 wherever the test runs: dusk under the default sunset 20:30, golden under 21:15. */
const NINE_PM = new Date(2026, 10, 19, 21, 0, 0).getTime()
const sunOf = (values: Record<string, number> | undefined): number | undefined => (values?.world === undefined ? undefined : values.world % 8)

test('the sun field follows the clock and the settings, /bedroom time holds a phase through a reload, and the VCR keeps the real time', { timeoutMs: 30000, options: { time: 'auto', weather: 'clear', hall: false, signal: false, sunrise: '05:45', sunset: '21:15' } }, async ($, on) => {
  if (!BUILT.includes('time')) return
  const room = await startRoom($, on, { now: NINE_PM })
  expect(sunOf(await room.values())).toBe(7)
  expect((await room.values())?.clock).toBe(540)

  const asked: [string, number][] = [...PHASES.map((phase, row): [string, number] => [phase, row]), ['late', 2], ['midday', 6], ['afternoon', 6], ['04:40', 3], ['auto', 7]]
  for (const [word, row] of asked) {
    expect(await room.run(`time ${word}`)).toMatch(word === 'auto' ? /^the room follows the clock: golden now/ : /^the room holds /)
    await room.clock.advance(6500)
    expect(sunOf(await room.values())).toBe(row)
    expect((room.store.get(STORE_KEY) as { time?: string }).time).toBe(word === 'auto' ? 'auto' : PHASES[row])
  }
  const { clock } = (await room.values()) ?? {}
  const now = new Date(room.clock.now())
  expect(clock).toBe((now.getHours() % 12) * 60 + now.getMinutes())

  expect(await room.run('time banana')).toMatch(/^say auto, a phase/)
  expect((room.store.get(STORE_KEY) as { time?: string }).time).toBe('auto')

  expect(await room.run('time noon')).toMatch(/^the room holds noon until \/bedroom time auto/)
  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  await room.clock.advance(8000)
  expect(await room.run('time')).toMatch(/^the room holds noon/)
  expect(sunOf(await room.values())).toBe(6)
  await room.unmount()
})
