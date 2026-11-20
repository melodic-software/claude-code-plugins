import type { EngineInterface } from 'claude-code'
import { expect, test } from 'claude-code/testing'

import { readNow } from '../core/clock.js'
import { ctxOf, usePieces } from '../core/context.js'
import type { Ctx, Fields, Piece } from '../core/piece.js'
import { load } from '../core/saved.js'
import { strike } from '../core/schedule.js'
import { useOptions } from '../core/settings.js'
import { EVENING, QUIET, startRoom } from '../core/testing.js'
import { BUILT, WITHOUT } from './index.js'
import { LENGTH_MS, TAKEN_MS, commandLineOf, engineCommand, engineSwitched, engineTick, type Sound } from './sound.js'

const soundOf = (text: string): Sound => (text.match(/([a-z0-9-]+)\.wav/)?.[1] ?? 'silence') as Sound

test('in the plugin, nothing plays while sound is off; on, the television plays through process.run', { timeoutMs: 20000, options: QUIET }, async ($, on) => {
  if (!BUILT.includes('sound')) return
  const runs: { argv: readonly string[]; timeoutMs?: number }[] = []
  const clips: unknown[] = []
  let looks = 0
  const ok = { stdout: '', stderr: '', isStdoutTruncated: false, isStderrTruncated: false }
  on('session.usage', () => ({ value: { startedAt: 0, context: { window: 200_000, tokens: 20_000, percent: 10 }, rateLimits: [] } }))
  on('session.info', () => {
    looks += 1
    return { value: { platform: 'linux', isHosted: false } as never }
  })
  on('env.get', (_, e) => {
    looks += 1
    return { value: e.name === 'PATH' ? '/usr/local/bin:/usr/bin' : undefined }
  })
  on('fs.exists', (_, e) => {
    looks += 1
    return { value: e.path === '/usr/bin/ffplay' }
  })
  on('process.run', (_, e) => {
    runs.push({ argv: e.argv, timeoutMs: e.init?.timeoutMs })
    if (runs.length > 50) throw new Error('more than 50 plays')
    return { value: { exitCode: 0, ...ok } }
  })
  on('audio.play', (_, e) => {
    clips.push(e.clip)
    return { value: undefined }
  })
  const room = await startRoom($, on, { fakes: false })
  await room.run('tv off')
  await room.run('tv on')
  await room.clock.advance(3 * 60_000)
  expect([runs.length, clips.length, looks]).toEqual([0, 0, 0])

  expect(await room.run('sound on')).toMatch(/^sound is on, played by ffplay/)
  await room.run('tv off')
  await room.clock.settle()
  const tv = runs.find(run => run.argv.at(-1)?.endsWith('/sounds/bedroom/tv-off.wav'))
  expect(tv?.argv.slice(0, -1)).toEqual(['ffplay', '-nodisp', '-autoexit', '-loglevel', 'quiet'])
  expect(tv?.timeoutMs).toBe(15_900)
  const cicadas = (): number => runs.filter(run => run.argv.at(-1)?.endsWith('/sounds/bedroom/cicadas.wav')).length
  expect(cicadas()).toBe(1)
  expect(runs.find(run => run.argv.at(-1)?.endsWith('/sounds/bedroom/cicadas.wav'))?.timeoutMs).toBe(39_000)
  await room.clock.advance(60_000)
  expect(cicadas()).toBe(3)
  expect(await room.run('sound off')).toMatch(/^sound is off/)
  await room.clock.advance(3 * 60_000)
  expect(cicadas()).toBe(3)
  expect(clips).toEqual([])
  await room.unmount()
})


/** What the weather and time pieces would give: the fields the sound follows. */
const sky: Pick<Fields, 'sun' | 'weather'> = { sun: 0, weather: 0 }
const standIn: Piece = { name: 'stand-in', fields: () => ({ ...sky }) }

type Play = { argv: readonly string[]; timeoutMs: number | undefined }
type Stand = {
  $: EngineInterface
  /** What the stand-in answers: the platform, PATH, the files on it, how a player exits, the minute chain held. */
  platform: string
  path: string
  files: Set<string>
  exit: number | 'reject'
  chain: number | undefined
  plays: Play[]
  clips: string[]
  /** Every engine call the piece made, by name. */
  calls: string[]
  notes: () => string[]
  ctx: () => Promise<Ctx>
  /** Moves the clock on, running each timer and ending each play as it comes due. */
  advance: (ms: number) => Promise<void>
  settle: () => Promise<void>
}

