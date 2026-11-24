import { expect, test, type Engine } from 'claude-code/testing'

import { PHASES, minutesOf } from '../core/settings.js'
import { BACKDROP, STORE_KEY, startRoom, type Room } from '../core/testing.js'
import { BUILT } from './index.js'
import { phaseOf, rowAt, rowStarts, seasonOf, sunTimes } from './time.js'

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

/**
 * Walks a local day in `auto` from 00:00:30, the clock running through every minute's tick, and reads the Shader
 * element 30 s into the minute before each of `minutes` and into the minute itself: the phase each time the sun field
 * changes, at which local minute, and whether the room's drawing was sent again. A change one minute early, or one that
 * does not come, shows as a wrong entry. Between reads the backdrop is unmounted: drawn, each tick costs about 21 ms
 * against about 1.6 ms (claude plugin test, two hours of ticks).
 */
async function walkDay($: Engine, room: Room, minutes: readonly number[]): Promise<{ changes: [string, string][]; redrawn: boolean }> {
  const read = async (): Promise<{ sun: number | undefined; source: unknown }> => {
    const ui = await $.ui.mount({ ...BACKDROP })
    const sun = sunOf((await ui.find({ type: 'Shader' }))?.props.values as Record<string, number> | undefined)
    const source = (await ui.find({ type: 'Svg' }))?.props.source
    await ui.unmount()
    return { sun, source }
  }
  const changes: [string, string][] = []
  const dayStart = room.clock.now() - 30_000
  await room.unmount()
  const first = await read()
  let was = first.sun
  let redrawn = false
  for (const at of [...new Set(minutes.flatMap(m => [m - 1, m]))].filter(m => m > 0).sort((a, b) => a - b)) {
    await room.clock.advance(dayStart + at * 60_000 + 30_000 - room.clock.now())
    const { sun, source } = await read()
    if (sun !== was && sun !== undefined) changes.push([PHASES[sun]!, hhmm(at)])
    redrawn ||= source !== first.source
    was = sun
  }
  return { changes, redrawn }
}

const MIDNIGHT = new Date(2026, 10, 20, 0, 0, 30).getTime()

test('auto walks the day from midnight: each phase at its row start, by the world value alone, with no room sent again', { timeoutMs: 180000, options: { time: 'auto', weather: 'clear', hall: false, signal: false, sunrise: '06:30', sunset: '20:30' } }, async ($, on) => {
  if (!BUILT.includes('time')) return
  const room = await startRoom($, on, { now: MIDNIGHT })
  expect(sunOf(await room.values())).toBe(PHASES.indexOf('night'))
  const { changes, redrawn } = await walkDay($, room, rowStarts(minutesOf('06:30'), minutesOf('20:30')))
  expect(changes).toEqual([
    ['predawn', '05:15'],
    ['dawn', '06:10'],
    ['morning', '07:10'],
    ['noon', '11:00'],
    ['golden', '19:00'],
    ['dusk', '20:30'],
    ['evening', '21:45'],
    ['night', '23:00'],
  ])
  expect(redrawn).toBe(false)
})

const dstOn = (year: number, month: number, day: number): number =>
  Math.max(new Date(year, 0, 1).getTimezoneOffset(), new Date(year, 6, 1).getTimezoneOffset()) - new Date(year, month, day, 12).getTimezoneOffset()

test('auto sunrise and sunset follow the season at 40 degrees north: day lengths of the solstices and equinoxes, about noon on the clock', () => {
  if (!BUILT.includes('time')) return
  const southern = new Date(2026, 0, 1).getTimezoneOffset() < new Date(2026, 6, 1).getTimezoneOffset()
  for (const [month, day, length] of [[5, 21, 15 * 60 + 1], [11, 21, 9 * 60 + 20], [2, 20, 12 * 60 + 9], [8, 22, 12 * 60 + 9]] as const) {
    const { sunrise, sunset } = seasonOf(new Date(2026, month, day, 12).getTime())
    const expected = !southern ? length : month === 5 ? 9 * 60 + 20 : month === 11 ? 15 * 60 + 1 : length
    expect([month, Math.abs(sunset - sunrise - expected) <= 4]).toEqual([month, true])
    expect([month, Math.abs((sunrise + sunset) / 2 - (12 * 60 + dstOn(2026, month, day))) <= 1]).toEqual([month, true])
  }
  if (!southern && dstOn(2026, 5, 21) === 60) {
    const june = seasonOf(new Date(2026, 5, 21, 12).getTime())
    expect(Math.abs(june.sunset - minutesOf('20:30'))).toBeLessThanOrEqual(5)
    const november = seasonOf(new Date(2026, 10, 20, 12).getTime())
    expect(Math.abs(november.sunset - minutesOf('16:45'))).toBeLessThanOrEqual(10)
  }
})

