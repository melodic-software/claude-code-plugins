import type { EngineInterface } from 'claude-code'
import { expect, test } from 'claude-code/testing'

import { readNow } from '../core/clock.js'
import { ctxOf, usePieces } from '../core/context.js'
import type { Ctx, Fields, Piece } from '../core/piece.js'
import { load, savedOf } from '../core/saved.js'
import { strike } from '../core/schedule.js'
import { useOptions } from '../core/settings.js'
import { EVENING, startRoom } from '../core/testing.js'
import { BUILT, WITHOUT } from './index.js'
import { LENGTH_MS, TAKEN_MS, WATCH_MS, argvOf, commandLineOf, engineCommand, engineSwitched, engineTick, gainOf, windowsScript, type Sound } from './sound.js'

const soundOf = (text: string): Sound => (text.match(/([a-z0-9-]+)\.wav/)?.[1] ?? 'silence') as Sound
const NIGHT = { time: 'night', weather: 'clear', hall: false, signal: false } as const
declare function setTimeout(fn: () => void, ms: number): unknown
const wait = (ms: number): Promise<void> => new Promise(resolve => void setTimeout(resolve, ms))

/** A child started through the engine in a kit test: the file it plays, and whether the engine has ended it. */
type Child = { file: string; argv: readonly string[]; ended: boolean }