async function stand(start = EVENING): Promise<Stand> {
  let now = start
  const timers: { at: number; fn: () => void }[] = []
  const later = (ms: number, fn: () => void): void => void timers.push({ at: now + ms, fn })
  const store = new Map<string, unknown>()
  const log: string[] = []
  const settle = async (): Promise<void> => {
    for (let i = 0; i < 200; i++) await Promise.resolve()
  }
  const s: Stand = {
    $: undefined as unknown as EngineInterface,
    platform: 'linux',
    path: '/opt/a:/usr/bin',
    files: new Set(),
    exit: 0,
    chain: undefined,
    plays: [],
    clips: [],
    calls: [],
    notes: () => log.filter(line => line.includes(' sound: ')),
    ctx: async () => {
      await readNow(s.$)
      return ctxOf(s.$)
    },
    settle,
    advance: async ms => {
      const until = now + ms
      for (;;) {
        await settle()
        timers.sort((a, b) => a.at - b.at)
        const next = timers[0]
        if (next === undefined || next.at > until) break
        timers.shift()
        now = next.at
        next.fn()
      }
      now = until
      await settle()
    },
  }
  const ok = { stdout: '', stderr: '', isStdoutTruncated: false, isStderrTruncated: false }
  s.$ = {
    plugin: { name: 'themes', root: '/room' },
    store: { get: async (key: string) => store.get(key), set: async (key: string, value: unknown) => void store.set(key, value) },
    state: { get: async () => ({ value: s.chain }) },
    ui: { toast: () => undefined, invalidate: () => undefined, log: (text: string) => void log.push(text) },
    clock: {
      now: async () => now,
      after: (ms: number, fn: () => void) => {
        later(ms, fn)
        return { cancel: () => undefined }
      },
    },
    session: {
      info: async () => {
        s.calls.push('session.info')
        return { platform: s.platform, isHosted: false }
      },
    },
    env: {
      get: async (name: string) => {
        s.calls.push('env.get')
        return name === 'PATH' ? s.path : undefined
      },
    },
    fs: {
      exists: async (path: string) => {
        s.calls.push('fs.exists')
        return s.files.has(path)
      },
    },
    process: {
      run: async (argv: readonly string[], init?: { timeoutMs?: number }) => {
        s.calls.push('process.run')
        if (argv[0] === 'wslpath') return { exitCode: 0, ...ok, stdout: 'W:\\room\\sounds\\bedroom\n' }
        s.plays.push({ argv, timeoutMs: init?.timeoutMs })
        const exit = s.exit
        await new Promise<void>(resolve => later(LENGTH_MS[soundOf(argv.join(' '))], resolve))
        if (exit === 'reject') throw new Error('the command could not start')
        return { exitCode: exit, ...ok, stderr: exit === 0 ? '' : 'no audio device' }
      },
    },
    audio: {
      play: async (clip: { asset: string }) => {
        s.calls.push('audio.play')
        s.clips.push(clip.asset)
        await new Promise<void>(resolve => later(LENGTH_MS[soundOf(clip.asset)], resolve))
      },
    },
  } as unknown as EngineInterface
  await load(s.$)
  usePieces([standIn])
  useOptions({})
  return s
}

const named = (s: Stand, sound: Sound): Play[] => s.plays.filter(play => play.argv.join(' ').includes(`${sound}.wav`))

/** Turns sound off and lets every play end, so the next test starts with nothing playing. */
async function quiet(s: Stand): Promise<void> {
  await engineCommand(s.$, await s.ctx(), 'sound', ['off'])
  await s.advance(120_000)
}

test('nothing reaches the engine while sound is off', async () => {
  if (!BUILT.includes('sound')) return
  const s = await stand()
  s.files = new Set(['/usr/bin/ffplay'])
  Object.assign(sky, { sun: 0, weather: 4 })
  for (let minute = 0; minute < 3; minute++) {
    const ctx = await s.ctx()
    await engineTick(s.$, ctx)
    engineSwitched(s.$, ctx, 'tv', minute % 2 === 0, 'click')
    await s.advance(60_000)
  }
  expect(s.calls).toEqual([])
  expect(await engineCommand(s.$, await s.ctx(), 'sound', [])).toMatch(/^sound is off\. player: not looked for yet/)
  expect(s.calls).toEqual([])
})

