import type { EngineInterface } from 'claude-code'
import { expect, test } from 'claude-code/testing'

import { minuteOfHalfDay, readNow } from '../core/clock.js'
import { ctxOf, usePieces } from '../core/context.js'
import type { Ctx, Fields, Piece } from '../core/piece.js'
import { load, savedOf } from '../core/saved.js'
import { noteForcedStrike, noteShaderStart, scheduledEventShows, strike } from '../core/schedule.js'
import { PHASES, useOptions } from '../core/settings.js'
import { WORLD } from '../core/signals.gen.js'
import { EVENING, startRoom } from '../core/testing.js'
import { rebuild, startShader } from '../core/values.js'
import { DEFAULT_STATE } from '../scene/lib.ts'
import { BUILT, WITHOUT } from './index.js'
import { BANK, LENGTH_MS, OBJECTS, PURR, chosenName, lengthOf, namesOf } from './sound-bank.js'
import { rowStarts, seasonOf } from './time.js'
import { BEAT_MS, PARENT_MS, PING_MS, QUIET_MS, STEADY_MS, STOP_FADE_MS, encodedOf, fileOf, linesOf, mixerScript, powershellArgv, wordsOf } from './sound-mixer.js'
import {
  COMMAND_LAG_MS,
  DUCK,
  DUCK_FADE_MS,
  HURRIED_MS,
  OFF_FADE_MS,
  PICK_FADE_MS,
  PICTURE_LAG_MS,
  START_FADE_MS,
  SUN_FADE_MS,
  EVENING_FADE_MS,
  BUILD_FROM_MIN,
  BUILD_LEVEL,
  EVENING_LEVEL,
  NIGHT_LEVEL,
  PREDAWN_LEVEL,
  bedOf,
  levelOf,
  TAKEN_MS,
  THUNDER_LIFT,
  WATCH_MS,
  WEATHER_EASE_MS,
  argvOf,
  bedName,
  COPY,
  HANDOVER_MS,
  RETRY_MS,
  SILENT_MS,
  hooks,
  commandLineOf,
  engineCommand,
  engineSwitched,
  engineTick,
  forcedDelayS,
  gainOf,
  purr,
  shownOf,
  strikeDelayS,
  thunderFor,
  thunderOf,
} from './sound.js'

declare function setTimeout(fn: () => void, ms: number): unknown
const wait = (ms: number): Promise<void> => new Promise(resolve => void setTimeout(resolve, ms))
const NIGHT = { time: 'night', weather: 'clear', hall: false, signal: false } as const

/** A command the fake mixer ran: its seq, its words, and when it reached it. */
type Ran = { seq: number; words: string[]; at: number }
/** A fake of the Windows mixer behind the engine: it answers each command line written to its file as the script does. */
type FakeMixer = { ran: Ran[]; outbox: string[]; wake?: () => void; ended: boolean; endedAt?: number; last: number; exitCode?: number; mute?: boolean }
const READY = 'ready C:\\Temp\\claude-bedroom-sound-1\\commands.txt\n'
const COMMANDS = '/mnt/c/Temp/claude-bedroom-sound-1/commands.txt'

/** Reads a command file as the mixer does: only a file that ends with `end`, each line above the last run, one-shots first. */
function runFile(m: FakeMixer, text: string, at: number): void {
  if (!text.endsWith('end\n')) return
  const todo = text
    .split('\n')
    .map(line => line.trim().split(' '))
    .filter(words => /^\d+$/.test(words[0] ?? '') && Number(words[0]) > m.last)
  for (const words of [...todo.filter(w => w[1] === 'shot'), ...todo.filter(w => w[1] !== 'shot')]) {
    m.ran.push({ seq: Number(words[0]), words: words.slice(1), at })
    m.outbox.push(`ok ${words[0]}\n`, ...(words[1] === 'shot' ? [`sounding ${words[0]}\n`] : []))
  }
  m.last = Math.max(m.last, ...todo.map(words => Number(words[0])))
  m.wake?.()
}

/**
 * The fake mixer's output: its ready line, its answers, and a dot each beat, as the script writes one every BEAT_MS.
 * The engine ends a child at once; the fake ends at its next beat, so a test waits BEAT_MS more for it.
 */
async function* mixerChild(m: FakeMixer, now: () => number, beat: (wake: () => void) => void): AsyncGenerator<{ stream: 'stdout' | 'stderr'; text: string }, { code: number | null; signal: string | null }> {
  try {
    yield { stream: 'stdout', text: `..${READY}` }
    for (;;) {
      if (m.mute === true) await new Promise<void>(() => undefined)
      if (m.outbox.length === 0 && m.exitCode === undefined) {
        await new Promise<void>(resolve => {
          m.wake = resolve
          beat(resolve)
        })
      }
      yield { stream: 'stdout', text: `.${m.outbox.splice(0).join('')}` }
      if (m.exitCode !== undefined) return { code: m.exitCode, signal: null }
    }
  } finally {
    m.ended = true
    m.endedAt = now()
  }
}

