import { expect, test } from 'claude-code/testing'

import { rebuild } from '../core/values.js'
import { BUILT } from './index.js'
import { BANK } from './sound-bank.js'
import { HURRIED_MS, PICTURE_LAG_MS, START_FADE_MS, SUN_FADE_MS, EVENING_FADE_MS, EVENING_LEVEL, NIGHT_LEVEL, PREDAWN_LEVEL, WATCH_MS, bedName, engineCommand, gainOf } from './sound.js'
import { sky, stand, ranBy, onWindows, quiet, KATYDIDS, CRICKETS, intoRow, shaderAt } from './sound-testing.js'

test('sound turned on partway through the evening starts both beds where the cross-fade is then', async () => {
  if (!BUILT.includes('sound')) return
  const s = await stand(intoRow(1, 30))
  onWindows(s)
  Object.assign(sky, { sun: 1, weather: 0 })
  await engineCommand(s.$, await s.ctx(), 'sound', ['on'])
  await s.settle()
  const beds = ranBy(s).filter(line => line.startsWith('bed ') || line.startsWith('to '))
  const turn = ((30 + START_FADE_MS / 60_000) / 75) * (Math.PI / 2)
  const rest = 45 * 60_000 - START_FADE_MS
  const g = gainOf(70)
  expect([beds, s.notes()]).toEqual([[
    `to ${BANK.cicadas.entries.chorus.bed} ${(g * Math.cos(turn)).toFixed(4)} ${START_FADE_MS} 0.0000 ${rest}`,
    `to ${KATYDIDS} ${(g * EVENING_LEVEL * Math.sin(turn)).toFixed(4)} ${START_FADE_MS} ${(g * EVENING_LEVEL).toFixed(4)} ${rest}`,
  ], []])
  await quiet(s)
})

test('from dusk the cicadas give way to the night insects across the whole evening, the night stays, before dawn is quieter, and dawn is quiet', async () => {
  if (!BUILT.includes('sound')) return
  const s = await stand()
  onWindows(s)
  Object.assign(sky, { sun: 0, weather: 0 })
  shaderAt(s, sky)
  await s.advance(10_000)
  await engineCommand(s.$, await s.ctx(), 'sound', ['on'])
  await s.settle()
  const beds = (): string[] => ranBy(s).filter(line => line.startsWith('bed ') || line.startsWith('level '))
  expect(beds()).toEqual([`bed ${BANK.cicadas.entries.chorus.bed} ${gainOf(70).toFixed(4)} ${START_FADE_MS}`])
  const moveTo = async (sun: number): Promise<void> => {
    sky.sun = sun
    rebuild({ ...sky, work: 0, zone: 0, hall: 0 }, s.now())
    await s.advance(PICTURE_LAG_MS + WATCH_MS + 10)
  }

  await moveTo(1)
  const evening = beds().at(-1)!.split(' ')
  expect(evening.slice(0, 3)).toEqual(['bed', KATYDIDS, (gainOf(70) * EVENING_LEVEL).toFixed(4)])
  expect(Number(evening[3])).toBeGreaterThan(EVENING_FADE_MS - WATCH_MS - 50)
  expect(Number(evening[3])).toBeLessThanOrEqual(EVENING_FADE_MS)
  expect(bedName()).toBe('night insects')

  await s.advance(60_000)
  const before = beds().length
  const sent = ranBy(s).length
  await moveTo(2)
  expect(beds().length).toBe(before)
  const late = ranBy(s).slice(sent).filter(line => line.startsWith('to ')).map(line => line.split(' '))
  expect(late.map(words => words.slice(0, 3))).toEqual([
    ['to', BANK.cicadas.entries.chorus.bed, '0.0000'],
    ['to', KATYDIDS, '0.0000'],
    ['to', CRICKETS, (gainOf(70) * NIGHT_LEVEL).toFixed(4)],
  ])
  expect(Number(late[2]![3])).toBeGreaterThan(SUN_FADE_MS - WATCH_MS - 50)
  expect(Number(late[2]![3])).toBeLessThanOrEqual(SUN_FADE_MS)

  await s.advance(60_000)
  await moveTo(3)
  expect(beds().at(-1)).toBe(`level ${(gainOf(70) * PREDAWN_LEVEL).toFixed(4)} ${SUN_FADE_MS}`)

  await s.advance(60_000)
  await moveTo(4)
  expect(beds().at(-1)!.split(' ').slice(0, 2)).toEqual(['bed', '-'])
  expect(bedName()).toBe('quiet')
  await quiet(s)
})

