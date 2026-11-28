import type { EngineInterface } from 'claude-code'

import { local, nowMs } from './clock.js'
import type { Ctx, Fields, Piece } from './piece.js'
import { current, save } from './saved.js'
import { settingOf } from './settings.js'
import { failedOnce, note } from './telemetry.js'
import { send, sendCue } from './values.js'

const QUIET: Fields = { sun: 0, weather: 0, work: 0, zone: 0, hall: 0 }

let pieces: readonly Piece[] = []
export function usePieces(built: readonly Piece[]): void {
  pieces = built
}
/** The pieces handed over: what core/ reads a piece's fields, words, room and switched from. */
export function builtPieces(): readonly Piece[] {
  return pieces
}

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
