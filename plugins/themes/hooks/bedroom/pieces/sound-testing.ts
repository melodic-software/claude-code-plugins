import type { EngineInterface } from 'claude-code'

import { readNow } from '../core/clock.js'
import { ctxOf, usePieces } from '../core/context.js'
import type { Ctx, Fields, Piece } from '../core/piece.js'
import { load } from '../core/saved.js'
import { useOptions } from '../core/settings.js'
import { EVENING } from '../core/testing.js'
import { startShader } from '../core/values.js'
import { DEFAULT_STATE } from '../scene/lib.ts'
import { lengthOf } from './sound-bank.js'
import { rowStarts, seasonOf } from './time.js'
import { BEAT_MS } from './sound-mixer.js'
import { engineCommand } from './sound.js'

declare function setTimeout(fn: () => void, ms: number): unknown
export const wait = (ms: number): Promise<void> => new Promise(resolve => void setTimeout(resolve, ms))
export const NIGHT = { time: 'night', weather: 'clear', hall: false, signal: false } as const

/** A command the fake mixer ran: its seq, its words, and when it reached it. */
export type Ran = { seq: number; words: string[]; at: number }
/** A fake of the Windows mixer behind the engine: it answers each command line written to its file as the script does. */
export type FakeMixer = { ran: Ran[]; outbox: string[]; wake?: () => void; ended: boolean; endedAt?: number; last: number; exitCode?: number; mute?: boolean }
const READY = 'ready C:\\Temp\\claude-bedroom-sound-1\\commands.txt\n'
export const COMMANDS = '/mnt/c/Temp/claude-bedroom-sound-1/commands.txt'

/** Reads a command file as the mixer does: only a file that ends with `end`, each line above the last run, one-shots first. */
export function runFile(m: FakeMixer, text: string, at: number): void {
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
export async function* mixerChild(m: FakeMixer, now: () => number, beat: (wake: () => void) => void): AsyncGenerator<{ stream: 'stdout' | 'stderr'; text: string }, { code: number | null; signal: string | null }> {
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

/** What the weather and time pieces would give: the fields the sound follows. */
export const sky: Pick<Fields, 'sun' | 'weather'> = { sun: 0, weather: 0 }
const standIn: Piece = { name: 'stand-in', fields: () => ({ ...sky }) }

type Play = { argv: readonly string[]; at: number; endedAt?: number }
export type Stand = {
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

export async function stand(start = EVENING): Promise<Stand> {
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

export const fileIn = (argv: readonly string[]): string => argv.at(-1)?.replace('/room/sounds/bedroom/', '') ?? ''

/** The commands the last mixer ran, as their words. */
export const ranBy = (s: Stand): string[] => (s.mixers.at(-1)?.ran ?? []).map(r => r.words.join(' '))
export const onWindows = (s: Stand): void => {
  s.platform = 'wsl'
  s.files = new Set(['/opt/a/powershell.exe', '/usr/bin/wslpath'])
}

/** Turns sound off and lets every play end, so the next test starts with nothing playing. */
export async function quiet(s: Stand): Promise<void> {
  await engineCommand(s.$, await s.ctx(), 'sound', ['off'])
  for (const words of [['volume', '70'], ['pick', 'cicadas', 'auto'], ['pick', 'night', 'auto'], ['pick', 'rain', 'roof'], ['pick', 'thunder', 'storm'], ['objects', 'on']]) await engineCommand(s.$, await s.ctx(), 'sound', words)
  await s.advance(120_000)
}

export const KATYDIDS = 'crickets/katydids.wav'
export const CRICKETS = 'crickets/crickets.wav'

/** A local clock time on 2026-11-19, `minutesIn` after the start of row `row` by the season's sunrise and sunset. */
export function intoRow(row: number, minutesIn: number): number {
  const noonOfDay = new Date(2026, 10, 19, 12).getTime()
  const { sunrise, sunset } = seasonOf(noonOfDay)
  const start = rowStarts(sunrise, sunset)[row]!
  return new Date(2026, 10, 19, 0, start + minutesIn, 0).getTime()
}

/**
 * Starts the shader's values with this sky, as the room does at load: from then on the bed follows the world code sent.
 * The values module stays started for the rest of the test file, so a file runs the tests that use it last.
 */
export function shaderAt(s: Stand, fields: Pick<Fields, 'sun' | 'weather'>): void {
  startShader({ ...DEFAULT_STATE }, { ...fields, work: 0, zone: 0, hall: 0 }, 480, s.now())
}