test('in the plugin, sound off ends the playing child at once, and a change of weather, volume or recording swaps the loop', { timeoutMs: 30000, options: NIGHT }, async ($, on) => {
  if (!BUILT.includes('sound')) return
  const children: Child[] = []
  on('session.usage', () => ({ value: { startedAt: 0, context: { window: 200_000, tokens: 20_000, percent: 10 }, rateLimits: [] } }))
  on('session.info', () => ({ value: { platform: 'linux', isHosted: false } as never }))
  on('env.get', (_, e) => ({ value: e.name === 'PATH' ? '/usr/bin' : undefined }))
  on('fs.exists', (_, e) => ({ value: e.path === '/usr/bin/ffplay' }))
  on('process.run', () => ({ value: { exitCode: 0, stdout: '', stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }))
  on('audio.play', () => ({ value: undefined }))
  on('process.spawn', async function* (_, e) {
    const child: Child = { file: soundOf(e.argv.join(' ')), argv: e.argv, ended: false }
    children.push(child)
    try {
      for (;;) {
        await wait(10)
        yield { stream: 'stderr' as const, text: '  1.00 M-A: 0.000\r' }
      }
    } finally {
      child.ended = true
    }
  })
  const room = await startRoom($, on, { fakes: false })
  const live = (): string[] => children.filter(child => !child.ended).map(child => child.file)

  expect(await room.run('sound on')).toMatch(/^sound is on, played by ffplay at volume 70/)
  await wait(50)
  expect(live()).toEqual(['cicadas-1'])
  expect(children[0]?.argv).toContain('-loop')

  for (const [weather, loop] of [['rain', 'rain-1'], ['downpour', 'downpour-1'], ['storm', 'storm-1'], ['overcast', 'cicadas-1']] as const) {
    await room.run(`weather ${weather}`)
    await room.clock.advance(1)
    await wait(60)
    expect([weather, live()]).toEqual([weather, [loop]])
  }

  await room.run('sound volume 40')
  await wait(60)
  expect(live()).toEqual(['cicadas-1'])
  expect(children.at(-1)?.argv.slice(children.at(-1)!.argv.indexOf('-volume'), children.at(-1)!.argv.indexOf('-volume') + 2)).toEqual(['-volume', '16'])
  await room.run('sound pick cicadas 2')
  await wait(60)
  expect(live()).toEqual(['cicadas-2'])

  const before = children.length
  expect(await room.run('sound off')).toMatch(/^sound is off: what was playing has stopped/)
  await wait(60)
  expect(live()).toEqual([])
  await room.clock.advance(3 * 60_000)
  expect(children.length).toBe(before)
  await room.unmount()
})

/** What the weather and time pieces would give: the fields the sound follows. */
const sky: Pick<Fields, 'sun' | 'weather'> = { sun: 0, weather: 0 }
const standIn: Piece = { name: 'stand-in', fields: () => ({ ...sky }) }

type Play = { argv: readonly string[]; at: number; endedAt?: number }
type Stand = {
  $: EngineInterface
  /** What the stand-in answers: the platform, PATH, the files on it, how a player exits, the minute chain held. */
  platform: string
  path: string
  files: Set<string>
  exit: number | 'reject'
  chain: number | undefined
  plays: Play[]
  clips: { asset: string; gain?: number; shouldLoop?: boolean }[]
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
  const timers: { at: number; fn: () => void; isCancelled?: boolean }[] = []
  const later = (ms: number, fn: () => void): { cancel: () => void } => {
    const timer: { at: number; fn: () => void; isCancelled?: boolean } = { at: now + ms, fn }
    timers.push(timer)
    return { cancel: () => void (timer.isCancelled = true) }
  }
  const sleep = (ms: number): Promise<void> => new Promise(resolve => void later(ms, resolve))
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
        if (next.isCancelled !== true) next.fn()
      }
      now = until
      await settle()
    },
  }
  const ok = { stdout: '', stderr: '', isStdoutTruncated: false, isStderrTruncated: false }
  /** A child: a dot each 250 ms until its file's length has passed, or for good when it repeats the file itself. */
  async function* child(argv: readonly string[]): AsyncGenerator<{ stream: 'stdout' | 'stderr'; text: string }, { code: number | null; signal: string | null }> {
    const play: Play = { argv, at: now }
    s.plays.push(play)
    const exit = s.exit
    if (exit === 'reject') throw new Error('the command could not start')
    const repeats = argv.includes('-loop')
    try {
      for (let ms = 0; repeats || ms < LENGTH_MS[soundOf(argv.join(' '))]; ms += 250) {
        await sleep(250)
        yield { stream: 'stdout', text: '.' }
      }
      if (exit !== 0) yield { stream: 'stderr', text: 'no audio device\n' }
      return { code: exit, signal: null }
    } finally {
      play.endedAt = now
    }
  }
  s.$ = {
    plugin: { name: 'themes', root: '/room' },
    store: { get: async (key: string) => store.get(key), set: async (key: string, value: unknown) => void store.set(key, value) },
    state: { get: async () => ({ value: s.chain }) },
    ui: { toast: () => undefined, invalidate: () => undefined, log: (text: string) => void log.push(text) },
    clock: { now: async () => now, after: later },
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
      run: async (argv: readonly string[]) => {
        s.calls.push('process.run')
        if (argv[0] === 'wslpath') return { exitCode: 0, ...ok, stdout: 'W:\\room\\sounds\\bedroom\n' }
        s.plays.push({ argv, at: now, endedAt: now })
        return { exitCode: 0, ...ok }
      },
      spawn: ({ argv }: { argv: readonly string[] }) => {
        s.calls.push('process.spawn')
        const stream = child(argv)
        let resolve: (value: { code: number | null; signal: string | null }) => void = () => undefined
        let reject: (error: unknown) => void = () => undefined
        const result = new Promise<{ code: number | null; signal: string | null }>((yes, no) => {
          resolve = yes
          reject = no
        })
        const wrapped = {
          result,
          next: async () => {
            const step = await stream.next()
            if (step.done === true) resolve(step.value)
            return step
          },
          return: async (value: unknown) => {
            reject(new Error('closed'))
            return stream.return(value as never)
          },
          throw: (error: unknown) => stream.throw(error),
          [Symbol.asyncIterator]() {
            return wrapped
          },
        }
        return wrapped
      },
    },
    audio: {
      play: async (clip: { asset: string }, options?: { gain?: number; shouldLoop?: boolean; signal?: AbortSignal }) => {
        s.calls.push('audio.play')
        s.clips.push({ asset: clip.asset, gain: options?.gain, shouldLoop: options?.shouldLoop })
        await new Promise<void>(resolve => {
          options?.signal?.addEventListener('abort', () => resolve())
          if (options?.shouldLoop !== true) later(LENGTH_MS[soundOf(clip.asset)], resolve)
        })
      },
    },
  } as unknown as EngineInterface
  await load(s.$)
  usePieces([standIn])
  useOptions({})
  return s
}

const named = (s: Stand, sound: Sound): Play[] => s.plays.filter(play => play.argv.join(' ').includes(`${sound}.wav`))
const live = (s: Stand): string[] => s.plays.filter(play => play.endedAt === undefined).map(play => soundOf(play.argv.join(' ')))

