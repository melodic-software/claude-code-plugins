import type { On, ProcessSpawnChunk, ProcessSpawnResult } from 'claude-code'
import { mock, type Engine, type MockClock } from 'claude-code/testing'

import { STORE_KEY } from './saved.js'

/**
 * Helpers for the kit's tests: a session with the room mounted on the desktop, its clock and store in memory. A test
 * file runs in a child of its own, so each file starts the plugin afresh; a test's own imports of core/ are a copy apart
 * from the plugin's, reached only through `$`.
 */
export { STORE_KEY }

/** A viewBox point as fractions of a window of this shape (the inverse of toViewBox). */
export function inWindow(x: number, y: number, aspect: number): { x: number; y: number } {
  const width = Math.min(1600, 1000 * aspect)
  const height = Math.min(1000, 1600 / aspect)
  return { x: (x - 800) / width + 0.5, y: (y - 500) / height + 0.5 }
}

export const BACKDROP = {
  plugin: 'themes',
  surface: 'desktop',
  component: 'Backdrop',
  props: { scene: 'bedroom', plugin: 'themes', glass: false },
} as const

/** 20:00 local time on 2026-11-19 wherever the test runs, so the VCR reads 480 at the start. */
export const EVENING = new Date(2026, 10, 19, 20, 0, 0).getTime()

/**
 * Settings that hold the atmosphere at code 0 of world and screen whatever pieces are built: dusk, clear, the hallway
 * still, the television not reacting. Given as a test's options (`test(name, { options: QUIET }, body)`), they stand as
 * the settings, so they hold through /bedroom reset, which clears the stored overrides.
 */
export const QUIET = { time: 'dusk', weather: 'clear', hall: false, signal: false } as const

export type Room = {
  clock: MockClock
  /** The plugin's store, answered from memory: a test may change what is saved under the mod. */
  store: Map<string, unknown>
  /** /bedroom <args>: the reply text. */
  run: (args: string) => Promise<string>
  /** The Shader element's values as last drawn, or undefined while the room shows alone. */
  values: () => Promise<Record<string, number> | undefined>
  /** The Svg element's source as last drawn. */
  source: () => Promise<string | undefined>
  toasts: string[]
  /** Every theme call that reached the engine, oldest first: `set <scene>` or `clear`. */
  themes: string[]
  /** The mod's debug log lines, oldest first. */
  events: () => string[]
  /** Every path the mod asked to write. */
  writes: string[]
  unmount: () => Promise<void>
}

/**
 * Starts a session with the room mounted, the store holding `saved` when given; waits out the first hold unless told
 * not to. The engine calls a piece may make at load or each minute are answered harmlessly (the context 10% full, every
 * process exiting 0, every play silent) unless `fakes` is false, for a test that answers them itself: it registers its
 * own hooks before calling startRoom, since the kit refuses an event hooked twice, and a hook added after the test's
 * first call to `$`.
 */
export async function startRoom(
  $: Engine,
  on: On,
  options: { saved?: unknown; now?: number; hold?: boolean; fakes?: boolean; early?: boolean; onWrite?: (path: string, text: string) => void } = {},
): Promise<Room> {
  const clock = mock.clock(on, { now: options.now ?? EVENING })
  const store = new Map<string, unknown>(options.saved === undefined ? [] : [[STORE_KEY, options.saved]])
  on('store.get', (_, e) => ({ value: store.get(e.key) }))
  on('store.set', (_, e) => {
    store.set(e.key, JSON.parse(JSON.stringify(e.value)))
    return { value: undefined }
  })
  on('store.delete', (_, e) => {
    store.delete(e.key)
    return { value: undefined }
  })
  on('store.keys', () => ({ value: [...store.keys()] }))
  const toasts: string[] = []
  on('command.register', () => ({ value: { command: 'bedroom' } }))
  const themes: string[] = []
  on('theme.set', (_, e) => {
    themes.push(`set ${e.backdrop !== undefined && 'scene' in e.backdrop ? e.backdrop.scene : 'none'}`)
    return { value: { isDrawn: true, requestId: 'backdrop' } }
  })
  on('theme.clear', () => {
    themes.push('clear')
    return { value: { isDrawn: false, reason: 'cleared' } }
  })
  const writes: string[] = []
  on('fs.write', (_, e) => {
    writes.push(e.path)
    options.onWrite?.(e.path, e.text)
    return { value: undefined }
  })
  const log: string[] = []
  on('ui.log', (_, e) => {
    log.push(String(e.text))
    return { value: undefined }
  })
  on('ui.toast', (_, e) => {
    toasts.push(String(e.text))
    return { value: undefined }
  })
  on('ui.place', (_, e) => ({ value: { isPlaced: true, requestId: e.id } }))
  if (options.fakes !== false) {
    on('session.usage', () => ({ value: { startedAt: clock.now(), context: { window: 200_000, tokens: 20_000, percent: 10 }, rateLimits: [] } }))
    on('process.run', () => ({ value: { exitCode: 0, stdout: '', stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }))
    on('audio.play', () => ({ value: undefined }))
    on('process.spawn', async function* (): AsyncGenerator<ProcessSpawnChunk, ProcessSpawnResult> {
      return { code: 0, signal: null }
    })
  }
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  const first = options.early === true ? await $.ui.mount({ ...BACKDROP }) : undefined
  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  const ui = first ?? (await $.ui.mount({ ...BACKDROP }))
  if (options.hold !== false) await clock.advance(7300)
  return {
    clock,
    store,
    toasts,
    themes,
    writes,
    events: () => [...log],
    run: async args => {
      const reply = await $.command.run({ command: 'bedroom', args, origin: { kind: 'composer' } as never, presentation: {} as never })
      return String((reply as { text?: unknown }).text ?? '')
    },
    values: async () => (await ui.find({ type: 'Shader' }))?.props.values as Record<string, number> | undefined,
    source: async () => (await ui.find({ type: 'Svg' }))?.props.source as string | undefined,
    unmount: () => ui.unmount(),
  }
}

/** The names whose values differ between two drawings. */
export function changed(a: Record<string, number> | undefined, b: Record<string, number> | undefined): string[] {
  const names = new Set([...Object.keys(a ?? {}), ...Object.keys(b ?? {})])
  return [...names].filter(name => a?.[name] !== b?.[name])
}