test('an hour set by command moves the beds over the picture\'s hurried ease; back to the clock mid-evening lands on the clock\'s cross-fade', async () => {
  if (!BUILT.includes('sound')) return
  const s = await stand(intoRow(1, 30))
  onWindows(s)
  const g = gainOf(70)
  const lines = (): string[] => ranBy(s).filter(line => /^(bed|to|level) /.test(line))
  const hold = async (time: string | undefined, sun: number): Promise<void> => {
    await (await s.ctx()).save({ time })
    sky.sun = sun
    rebuild({ ...sky, work: 0, zone: 0, hall: 0 }, s.now(), { hurry: true })
    await s.advance(PICTURE_LAG_MS + WATCH_MS + 10)
  }
  Object.assign(sky, { sun: 0, weather: 0 })
  await (await s.ctx()).save({ time: 'dusk' })
  shaderAt(s, sky)
  await s.advance(10_000)
  await engineCommand(s.$, await s.ctx(), 'sound', ['on'])
  await s.settle()
  expect(lines()).toEqual([`bed ${BANK.cicadas.entries.chorus.bed} ${g.toFixed(4)} ${START_FADE_MS}`])

  await hold('evening', 1)
  const evening = lines().at(-1)!.split(' ')
  expect(evening.slice(0, 3)).toEqual(['bed', KATYDIDS, (g * EVENING_LEVEL).toFixed(4)])
  expect(Number(evening[3])).toBeGreaterThan(HURRIED_MS - WATCH_MS - 50)
  expect(Number(evening[3])).toBeLessThanOrEqual(HURRIED_MS)

  await s.advance(15_000)
  await hold('night', 2)
  const night = lines().at(-1)!.split(' ')
  expect(night.slice(0, 3)).toEqual(['bed', CRICKETS, (g * NIGHT_LEVEL).toFixed(4)])
  expect(Number(night[3])).toBeLessThanOrEqual(HURRIED_MS)
  await s.advance(15_000)
  await hold('predawn', 3)
  expect(lines().at(-1)!.split(' ').slice(0, 2)).toEqual(['level', (g * PREDAWN_LEVEL).toFixed(4)])

  await s.advance(15_000)
  await hold('dusk', 0)
  const dusk = lines().at(-1)!.split(' ')
  expect(dusk.slice(0, 3)).toEqual(['bed', BANK.cicadas.entries.chorus.bed, g.toFixed(4)])
  expect(Number(dusk[3])).toBeLessThanOrEqual(HURRIED_MS)

  await s.advance(15_000)
  await hold('evening', 1)
  await s.advance(15_000)
  const before = lines().length
  await (await s.ctx()).save({ time: undefined })
  await s.advance(WATCH_MS + 10)
  const back = lines().slice(before)
  expect(back.map(line => line.split(' ').slice(0, 2).join(' '))).toEqual([`to ${BANK.cicadas.entries.chorus.bed}`, `to ${KATYDIDS}`])
  const [cicadas, insects] = back.map(line => line.split(' ').slice(2).map(Number))
  expect(cicadas![0]! > 0 && cicadas![0]! < g).toBe(true)
  expect(insects![0]! > 0 && insects![0]! < g * EVENING_LEVEL).toBe(true)
  expect([cicadas![1], cicadas![2], insects![1], insects![2]]).toEqual([HURRIED_MS, 0, HURRIED_MS, Number((g * EVENING_LEVEL).toFixed(4))])
  await quiet(s)
})