/** Turns sound off and lets every play end, so the next test starts with nothing playing. */
async function quiet(s: Stand): Promise<void> {
  await engineCommand(s.$, await s.ctx(), 'sound', ['off'])
  await engineCommand(s.$, await s.ctx(), 'sound', ['volume', '70'])
  await engineCommand(s.$, await s.ctx(), 'sound', ['pick', 'cicadas', '1'])
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
  expect(await engineCommand(s.$, await s.ctx(), 'sound', [])).toMatch(/^sound is off, volume 70\. recordings: cicadas 1, rain 1, downpour 1, storm 1, thunder 1\. player: not looked for yet/)
  expect(s.calls).toEqual([])
})

test("each player's argument list carries the volume, and the players that can repeat a loop themselves do", async () => {
  if (!BUILT.includes('sound')) return
  expect([0, 50, 70, 100].map(gainOf)).toEqual([0, 0.25, 0.48999999999999994, 1])
  expect(argvOf('ffplay', '/x/rain-1.wav', 0.25, true)).toEqual(['ffplay', '-nodisp', '-autoexit', '-loglevel', 'quiet', '-stats', '-volume', '25', '-loop', '0', '/x/rain-1.wav'])
  expect(argvOf('ffplay', '/x/tv-on.wav', 1, false)).toEqual(['ffplay', '-nodisp', '-autoexit', '-loglevel', 'quiet', '-stats', '-volume', '100', '/x/tv-on.wav'])
  expect(argvOf('paplay', '/x/tv-on.wav', 0.25, true)).toEqual(['paplay', '--verbose', '--volume=16384', '/x/tv-on.wav'])
  expect(argvOf('aplay', '/x/tv-on.wav', 0.25, false)).toEqual(['aplay', '-V', 'mono', '/x/tv-on.wav'])
  const windows = argvOf('powershell.exe', "W:\\it's\\rain-1.wav", 0.49, true)
  expect(windows.slice(0, 4)).toEqual(['powershell.exe', '-NoProfile', '-NonInteractive', '-Command'])
  expect(windows[4]).toBe(windowsScript("W:\\it's\\rain-1.wav", 0.49, true))
  expect(windows[4]).toContain("$p.Volume=0.4900;$p.Open([Uri]'W:\\it''s\\rain-1.wav')")
  expect(windows[4]).toContain('if($true){$p.Position=[TimeSpan]::Zero;$p.Play()')
  expect(windowsScript('W:\\tv-on.wav', 1, false)).toContain('if($false){')
  expect(windows[4]).not.toContain('SoundPlayer')
  expect(commandLineOf('mpv --volume={volume} {file}', '/x/rain-1.wav', 0.25)).toEqual(['mpv', '--volume=25', '/x/rain-1.wav'])
  expect(commandLineOf('play -q', '/x/rain-1.wav')).toEqual(['play', '-q', '/x/rain-1.wav'])

  const s = await stand()
  Object.assign(sky, { sun: 6, weather: 0 })
  s.platform = 'wsl'
  s.files = new Set(['/opt/a/powershell.exe', '/usr/bin/wslpath', '/usr/bin/ffplay'])
  expect(await engineCommand(s.$, await s.ctx(), 'sound', ['on'])).toMatch(/^sound is on, played by powershell\.exe at volume 70/)
  engineSwitched(s.$, await s.ctx(), 'tv', true, 'click')
  await s.advance(LENGTH_MS['tv-on'] + 250)
  expect(s.plays.at(-1)?.argv[4]).toBe(windowsScript('W:\\room\\sounds\\bedroom\\tv-on.wav', gainOf(70), false))

  s.platform = 'macos'
  await engineCommand(s.$, await s.ctx(), 'sound', ['volume', '50'])
  expect(await engineCommand(s.$, await s.ctx(), 'sound', ['on'])).toMatch(/^sound is on, played by the engine/)
  engineSwitched(s.$, await s.ctx(), 'tv', false, 'click')
  await s.advance(LENGTH_MS['tv-off'])
  expect(s.clips).toEqual([{ asset: 'sounds/bedroom/tv-off.wav', gain: 0.25, shouldLoop: undefined }])

  s.platform = 'linux'
  s.files = new Set()
  await engineCommand(s.$, await s.ctx(), 'sound', ['off'])
  expect(await engineCommand(s.$, await s.ctx(), 'sound', ['on'])).toMatch(/^no player was found .* so sound stays off$/)
  expect((await s.ctx()).setting('sound')).toBe(false)
  await quiet(s)
})

