import { expect, test } from 'claude-code/testing'

import { minuteOfHalfDay } from '../core/clock.js'
import { savedOf } from '../core/saved.js'
import { noteForcedStrike, noteShaderStart, scheduledEventShows, strike } from '../core/schedule.js'
import { WORLD } from '../core/signals.gen.js'
import { EVENING, startRoom } from '../core/testing.js'
import { rebuild } from '../core/values.js'
import { BUILT, WITHOUT } from './index.js'
import { BANK, lengthOf } from './sound-bank.js'
import {
  DUCK,
  DUCK_FADE_MS,
  HURRIED_MS,
  PICTURE_LAG_MS,
  START_FADE_MS,
  TAKEN_MS,
  THUNDER_LIFT,
  WATCH_MS,
  WEATHER_EASE_MS,
  bedName,
  engineCommand,
  engineTick,
  forcedDelayS,
  gainOf,
  shownOf,
  strikeDelayS,
  thunderFor,
  thunderOf,
} from './sound.js'
import {
  wait,
  NIGHT,
  type Ran,
  type FakeMixer,
  COMMANDS,
  isCommands,
  runFile,
  mixerChild,
  sky,
  stand,
  ranBy,
  onWindows,
  quiet,
  shaderAt,
} from './sound-testing.js'

declare function setTimeout(fn: () => void, ms: number): unknown

