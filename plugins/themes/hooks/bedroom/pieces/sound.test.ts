import { expect, test } from 'claude-code/testing'

import { savedOf } from '../core/saved.js'
import { BUILT } from './index.js'
import { BANK, LENGTH_MS, chosenName, lengthOf, namesOf } from './sound-bank.js'
import { PICK_FADE_MS, WATCH_MS, argvOf, commandLineOf, engineCommand, engineSwitched, engineTick, gainOf, purr, thunderFor } from './sound.js'
import { sky, type Stand, stand, fileIn, ranBy, onWindows, quiet, KATYDIDS, CRICKETS } from './sound-testing.js'

const live = (s: Stand): string[] => s.plays.filter(play => play.endedAt === undefined).map(play => fileIn(play.argv))
const named = (s: Stand, file: string): Stand['plays'] => s.plays.filter(play => fileIn(play.argv) === file)
const CHORUS = BANK.cicadas.entries.chorus.bed

test('nothing reaches the engine while sound is off', async () => {
  if (!BUILT.includes('sound')) return
  const s = await stand()
  s.files = new Set(['/usr/bin/ffplay'])
  Object.assign(sky, { sun: 0, weather: 4 })
  for (let minute = 0; minute < 3; minute++) {
    const ctx = await s.ctx()
    await engineTick(s.$, ctx)
    engineSwitched(s.$, ctx, 'tv', minute % 2 === 0, 'click')
    engineSwitched(s.$, ctx, 'lamp', minute % 2 === 0, 'click')
    purr(s.$)
    await thunderFor(s.$, { at: s.now(), delayS: 2 })
    await s.advance(60_000)
  }
  expect(s.calls).toEqual([])
  expect(await engineCommand(s.$, await s.ctx(), 'sound', [])).toMatch(/^sound is off, volume 70, objects on\. bank: cicadas auto, night auto, rain roof, thunder storm, tv tube\. player: not looked for yet/)
  expect(s.calls).toEqual([])
})

test('S1: each kind has named entries with a default, picked by name or number and saved; 0.3\'s picks carry over', async () => {
  if (!BUILT.includes('sound')) return
  expect(namesOf('cicadas')).toEqual(['auto', 'chorus', 'river'])
  expect(namesOf('night')).toEqual(['auto', 'katydids', 'crickets'])
  expect(namesOf('rain')).toEqual(['roof'])
  expect(namesOf('thunder')).toEqual(['storm', 'distant'])
  expect(namesOf('tv')).toEqual(['tube'])
  for (const file of Object.keys(LENGTH_MS)) expect(LENGTH_MS[file]! > 0).toBe(true)
  expect(savedOf({ picks: { cicadas: 2, rain: 2, thunder: 2 } }).bank).toEqual({ cicadas: 'river' })
  expect(savedOf({ picks: { rain: 2 } }).bank).toBeUndefined()
  expect(savedOf({ bank: { cicadas: 'river', rain: 'Bad name' }, picks: { rain: 2 } }).bank).toEqual({ cicadas: 'river' })
  expect(chosenName(savedOf({ bank: { rain: 'window' } }), 'rain')).toBe('roof')
  expect(savedOf({ objects: false }).objects).toBe(false)

  const s = await stand()
  onWindows(s)
  Object.assign(sky, { sun: 0, weather: 0 })
  await engineCommand(s.$, await s.ctx(), 'sound', ['on'])
  await s.settle()
  expect(await engineCommand(s.$, await s.ctx(), 'sound', ['pick', 'cicadas', 'river'])).toBe('cicadas plays river')
  expect(ranBy(s).filter(line => line.startsWith('bed ')).at(-1)).toBe(`bed ${BANK.cicadas.entries.river.bed} 0.4900 ${PICK_FADE_MS}`)
  expect((await s.ctx()).saved.bank).toEqual({ cicadas: 'river' })
  expect(await engineCommand(s.$, await s.ctx(), 'sound', ['pick', 'cicadas', '2'])).toBe('cicadas plays chorus')
  expect(await engineCommand(s.$, await s.ctx(), 'sound', ['pick', 'cicadas', 'auto'])).toBe('cicadas plays auto')
  expect(await engineCommand(s.$, await s.ctx(), 'sound', ['pick', 'night', 'auto'])).toBe('night plays auto')
  expect(await engineCommand(s.$, await s.ctx(), 'sound', ['pick', 'thunder', 'distant'])).toBe('thunder plays distant')
  expect(await engineCommand(s.$, await s.ctx(), 'sound', ['pick', 'night', 'crickets'])).toBe('night plays crickets')
  expect(await engineCommand(s.$, await s.ctx(), 'sound', ['pick', 'night', 'katydids'])).toBe('night plays katydids')
  expect(await engineCommand(s.$, await s.ctx(), 'sound', ['pick', 'crickets', 'crickets'])).toMatch(/^say a kind and one of its sounds/)
  expect(ranBy(s)).toContain(`load ${BANK.thunder.entries.distant.far[0]}`)
  expect(await engineCommand(s.$, await s.ctx(), 'sound', ['pick', 'wind', 'x'])).toMatch(/^say a kind and one of its sounds, as in \/bedroom sound pick cicadas river\. cicadas: auto or chorus or river; night: auto or katydids or crickets; rain: roof; thunder: storm or distant; tv: tube\. Now:/)
  expect(await engineCommand(s.$, await s.ctx(), 'sound', ['pick', 'rain', 'tin'])).toMatch(/^say a kind/)
  await quiet(s)
})

