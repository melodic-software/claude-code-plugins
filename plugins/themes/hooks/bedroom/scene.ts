import { compose } from './scene/compose.ts'
import type { State } from './scene/lib.ts'
import { part as desk } from './scene/parts/desk.ts'
import { part as dresser } from './scene/parts/dresser.ts'
import { part as room } from './scene/parts/room.ts'
import { part as tv } from './scene/parts/tv.ts'
import { part as window } from './scene/parts/window.ts'

const built = new Map<string, string>()

/** The room as one SVG, for what is switched on. dim, 0 to 1, lays a dark veil over it. */
export function bedroomSvg(state: State, dim = 0, marker = ''): string {
  const key = JSON.stringify([state, dim, marker])
  let svg = built.get(key)

  if (svg === undefined) {
    svg = compose(
      [
        ['room', room(state)],
        ['window', window(state)],
        ['dresser', dresser(state)],
        ['tv', tv(state)],
        ['desk', desk(state)],
      ],
      marker === '' ? { dim } : { dim, marker },
    )
    if (built.size > 40) {
      built.clear()
    }
    built.set(key, svg)
  }

  return svg
}