test("each player's argument list, and a timeout of the file's length plus 15 s", async () => {
  if (!BUILT.includes('sound')) return
  const s = await stand()
  Object.assign(sky, { sun: 6, weather: 0 })
  const tvOn = async (): Promise<Play | undefined> => {
    const ctx = await s.ctx()
    engineSwitched(s.$, ctx, 'tv', true, 'click')
    engineSwitched(s.$, ctx, 'tv', false, 'click')
    await s.advance(LENGTH_MS['tv-on'])
    return s.plays.at(-1)
  }

  s.platform = 'wsl'
  s.files = new Set(['/opt/a/powershell.exe', '/usr/bin/wslpath', '/usr/bin/ffplay'])
  expect(await engineCommand(s.$, await s.ctx(), 'sound', ['on'])).toMatch(/^sound is on, played by powershell\.exe/)
  expect(await tvOn()).toEqual({
    argv: ['powershell.exe', '-NoProfile', '-NonInteractive', '-Command', "(New-Object System.Media.SoundPlayer 'W:\\room\\sounds\\bedroom\\tv-on.wav').PlaySync()"],
    timeoutMs: 16_200,
  })
  expect(s.plays.length).toBe(1)

  s.platform = 'linux'
  for (const [file, argv] of [
    ['/usr/bin/ffplay', ['ffplay', '-nodisp', '-autoexit', '-loglevel', 'quiet']],
    ['/usr/bin/paplay', ['paplay']],
    ['/opt/a/aplay', ['aplay', '-q']],
  ] as const) {
    s.files = new Set([file])
    expect(await engineCommand(s.$, await s.ctx(), 'sound', ['on'])).toMatch(new RegExp(`^sound is on, played by ${argv[0]}`))
    expect(await tvOn()).toEqual({ argv: [...argv, '/room/sounds/bedroom/tv-on.wav'], timeoutMs: 16_200 })
  }

  useOptions({ soundPlayer: 'mpv --really-quiet {file}' })
  expect(await engineCommand(s.$, await s.ctx(), 'sound', ['on'])).toMatch(/^sound is on, played by mpv/)
  expect((await tvOn())?.argv).toEqual(['mpv', '--really-quiet', '/room/sounds/bedroom/tv-on.wav'])
  expect(commandLineOf('play -q', '/x/rain.wav')).toEqual(['play', '-q', '/x/rain.wav'])
  useOptions({})

  s.files = new Set(['/usr/bin/paplay'])
  const before = s.plays.length
  const testing = engineCommand(s.$, await s.ctx(), 'sound', ['test'])
  await s.advance(LENGTH_MS.silence)
  expect(await testing).toBe('paplay played silence.wav and exited 0')
  expect(s.plays.slice(before)).toEqual([{ argv: ['paplay', '/room/sounds/bedroom/silence.wav'], timeoutMs: 15_400 }])

  s.platform = 'macos'
  expect(await engineCommand(s.$, await s.ctx(), 'sound', ['on'])).toMatch(/^sound is on, played by the engine/)
  const runs = s.plays.length
  await tvOn()
  expect(s.clips).toEqual(['sounds/bedroom/tv-on.wav'])
  expect(s.plays.length).toBe(runs)

  s.platform = 'linux'
  s.files = new Set()
  await engineCommand(s.$, await s.ctx(), 'sound', ['off'])
  expect(await engineCommand(s.$, await s.ctx(), 'sound', ['on'])).toMatch(/^no player was found .* so sound stays off$/)
  expect((await s.ctx()).setting('sound')).toBe(false)
  await quiet(s)
})

test('a loop is a chain of single plays that stops within one play of sound off, the weather changing or a reload', async () => {
  if (!BUILT.includes('sound')) return
  const s = await stand()
  s.files = new Set(['/usr/bin/ffplay'])
  Object.assign(sky, { sun: 0, weather: 0 })
  await engineCommand(s.$, await s.ctx(), 'sound', ['on'])
  await s.settle()
  expect(named(s, 'cicadas').length).toBe(1)
  expect(named(s, 'cicadas')[0]?.timeoutMs).toBe(39_000)
  await s.advance(LENGTH_MS.cicadas)
  expect(named(s, 'cicadas').length).toBe(2)
  await engineTick(s.$, await s.ctx())
  await s.settle()
  expect(named(s, 'cicadas').length).toBe(2)

  sky.weather = 2
  await s.advance(LENGTH_MS.cicadas)
  expect(named(s, 'cicadas').length).toBe(2)
  await engineTick(s.$, await s.ctx())
  await s.settle()
  expect(named(s, 'rain').length).toBe(1)
  expect(named(s, 'rain')[0]?.timeoutMs).toBe(41_000)
  await s.advance(LENGTH_MS.rain)
  expect(named(s, 'rain').length).toBe(2)

  sky.weather = 0
  await s.advance(LENGTH_MS.rain)
  expect(named(s, 'rain').length).toBe(2)
  await engineTick(s.$, await s.ctx())
  await s.settle()
  expect(named(s, 'cicadas').length).toBe(3)
  sky.weather = 2
  await s.advance(LENGTH_MS.cicadas)
  await engineTick(s.$, await s.ctx())
  await s.settle()
  expect(named(s, 'rain').length).toBe(3)

  await engineCommand(s.$, await s.ctx(), 'sound', ['off'])
  await s.advance(3 * LENGTH_MS.rain)
  expect(named(s, 'rain').length).toBe(3)

  Object.assign(sky, { sun: 2, weather: 1 })
  await engineCommand(s.$, await s.ctx(), 'sound', ['on'])
  await s.settle()
  expect(named(s, 'cicadas').length).toBe(4)
  sky.sun = 5
  await s.advance(3 * LENGTH_MS.cicadas)
  expect(named(s, 'cicadas').length).toBe(4)

  sky.sun = 0
  s.chain = 7
  await engineTick(s.$, await s.ctx())
  await s.settle()
  expect(named(s, 'cicadas').length).toBe(5)
  s.chain = 8
  await s.advance(3 * LENGTH_MS.cicadas)
  expect(named(s, 'cicadas').length).toBe(5)
  s.chain = undefined
  await quiet(s)
})

