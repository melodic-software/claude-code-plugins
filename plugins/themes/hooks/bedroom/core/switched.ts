import type { EngineInterface } from 'claude-code'

import { switchedPieces } from '../pieces/index.js'
import { builtPieces } from './context.js'
import type { Ctx, Switch } from './piece.js'
import { failed } from './telemetry.js'

/** Tells every piece a switch changed; one that throws is noted and passed over. It imports pieces/index.ts, so no piece may import it. */
export function switched($: EngineInterface, ctx: Ctx, name: Switch, isOn: boolean, by: 'click' | 'command'): void {
  for (const piece of builtPieces()) {
    try {
      piece.switched?.(ctx, name, isOn, by)
    } catch (error) {
      failed(piece.name, 'switched', error)
    }
  }
  switchedPieces($, ctx, name, isOn, by)
}
