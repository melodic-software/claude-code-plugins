import type { Look } from './sky.ts'

/** One part of the scene. Every field is an SVG fragment string (style is CSS text, with no tags). */
export type Part = {
  /** CSS for this part: class names and keyframe names carry the part's prefix. */
  style?: string
  /** Children of the one shared defs element: gradients, patterns, filters, clip paths, masks. Ids carry the part's prefix. */
  defs?: string
  /** Drawn on the wall and floor before any part's body: cast shadows, light pools, halos on the wall. */
  under?: string
  /** The part itself. */
  body?: string
  /** Drawn after every part's body: bloom, haze, light that spills over other things. */
  over?: string
}

/** The vanishing point of the one-point perspective. Eye level is y = 500. */
export const VP = { x: 800, y: 500 }
/** viewBox units per inch on the back-wall plane. */
export const U = 7.8
/** Where the back wall meets the floor. */
export const FLOOR_Y = 850
/** Where the back wall meets the ceiling (96 inches up). */
export const CEILING_Y = 101

/**
 * Moves a back-wall point to a plane nearer the camera. s is 1 on the wall and grows toward the camera
 * (dresser front 1.16, desk front 1.2, chair 1.36). Edges that run away from the camera join p and proj(p, s).
 */
export function proj(x: number, y: number, s: number): [number, number] {
  return [VP.x + (x - VP.x) * s, VP.y + (y - VP.y) * s]
}

/** The back-wall point behind a point drawn on a plane of scale s. */
export function toWall(x: number, y: number, s: number): [number, number] {
  return [VP.x + (x - VP.x) / s, VP.y + (y - VP.y) / s]
}

/** A repeatable number in [0, 1): every build draws the same scene. */
export function unit(n: number, salt: number): number {
  const x = Math.sin(n * 127.1 + salt * 311.7) * 43758.5453
  return x - Math.floor(x)
}

/** A short decimal for markup: one decimal place, no trailing zero. */
export function f(v: number): string {
  return String(Math.round(v * 10) / 10)
}

/** Points for a polygon or polyline. */
export function pts(points: readonly (readonly [number, number])[]): string {
  return points.map(([x, y]) => `${f(x)},${f(y)}`).join(' ')
}

/** Inches on the back-wall plane to viewBox units. */
export function inch(v: number): number {
  return v * U
}

/** What the person has switched on. Every part draws itself for any combination. */
export type State = {
  /** The television. Off: a dark tube, and no blue light anywhere. */
  tv: boolean
  /** A tape is in the deck and playing. */
  tape: boolean
  /** The game console is on; with the television on, its screen shows the console. */
  console: boolean
  /** The computer: monitor, tower lights, and the monitor glow. */
  pc: boolean
  /** The ceiling light, by the wall switch. */
  light: boolean
  /** The desk lamp. */
  lamp: boolean
  /** The lava lamp on the dresser. */
  lava: boolean
  /** plain: posters with no real person in them, the only kind drawn. */
  posters: 'plain'
  /** Titles written in the room. Absent, the made-up defaults show. */
  titles?: Titles
  /**
   * The room is drawn for the shader to run over: the console's title card stays on every screen, for the shader to
   * show while the console plays and paint over at other times. Absent, the card shows only on the console's screen.
   */
  underShader?: true
  /** The time of day and weather the hand-drawn room shows; given only while the shader setting is off. Absent, the dusk in clear weather. */
  look?: Look
}

/** The titles written in the room, kept on this machine only: the console game's on the screen, the tape's on its spine, and the pennant's two lines. */
export type Titles = { console?: string; tape?: string; pennant?: string; 'pennant-top'?: string }

/** Text made safe to write inside an SVG element or attribute. */
export function esc(text: string): string {
  return text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;')
}

export const DEFAULT_STATE: State = { tv: true, tape: false, console: false, pc: true, light: false, lamp: false, lava: false, posters: 'plain' }

/** Where a click lands on each thing, as viewBox rectangles [x, y, width, height]. Generous on purpose: a click is only known to 1/64 of the window. */
export const HITS: Record<string, readonly [number, number, number, number]> = {
  tv: [1125, 425, 166, 122],
  tape: [1125, 562, 166, 46],
  console: [1298, 490, 46, 118],
  pc: [195, 500, 150, 145],
  light: [1398, 468, 34, 50],
  lamp: [498, 530, 58, 70],
  spine: [1337, 533, 21, 69],
  lava: [1358, 470, 42, 136],
  cat: [1135, 360, 155, 62],
}