for (const [name, month, day] of [['December', 11, 21], ['June', 5, 21]] as const) {
  test(`auto walks a ${name} day by the season's sunrise and sunset`, { timeoutMs: 180000, options: { time: 'auto', weather: 'clear', hall: false, signal: false } }, async ($, on) => {
    if (!BUILT.includes('time')) return
    const start = new Date(2026, month, day, 0, 0, 30).getTime()
    const { sunrise, sunset } = seasonOf(start)
    const starts = rowStarts(sunrise, sunset)
    const expected = [3, 4, 5, 6, 7, 0, 1, 2].map(row => [PHASES[row]!, hhmm(starts[row]!)] as [string, string])
    const room = await startRoom($, on, { now: start })
    const { changes } = await walkDay($, room, [...starts, ...rowStarts(minutesOf('06:30'), minutesOf('20:30'))])
    expect(changes).toEqual(expected)
    expect(await room.run('time')).toMatch(/sunrise \d\d:\d\d \(the season\), sunset \d\d:\d\d \(the season\)/)
  })
}

test('/bedroom date 06-21 puts the room on June\'s sunrise and sunset while the clock says November; auto, seasons, bad input and a reload', { timeoutMs: 60000, options: { time: 'auto', weather: 'clear', hall: false, signal: false } }, async ($, on) => {
  if (!BUILT.includes('time')) return
  const room = await startRoom($, on, { now: MIDNIGHT })
  expect(await room.run('date')).toMatch(/^the room is on 11-20, the real date; sunrise \d\d:\d\d, sunset \d\d:\d\d; the VCR still shows the real time$/)
  expect(await room.run('date 06-21')).toMatch(/^the room is on 06-21, held until \/bedroom date auto/)
  expect((room.store.get(STORE_KEY) as { date?: string }).date).toBe('06-21')
  for (const word of ['13-01', '02-30', '6-21', 'june', '06/21']) expect(await room.run(`date ${word}`)).toBe('say auto, a day as MM-DD or a season (spring 04-20, summer 07-15, autumn 10-15, winter 01-15), as in /bedroom date 06-21')
  const june = seasonOf(new Date(2026, 5, 21, 12).getTime())
  const november = seasonOf(new Date(2026, 10, 20, 12).getTime())
  const starts = rowStarts(june.sunrise, june.sunset)
  await room.clock.advance(8000)
  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  await room.clock.advance(8000)
  expect(await room.run('date')).toMatch(/^the room is on 06-21, held until/)
  const { changes } = await walkDay($, room, [...starts, ...rowStarts(november.sunrise, november.sunset)])
  expect(changes).toEqual([3, 4, 5, 6, 7, 0, 1, 2].map(row => [PHASES[row]!, hhmm(starts[row]!)]))
  expect(new Date(room.clock.now()).getMonth()).toBe(10)
  expect(await room.run('date summer')).toMatch(/^the room is on 07-15, held for summer until \/bedroom date auto/)
  expect(await room.run('date auto')).toMatch(/^the room is on 11-20, the real date/)
  expect(await room.run('date winter')).toMatch(/^the room is on 01-15, held for winter/)
  expect(await room.run('date default')).toMatch(/^date follows its setting again \(now auto\)/)
})

test('an HH:MM sunrise or sunset holds all year over the season', () => {
  if (!BUILT.includes('time')) return
  const december = new Date(2026, 11, 21, 12).getTime()
  const ctx = (rise: string, set: string) => ({ nowMs: december, setting: (key: string) => (key === 'sunrise' ? rise : key === 'sunset' ? set : 'auto') }) as unknown as Parameters<typeof sunTimes>[0]
  expect(sunTimes(ctx('06:30', '20:30'))).toEqual([minutesOf('06:30'), minutesOf('20:30')])
  expect(sunTimes(ctx('auto', '20:30'))).toEqual([seasonOf(december).sunrise, minutesOf('20:30')])
  expect(seasonOf(december).sunset).toBeLessThan(minutesOf('18:00'))
})

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
