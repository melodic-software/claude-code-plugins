import type { On } from 'claude-code'

import type { Saved } from './saved.js'
import type { SettingKey, SettingValue } from './settings.js'

export type { On }
export const SWITCHES = ['tv', 'tape', 'console', 'pc', 'light', 'lamp', 'lava'] as const
export type Switch = (typeof SWITCHES)[number]

/** The atmosphere the shader is sent, coded in its `world` and `screen` values. */
export type Fields = { sun: number; weather: number; work: number; zone: number; hall: number }

/** Local time, from the cached clock: hours 0 to 23, minutes, day of the year from 1, and the year. */
export type Local = { hours: number; minutes: number; day: number; year: number }

/**
 * What a piece is given. It holds no `$`: validate refuses `$` put in an object. A piece that calls the engine does so
 * in its own hooks, where each hook gets `$`, and makes a Ctx there with ctxOf($).
 */
export type Ctx = {
  /** Milliseconds since the epoch, read from $.clock before this hook ran. */
  readonly nowMs: number
  local: () => Local
  setting: <K extends SettingKey>(key: K) => SettingValue<K>
  readonly saved: Saved
  save: (patch: Partial<Saved>) => Promise<void>
  /** The fields every piece gives now, merged. */
  fields: () => Fields
  /**
   * Rebuilds world and screen from the fields and asks for a redraw, within the send limits of core/values.ts. hurry:
   * the change comes from a command, so the shader moves to it fast. stalled: the minute tick came late.
   */
  send: (cause: string, options?: { hurry?: boolean; stalled?: boolean }) => Promise<void>
  /** A line in the debug log. */
  note: (line: string) => void
}

/**
 * One piece of the bedroom: what it gives through this object needs no engine call. validate follows `on` and `$` only
 * through named functions of the module's own, and refuses a second registration of an event the core hooks
 * (session.start, ui.render, ui.pointer, command.run for bedroom) without a matcher of its own. So a piece that needs
 * them exports, beside `piece`, any of these from its own file, and the generated pieces/index.ts calls them:
 *   export function hooks(on: On): void                                   inside register: hooks on other events
 *   export async function engineStart($, ctx): Promise<void>               at session.start
 *   export async function engineTick($, ctx): Promise<void>                each minute
 *   export function engineSwitched($, ctx, name, isOn, by): void           after a switch changed
 *   export async function engineCommand($, ctx, word, args): Promise<string | undefined>   its own words
 * pieces/index.ts imports every piece, so a piece imports nothing that imports pieces/index.ts: not ./index.js itself
 * (BUILT and WITHOUT are in core/signals.gen.js), and of core/, not clicks.js, commands.js or switched.js.
 */
export type Piece = {
  name: string
  /** The fields this piece owns; called whenever `world` and `screen` are rebuilt. */
  fields?: (ctx: Ctx) => Partial<Fields>
  /** `/bedroom <word> ...`: the reply text. */
  commands?: Record<string, (ctx: Ctx, args: readonly string[]) => string | Promise<string>>
  /** Each minute, before the redraw is asked. */
  tick?: (ctx: Ctx) => void | Promise<void>
  /** After a switch changed by a click or a command. */
  switched?: (ctx: Ctx, name: Switch, isOn: boolean, by: 'click' | 'command') => void
  /** What the hand-drawn room should show; read only while the shader setting is off. */
  room?: (ctx: Ctx) => { sun: number; weather: number } | undefined
}

/** What a piece's command answers when the piece is left out of the build. */
export const NOT_BUILT = 'not in this build'
