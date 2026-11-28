import type { EngineInterface } from 'claude-code'

import { DEFAULT_STATE, type State, type Titles } from '../scene/lib.ts'

/** The key the bedroom's settings are stored under in the themes plugin's store, named for the theme so another theme's cannot collide. */
export const STORE_KEY = 'bedroom:saved'

/**
 * What is kept across sessions: the switches, how far back the room sits, the window's shape for clicks, the panels,
 * the titles, the sound's volume and recordings, and the overrides a command stores. A value 0.2 stored, without the
 * newer keys, loads as it was. `shader` is held for the session only: shader off is for diagnosis, so a new session
 * starts with the shader on.
 */
export type Saved = {
  state: State
  dim: number
  aspect: number
  glass: number
  blur: number
  titles: Titles
  time?: string
  date?: string
  weather?: string
  lightning?: string
  sound?: boolean
  signal?: boolean
  hall?: boolean
  shader?: boolean
  /** The sound's volume, 0 to 100. */
  volume?: number
  /** The sound bank's entry each kind plays, by kind (pieces/sound-bank.ts); the kind's default when absent. */
  bank?: Partial<Record<string, string>>
  /** Whether the room's things (lamp, light, monitor, console, tape, cat) make their sounds; on when absent. */
  objects?: boolean
}

/** The sound's volume when none is saved, 0 to 100. */
export const DEFAULT_VOLUME = 70
export const volumeOf = (kept: Saved): number => kept.volume ?? DEFAULT_VOLUME

/** The window's width over its height. The backdrop fills the whole app window, so a click is mapped with it. */
export const DEFAULT_ASPECT = 2000 / 1062
export const defaults = (): Saved => ({ state: { ...DEFAULT_STATE }, dim: 0, aspect: DEFAULT_ASPECT, glass: 0, blur: 0, titles: {} })

let saved: Saved = defaults()

export function current(): Saved {
  return saved
}

const number = (value: unknown, fallback: number): number => (typeof value === 'number' && Number.isFinite(value) ? value : fallback)
const TITLE_KEYS = ['console', 'tape', 'pennant', 'pennant-top'] as const

function titlesOf(value: unknown): Titles {
  if (typeof value !== 'object' || value === null) return {}
  const given = value as Record<string, unknown>
  return Object.fromEntries(TITLE_KEYS.filter(key => typeof given[key] === 'string').map(key => [key, given[key]]))
}

function bankOf(value: unknown, picks: unknown): Saved['bank'] {
  const named = typeof value === 'object' && value !== null ? Object.entries(value).filter(([, name]) => typeof name === 'string' && /^[a-z-]+$/.test(name)) : []
  if (named.length > 0) return Object.fromEntries(named)
  if (typeof picks !== 'object' || picks === null) return undefined
  return (picks as Record<string, unknown>).cicadas === 2 ? { cicadas: 'river' } : undefined
}

/** The saved value a stored one reads as: each known key checked, a missing or wrong one at its default, `shader` dropped. */
export function savedOf(stored: unknown): Saved {
  const base = defaults()
  if (typeof stored !== 'object' || stored === null) return base
  const { shader: _session, volume, bank, objects, picks, ...given } = stored as Partial<Saved> & { picks?: unknown }
  const state = typeof given.state === 'object' && given.state !== null ? given.state : {}
  const loaded: Saved = {
    ...given,
    state: { ...base.state, ...state, posters: 'plain' },
    dim: number(given.dim, 0),
    aspect: number(given.aspect, DEFAULT_ASPECT),
    glass: number(given.glass, 0),
    blur: number(given.blur, 0),
    titles: titlesOf(given.titles),
  }
  if (typeof volume === 'number' && Number.isInteger(volume) && volume >= 0 && volume <= 100) loaded.volume = volume
  const chosen = bankOf(bank, picks)
  if (chosen !== undefined) loaded.bank = chosen
  if (typeof objects === 'boolean') loaded.objects = objects
  return loaded
}

/** Reads the store. */
export async function load($: EngineInterface): Promise<Saved> {
  saved = savedOf(await $.store.get(STORE_KEY))
  return saved
}

/** Changes what is kept at once and writes the store, without `shader`; a key given as undefined is cleared. */
export function save($: EngineInterface, patch: Partial<Saved>): Promise<void> {
  const next: Saved = { ...saved, ...patch }
  for (const key of Object.keys(patch) as (keyof Saved)[]) if (patch[key] === undefined) delete next[key]
  saved = next
  const { shader: _session, ...kept } = saved
  return $.store.set(STORE_KEY, kept).then(() => undefined)
}