test('one bed at a time: the hour\'s insects when dry, and rain, downpour and storm each their own', async () => {
  if (!BUILT.includes('sound')) return
  const s = await stand()
  s.files = new Set(['/usr/bin/ffplay'])
  Object.assign(sky, { sun: 0, weather: 0 })
  await engineCommand(s.$, await s.ctx(), 'sound', ['on'])
  await s.settle()
  expect(live(s)).toEqual([BANK.cicadas.entries.chorus.bed])
  const roof = BANK.rain.entries.roof
  const cases = [
    [{ sun: 1, weather: 1 }, [KATYDIDS]],
    [{ sun: 2, weather: 2 }, [roof.rain]],
    [{ sun: 2, weather: 3 }, [roof.downpour]],
    [{ sun: 6, weather: 4 }, [roof.storm]],
    [{ sun: 5, weather: 0 }, []],
    [{ sun: 3, weather: 1 }, [CRICKETS]],
    [{ sun: 0, weather: 0 }, [BANK.cicadas.entries.chorus.bed]],
  ] as const
  for (const [fields, beds] of cases) {
    Object.assign(sky, fields)
    await engineTick(s.$, await s.ctx())
    await s.advance(250)
    expect([fields, live(s)]).toEqual([fields, [...beds]])
  }
  const children = s.plays.length
  for (let minute = 0; minute < 10; minute++) {
    await engineTick(s.$, await s.ctx())
    await s.advance(60_000)
  }
  expect(s.plays.filter(play => !fileIn(play.argv).startsWith('thunder/')).length).toBe(children)
  expect(live(s)).toEqual([BANK.cicadas.entries.chorus.bed])
  expect(s.plays.at(0)?.argv).toContain('-loop')
  await engineCommand(s.$, await s.ctx(), 'sound', ['volume', '40'])
  await s.advance(250)
  expect(s.plays.at(-1)?.argv.slice(6, 8)).toEqual(['-volume', '16'])
  await engineCommand(s.$, await s.ctx(), 'sound', ['off'])
  await s.advance(250)
  expect(live(s)).toEqual([])
  await quiet(s)
})

