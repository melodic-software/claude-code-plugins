/** The time of day and the weather the hand-drawn room shows: `sun` is the row of the day, 0 to 7; `weather` 0 (clear) to 4 (storm). */
export type Look = { sun: number; weather: number }
/** A gradient stop: offset, color, opacity. */
export type Stop = [number, string, number?]

/** The dusk sky as the room has always drawn it, top (y 234) to the field (y 563). */
export const DUSK_SKY: Stop[] = [
  [0, '#08112c'], [0.18, '#0c1638'], [0.38, '#161d48'], [0.55, '#241f50'], [0.68, '#3a2853'],
  [0.78, '#563354'], [0.86, '#7a4650'], [0.93, '#8b5541'], [0.97, '#955e43'], [1, '#8a5844'],
]
/** The dusk clouds, lit from below. */
export const DUSK_CLOUD: Stop[] = [[0, '#2a2650', 0.35], [0.55, '#6a4462', 0.55], [1, '#d08a6c', 0.9]]

type Land = [string, string, string, string, string, string]
type Row = {
  sky: string[]
  cloud: Stop[]
  glow: number
  land: Land
  night: boolean
}

const ROWS: Row[] = [
  { sky: [], cloud: DUSK_CLOUD, glow: 1, land: ['#3a2c4c', '#1e1a32', '#171426', '#08090f', '#06070c', '#07080e'], night: true },
  { sky: ['#050a20', '#0a1234', '#141a42', '#221c44', '#2e2040'], cloud: [[0, '#141832', 0.3], [0.55, '#2a2448', 0.4], [1, '#4a3050', 0.5]], glow: 0.3, land: ['#221c32', '#141224', '#100e1c', '#06070c', '#05060a', '#05060b'], night: true },
  { sky: ['#03050f', '#050816', '#070b1e', '#0a0e25', '#0d112a'], cloud: [[0, '#0a0c1a', 0.25], [0.55, '#12142a', 0.3], [1, '#181a32', 0.35]], glow: 0, land: ['#0f1020', '#0a0b16', '#090a12', '#040509', '#04050a', '#040509'], night: true },
  { sky: ['#050a20', '#0c1636', '#1c2650', '#363c62', '#4a4a6a'], cloud: [[0, '#141a36', 0.3], [0.55, '#2c3050', 0.4], [1, '#50506e', 0.5]], glow: 0, land: ['#24243a', '#161828', '#12131e', '#07080d', '#05060b', '#05060b'], night: true },
  { sky: ['#2a3e72', '#50639a', '#9a8ca8', '#d8a490', '#e8b894'], cloud: [[0, '#6a6c98', 0.35], [0.55, '#c08c98', 0.55], [1, '#f2b08a', 0.8]], glow: 0.7, land: ['#5a5a6c', '#3a3e48', '#3a4228', '#1e2414', '#12180e', '#16161a'], night: false },
  { sky: ['#4a7cc4', '#6a94d0', '#93b0d8', '#bccddf', '#cbd6e0'], cloud: [[0, '#f4f6fa', 0.45], [0.55, '#ffffff', 0.55], [1, '#dfe4ec', 0.6]], glow: 0, land: ['#6a8478', '#3e5446', '#4c6a30', '#2a3c1a', '#16220f', '#2a241e'], night: false },
  { sky: ['#5c8cd1', '#6c98d4', '#90b0d8', '#aac2da', '#b3c7db'], cloud: [[0, '#ffffff', 0.5], [0.55, '#ffffff', 0.6], [1, '#e8ecf2', 0.65]], glow: 0, land: ['#6e8a7a', '#425a48', '#527234', '#2e421c', '#182410', '#2a241e'], night: false },
  { sky: ['#5a7eb8', '#7c94b8', '#b8a8a0', '#e8aa78', '#f2a86b'], cloud: [[0, '#b8a8b8', 0.4], [0.55, '#f0c4a0', 0.6], [1, '#ffcc90', 0.8]], glow: 1.4, land: ['#7a6a5a', '#4a4036', '#5a5a28', '#30301a', '#1c1c10', '#2a2018'], night: false },
]

const WEATHER: [share: number, keep: number, rain: number][] = [
  [0, 1, 0],
  [0.75, 0.86, 0],
  [0.9, 0.72, 1],
  [1, 0.58, 2],
  [1, 0.5, 2],
]
const DAY = [0, 0, 0, 0, 0.35, 0.85, 1, 0.65]

const hex = (c: string): number[] => [1, 3, 5].map(i => parseInt(c.slice(i, i + 2), 16))
const toHex = (v: number[]): string => '#' + v.map(x => Math.max(0, Math.min(255, Math.round(x))).toString(16).padStart(2, '0')).join('')
function weathered(c: string, share: number, keep: number): string {
  const rgb = hex(c)
  const y = 0.3 * rgb[0]! + 0.59 * rgb[1]! + 0.11 * rgb[2]!
  const gray = [y * 0.97, y * 0.99, y * 1.04]
  return toHex(rgb.map((x, i) => (x + (gray[i]! - x) * share) * keep))
}

export type Outside = {
  sky: Stop[]
  cloud: Stop[]
  glow: number
  land: Land
  /** Stars and the meteor: a clear night's. */
  stars: boolean
  /** Fireflies: a dry evening's and night's. */
  flies: boolean
  /** The yard light: on from dusk to dawn. */
  yard: boolean
  /** 0 dry, 1 rain, 2 a downpour or a storm. */
  rain: number
  /** The row's share of daylight, 0 to 1. */
  day: number
  /** How much light the rain catches: little at night, where bright drops would read as stars. */
  drops: number
}

/** The outside for a look: sun 0 to 7 and weather 0 to 4, anything else read as 0. Sun 0 in clear weather is the dusk as drawn. */
export function outside(look: Look): Outside {
  const sun = Number.isInteger(look.sun) && look.sun >= 0 && look.sun <= 7 ? look.sun : 0
  const weather = Number.isInteger(look.weather) && look.weather >= 0 && look.weather <= 4 ? look.weather : 0
  const row = ROWS[sun]!
  const [share, keep, rain] = WEATHER[weather]!
  const sky: Stop[] = sun === 0 ? DUSK_SKY : row.sky.map((c, i): Stop => [[0, 0.3, 0.6, 0.85, 1][i]!, c])
  const wet = (list: Stop[]): Stop[] => list.map(([o, c, a]): Stop => (a === undefined ? [o, weathered(c, share, keep)] : [o, weathered(c, share, keep), a]))
  return {
    sky: wet(sky),
    cloud: wet(row.cloud),
    glow: weather === 0 ? row.glow : 0,
    land: row.land.map(c => weathered(c, share * 0.5, keep)) as Land,
    stars: row.night && weather === 0,
    flies: row.night && sun !== 3 && rain === 0,
    yard: row.night,
    rain,
    day: DAY[sun]!,
    drops: [0.7, 0.5, 0.35, 0.45, 0.85, 1, 1, 1][sun]!,
  }
}
