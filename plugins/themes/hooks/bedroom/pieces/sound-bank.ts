import type { Saved } from '../core/saved.js'

/**
 * The sound bank: for each kind, named entries and the default, each entry's files under sounds/bedroom/<kind>/ (the
 * night kind's under crickets/).
 * sounds/bedroom/sources.md says where each file comes from. A file's length in ms is beside it: a player that cannot
 * repeat a file itself is started again after that long.
 */
export const BANK = {
  cicadas: {
    default: 'auto',
    entries: {
      auto: { bed: 'cicadas/chorus.wav', swell: 'cicadas/river.wav' },
      chorus: { bed: 'cicadas/chorus.wav', swell: undefined },
      river: { bed: 'cicadas/river.wav', swell: undefined },
    },
  },
  night: {
    default: 'auto',
    entries: {
      auto: { evening: 'crickets/katydids.wav', late: 'crickets/crickets.wav' },
      katydids: { evening: 'crickets/katydids.wav', late: 'crickets/katydids.wav' },
      crickets: { evening: 'crickets/crickets.wav', late: 'crickets/crickets.wav' },
    },
  },
  rain: {
    default: 'roof',
    entries: { roof: { rain: 'rain/roof-rain.wav', downpour: 'rain/roof-downpour.wav', storm: 'rain/roof-storm.wav' } },
  },
  thunder: {
    default: 'storm',
    entries: {
      storm: { near: ['thunder/storm-near.wav'], mid: ['thunder/storm-mid.wav'], far: ['thunder/storm-far-1.wav', 'thunder/storm-far-2.wav'] },
      distant: { near: ['thunder/distant-near.wav'], mid: ['thunder/distant-mid.wav'], far: ['thunder/distant-far.wav'] },
    },
  },
  tv: { default: 'tube', entries: { tube: { on: 'tv/tube-on.wav', off: 'tv/tube-off.wav' } } },
} as const

export type Kind = keyof typeof BANK
export const KINDS = Object.keys(BANK) as Kind[]
export type EntryOf<K extends Kind> = (typeof BANK)[K]['entries'][keyof (typeof BANK)[K]['entries']]

/** The names a kind's entries go by, the default first. */
export function namesOf(kind: Kind): string[] {
  const names = Object.keys(BANK[kind].entries)
  return [BANK[kind].default, ...names.filter(name => name !== BANK[kind].default)]
}

/** The entry chosen for a kind: the saved name when it is one of the kind's, else the default. */
export function chosenName(saved: Saved, kind: Kind): string {
  const name = saved.bank?.[kind]
  return name !== undefined && name in BANK[kind].entries ? name : BANK[kind].default
}
export function chosen<K extends Kind>(saved: Saved, kind: K): EntryOf<K> {
  return (BANK[kind].entries as unknown as Record<string, EntryOf<K>>)[chosenName(saved, kind)]!
}

/** The room's things that make a sound when they change, each with its on and off file; the lava lamp is silent. */
export const OBJECTS = {
  lamp: ['objects/lamp-on.wav', 'objects/lamp-off.wav'],
  light: ['objects/light-on.wav', 'objects/light-off.wav'],
  pc: ['objects/pc-on.wav', 'objects/pc-off.wav'],
  console: ['objects/console-on.wav', 'objects/console-off.wav'],
  tape: ['objects/tape-in.wav', 'objects/tape-out.wav'],
} as const
export const PURR = 'objects/purr.wav'
export const SILENCE = 'silence.wav'

/** Every file's length in ms. */
export const LENGTH_MS: Record<string, number> = {
  'cicadas/chorus.wav': 20000,
  'cicadas/river.wav': 20000,
  'crickets/katydids.wav': 20000,
  'crickets/crickets.wav': 20000,
  'rain/roof-rain.wav': 20000,
  'rain/roof-downpour.wav': 20000,
  'rain/roof-storm.wav': 20000,
  'thunder/storm-near.wav': 6000,
  'thunder/storm-mid.wav': 7000,
  'thunder/storm-far-1.wav': 8000,
  'thunder/storm-far-2.wav': 8000,
  'thunder/distant-near.wav': 7000,
  'thunder/distant-mid.wav': 8000,
  'thunder/distant-far.wav': 8000,
  'tv/tube-on.wav': 1400,
  'tv/tube-off.wav': 1100,
  'objects/lamp-on.wav': 120,
  'objects/lamp-off.wav': 120,
  'objects/light-on.wav': 120,
  'objects/light-off.wav': 120,
  'objects/pc-on.wav': 1200,
  'objects/pc-off.wav': 600,
  'objects/console-on.wav': 2600,
  'objects/console-off.wav': 1200,
  'objects/tape-in.wav': 1700,
  'objects/tape-out.wav': 1500,
  'objects/purr.wav': 3500,
  'silence.wav': 400,
}
export const lengthOf = (file: string): number => LENGTH_MS[file] ?? 10_000

/** The one-shots the mixer opens ahead: every file that is not a bed. */
export function shotsOf(saved: Saved): string[] {
  const thunder = chosen(saved, 'thunder')
  const tv = chosen(saved, 'tv')
  return [tv.on, tv.off, ...thunder.near, ...thunder.mid, ...thunder.far, ...Object.values(OBJECTS).flat(), PURR]
}