test('thunder follows a scheduled strike in a storm, and not in rain', async () => {
  if (!BUILT.includes('sound')) return
  const evening = new Date(EVENING)
  const strikes = Array.from({ length: 240 }, (_, i) => 480 + i).filter(minute => strike(minute) !== undefined)
  const tickAt = (minute: number): number => new Date(evening.getFullYear(), evening.getMonth(), evening.getDate(), 20, minute - 480, 0, 50).getTime()
  const s = await stand(tickAt(strikes[0] ?? 0) - 1000)
  s.files = new Set(['/usr/bin/ffplay'])
  Object.assign(sky, { sun: 6, weather: 4 })
  await engineCommand(s.$, await s.ctx(), 'sound', ['on'])
  const thunder = (): Play[] => s.plays.filter(play => /thunder-\d\.wav$/.test(play.argv.at(-1) ?? ''))
  const thunders = BUILT.includes('weather') && !WITHOUT.includes('weather.lightning')

  for (const minute of strikes.slice(0, 4)) {
    await s.advance(tickAt(minute) - (await s.$.clock.now()))
    await engineTick(s.$, await s.ctx())
    const before = thunder().length
    await s.advance(TAKEN_MS + (strike(minute) ?? 0) * 1000 + 990)
    expect(thunder().length).toBe(before)
    await s.advance(3020)
    expect(thunder().length).toBe(before + (thunders ? 1 : 0))
  }
  if (thunders) expect(thunder()[0]?.timeoutMs).toBe(LENGTH_MS[soundOf(thunder()[0]?.argv.at(-1) ?? '')] + 15_000)

  sky.weather = 2
  const stormed = thunder().length
  await s.advance(tickAt(strikes[4] ?? 0) - (await s.$.clock.now()))
  await engineTick(s.$, await s.ctx())
  await s.advance(55_000)
  expect(thunder().length).toBe(stormed)
  await quiet(s)
})

test('a failing player becomes one line in the debug log, not an error', async () => {
  if (!BUILT.includes('sound')) return
  const s = await stand()
  s.files = new Set(['/usr/bin/ffplay'])
  Object.assign(sky, { sun: 0, weather: 0 })
  s.exit = 1
  expect(await engineCommand(s.$, await s.ctx(), 'sound', ['on'])).toMatch(/^sound is on/)
  await s.advance(LENGTH_MS.cicadas)
  for (let minute = 0; minute < 3; minute++) {
    const ctx = await s.ctx()
    await engineTick(s.$, ctx)
    engineSwitched(s.$, ctx, 'tv', true, 'click')
    await s.advance(60_000)
  }
  expect(s.plays.length).toBe(1)
  expect(s.notes().length).toBe(1)
  expect(s.notes()[0]).toMatch(/sound: ffplay exited 1 playing cicadas: no audio device; nothing plays until \/bedroom sound on$/)
  expect(await engineCommand(s.$, await s.ctx(), 'sound', [])).toMatch(/^sound is on\. player: ffplay, stopped: ffplay exited 1/)

  s.exit = 'reject'
  await engineCommand(s.$, await s.ctx(), 'sound', ['on'])
  await s.advance(2 * LENGTH_MS.cicadas)
  expect(s.plays.length).toBe(2)
  expect(s.notes().length).toBe(2)
  expect(s.notes()[1]).toMatch(/sound: ffplay failed playing cicadas: the command could not start/)
  s.exit = 0

  const testing = engineCommand(s.$, await s.ctx(), 'sound', ['test'])
  await s.advance(LENGTH_MS.silence)
  expect(await testing).toBe('ffplay played silence.wav and exited 0')
  await engineTick(s.$, await s.ctx())
  await s.advance(2 * LENGTH_MS.cicadas)
  expect(s.plays.map(play => soundOf(play.argv.join(' ')))).toEqual(['cicadas', 'cicadas', 'silence'])
  expect(await engineCommand(s.$, await s.ctx(), 'sound', [])).toMatch(/, stopped: ffplay failed playing cicadas/)
  await quiet(s)
})
