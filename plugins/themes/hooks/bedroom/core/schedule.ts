import { STRIKE } from './signals.gen.js'

/**
 * The one storm schedule the mod and the shader share: a strike in a minute where (minute * every + shift) mod modulo
 * < below, at beatBase + (minute * beatEvery + beatShift) mod beatModulo seconds after the minute is taken. The
 * shader's weather column runs the same integers on the VCR minute. Answers the seconds into the minute of its strike,
 * or undefined for a minute without one; minute is 0 to 719.
 */
export function strike(minute: number): number | undefined {
  if ((minute * STRIKE.every + STRIKE.shift) % STRIKE.modulo >= STRIKE.below) return undefined
  return STRIKE.beatBase + ((minute * STRIKE.beatEvery + STRIKE.beatShift) % STRIKE.beatModulo)
}

/**
 * How long after its cue is sent a strike asked for with /bedroom weather strike shows: the app's delay and ease, then
 * the shader's 2.5 s hold. Thunder belongs 1 to 4 s after that.
 */
export const STRIKE_SHOWS_MS = 4500
/** The fewest milliseconds between two strikes asked for. */
export const STRIKE_GAP_MS = 20_000

let forced: number | undefined
/** Notes that a strike was asked for and its cue sent `delay` ms from `now`; answers when it should show. */
export function noteForcedStrike(now: number, delay: number): number {
  forced = now + delay + STRIKE_SHOWS_MS
  return forced
}
/**
 * When the last strike asked for shows (milliseconds since the epoch, on the mod's clock), or undefined if none was
 * asked for since the mod loaded. The sound piece plays its thunder 1 to 4 s after this.
 */
export function forcedStrikeAt(): number | undefined {
  return forced
}