test('in the plugin, one mixer plays the bed, the television and a change of weather, and sound off ends it', { timeoutMs: 30000, options: NIGHT }, async ($, on) => {
  if (!BUILT.includes('sound')) return
  const mixers: FakeMixer[] = []
  on('session.usage', () => ({ value: { startedAt: 0, context: { window: 200_000, tokens: 20_000, percent: 10 }, rateLimits: [] } }))
  on('session.info', () => ({ value: { platform: 'wsl', isHosted: false } as never }))
  on('env.get', (_, e) => ({ value: e.name === 'PATH' ? '/win:/usr/bin' : undefined }))
  on('fs.exists', (_, e) => ({ value: e.path === '/win/powershell.exe' || e.path === '/usr/bin/wslpath' }))
  on('process.run', (_, e) => ({ value: { exitCode: 0, stdout: e.argv[1] === '-u' ? `${COMMANDS}\n` : 'W:\\room\\sounds\\bedroom\n', stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }))
  on('audio.play', () => ({ value: undefined }))
  let clockNow = (): number => 0
  on('process.spawn', async function* (_, e) {
    const m: FakeMixer = { ran: [], outbox: [], ended: false, last: 0 }
    if (e.argv[0] === 'powershell.exe') {
      mixers.push(m)
      expect(e.argv.slice(0, 4)).toEqual(['powershell.exe', '-NoProfile', '-NonInteractive', '-EncodedCommand'])
      expect(e.argv.some(word => word.includes('$') || word.includes('MediaPlayer'))).toBe(false)
    }
    yield* mixerChild(m, () => clockNow(), wake => void setTimeout(wake, 20))
  })
  const room = await startRoom($, on, { fakes: false, onWrite: (path, text) => (path === COMMANDS ? runFile(mixers.at(-1)!, text, clockNow()) : undefined) })
  clockNow = () => room.clock.now()
  const verbs = (): string[] => (mixers[0]?.ran ?? []).map(r => r.words.join(' '))

  expect(await room.run('sound on')).toMatch(/^sound is on, played by the Windows mixer \(powershell\.exe\) at volume 70/)
  await wait(50)
  expect(mixers.length).toBe(1)
  expect(verbs()).toContain(`bed ${BANK.night.entries.auto.late} ${(gainOf(70) * NIGHT_LEVEL).toFixed(4)} ${START_FADE_MS}`)
  expect(verbs()).toContain(`load ${BANK.tv.entries.tube.on}`)

  await room.run('tv')
  await wait(50)
  expect(verbs().some(line => line.startsWith(`shot ${BANK.tv.entries.tube.on} `) || line.startsWith(`shot ${BANK.tv.entries.tube.off} `))).toBe(false)
  await room.clock.advance(COMMAND_LAG_MS.direction)
  await wait(50)
  expect(verbs().filter(line => line.startsWith('shot tv/')).length).toBe(1)

  await room.run('weather rain')
  await room.clock.advance(PICTURE_LAG_MS - WATCH_MS)
  await wait(50)
  expect(verbs().some(line => line.startsWith('bed rain/'))).toBe(false)
  for (let step = 0; step < 10 && !verbs().some(line => line.startsWith('bed rain/')); step++) {
    await room.clock.advance(1000)
    await wait(30)
  }
  const rain = verbs().find(line => line.startsWith('bed rain/'))
  expect(rain?.split(' ').slice(0, 2)).toEqual(['bed', BANK.rain.entries.roof.rain])
  expect(Number(rain?.split(' ')[3])).toBeGreaterThan(HURRIED_MS - 1000)

  await room.run('sound volume 40')
  await wait(50)
  expect(verbs().at(-1)).toBe(`level ${gainOf(40).toFixed(4)} 400`)

  expect(await room.run('sound off')).toMatch(/^sound is off: what was playing has faded out/)
  await wait(50)
  expect(verbs().at(-1)).toBe(`quit ${OFF_FADE_MS}`)
  expect(mixers[0]?.ended).toBe(false)
  await room.clock.advance(OFF_FADE_MS + 250)
  await wait(50)
  expect(mixers[0]?.ended).toBe(true)
  await room.clock.advance(3 * 60_000)
  await wait(50)
  expect(mixers.length).toBe(1)
  await room.unmount()
})

test('in the plugin, /bedroom weather strike (the card\'s bolt) brings one thunder to the mixer, 1 to 4 s after the flash, and /bedroom sound names it', { timeoutMs: 30000, options: { ...NIGHT, weather: 'storm' } }, async ($, on) => {
  if (!BUILT.includes('sound') || !BUILT.includes('weather') || WITHOUT.includes('weather.lightning')) return
  const mixers: FakeMixer[] = []
  on('session.usage', () => ({ value: { startedAt: 0, context: { window: 200_000, tokens: 20_000, percent: 10 }, rateLimits: [] } }))
  on('session.info', () => ({ value: { platform: 'wsl', isHosted: false } as never }))
  on('env.get', (_, e) => ({ value: e.name === 'PATH' ? '/win:/usr/bin' : undefined }))
  on('fs.exists', (_, e) => ({ value: e.path === '/win/powershell.exe' || e.path === '/usr/bin/wslpath' }))
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
  const room = await startRoom($, on, { now: calm, fakes: false, onWrite: (path, text) => (path === COMMANDS ? runFile(mixers.at(-1)!, text, clockNow()) : undefined) })
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

test("the mixer's command file, its answers and its script", () => {
  expect(wordsOf({ verb: 'bed', name: undefined, gain: 0.5, fadeMs: 6000.4 })).toBe('bed - 0.5000 6000')
  expect(wordsOf({ verb: 'bed', name: 'night/x.wav', gain: 0.5, fadeMs: 60, from: 0.125 })).toBe('bed night/x.wav 0.5000 60 0.1250')
  expect(mixerScript('W:\\s')).toContain('a=$(if($w.Count -gt 5){[double]$w[5]}else{0})')
  expect(wordsOf({ verb: 'shot', name: 'tv/tube-on.wav', gain: 1.2 })).toBe('shot tv/tube-on.wav 1.0000')
  expect(fileOf([{ seq: 3, command: { verb: 'ping' } }, { seq: 4, command: { verb: 'quit', fadeMs: 150 } }])).toBe('3 ping\n4 quit 150\nend\n')
  expect(linesOf('..ready D:\\tmp\\a.b\\commands.txt\n.ok 3\nsounding 3\n..ok')).toEqual({
    lines: [
      { kind: 'ready', path: 'D:\\tmp\\a.b\\commands.txt' },
      { kind: 'ok', seq: 3 },
      { kind: 'sounding', seq: 3 },
    ],
    rest: 'ok',
  })
  const script = mixerScript("W:\\it's\\sounds")
  expect(script).toContain("$root='W:\\it''s\\sounds'")
  expect(script).toContain('System.Windows.Media.MediaPlayer')
  expect(script).toContain(`if($now-$seen -gt ${QUIET_MS}){Stop $now}`)
  expect(script).toContain(`function Stop($now){if($script:quit -lt 0){foreach($v in $voices){Fade $v 0 ${STOP_FADE_MS} $now;$v.drop=$true};$script:quit=$now+${STOP_FADE_MS}}}`)
  expect(script).toContain(`if($parent -gt 0 -and $now-$looked -ge ${PARENT_MS}){$looked=$now;try{[void][Diagnostics.Process]::GetProcessById($parent)}catch{Stop $now}}`)
  expect(script).toContain("Say ('pid '+$PID)")
  expect(linesOf('pid 4242\n').lines).toEqual([{ kind: 'pid', pid: 4242 }])
  expect(script).toContain(`if($now-$beat -ge ${BEAT_MS})`)
  expect(script).toContain('Remove-Item -LiteralPath $dir')
  expect(script).toContain(`if($key -ne $stamp -or $now -ge $reread){$reread=$now+${STEADY_MS};`)
  expect(script).not.toContain('else{break}')
  expect(script.endsWith(';exit $code')).toBe(true)
  expect(PING_MS * 3).toBeLessThanOrEqual(QUIET_MS)
  expect(STOP_FADE_MS).toBeLessThanOrEqual(1000)

  expect([encodedOf('a'), encodedOf('ab'), encodedOf('abc'), encodedOf('é')]).toEqual(['YQA=', 'YQBiAA==', 'YQBiAGMA', '6QA='])
  const argv = powershellArgv(script)
  expect(argv.slice(0, 4)).toEqual(['powershell.exe', '-NoProfile', '-NonInteractive', '-EncodedCommand'])
  expect(argv[4]).toMatch(/^[A-Za-z0-9+/]+=*$/)
  expect(argv.length).toBe(5)
  expect(argv.join(' ').length).toBeLessThan(32_767)
})

/** What the weather and time pieces would give: the fields the sound follows. */
const sky: Pick<Fields, 'sun' | 'weather'> = { sun: 0, weather: 0 }
const standIn: Piece = { name: 'stand-in', fields: () => ({ ...sky }) }

type Play = { argv: readonly string[]; at: number; endedAt?: number }
type Stand = {
  $: EngineInterface
  platform: string
  path: string
  files: Set<string>
  exit: number | 'reject'
  plays: Play[]
  clips: { asset: string; gain?: number; shouldLoop?: boolean }[]
  mixers: FakeMixer[]
  state: Map<string, unknown>
  calls: string[]
  notes: () => string[]
  ctx: () => Promise<Ctx>
  now: () => number
  advance: (ms: number) => Promise<void>
  settle: () => Promise<void>
}

async function stand(start = EVENING): Promise<Stand> {
  let now = start
  const timers: { at: number; fn: () => void; isCancelled?: boolean }[] = []
  const later = (ms: number, fn: () => void): { cancel: () => void } => {
    const timer: { at: number; fn: () => void; isCancelled?: boolean } = { at: now + Math.max(0, ms), fn }
    timers.push(timer)
    return { cancel: () => void (timer.isCancelled = true) }
  }
  const sleep = (ms: number): Promise<void> => new Promise(resolve => void later(ms, resolve))
  const store = new Map<string, unknown>()
  const log: string[] = []
  const settle = async (): Promise<void> => {
    for (let i = 0; i < 300; i++) await Promise.resolve()
  }
  const s: Stand = {
    $: undefined as unknown as EngineInterface,
    platform: 'linux',
    path: '/opt/a:/usr/bin',
    files: new Set(),
    exit: 0,
    plays: [],
    clips: [],
    state: new Map(),
    mixers: [],
    calls: [],
    notes: () => log.filter(line => line.includes(' sound: ')),
    ctx: async () => {
      await readNow(s.$)
      return ctxOf(s.$)
    },
    now: () => now,
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
  /** A player's child: a dot each 250 ms until its file's length has passed, or for good when it repeats the file itself. */
  async function* child(argv: readonly string[]): AsyncGenerator<{ stream: 'stdout' | 'stderr'; text: string }, { code: number | null; signal: string | null }> {
    const play: Play = { argv, at: now }
    s.plays.push(play)
    const exit = s.exit
    if (exit === 'reject') throw new Error('the command could not start')
    const repeats = argv.includes('-loop')
    try {
      for (let ms = 0; repeats || ms < lengthOf(fileIn(argv)); ms += 250) {
        await sleep(250)
        yield { stream: 'stdout', text: '.' }
      }
      if (exit !== 0) yield { stream: 'stderr', text: 'no audio device\n' }
      return { code: exit, signal: null }
    } finally {
      play.endedAt = now
    }
  }
  const streamOf = (stream: AsyncGenerator<{ stream: 'stdout' | 'stderr'; text: string }, { code: number | null; signal: string | null }>) => {
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
  }
  s.$ = {
    plugin: { name: 'themes', root: '/room' },
    store: { get: async (key: string) => store.get(key), set: async (key: string, value: unknown) => void store.set(key, value) },
    state: {
      get: async ({ key }: { key: string }) => ({ value: s.state.get(key) }),
      set: async ({ key }: { key: string }, value: unknown) => void s.state.set(key, value),
    },
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
      write: async (path: string, text: string) => {
        s.calls.push('fs.write')
        if (path === COMMANDS) runFile(s.mixers.at(-1)!, text, now)
      },
    },
    process: {
      run: async (argv: readonly string[]) => {
        s.calls.push('process.run')
        if (argv[0] === 'wslpath') return { exitCode: 0, ...ok, stdout: argv[1] === '-u' ? `${COMMANDS}\n` : 'W:\\room\\sounds\\bedroom\n' }
        s.plays.push({ argv, at: now, endedAt: now })
        return { exitCode: 0, ...ok }
      },
      spawn: ({ argv }: { argv: readonly string[] }) => {
        s.calls.push('process.spawn')
        if (argv[0] !== 'powershell.exe') return streamOf(child(argv))
        const m: FakeMixer = { ran: [], outbox: [], ended: false, last: 0 }
        s.mixers.push(m)
        return streamOf(mixerChild(m, () => now, wake => void later(BEAT_MS, wake)))
      },
    },
    audio: {
      play: async (clip: { asset: string }, options?: { gain?: number; shouldLoop?: boolean; signal?: AbortSignal }) => {
        s.calls.push('audio.play')
        s.clips.push({ asset: clip.asset, gain: options?.gain, shouldLoop: options?.shouldLoop })
        await new Promise<void>(resolve => {
          options?.signal?.addEventListener('abort', () => resolve())
          if (options?.shouldLoop !== true) later(lengthOf(clip.asset.replace('sounds/bedroom/', '')), resolve)
        })
      },
    },
  } as unknown as EngineInterface
  await load(s.$)
  usePieces([standIn])
  useOptions({})
  return s
}

const fileIn = (argv: readonly string[]): string => argv.at(-1)?.replace('/room/sounds/bedroom/', '') ?? ''
const live = (s: Stand): string[] => s.plays.filter(play => play.endedAt === undefined).map(play => fileIn(play.argv))
/** The commands the last mixer ran, as their words. */
const ranBy = (s: Stand): string[] => (s.mixers.at(-1)?.ran ?? []).map(r => r.words.join(' '))
const onWindows = (s: Stand): void => {
  s.platform = 'wsl'
  s.files = new Set(['/opt/a/powershell.exe', '/usr/bin/wslpath'])
}

/** Turns sound off and lets every play end, so the next test starts with nothing playing. */
async function quiet(s: Stand): Promise<void> {
  await engineCommand(s.$, await s.ctx(), 'sound', ['off'])
  for (const words of [['volume', '70'], ['pick', 'cicadas', 'chorus'], ['pick', 'rain', 'roof'], ['pick', 'thunder', 'storm'], ['objects', 'on']]) await engineCommand(s.$, await s.ctx(), 'sound', words)
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
    engineSwitched(s.$, ctx, 'lamp', minute % 2 === 0, 'click')
    purr(s.$)
    await thunderFor(s.$, { at: s.now(), delayS: 2 })
    await s.advance(60_000)
  }
  expect(s.calls).toEqual([])
  expect(await engineCommand(s.$, await s.ctx(), 'sound', [])).toMatch(/^sound is off, volume 70, objects on\. bank: cicadas chorus, night auto, rain roof, thunder storm, tv tube\. player: not looked for yet/)
  expect(s.calls).toEqual([])
})

test('S2: a one-shot is a line in the running mixer\'s file, written in the same turn as the click, with no process started', async () => {
  if (!BUILT.includes('sound')) return
  const s = await stand()
  onWindows(s)
  Object.assign(sky, { sun: 4, weather: 0 })
  expect(await engineCommand(s.$, await s.ctx(), 'sound', ['on'])).toMatch(/^sound is on, played by the Windows mixer/)
  await s.settle()
  expect(s.mixers.length).toBe(1)
  expect(ranBy(s)).toContain('bed - 0.4900 1500')
  for (const file of [BANK.tv.entries.tube.on, ...OBJECTS.lamp, PURR, ...BANK.thunder.entries.storm.far]) expect(ranBy(s)).toContain(`load ${file}`)

  const spawns = s.calls.filter(call => call === 'process.spawn').length
  const at = s.now()
  engineSwitched(s.$, await s.ctx(), 'tv', true, 'click')
  await s.settle()
  const shot = s.mixers[0]!.ran.find(r => r.words[0] === 'shot')
  expect(shot?.words).toEqual(['shot', BANK.tv.entries.tube.on, '0.4900'])
  expect(shot?.at).toBe(at)
  engineSwitched(s.$, await s.ctx(), 'lamp', true, 'click')
  engineSwitched(s.$, await s.ctx(), 'tape', true, 'click')
  purr(s.$)
  await s.settle()
  expect(ranBy(s).filter(line => line.startsWith('shot ')).map(line => line.split(' ')[1])).toEqual([BANK.tv.entries.tube.on, OBJECTS.lamp[0], OBJECTS.tape[0], PURR])
  expect(s.calls.filter(call => call === 'process.spawn').length).toBe(spawns)
  expect(s.notes().filter(line => / sounding \d+ ms after it was sent$/.test(line)).length).toBe(3)

  engineSwitched(s.$, await s.ctx(), 'tv', false, 'command')
  engineSwitched(s.$, await s.ctx(), 'console', true, 'command')
  await s.settle()
  expect(ranBy(s).filter(line => line.startsWith('shot tv/tube-off'))).toEqual([])
  await s.advance(COMMAND_LAG_MS.direction)
  expect(ranBy(s).filter(line => line.startsWith('shot tv/tube-off')).length).toBe(1)
  expect(ranBy(s).filter(line => line.startsWith(`shot ${OBJECTS.console[0]}`))).toEqual([])
  await s.advance(COMMAND_LAG_MS.screen - COMMAND_LAG_MS.direction)
  expect(ranBy(s).filter(line => line.startsWith(`shot ${OBJECTS.console[0]}`)).length).toBe(1)

  sky.weather = 4
  await engineTick(s.$, await s.ctx())
  await thunderFor(s.$, { at: s.now() - 1000, delayS: 1 })
  engineSwitched(s.$, await s.ctx(), 'light', true, 'click')
  await s.advance(WATCH_MS)
  expect(ranBy(s).filter(line => !line.startsWith('level ')).slice(-3).map(line => line.split(' ').slice(0, 2).join(' ')).sort()).toEqual([`bed ${BANK.rain.entries.roof.storm}`, `shot ${BANK.thunder.entries.storm.near[0]}`, `shot ${OBJECTS.light[0]}`].sort())

  await engineCommand(s.$, await s.ctx(), 'sound', ['objects', 'off'])
  const shots = ranBy(s).filter(line => line.startsWith('shot ')).length
  for (const name of ['lava', 'lamp', 'pc'] as const) engineSwitched(s.$, await s.ctx(), name, true, 'click')
  purr(s.$)
  await s.settle()
  expect(ranBy(s).filter(line => line.startsWith('shot ')).length).toBe(shots)
  engineSwitched(s.$, await s.ctx(), 'tv', true, 'click')
  await s.settle()
  expect(ranBy(s).filter(line => line.startsWith('shot ')).length).toBe(shots + 1)

  await engineCommand(s.$, await s.ctx(), 'sound', ['off'])
  expect(ranBy(s).at(-1)).toBe(`quit ${OFF_FADE_MS}`)
  const offAt = s.now()
  await s.advance(OFF_FADE_MS)
  expect(s.mixers[0]!.ended).toBe(false)
  await s.advance(250 + BEAT_MS)
  expect(s.mixers.every(m => m.ended)).toBe(true)
  expect(s.mixers[0]!.endedAt! - offAt).toBeLessThanOrEqual(OFF_FADE_MS + 250 + BEAT_MS)
  await quiet(s)
})

test('S2: the mixer pings while it runs, and a mixer that exits by itself is one line in the debug log', async () => {
  if (!BUILT.includes('sound')) return
  const s = await stand()
  onWindows(s)
  Object.assign(sky, { sun: 4, weather: 0 })
  await engineCommand(s.$, await s.ctx(), 'sound', ['on'])
  await s.advance(3 * PING_MS + 10)
  expect(ranBy(s).filter(line => line === 'ping').length).toBe(3)
  const m = s.mixers[0]!
  m.outbox.push('error the file did not open\n')
  m.exitCode = 3
  m.wake?.()
  await s.settle()
  expect(m.ended).toBe(true)
  expect(s.notes().filter(line => !line.includes('powershell.exe process'))).toEqual([expect.stringMatching(new RegExp(`sound: the mixer exited 3: the file did not open; the mixer starts again in ${RETRY_MS / 1000} s$`))])
  engineSwitched(s.$, await s.ctx(), 'tv', true, 'click')
  await s.advance(1000)
  expect(s.mixers.length).toBe(1)
  expect(await engineCommand(s.$, await s.ctx(), 'sound', [])).toMatch(/sound is on but nothing plays: the mixer exited 3/)
  await s.advance(RETRY_MS + WATCH_MS)
  expect(s.mixers.length).toBe(2)
  await quiet(s)
})

test('a mixer that stops by itself after its idle limit is started again with sound still on; an early clean exit is a failure', async () => {
  if (!BUILT.includes('sound')) return
  const s = await stand()
  onWindows(s)
  Object.assign(sky, { sun: 4, weather: 0 })
  await engineCommand(s.$, await s.ctx(), 'sound', ['on'])
  await s.advance(QUIET_MS + 10)
  s.mixers[0]!.exitCode = 0
  s.mixers[0]!.wake?.()
  await s.advance(WATCH_MS + 10)
  expect(s.mixers[0]!.ended).toBe(true)
  expect(s.notes()).toEqual([expect.stringMatching(new RegExp(`sound: the mixer stopped after ${QUIET_MS / 1000} s with no command; the next sound starts it again$`))])
  expect(s.mixers.length).toBe(2)
  expect(ranBy(s).some(line => line.startsWith('bed '))).toBe(true)
  expect(await engineCommand(s.$, await s.ctx(), 'sound', [])).not.toMatch(/stopped:/)

  await s.advance(1000)
  s.mixers[1]!.exitCode = 0
  s.mixers[1]!.wake?.()
  await s.advance(WATCH_MS + 10)
  expect(s.notes().at(-1)).toMatch(new RegExp(`sound: the mixer exited 0; the mixer starts again in ${RETRY_MS / 1000} s$`))
  expect(s.mixers.length).toBe(2)
  await s.advance(RETRY_MS + WATCH_MS)
  expect(s.mixers.length).toBe(3)
  await quiet(s)
})

/** The sound piece's own hooks, by event, as register adds them. */
function soundHooks(): Map<string, ($: EngineInterface, e: unknown, next: (e: unknown) => unknown) => unknown> {
  const handlers = new Map<string, ($: EngineInterface, e: unknown, next: (e: unknown) => unknown) => unknown>()
  hooks(((name: string, fn: never) => void handlers.set(name, fn)) as never)
  return handlers
}

test('the session ending, or its desktop window going, fades the mixer out and keeps it out until a window attaches', async () => {
  if (!BUILT.includes('sound')) return
  const on = soundHooks()
  const s = await stand()
  onWindows(s)
  Object.assign(sky, { sun: 0, weather: 0 })
  await engineCommand(s.$, await s.ctx(), 'sound', ['on'])
  await s.settle()
  on.get('session.detach')!(s.$, { surface: 'desktop', clientId: 'c1', reason: 'closed' }, e => e)
  await s.settle()
  expect(ranBy(s).at(-1)).toBe(`quit ${OFF_FADE_MS}`)
  await s.advance(10 * WATCH_MS)
  expect(s.mixers.length).toBe(1)
  expect(await engineCommand(s.$, await s.ctx(), 'sound', [])).toMatch(/^sound is on but nothing plays: no desktop window shows this session/)
  on.get('session.attach')!(s.$, { surface: 'desktop', clientId: 'c2' }, e => e)
  await s.advance(WATCH_MS)
  expect(s.mixers.length).toBe(2)
  expect(ranBy(s).some(line => line.startsWith(`bed ${BANK.cicadas.entries.chorus.bed} `))).toBe(true)
  on.get('session.end')!(s.$, { reason: 'other', sessionId: 's1' }, e => e)
  await s.settle()
  expect(ranBy(s).at(-1)).toBe(`quit ${OFF_FADE_MS}`)
  await s.advance(10 * WATCH_MS)
  expect(s.mixers.length).toBe(2)
  on.get('session.attach')!(s.$, { surface: 'desktop', clientId: 'c3' }, e => e)
  await quiet(s)
})

test('pings keep a quiet morning\'s mixer alive, and a mixer silent past its limit with no exit seen is replaced and sent the bed', async () => {
  if (!BUILT.includes('sound')) return
  const s = await stand()
  onWindows(s)
  Object.assign(sky, { sun: 5, weather: 0 })
  await engineCommand(s.$, await s.ctx(), 'sound', ['on'])
  await s.advance(4 * PING_MS + 10)
  expect(ranBy(s).filter(line => line === 'ping').length).toBe(4)
  expect(ranBy(s).filter(line => line.startsWith('bed '))).toEqual([`bed - 0.4900 ${START_FADE_MS}`])
  expect(s.mixers.length).toBe(1)

  s.mixers[0]!.mute = true
  Object.assign(sky, { sun: 0, weather: 0 })
  await s.advance(SILENT_MS + 2 * WATCH_MS)
  expect(s.mixers.length).toBe(2)
  expect(s.notes()).toContainEqual(expect.stringMatching(new RegExp(`sound: the mixer has said nothing for ${SILENT_MS / 1000} s; starting another$`)))
  expect(ranBy(s).filter(line => line.startsWith('bed '))).toEqual([`bed ${BANK.cicadas.entries.chorus.bed} 0.4900 ${START_FADE_MS}`])
  await quiet(s)
})

test('one player per session: a newer copy of the mod holding it ends this one\'s, and this one waits for an older copy to fade out', async () => {
  if (!BUILT.includes('sound')) return
  const s = await stand()
  onWindows(s)
  Object.assign(sky, { sun: 0, weather: 0 })
  await engineCommand(s.$, await s.ctx(), 'sound', ['on'])
  await s.settle()
  expect(s.mixers.length).toBe(1)
  s.state.set('bedroom-mixer', COPY + 1)
  await s.advance(WATCH_MS + 10)
  expect(ranBy(s).at(-1)).toBe(`quit ${OFF_FADE_MS}`)
  await s.advance(10 * WATCH_MS)
  expect(s.mixers.length).toBe(1)
  expect(await engineCommand(s.$, await s.ctx(), 'sound', [])).toMatch(/nothing plays: a newer copy of the mod plays it/)

  s.state.set('bedroom-mixer', COPY - 1)
  await s.advance(WATCH_MS + 10)
  expect([s.mixers.length, s.state.get('bedroom-mixer')]).toEqual([1, COPY])
  await s.advance(HANDOVER_MS + WATCH_MS)
  expect(s.mixers.length).toBe(2)
  expect(s.state.get('bedroom-mixer')).toBe(COPY)
  await quiet(s)
})

test('with sound saved on and nothing started yet, as after a reload, a change of hour starts the mixer and sends the bed', async () => {
  if (!BUILT.includes('sound')) return
  const s = await stand()
  onWindows(s)
  Object.assign(sky, { sun: 0, weather: 0 })
  await (await s.ctx()).save({ sound: true })
  expect(s.mixers.length).toBe(0)
  await engineCommand(s.$, await s.ctx(), 'time', ['dusk'])
  await s.advance(10)
  expect(s.mixers.length).toBe(1)
  expect(ranBy(s).filter(line => line.startsWith('bed '))).toEqual([`bed ${BANK.cicadas.entries.chorus.bed} 0.4900 ${START_FADE_MS}`])
  await s.advance(5 * PING_MS)
  expect(ranBy(s).filter(line => line === 'ping').length).toBe(5)
  await quiet(s)
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

test("S6: a minute's scheduled strike in a storm brings its thunder through the same call, and none in rain", async () => {
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
  sky.weather = 2
  const stormed = heard().length
  await s.advance(tickAt(strikes[4] ?? 0) - s.now())
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

test('S1: each kind has named entries with a default, picked by name or number and saved; 0.3\'s picks carry over', async () => {
  if (!BUILT.includes('sound')) return
  expect(namesOf('cicadas')).toEqual(['chorus', 'river'])
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
  expect(await engineCommand(s.$, await s.ctx(), 'sound', ['pick', 'cicadas', '1'])).toBe('cicadas plays chorus')
  expect(await engineCommand(s.$, await s.ctx(), 'sound', ['pick', 'thunder', 'distant'])).toBe('thunder plays distant')
  expect(await engineCommand(s.$, await s.ctx(), 'sound', ['pick', 'night', 'crickets'])).toBe('night plays crickets')
  expect(await engineCommand(s.$, await s.ctx(), 'sound', ['pick', 'night', 'katydids'])).toBe('night plays katydids')
  expect(await engineCommand(s.$, await s.ctx(), 'sound', ['pick', 'crickets', 'crickets'])).toMatch(/^say a kind and one of its sounds/)
  expect(ranBy(s)).toContain(`load ${BANK.thunder.entries.distant.far[0]}`)
  expect(await engineCommand(s.$, await s.ctx(), 'sound', ['pick', 'wind', 'x'])).toMatch(/^say a kind and one of its sounds, as in \/bedroom sound pick cicadas river\. cicadas: chorus or river; night: auto or katydids or crickets; rain: roof; thunder: storm or distant; tv: tube\. Now:/)
  expect(await engineCommand(s.$, await s.ctx(), 'sound', ['pick', 'rain', 'tin'])).toMatch(/^say a kind/)
  await quiet(s)
})

const KATYDIDS = 'crickets/katydids.wav'
const CRICKETS = 'crickets/crickets.wav'

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
  s.exit = 0
  expect(await engineCommand(s.$, await s.ctx(), 'sound', ['test'])).toBe('paplay played silence.wav and exited 0')
  await quiet(s)
})

test('a volume, bank and objects stored outside their range load as the defaults', () => {
  expect(savedOf({ volume: 40, bank: { cicadas: 'river' } })).toMatchObject({ volume: 40, bank: { cicadas: 'river' } })
  expect(savedOf({ volume: 140 }).volume).toBeUndefined()
  expect(savedOf({ volume: 4.5 }).volume).toBeUndefined()
  expect(savedOf({ objects: 'yes' }).objects).toBeUndefined()
})

/** A local clock time on 2026-11-19, `minutesIn` after the start of row `row` by the season's sunrise and sunset. */
function intoRow(row: number, minutesIn: number): number {
  const noonOfDay = new Date(2026, 10, 19, 12).getTime()
  const { sunrise, sunset } = seasonOf(noonOfDay)
  const start = rowStarts(sunrise, sunset)[row]!
  return new Date(2026, 10, 19, 0, start + minutesIn, 0).getTime()
}

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

/**
 * Starts the shader's values with this sky, as the room does at load: from then on the bed follows the world code sent.
 * The values module stays started for the rest of the file, so this test runs last.
 */
function shaderAt(s: Stand, fields: Pick<Fields, 'sun' | 'weather'>): void {
  startShader({ ...DEFAULT_STATE }, { ...fields, work: 0, zone: 0, hall: 0 }, 480, s.now())
}

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
