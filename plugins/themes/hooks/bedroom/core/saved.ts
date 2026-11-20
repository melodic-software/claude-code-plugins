import type { EngineInterface } from 'claude-code'

import { DEFAULT_STATE, type State, type Titles } from '../scene/lib.ts'

/** The key the bedroom's settings are stored under in the themes plugin's store, named for the theme so another theme's cannot collide. */
export const STORE_KEY = 'bedroom:saved'

/**
 * What is kept across sessions: the switches, how far back the room sits, the window's shape for clicks, the panels,
 * the titles, and the overrides a command stores. A value 0.2 stored, without the newer keys, loads as it was.
 */
export type Saved = {
  state: State
  dim: number
  aspect: number
  glass: number
  blur: number
  titles: Titles
  time?: string
  weather?: string
  sound?: boolean
  signal?: boolean
  hall?: boolean
  shader?: boolean
}

/** The window's width over its height. The backdrop fills the whole app window, so a click is mapped with it. */
export const DEFAULT_ASPECT = 2000 / 1062
export const defaults = (): Saved => ({ state: { ...DEFAULT_STATE }, dim: 0, aspect: DEFAULT_ASPECT, glass: 0, blur: 0, titles: {} })

let saved: Saved = defaults()

export function current(): Saved {
  return saved
}

const number = (value: unknown, fallback: number): number => (typeof value === 'number' && Number.isFinite(value) ? value : fallback)
const TITLE_KEYS = ['console', 'tape', 'pennant', 'pennant-top'] as const

/** The stored titles that are text, under the four names a title has. */
function titlesOf(value: unknown): Titles {
  if (typeof value !== 'object' || value === null) return {}
  const given = value as Record<string, unknown>
  return Object.fromEntries(TITLE_KEYS.filter(key => typeof given[key] === 'string').map(key => [key, given[key]]))
}

/** The saved value a stored one reads as: each known key checked, a missing or wrong one at its default. */
export function savedOf(stored: unknown): Saved {
  const base = defaults()
  if (typeof stored !== 'object' || stored === null) return base
  const given = stored as Partial<Saved>
  const state = typeof given.state === 'object' && given.state !== null ? given.state : {}
  return {
    ...given,
    state: { ...base.state, ...state, posters: 'plain' },
    dim: number(given.dim, 0),
    aspect: number(given.aspect, DEFAULT_ASPECT),
    glass: number(given.glass, 0),
    blur: number(given.blur, 0),
    titles: titlesOf(given.titles),
  }
}

/** Reads the store. */
export async function load($: EngineInterface): Promise<Saved> {
  saved = savedOf(await $.store.get(STORE_KEY))
  return saved
}

/** Changes what is kept at once and writes the store; a key given as undefined is cleared. */
export function save($: EngineInterface, patch: Partial<Saved>): Promise<void> {
  const next: Saved = { ...saved, ...patch }
  for (const key of Object.keys(patch) as (keyof Saved)[]) if (patch[key] === undefined) delete next[key]
  saved = next
  return $.store.set(STORE_KEY, saved).then(() => undefined)
}