test("each player's argument list carries the volume; macOS plays through the engine, and no player keeps sound off", async () => {
  if (!BUILT.includes('sound')) return
  expect([0, 50, 70, 100].map(gainOf)).toEqual([0, 0.25, 0.48999999999999994, 1])
  expect(argvOf('ffplay', '/x/rain-1.wav', 0.25, true)).toEqual(['ffplay', '-nodisp', '-autoexit', '-loglevel', 'quiet', '-stats', '-volume', '25', '-loop', '0', '/x/rain-1.wav'])
  expect(argvOf('paplay', '/x/tv-on.wav', 0.25, true)).toEqual(['paplay', '--verbose', '--volume=16384', '/x/tv-on.wav'])
  expect(argvOf('aplay', '/x/tv-on.wav', 0.25, false)).toEqual(['aplay', '-V', 'mono', '/x/tv-on.wav'])
  expect(commandLineOf('mpv --volume={volume} {file}', '/x/rain-1.wav', 0.25)).toEqual(['mpv', '--volume=25', '/x/rain-1.wav'])
  expect(commandLineOf('play -q', '/x/rain-1.wav')).toEqual(['play', '-q', '/x/rain-1.wav'])

  const s = await stand()
  Object.assign(sky, { sun: 4, weather: 0 })
  s.platform = 'macos'
  await engineCommand(s.$, await s.ctx(), 'sound', ['volume', '50'])
  expect(await engineCommand(s.$, await s.ctx(), 'sound', ['on'])).toMatch(/^sound is on, played by the engine/)
  engineSwitched(s.$, await s.ctx(), 'tv', false, 'click')
  await s.advance(1100)
  expect(s.clips).toEqual([{ asset: `sounds/bedroom/${BANK.tv.entries.tube.off}`, gain: 0.25, shouldLoop: undefined }])

  s.platform = 'linux'
  s.files = new Set()
  await engineCommand(s.$, await s.ctx(), 'sound', ['off'])
  expect(await engineCommand(s.$, await s.ctx(), 'sound', ['on'])).toMatch(/^no player was found .* so sound stays off$/)
  expect((await s.ctx()).setting('sound')).toBe(false)
  await quiet(s)
})

test('sound off, a change of bed and volume 0 stop the playing child within one beat', async () => {
  if (!BUILT.includes('sound')) return
  const s = await stand()
  s.files = new Set(['/usr/bin/ffplay'])
  Object.assign(sky, { sun: 0, weather: 0 })
  const roof = BANK.rain.entries.roof
  await engineCommand(s.$, await s.ctx(), 'sound', ['on'])
  await s.advance(5000)
  const cicadas = named(s, CHORUS)[0]!
  expect(cicadas.endedAt).toBeUndefined()

  sky.weather = 2
  const changedAt = s.now()
  await s.advance(WATCH_MS + 250)
  expect(cicadas.endedAt).toBeDefined()
  expect(cicadas.endedAt! - changedAt).toBeLessThanOrEqual(WATCH_MS + 250)
  expect(live(s)).toEqual([roof.rain])

  engineSwitched(s.$, await s.ctx(), 'tv', true, 'click')
  await s.advance(250)
  expect(live(s).sort()).toEqual([roof.rain, BANK.tv.entries.tube.on].sort())
  const at = s.now()
  await engineCommand(s.$, await s.ctx(), 'sound', ['off'])
  await s.advance(250)
  expect(live(s)).toEqual([])
  expect(Math.max(...s.plays.map(play => play.endedAt ?? Infinity))).toBeLessThanOrEqual(at + 250)

  await engineCommand(s.$, await s.ctx(), 'sound', ['on'])
  await s.advance(250)
  expect(live(s)).toEqual([roof.rain])
  await engineCommand(s.$, await s.ctx(), 'sound', ['volume', '0'])
  await s.advance(250)
  expect(live(s)).toEqual([])
  engineSwitched(s.$, await s.ctx(), 'tv', false, 'click')
  await s.advance(250)
  expect(live(s)).toEqual([])
  await engineCommand(s.$, await s.ctx(), 'sound', ['volume', '70'])
  await s.advance(250)
  expect(live(s)).toEqual([roof.rain])
  expect(await engineCommand(s.$, await s.ctx(), 'sound', ['volume', '101'])).toMatch(/^give a whole number from 0 to 100/)
  await quiet(s)
})

