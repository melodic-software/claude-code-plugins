import { expect, test } from 'claude-code/testing'

import { savedOf } from '../core/saved.js'
import { PHASES } from '../core/settings.js'
import { BUILT } from './index.js'
import { BANK, chosenName } from './sound-bank.js'
import { rowStarts, seasonOf } from './time.js'
import { PICK_FADE_MS, START_FADE_MS, BUILD_FROM_MIN, BUILD_LEVEL, EVENING_LEVEL, NIGHT_LEVEL, PREDAWN_LEVEL, bedOf, levelOf, WATCH_MS, engineCommand, gainOf } from './sound.js'
import { sky, stand, ranBy, onWindows, quiet, KATYDIDS, CRICKETS } from './sound-testing.js'

test('the insects follow the hour when dry: cicadas from mid-afternoon through dusk, the night insects settling from evening until dawn, quiet at dawn, morning and a held noon; rain at every hour when wet', () => {
  if (!BUILT.includes('sound')) return
  const saved = savedOf({})
  const cicadas = BANK.cicadas.entries.chorus.bed
  const dry = PHASES.map((phase, sun) => [phase, bedOf(saved, { sun, weather: 0 }) ?? '-', levelOf({ sun, weather: 0 })])
  expect(dry).toEqual([
    ['dusk', cicadas, 1],
    ['evening', KATYDIDS, EVENING_LEVEL],
    ['night', CRICKETS, NIGHT_LEVEL],
    ['predawn', CRICKETS, PREDAWN_LEVEL],
    ['dawn', '-', 1],
    ['morning', '-', 1],
    ['noon', '-', BUILD_LEVEL],
    ['golden', cicadas, 1],
  ])
  expect([EVENING_LEVEL, NIGHT_LEVEL, PREDAWN_LEVEL]).toEqual([0.5, 0.4, 0.3])
  expect(bedOf(saved, { sun: 6, weather: 0 }, 0)).toBe(cicadas)
  const afternoon = [0, 0.25, 0.5, 0.75, 0.999, 1].map(share => levelOf({ sun: 6, weather: 0 }, share))
  expect(afternoon[0]).toBe(BUILD_LEVEL)
  expect(afternoon.at(-1)).toBe(1)
  for (let i = 1; i < afternoon.length; i++) expect(afternoon[i]! >= afternoon[i - 1]!).toBe(true)
  const roof = BANK.rain.entries.roof
  for (let sun = 0; sun < 8; sun++) {
    expect([sun, bedOf(saved, { sun, weather: 2 }, 0.5), bedOf(saved, { sun, weather: 3 }), bedOf(saved, { sun, weather: 4 }), levelOf({ sun, weather: 3 })]).toEqual([sun, roof.rain, roof.downpour, roof.storm, 1])
  }
  for (const [choice, evening, late] of [['katydids', KATYDIDS, KATYDIDS], ['crickets', CRICKETS, CRICKETS], ['auto', KATYDIDS, CRICKETS]] as const) {
    const held = savedOf({ bank: { night: choice } })
    expect([choice, ...[1, 2, 3].map(sun => bedOf(held, { sun, weather: 0 }))]).toEqual([choice, evening, late, late])
  }
  const older = savedOf({ bank: { crickets: 'crickets' } })
  expect(chosenName(older, 'night')).toBe('auto')
  expect(chosenName(savedOf({ bank: { night: 'katydids' } }), 'night')).toBe('katydids')
})

function intoBuild(year: number, month: number, day: number, minutesIn: number): { at: number; span: number; sunset: number } {
  const { sunrise, sunset } = seasonOf(new Date(year, month, day, 12).getTime())
  const from = sunset - BUILD_FROM_MIN
  return { at: new Date(year, month, day, 0, from + minutesIn, 0).getTime(), span: (rowStarts(sunrise, sunset)[7]! - from) * 60_000, sunset }
}

test('noon is silent until the cicadas start in mid-afternoon, from the room\'s own sunset; a held noon is silent', async () => {
  if (!BUILT.includes('sound')) return
  const june = intoBuild(2026, 5, 21, 0)
  expect(june.sunset - BUILD_FROM_MIN).toBeGreaterThanOrEqual(15 * 60)
  const december = intoBuild(2026, 11, 21, 0)
  expect(december.sunset - BUILD_FROM_MIN).toBeLessThan(june.sunset - BUILD_FROM_MIN - 60)
  for (const [at, playing] of [[new Date(2026, 5, 21, 11, 0).getTime(), false], [new Date(2026, 5, 21, 14, 0).getTime(), false], [intoBuild(2026, 5, 21, 30).at, true], [intoBuild(2026, 11, 21, 30).at, true], [intoBuild(2026, 11, 21, -30).at, false]] as const) {
    const s = await stand(at)
    onWindows(s)
    Object.assign(sky, { sun: 6, weather: 0 })
    await engineCommand(s.$, await s.ctx(), 'sound', ['on'])
    await s.settle()
    const bed = ranBy(s).filter(line => line.startsWith('bed ')).at(-1)!.split(' ')[1]
    expect([new Date(at).toString(), bed]).toEqual([new Date(at).toString(), playing ? BANK.cicadas.entries.chorus.bed : '-'])
    if (playing) {
      await (await s.ctx()).save({ time: 'noon' })
      await s.advance(WATCH_MS + 10)
      expect(ranBy(s).filter(line => line.startsWith('bed ')).at(-1)!.split(' ')[1]).toBe('-')
      await (await s.ctx()).save({ time: undefined })
    }
    await quiet(s)
  }
})

test('through the mixer the afternoon builds in one ease to the golden hour, re-aimed when the hour is held or follows the clock again', async () => {
  if (!BUILT.includes('sound')) return
  const { at, span } = intoBuild(2026, 10, 19, 40)
  const s = await stand(at)
  onWindows(s)
  Object.assign(sky, { sun: 6, weather: 0 })
  await engineCommand(s.$, await s.ctx(), 'sound', ['on'])
  await s.settle()
  const g = gainOf(70)
  const lines = (): string[] => ranBy(s).filter(line => line.startsWith('bed ') || line.startsWith('level '))
  const startLevel = levelOf({ sun: 6, weather: 0 }, (40 * 60_000) / span, true)
  expect(startLevel > BUILD_LEVEL && startLevel < 0.5).toBe(true)
  expect(lines()).toEqual([`bed ${BANK.cicadas.entries.chorus.bed} ${(g * startLevel).toFixed(4)} ${START_FADE_MS}`])
  await s.advance(START_FADE_MS + WATCH_MS)
  const aimed = lines().at(-1)!.split(' ')
  expect(aimed.slice(0, 2)).toEqual(['level', g.toFixed(4)])
  expect(Math.abs(Number(aimed[2]) - (span - 40 * 60_000))).toBeLessThan(START_FADE_MS + 2 * WATCH_MS)
  await s.advance(10 * 60_000)
  expect(lines().length).toBe(2)

  await (await s.ctx()).save({ time: 'noon' })
  await s.advance(WATCH_MS + 10)
  expect(lines().at(-1)!.split(' ').slice(0, 2)).toEqual(['bed', '-'])
  await (await s.ctx()).save({ time: undefined })
  await s.advance(PICK_FADE_MS + 3 * WATCH_MS)
  const again = lines().filter(line => line.startsWith('level ')).at(-1)!.split(' ')
  expect(again.slice(0, 2)).toEqual(['level', g.toFixed(4)])
  expect(Number(again[2])).toBeLessThan(span - 40 * 60_000 - 10 * 60_000)
  await quiet(s)
})
