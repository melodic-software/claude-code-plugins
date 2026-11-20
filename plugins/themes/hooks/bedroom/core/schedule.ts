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