test('one loop at a time: cicadas only when dry from dusk through night, and rain, downpour and storm each their own', async () => {
  if (!BUILT.includes('sound')) return
  const s = await stand()
  s.files = new Set(['/usr/bin/ffplay'])
  Object.assign(sky, { sun: 0, weather: 0 })
  await engineCommand(s.$, await s.ctx(), 'sound', ['on'])
  await s.settle()
  expect(live(s)).toEqual(['cicadas-1'])

  const cases = [
    [{ sun: 1, weather: 1 }, ['cicadas-1']],
    [{ sun: 2, weather: 2 }, ['rain-1']],
    [{ sun: 2, weather: 3 }, ['downpour-1']],
    [{ sun: 6, weather: 4 }, ['storm-1']],
    [{ sun: 6, weather: 0 }, []],
    [{ sun: 3, weather: 1 }, []],
    [{ sun: 2, weather: 0 }, ['cicadas-1']],
  ] as const
  for (const [fields, loops] of cases) {
    Object.assign(sky, fields)
    await engineTick(s.$, await s.ctx())
    await s.advance(250)
    expect([fields, live(s)]).toEqual([fields, [...loops]])
  }
  const children = s.plays.length
  for (let minute = 0; minute < 10; minute++) {
    await engineTick(s.$, await s.ctx())
    await s.advance(60_000)
  }
  expect(s.plays.length).toBe(children)

  for (const [kind, sound] of [['cicadas', 'cicadas-2'], ['rain', 'rain-2']] as const) {
    if (kind === 'rain') sky.weather = 2
    await engineCommand(s.$, await s.ctx(), 'sound', ['pick', kind, '2'])
    await engineTick(s.$, await s.ctx())
    await s.advance(250)
    expect(live(s)).toEqual([sound])
  }
  expect(await engineCommand(s.$, await s.ctx(), 'sound', ['pick', 'wind', '2'])).toMatch(/^say which recording of cicadas, rain, downpour, storm, thunder/)
  await engineCommand(s.$, await s.ctx(), 'sound', ['pick', 'rain', '1'])
  await quiet(s)
})

test('sound off, a change of loop and a reload stop the playing child within one beat', async () => {
  if (!BUILT.includes('sound')) return
  const s = await stand()
  s.files = new Set(['/usr/bin/ffplay'])
  Object.assign(sky, { sun: 0, weather: 0 })
  await engineCommand(s.$, await s.ctx(), 'sound', ['on'])
  await s.advance(5000)
  const cicadas = named(s, 'cicadas-1')[0]!
  expect(cicadas.endedAt).toBeUndefined()

  sky.weather = 2
  const changedAt = await s.$.clock.now()
  await s.advance(WATCH_MS + 250)
  expect(cicadas.endedAt).toBeDefined()
  expect(cicadas.endedAt! - changedAt).toBeLessThanOrEqual(WATCH_MS + 250)
  expect(live(s)).toEqual(['rain-1'])

  engineSwitched(s.$, await s.ctx(), 'tv', true, 'click')
  await s.advance(250)
  expect(live(s).sort()).toEqual(['rain-1', 'tv-on'])
  const at = await s.$.clock.now()
  await engineCommand(s.$, await s.ctx(), 'sound', ['off'])
  await s.advance(250)
  expect(live(s)).toEqual([])
  expect(Math.max(...s.plays.map(play => play.endedAt ?? Infinity))).toBeLessThanOrEqual(at + 250)

  await engineCommand(s.$, await s.ctx(), 'sound', ['on'])
  await s.advance(250)
  expect(live(s)).toEqual(['rain-1'])
  await engineCommand(s.$, await s.ctx(), 'sound', ['volume', '0'])
  await s.advance(250)
  expect(live(s)).toEqual([])
  engineSwitched(s.$, await s.ctx(), 'tv', false, 'click')
  await s.advance(250)
  expect(live(s)).toEqual([])
  await engineCommand(s.$, await s.ctx(), 'sound', ['volume', '70'])
  await s.advance(250)
  expect(live(s)).toEqual(['rain-1'])
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
  expect(named(s, 'cicadas-1').length).toBe(1)
  await s.advance(LENGTH_MS['cicadas-1'] + 250)
  expect(named(s, 'cicadas-1').length).toBe(2)
  s.chain = 7
  await engineTick(s.$, await s.ctx())
  s.chain = 8
  await s.advance(3 * LENGTH_MS['cicadas-1'])
  expect(named(s, 'cicadas-1').length).toBe(2)
  s.chain = undefined
  await quiet(s)
})

