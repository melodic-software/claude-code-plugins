import type { Part } from './lib.ts'

/** Draw order of the parts' bodies. A room shell (room or stub) comes first and its `over` comes last. */
export const ORDER = ['room', 'stub', 'guides', 'window', 'dresser', 'tv', 'desk']

/** Character budget of each part: style, defs, under, body and over together. The engine refuses a scene over 131072. */
export const BUDGET: Record<string, number> = { room: 19000, window: 26000, dresser: 23500, tv: 34000, desk: 29000 }

export const LIMIT = 131072

export type ComposeOptions = {
  /** 0 to 1: a dark veil over the whole scene, so the room sits further back behind the chat. */
  dim?: number
  /** A viewBox other than the whole scene, for a zoomed look at one area. */
  viewBox?: string
  /** `meet` for a zoomed look; the app always uses `slice`. */
  fit?: 'slice' | 'meet'
  /**
   * A color for a small square at the very center of the scene, drawn last. The mod's shader reads it to tell
   * which room it has been handed, and paints over it, so it shows only where no shader plays.
   */
  marker?: string
}

export function partSize(part: Part): number {
  return (part.style ?? '').length + (part.defs ?? '').length + (part.under ?? '').length + (part.body ?? '').length + (part.over ?? '').length
}

export function compose(parts: readonly (readonly [string, Part])[], options: ComposeOptions = {}): string {
  const sorted = [...parts].sort((a, b) => ORDER.indexOf(a[0]) - ORDER.indexOf(b[0]))
  const shells = sorted.filter(([key]) => key === 'room' || key === 'stub')
  const rest = sorted.filter(([key]) => key !== 'room' && key !== 'stub')
  const pick = (list: typeof sorted, field: keyof Part): string =>
    list.map(([key, part]) => (part[field] ? `<g id="${key}-${field}">${part[field]}</g>` : '')).join('')
  const dim = options.dim ?? 0
  const veil = dim > 0 ? `<rect width="1600" height="1000" fill="#07080f" opacity="${dim}"/>` : ''

  return (
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${options.viewBox ?? '0 0 1600 1000'}" preserveAspectRatio="xMidYMid ${options.fit ?? 'slice'}">` +
    `<style>${sorted.map(([, part]) => part.style ?? '').join('')}</style>` +
    `<defs>${sorted.map(([, part]) => part.defs ?? '').join('')}</defs>` +
    pick(shells, 'body') +
    pick(rest, 'under') +
    pick(rest, 'body') +
    pick(rest, 'over') +
    pick(shells, 'over') +
    veil +
    (options.marker ? `<rect x="797" y="497" width="6" height="6" fill="${options.marker}"/>` : '') +
    `</svg>`
  )
}
