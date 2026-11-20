import type { EngineInterface } from 'claude-code'

import { local, nowMs } from './clock.js'
import type { Ctx, Fields, Piece } from './piece.js'
import { current, save } from './saved.js'
import { settingOf } from './settings.js'
import { failedOnce, note } from './telemetry.js'
import { send, sendCue } from './values.js'

/** No piece built, no atmosphere: dusk, clear, Claude idle, the hallway still. */
const QUIET: Fields = { sun: 0, weather: 0, work: 0, zone: 0, hall: 0 }

/**
 * The pieces of this build, handed over by register with usePieces. A piece imports this file for ctxOf, and
 * pieces/index.ts imports the pieces, so nothing this file imports may import pieces/index.ts.
 */
let pieces: readonly Piece[] = []
export function usePieces(built: readonly Piece[]): void {
  pieces = built
}
/** The pieces handed over: what core/ reads a piece's fields, words, room and switched from. */
export function builtPieces(): readonly Piece[] {
  return pieces
}

/** A piece's fields; one whose fields() throws gives none, so its fields read as QUIET's. */
function fieldsOf(piece: Piece, ctx: Ctx): Partial<Fields> {
  try {
    return piece.fields?.(ctx) ?? {}
  } catch (error) {
    failedOnce(piece.name, 'fields', error)
    return {}
  }
}

/** What a piece is given, made for each hook from its `$`. */
export function ctxOf($: EngineInterface): Ctx {
  const ctx: Ctx = {
    nowMs: nowMs(),
    local: () => local(nowMs()),
    setting: key => settingOf(key, current()),
    get saved() {
      return current()
    },
    save: patch => save($, patch),
    fields: () => pieces.reduce<Fields>((all, piece) => ({ ...all, ...fieldsOf(piece, ctx) }), { ...QUIET }),
    send: (why, options) => send($, why, ctx.fields(), options),
    cue: (id, why) => sendCue($, id, why),
    note,
  }
  return ctx
}