test('thunder follows a scheduled strike in a storm at the volume, and not in rain', async () => {
  if (!BUILT.includes('sound')) return
  const evening = new Date(EVENING)
  const strikes = Array.from({ length: 240 }, (_, i) => 480 + i).filter(minute => strike(minute) !== undefined)
  const tickAt = (minute: number): number => new Date(evening.getFullYear(), evening.getMonth(), evening.getDate(), 20, minute - 480, 0, 50).getTime()
  const s = await stand(tickAt(strikes[0] ?? 0) - 1000)
  s.files = new Set(['/usr/bin/ffplay'])
  Object.assign(sky, { sun: 6, weather: 4 })
  await engineCommand(s.$, await s.ctx(), 'sound', ['volume', '50'])
  await engineCommand(s.$, await s.ctx(), 'sound', ['on'])
  const thunder = (): Play[] => s.plays.filter(play => /thunder-\d-\d\.wav$/.test(play.argv.at(-1) ?? ''))
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
  if (thunders) {
    expect(thunder()[0]?.argv.slice(6, 8)).toEqual(['-volume', '25'])
    expect(thunder().map(play => soundOf(play.argv.join(' '))).every(name => name.startsWith('thunder-1-'))).toBe(true)
  }

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
  s.files = new Set(['/usr/bin/paplay'])
  Object.assign(sky, { sun: 0, weather: 0 })
  s.exit = 1
  expect(await engineCommand(s.$, await s.ctx(), 'sound', ['on'])).toMatch(/^sound is on/)
  await s.advance(LENGTH_MS['cicadas-1'] + 500)
  for (let minute = 0; minute < 3; minute++) {
    const ctx = await s.ctx()
    await engineTick(s.$, ctx)
    engineSwitched(s.$, ctx, 'tv', true, 'click')
    await s.advance(60_000)
  }
  expect(s.plays.length).toBe(1)
  expect(s.notes().length).toBe(1)
  expect(s.notes()[0]).toMatch(/sound: paplay exited 1 playing cicadas-1: no audio device; nothing plays until \/bedroom sound on$/)
  expect(await engineCommand(s.$, await s.ctx(), 'sound', [])).toMatch(/^sound is on, volume 70\. .* player: paplay, stopped: paplay exited 1/)

  s.exit = 'reject'
  await engineCommand(s.$, await s.ctx(), 'sound', ['on'])
  await s.advance(2 * LENGTH_MS['cicadas-1'])
  expect(s.plays.length).toBe(2)
  expect(s.notes().length).toBe(2)
  expect(s.notes()[1]).toMatch(/sound: paplay failed playing cicadas-1: the command could not start/)
  s.exit = 0

  expect(await engineCommand(s.$, await s.ctx(), 'sound', ['test'])).toBe('paplay played silence.wav and exited 0')
  await engineTick(s.$, await s.ctx())
  await s.advance(2 * LENGTH_MS['cicadas-1'])
  expect(s.plays.map(play => soundOf(play.argv.join(' ')))).toEqual(['cicadas-1', 'cicadas-1', 'silence'])
  expect(await engineCommand(s.$, await s.ctx(), 'sound', [])).toMatch(/, stopped: paplay failed playing cicadas-1/)
  await quiet(s)
})

test('a volume and recordings stored outside their range load as the defaults', () => {
  expect(savedOf({ volume: 40, picks: { cicadas: 2, rain: 3, storm: 'x' } })).toMatchObject({ volume: 40, picks: { cicadas: 2 } })
  expect(savedOf({ volume: 140 }).volume).toBeUndefined()
  expect(savedOf({ volume: 4.5 }).volume).toBeUndefined()
})