test('in the plugin, /bedroom weather strike (the card\'s bolt) brings one thunder to the mixer, 1 to 4 s after the flash, and /bedroom sound names it', { timeoutMs: 30000, options: { ...NIGHT, weather: 'storm' } }, async ($, on) => {
  if (!BUILT.includes('sound') || !BUILT.includes('weather') || WITHOUT.includes('weather.lightning')) return
  const mixers: FakeMixer[] = []
  on('session.usage', () => ({ value: { startedAt: 0, context: { window: 200_000, tokens: 20_000, percent: 10 }, rateLimits: [] } }))
  on('session.info', () => ({ value: { platform: 'wsl', isHosted: false } as never }))
  on('env.get', (_, e) => ({ value: e.name === 'PATH' ? '/win:/usr/bin' : undefined }))
  on('fs.exists', (_, e) => ({ value: ['/win/powershell.exe', '/usr/bin/wslpath'].includes(String(e.path).replace(/^[A-Za-z]:/, '').replace(/\\/g, '/')) }))
  on('process.run', (_, e) => ({ value: { exitCode: 0, stdout: e.argv[1] === '-u' ? `${COMMANDS}\n` : 'W:\\room\\sounds\\bedroom\n', stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }))
  on('audio.play', () => ({ value: undefined }))
  let clockNow = (): number => 0
  on('process.spawn', async function* () {
    const m: FakeMixer = { ran: [], outbox: [], ended: false, last: 0 }
    mixers.push(m)
    yield* mixerChild(m, () => clockNow(), wake => void setTimeout(wake, 20))
  })
  let calm = EVENING
  while (![0, 1, 2].every(k => strike((minuteOfHalfDay(calm) + k) % 720) === undefined)) calm += 60_000
  const room = await startRoom($, on, { now: calm, fakes: false, onWrite: (path, text) => (isCommands(path) ? runFile(mixers.at(-1)!, text, clockNow()) : undefined) })
  clockNow = () => room.clock.now()
  const thunder = (): Ran[] => mixers.flatMap(m => m.ran).filter(r => r.words[0] === 'shot' && r.words[1]!.startsWith('thunder/'))

  expect(await room.run('sound on')).toMatch(/^sound is on/)
  await room.clock.advance(40_000)
  await wait(30)
  const before = thunder().length
  const asked = room.clock.now()
  const reply = await room.run('weather strike')
  expect(reply).toMatch(/^lightning strikes in about \d+ s$/)
  const flashS = Number(/about (\d+) s/.exec(reply)![1])
  for (let step = 0; step < 40 && thunder().length === before; step++) {
    await room.clock.advance(250)
    await wait(5)
  }
  await room.clock.advance(15_000)
  await wait(30)
  const heard = thunder().slice(before)
  expect(heard.length).toBe(1)
  const afterFlashS = (heard[0]!.at - asked) / 1000 - flashS
  expect(afterFlashS).toBeGreaterThanOrEqual(0.5)
  expect(afterFlashS).toBeLessThanOrEqual(4.5)
  expect(Number(heard[0]!.words[2])).toBeGreaterThan(0.3)
  expect(await room.run('sound')).toMatch(new RegExp(`last one-shot sent: ${heard[0]!.words[1]!.replace(/\.wav$/, '')} \\d+ s ago`))
  await room.run('sound off')
  await room.clock.advance(1000)
  await room.unmount()
})

test('S4: the sky the bed follows is the world code sent, and a code that is not the atmosphere leaves it', () => {
  const code = (sun: number, weather: number): number => sun + WORLD.sun * weather
  expect(shownOf({ code: 0, at: -Infinity, hurryAt: -Infinity, hurryWaits: false }, { sun: 2, weather: 3 }, undefined, 5)).toEqual({ sky: { sun: 2, weather: 3 }, at: 5, fadeMs: START_FADE_MS })
  expect(shownOf({ code: code(1, 4), at: 1000, hurryAt: 1000, hurryWaits: false }, { sun: 0, weather: 0 }, { sun: 1, weather: 0 }, 2000)).toEqual({ sky: { sun: 1, weather: 4 }, at: 1000 + PICTURE_LAG_MS, fadeMs: HURRIED_MS })
  expect(shownOf({ code: code(3, 0), at: 1000, hurryAt: -Infinity, hurryWaits: false }, { sun: 0, weather: 0 }, { sun: 2, weather: 0 }, 2000)?.fadeMs).toBe(30_000)
  expect(shownOf({ code: WORLD.top + 3, at: 1000, hurryAt: -Infinity, hurryWaits: false }, { sun: 0, weather: 0 }, undefined, 2000)).toBeUndefined()
})

test('S6: thunder comes 1 to 6 s after its strike, quieter and farther the longer the wait', async () => {
  if (!BUILT.includes('sound')) return
  const saved = savedOf({})
  const set = BANK.thunder.entries.storm
  expect(thunderOf(saved, { at: 10_000, delayS: 1 })).toEqual({ file: set.near[0], factor: THUNDER_LIFT, at: 11_000 })
  expect(thunderOf(saved, { at: 10_000, delayS: 3 })).toEqual({ file: set.mid[0], factor: THUNDER_LIFT * 0.8, at: 13_000 })
  expect(Math.abs(thunderOf(saved, { at: 10_000, delayS: 6 }).factor - THUNDER_LIFT / 2)).toBeLessThan(1e-9)
  expect([10_000, 11_000].map(at => thunderOf(saved, { at, delayS: 5 }).file).sort()).toEqual([...set.far].sort())
  expect(thunderOf(saved, { at: 0, delayS: 0.2 }).at).toBe(1000)
  expect(thunderOf(savedOf({ bank: { thunder: 'distant' } }), { at: 0, delayS: 1.5 }).file).toBe(BANK.thunder.entries.distant.near[0])
  for (let minute = 0; minute < 720; minute++) {
    const delay = strikeDelayS(minute)
    expect(delay >= 1 && delay <= 6).toBe(true)
  }

  const s = await stand()
  onWindows(s)
  Object.assign(sky, { sun: 6, weather: 4 })
  await engineCommand(s.$, await s.ctx(), 'sound', ['on'])
  await s.settle()
  const struck = s.now() + 2000
  await thunderFor(s.$, { at: struck, delayS: 4.5 })
  await s.advance(2000 + 4490)
  expect(ranBy(s).filter(line => line.startsWith('shot thunder/'))).toEqual([])
  await s.advance(10)
  const thunder = s.mixers[0]!.ran.filter(r => r.words[0] === 'shot' && r.words[1]!.startsWith('thunder/'))
  expect(thunder.map(r => [r.words[1], r.at])).toEqual([[thunderOf(saved, { at: struck, delayS: 4.5 }).file, struck + 4500]])
  expect(Math.abs(Number(thunder[0]!.words[2]) - Math.min(1, gainOf(70) * thunderOf(saved, { at: struck, delayS: 4.5 }).factor))).toBeLessThan(0.0001)
  const levels = s.mixers[0]!.ran.filter(r => r.words[0] === 'level')
  expect(levels.map(r => [r.words.join(' '), r.at])).toEqual([
    [`level ${(gainOf(70) * DUCK).toFixed(4)} ${DUCK_FADE_MS.down}`, struck + 4500],
  ])
  await s.advance(lengthOf(thunder[0]!.words[1]!))
  expect(s.mixers[0]!.ran.filter(r => r.words[0] === 'level').at(-1)?.words.join(' ')).toBe(`level ${gainOf(70).toFixed(4)} ${DUCK_FADE_MS.up}`)

  const overlap = s.now()
  await thunderFor(s.$, { at: overlap, delayS: 1 })
  await thunderFor(s.$, { at: overlap + 3000, delayS: 1 })
  await s.advance(20_000)
  const ducked = s.mixers[0]!.ran.filter(r => r.words[0] === 'level' && r.at > overlap)
  expect(ducked.map(r => r.words[2])).toEqual([String(DUCK_FADE_MS.down), String(DUCK_FADE_MS.up)])
  expect(ducked[1]!.at).toBe(overlap + 4000 + lengthOf(thunderOf(saved, { at: overlap + 3000, delayS: 1 }).file))
  await quiet(s)
})

test("S6: a minute's scheduled strike in a storm brings its thunder through the same call, and neither thunder nor a dip once the storm has gone, at the tick or before the strike shows", async () => {
  if (!BUILT.includes('sound')) return
  const evening = new Date(EVENING)
  const strikes = Array.from({ length: 240 }, (_, i) => 480 + i).filter(minute => strike(minute) !== undefined)
  const tickAt = (minute: number): number => new Date(evening.getFullYear(), evening.getMonth(), evening.getDate(), 20, minute - 480, 0, 50).getTime()
  const first = tickAt(strikes[0] ?? 0)
  expect(scheduledEventShows(first, -Infinity)).toBe(false)
  noteShaderStart(first - 20_000)
  expect(scheduledEventShows(first, -Infinity)).toBe(false)
  expect(scheduledEventShows(first + 10_000, -Infinity)).toBe(true)
  expect(scheduledEventShows(first + 10_000, first - 15_000)).toBe(false)
  noteShaderStart(first - 120_000)
  const s = await stand(first - 1000)
  onWindows(s)
  Object.assign(sky, { sun: 6, weather: 4 })
  await engineCommand(s.$, await s.ctx(), 'sound', ['on'])
  const thunders = BUILT.includes('weather') && !WITHOUT.includes('weather.lightning')
  const heard = (): Ran[] => s.mixers.flatMap(m => m.ran).filter(r => r.words[0] === 'shot' && r.words[1]!.startsWith('thunder/'))
  for (const minute of strikes.slice(0, 4)) {
    await s.advance(tickAt(minute) - s.now())
    const tick = s.now()
    await engineTick(s.$, await s.ctx())
    const before = heard().length
    const due = tick + TAKEN_MS + (strike(minute) ?? 0) * 1000 + strikeDelayS(minute) * 1000
    await s.advance(due - s.now() - 10)
    expect(heard().length).toBe(before)
    await s.advance(20)
    expect(heard().length).toBe(before + (thunders ? 1 : 0))
    if (thunders) {
      expect(heard().at(-1)!.at).toBe(due)
      expect(Number(heard().at(-1)!.words[2])).toBeGreaterThan(0.3)
    }
  }
  const stormed = heard().length
  const ducks = (): number => s.mixers.flatMap(m => m.ran).filter(r => r.words[0] === 'level' && r.words[2] === String(DUCK_FADE_MS.down)).length
  const ducked = ducks()
  await s.advance(tickAt(strikes[4] ?? 0) - s.now())
  await engineTick(s.$, await s.ctx())
  await s.settle()
  sky.weather = 2
  await s.advance(55_000)
  expect([heard().length, ducks()]).toEqual([stormed, ducked])
  await s.advance(tickAt(strikes[5] ?? 0) - s.now())
  await engineTick(s.$, await s.ctx())
  await s.advance(55_000)
  expect(heard().length).toBe(stormed)
  await quiet(s)
})

test('S6: a strike asked for with /bedroom weather strike brings its thunder once, 1 to 4 s after it shows', async () => {
  if (!BUILT.includes('sound')) return
  const s = await stand()
  onWindows(s)
  Object.assign(sky, { sun: 6, weather: 4 })
  await engineCommand(s.$, await s.ctx(), 'sound', ['on'])
  await s.settle()
  const heard = (): Ran[] => s.mixers.flatMap(m => m.ran).filter(r => r.words[0] === 'shot' && r.words[1]!.startsWith('thunder/'))
  const shows = noteForcedStrike(s.now(), 1000)
  const due = shows + forcedDelayS(shows) * 1000
  expect(forcedDelayS(shows) >= 1 && forcedDelayS(shows) <= 4).toBe(true)
  await s.advance(due - s.now() - 10)
  expect(heard()).toEqual([])
  await s.advance(20)
  const thunders = BUILT.includes('weather') && !WITHOUT.includes('weather.lightning')
  expect(heard().map(r => [r.words[1], r.at])).toEqual(thunders ? [[thunderOf(savedOf({}), { at: shows, delayS: forcedDelayS(shows) }).file, due]] : [])
  await s.advance(10_000)
  expect(heard().length).toBe(thunders ? 1 : 0)
  await quiet(s)
})

test("S4: a change of weather fades the beds over the picture's own ease, from when the picture starts to move", async () => {
  if (!BUILT.includes('sound')) return
  const s = await stand()
  onWindows(s)
  Object.assign(sky, { sun: 0, weather: 0 })
  shaderAt(s, sky)
  await s.advance(10_000)
  await engineCommand(s.$, await s.ctx(), 'sound', ['on'])
  await s.settle()
  expect(ranBy(s).filter(line => line.startsWith('bed '))).toEqual([`bed ${BANK.cicadas.entries.chorus.bed} 0.4900 ${START_FADE_MS}`])
  expect(bedName()).toBe('cicadas')

  sky.weather = 2
  const sentAt = s.now()
  rebuild({ ...sky, work: 0, zone: 0, hall: 0 }, sentAt, { hurry: true })
  await s.advance(PICTURE_LAG_MS - 10)
  expect(ranBy(s).filter(line => line.startsWith('bed ')).length).toBe(1)
  await s.advance(10 + WATCH_MS)
  const rain = s.mixers[0]!.ran.filter(r => r.words[0] === 'bed').at(-1)!
  expect(rain.words.slice(0, 2)).toEqual(['bed', BANK.rain.entries.roof.rain])
  expect(rain.at - sentAt).toBeGreaterThanOrEqual(PICTURE_LAG_MS)
  expect(Number(rain.words[3])).toBeGreaterThan(HURRIED_MS - WATCH_MS - 50)
  expect(Number(rain.words[3])).toBeLessThanOrEqual(HURRIED_MS)
  expect(bedName()).toBe('rain')

  await s.advance(40_000)
  sky.weather = 3
  rebuild({ ...sky, work: 0, zone: 0, hall: 0 }, s.now())
  await s.advance(PICTURE_LAG_MS + WATCH_MS)
  const downpour = s.mixers[0]!.ran.filter(r => r.words[0] === 'bed').at(-1)!
  expect(downpour.words.slice(0, 2)).toEqual(['bed', BANK.rain.entries.roof.downpour])
  expect(Number(downpour.words[3])).toBeGreaterThan(WEATHER_EASE_MS - 1000)

  await engineCommand(s.$, await s.ctx(), 'sound', ['volume', '50'])
  expect(ranBy(s).at(-1)).toBe(`level ${gainOf(50).toFixed(4)} 400`)
  await quiet(s)
})
