import { expect, test } from 'claude-code/testing'

import { savedOf } from '../core/saved.js'
import { PHASES } from '../core/settings.js'
import { rebuild } from '../core/values.js'
import { BUILT } from './index.js'
import { BANK, chosenName } from './sound-bank.js'
import { rowStarts, seasonOf } from './time.js'
import {
  DUCK_FADE_MS,
  PICK_FADE_MS,
  PICTURE_LAG_MS,
  START_FADE_MS,
  BUILD_FROM_MIN,
  BUILD_LEVEL,
  EVENING_LEVEL,
  NIGHT_LEVEL,
  PREDAWN_LEVEL,
  bedOf,
  levelOf,
  WATCH_MS,
  SWELL,
  engineCommand,
  gainOf,
  thunderFor,
} from './sound.js'
import { sky, type Stand, stand, ranBy, onWindows, quiet, KATYDIDS, CRICKETS, intoRow, shaderAt } from './sound-testing.js'

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

/** On a local date, `minutesIn` after the cicadas' build starts (BUILD_FROM_MIN before that day's sunset), and the build's span in ms. */
function intoBuild(year: number, month: number, day: number, minutesIn: number): { at: number; span: number; sunset: number } {
  const { sunrise, sunset } = seasonOf(new Date(year, month, day, 12).getTime())
  const from = sunset - BUILD_FROM_MIN
  return { at: new Date(year, month, day, 0, from + minutesIn, 0).getTime(), span: (rowStarts(sunrise, sunset)[7]! - from) * 60_000, sunset }
}

test('noon is silent until the cicadas start in mid-afternoon, from the room\'s own sunset; a held noon is silent', async () => {
  if (!BUILT.includes('sound')) return
  const june = intoBuild(2026, 5, 21, 0)
  expect(june.sunset - BUILD_FROM_MIN).toBeGreaterThan(15 * 60)
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

const RIVER = BANK.cicadas.entries.river.bed
/** The swells the mixer was sent: when each rose, its peak, and when it was told to fall. */
function swellsOf(s: Stand): { at: number; peak: number; fallAt?: number; fallMs?: number }[] {
  const out: { at: number; peak: number; fallAt?: number; fallMs?: number }[] = []
  for (const r of s.mixers.flatMap(m => m.ran)) {
    if (r.words[0] !== 'to' || r.words[1] !== RIVER) continue
    if (Number(r.words[2]) > 0) out.push({ at: r.at, peak: Number(r.words[2]) })
    else if (out.at(-1) !== undefined && out.at(-1)!.fallAt === undefined) Object.assign(out.at(-1)!, { fallAt: r.at, fallMs: Number(r.words[3]) })
  }
  return out
}

test('under cicadas auto a nearer cicada swells over the chorus now and then at dusk: 3 to 8 minutes apart, 25 to 45 s long, at 0.6 of the chorus', async () => {
  if (!BUILT.includes('sound')) return
  const s = await stand(intoRow(0, 5))
  onWindows(s)
  Object.assign(sky, { sun: 0, weather: 0 })
  await (await s.ctx()).save({ time: 'dusk' })
  shaderAt(s, sky)
  await s.advance(10_000)
  await engineCommand(s.$, await s.ctx(), 'sound', ['on'])
  await s.settle()
  const started = s.now()
  const g = gainOf(70)
  await s.advance(60 * 60_000)
  const swells = swellsOf(s)
  expect(swells.length).toBeGreaterThanOrEqual(6)
  expect(swells.length).toBeLessThanOrEqual(16)
  expect(swells[0]!.at - started).toBeGreaterThanOrEqual(SWELL.gapMin * 60_000)
  for (const [i, one] of swells.entries()) {
    expect(Math.abs(one.peak - g * SWELL.peak)).toBeLessThan(0.0001)
    if (one.fallAt === undefined) continue
    const length = one.fallAt + one.fallMs! - one.at
    expect(length >= SWELL.minMs && length <= SWELL.maxMs + 1).toBe(true)
    const next = swells[i + 1]
    if (next === undefined) continue
    expect(next.at - (one.fallAt + one.fallMs!)).toBeGreaterThanOrEqual(SWELL.gapMin * 60_000 - SWELL.maxMs)
    expect(next.at - one.at).toBeLessThanOrEqual(SWELL.gapMax * 60_000 + SWELL.maxMs + 2 * WATCH_MS)
  }
  expect(new Set(swells.slice(1).map((one, i) => Math.round((one.at - swells[i]!.at) / 60_000))).size).toBeGreaterThan(1)
  await (await s.ctx()).save({ time: undefined })
  await quiet(s)
})

test('no swell with the chorus held, at noon, in the evening, or while thunder ducks the bed; rain fades one in progress with the bed', async () => {
  if (!BUILT.includes('sound')) return
  const s = await stand(intoRow(0, 5))
  onWindows(s)
  Object.assign(sky, { sun: 0, weather: 0 })
  await (await s.ctx()).save({ time: 'dusk' })
  shaderAt(s, sky)
  await s.advance(10_000)
  const moveTo = async (fields: { sun?: number; weather?: number }): Promise<void> => {
    Object.assign(sky, fields)
    rebuild({ ...sky, work: 0, zone: 0, hall: 0 }, s.now())
    await s.advance(PICTURE_LAG_MS + WATCH_MS + 10)
  }
  await engineCommand(s.$, await s.ctx(), 'sound', ['pick', 'cicadas', 'chorus'])
  await engineCommand(s.$, await s.ctx(), 'sound', ['on'])
  await s.advance(20 * 60_000)
  expect(swellsOf(s)).toEqual([])
  await engineCommand(s.$, await s.ctx(), 'sound', ['pick', 'cicadas', 'auto'])
  for (const sun of [6, 1]) {
    await moveTo({ sun })
    await s.advance(20 * 60_000)
    expect([sun, swellsOf(s)]).toEqual([sun, []])
  }
  await moveTo({ sun: 0 })
  for (let i = 0; i < 40 && swellsOf(s).length === 0; i++) await s.advance(30_000)
  expect(swellsOf(s).length).toBe(1)
  await thunderFor(s.$, { at: s.now() - 1000, delayS: 1 })
  await s.advance(WATCH_MS)
  expect(swellsOf(s)[0]!.fallMs).toBe(DUCK_FADE_MS.down)
  for (let i = 0; i < 40 && swellsOf(s).length === 1; i++) await s.advance(30_000)
  expect(swellsOf(s).length).toBe(2)
  const rainAt = s.now()
  await moveTo({ weather: 2 })
  const ran = s.mixers.flatMap(m => m.ran)
  const bedAt = ran.find(r => r.at >= rainAt && r.words[0] === 'bed')!
  expect(bedAt.words[1]).toBe(BANK.rain.entries.roof.rain)
  expect(swellsOf(s)[1]!.fallAt).toBe(bedAt.at)
  await s.advance(60_000)
  expect(s.mixers.flatMap(m => m.ran).filter(r => r.at > bedAt.at && r.words[0] === 'to' && r.words[1] === RIVER)).toEqual([])
  await (await s.ctx()).save({ time: undefined })
  await quiet(s)
})