test('a player that cannot repeat a file plays a chain, the next only after the last has run its length', async () => {
  if (!BUILT.includes('sound')) return
  const s = await stand()
  s.files = new Set(['/usr/bin/paplay'])
  Object.assign(sky, { sun: 0, weather: 0 })
  await engineCommand(s.$, await s.ctx(), 'sound', ['on'])
  await s.settle()
  expect(named(s, CHORUS).length).toBe(1)
  await s.advance(lengthOf(CHORUS) + 250)
  expect(named(s, CHORUS).length).toBe(2)
  s.state.set('bedroom-chain', 7)
  await engineTick(s.$, await s.ctx())
  s.state.set('bedroom-chain', 8)
  await s.advance(3 * lengthOf(CHORUS))
  expect(named(s, CHORUS).length).toBe(2)
  s.state.delete('bedroom-chain')
  await quiet(s)
})

test('a failing player becomes one line in the debug log, not an error', async () => {
  if (!BUILT.includes('sound')) return
  const s = await stand()
  s.files = new Set(['/usr/bin/paplay'])
  Object.assign(sky, { sun: 0, weather: 0 })
  s.exit = 1
  expect(await engineCommand(s.$, await s.ctx(), 'sound', ['on'])).toMatch(/^sound is on/)
  await s.advance(20_500)
  for (let minute = 0; minute < 3; minute++) {
    const ctx = await s.ctx()
    await engineTick(s.$, ctx)
    engineSwitched(s.$, ctx, 'tv', true, 'click')
    await s.advance(60_000)
  }
  expect(s.plays.length).toBe(1)
  expect(s.notes().length).toBe(1)
  expect(s.notes()[0]).toMatch(/sound: paplay exited 1 playing cicadas\/chorus\.wav: no audio device; nothing plays until \/bedroom sound on$/)
  expect(await engineCommand(s.$, await s.ctx(), 'sound', [])).toMatch(/^sound is on but nothing plays: paplay exited 1 playing cicadas\/chorus\.wav: no audio device; say \/bedroom sound on to try again, volume 70, objects on\. .* player: paplay, stopped: paplay exited 1/)

  s.exit = 'reject'
  await engineCommand(s.$, await s.ctx(), 'sound', ['on'])
  await s.advance(2 * lengthOf(CHORUS))
  expect(s.plays.length).toBe(2)
  expect(s.notes().length).toBe(2)
  expect(s.notes()[1]).toMatch(/sound: paplay failed playing cicadas\/chorus\.wav: the command could not start/)
  s.exit = 0

  expect(await engineCommand(s.$, await s.ctx(), 'sound', ['test'])).toBe('paplay played silence.wav and exited 0')
  await engineTick(s.$, await s.ctx())
  await s.advance(2 * lengthOf(CHORUS))
  expect(s.plays.map(play => fileIn(play.argv))).toEqual([CHORUS, CHORUS, 'silence.wav'])
  expect(await engineCommand(s.$, await s.ctx(), 'sound', [])).toMatch(/, stopped: paplay failed playing cicadas\/chorus\.wav/)
  await quiet(s)
})

test('a volume, bank and objects stored outside their range load as the defaults', () => {
  expect(savedOf({ volume: 40, bank: { cicadas: 'river' } })).toMatchObject({ volume: 40, bank: { cicadas: 'river' } })
  expect(savedOf({ volume: 140 }).volume).toBeUndefined()
  expect(savedOf({ volume: 4.5 }).volume).toBeUndefined()
  expect(savedOf({ objects: 'yes' }).objects).toBeUndefined()
})
