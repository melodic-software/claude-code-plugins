import { ACCEPT, EVENTS, HURRY, STRIKE } from './signals.gen.js'

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

let shaderFrom: number | undefined
/** Notes when the shader starts or is due to start (milliseconds on the mod's clock), or that none is. */
export function noteShaderStart(at: number | undefined): void {
  shaderFrom = at
}

/** When the shader started, or undefined while none runs: its own events start again from nothing then. */
export function shaderStartedAt(): number | undefined {
  return shaderFrom
}

/** From a hurry flip sent to the shader taking it: the app eases screen about 510 ms after the redraw, then holds ACCEPT.screen s. */
const HURRY_TAKEN_MS = 510 + ACCEPT.screen * 1000

/**
 * Whether the shader runs one of its own timed events (a scheduled strike, the hallway's pass or light) that falls at
 * `at`: it runs none in its first EVENTS.after seconds, nor for HURRY.seconds after it takes the hurry flip sent at
 * `hurrySentAt`.
 */
export function scheduledEventShows(at: number, hurrySentAt: number): boolean {
  if (shaderFrom === undefined || at < shaderFrom + EVENTS.after * 1000) return false
  return at >= hurrySentAt + HURRY_TAKEN_MS + HURRY.seconds * 1000
}

/**
 * Margin for the app starting the shader after the mod draws it, which no test has measured: a cue is answered as ready
 * this long after EVENTS.after has run out on the mod's clock.
 */
export const CUE_START_SLACK_MS = 5000

/**
 * Why a cue sent now would show nothing, with when it can: the shader draws every cue's event, and in its first
 * EVENTS.after seconds it takes none, so a cue sent then is lost. Undefined when the shader takes it.
 */
export function cueRefusal(now: number): string | undefined {
  if (shaderFrom === undefined) return 'the shader is not running, and only the shader draws it: say /bedroom shader on'
  const ready = shaderFrom + EVENTS.after * 1000 + CUE_START_SLACK_MS
  if (now >= ready) return undefined
  return `the shader takes nothing in its first ${EVENTS.after} s after it starts, and it ${now < shaderFrom ? 'has not started again yet' : 'started just now'}: try again in ${Math.ceil((ready - now) / 1000)} s`
}
