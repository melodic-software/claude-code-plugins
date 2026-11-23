import type { Ctx, Piece } from '../core/piece.js'
import { PHASES, SEASONS, SEASON_DATES, accepts, minutesOf } from '../core/settings.js'

/**
 * The time of day: the sun field from the local time, the sunrise and sunset settings and a stored /bedroom time, and
 * the command that holds a phase. The VCR clock always shows the real time.
 */
const DAY = 24 * 60
const ALIASES: Record<string, (typeof PHASES)[number]> = { late: 'night', midday: 'noon', afternoon: 'noon' }

/** Where each row starts, in minutes of the day, in row order: dusk at sunset, evening, night, predawn, dawn, morning, noon at 11:00, golden. */
export function rowStarts(sunrise: number, sunset: number): number[] {
  return [sunset, sunset + 75, sunset + 150, sunrise - 75, sunrise - 20, sunrise + 40, 11 * 60, sunset - 90].map(start => (start + DAY) % DAY)
}

/** The row at a minute of the day: the one that started last, round midnight. */
export function rowAt(minute: number, sunrise: number, sunset: number): number {
  const since = rowStarts(sunrise, sunset).map(start => (minute - start + DAY) % DAY)
  return since.indexOf(Math.min(...since))
}

/** A word of /bedroom time as the phase it holds: auto, a phase or its alias, or HH:MM read with these settings. */
export function phaseOf(word: string, sunrise: number, sunset: number): string | undefined {
  if (word === 'auto' || (PHASES as readonly string[]).includes(word)) return word
  if (word in ALIASES) return ALIASES[word]
  const clock = /^(\d{1,2}):(\d\d)$/.exec(word)
  if (clock === null || Number(clock[1]) > 23 || Number(clock[2]) > 59) return undefined
  return PHASES[rowAt(Number(clock[1]) * 60 + Number(clock[2]), sunrise, sunset)]
}

/** The latitude `auto` sunrise and sunset are worked out for, in degrees north; the room asks for no location. */
export const LATITUDE = 40

/**
 * Sunrise and sunset in minutes of the local day for the date of `ms`, at LATITUDE: the sun's declination from the day
 * of the year, with the orbit's eccentricity (https://en.wikipedia.org/wiki/Position_of_the_Sun#Declination_of_the_Sun_as_seen_from_Earth), the hour angle at which its top meets the horizon (refraction 0.833 degrees), about
 * solar noon at 12:00 standard time. The clock's daylight saving time on that date, against the year's standard offset,
 * moves both. A zone whose January offset is ahead of its July offset keeps southern daylight saving time, so the
 * season is turned for it; a zone without daylight saving time reads as northern.
 */
export function seasonOf(ms: number): { sunrise: number; sunset: number } {
  const date = new Date(ms)
  const year = date.getFullYear()
  const jan = new Date(year, 0, 1).getTimezoneOffset()
  const jul = new Date(year, 6, 1).getTimezoneOffset()
  const day = Math.round((Date.UTC(year, date.getMonth(), date.getDate()) - Date.UTC(year, 0, 1)) / 86_400_000) + 1
  const rad = Math.PI / 180
  const orbit = (360 / 365.24) * rad
  const declination = Math.asin(-Math.sin(23.44 * rad) * Math.cos(orbit * (day + 9.5) + 2 * 0.0167 * Math.sin(orbit * (day - 2.5))))
  const latitude = (jan < jul ? -LATITUDE : LATITUDE) * rad
  const cos = (Math.sin(-0.833 * rad) - Math.sin(latitude) * Math.sin(declination)) / (Math.cos(latitude) * Math.cos(declination))
  const half = (Math.acos(Math.min(1, Math.max(-1, cos))) / rad) * 4
  const noon = 12 * 60 + Math.max(jan, jul) - new Date(year, date.getMonth(), date.getDate(), 12).getTimezoneOffset()
  return { sunrise: Math.round(noon - half), sunset: Math.round(noon + half) }
}

/**
 * The room's date, as noon of that day in milliseconds on the local clock: the real date under `/bedroom date auto`, else
 * the day held (MM-DD, or a season's) in the real date's year. Everything seasonal reads the date from here; the clock's
 * hours and the VCR keep the real time.
 */
export function roomDate(ctx: Ctx): number {
  const held = ctx.setting('date')
  if (held === 'auto') return ctx.nowMs
  const monthDay = held in SEASON_DATES ? SEASON_DATES[held as keyof typeof SEASON_DATES] : held
  return new Date(new Date(ctx.nowMs).getFullYear(), Number(monthDay.slice(0, 2)) - 1, Number(monthDay.slice(3, 5)), 12).getTime()
}

/** Sunrise and sunset now, in minutes of the day: a setting's HH:MM all year, or `auto`'s for the room's date. */
export function sunTimes(ctx: Ctx): [number, number] {
  const season = seasonOf(roomDate(ctx))
  const rise = ctx.setting('sunrise')
  const set = ctx.setting('sunset')
  return [rise === 'auto' ? season.sunrise : minutesOf(rise), set === 'auto' ? season.sunset : minutesOf(set)]
}
const hhmm = (minute: number): string => `${String(Math.floor(minute / 60)).padStart(2, '0')}:${String(minute % 60).padStart(2, '0')}`

/** The row now: the phase held, or the one the clock gives. */
export function sunOf(ctx: Ctx): number {
  const held = ctx.setting('time')
  if (held !== 'auto') return PHASES.indexOf(held as (typeof PHASES)[number])
  const { hours, minutes } = ctx.local()
  return rowAt(hours * 60 + minutes, ...sunTimes(ctx))
}

async function time(ctx: Ctx, args: readonly string[]): Promise<string> {
  const word = (args[0] ?? '').toLowerCase()
  if (word === '') {
    const held = ctx.setting('time')
    const now = PHASES[sunOf(ctx)]
    const [rise, set] = sunTimes(ctx)
    const told = (key: 'sunrise' | 'sunset', minute: number): string => `${key} ${hhmm(minute)}${ctx.setting(key) === 'auto' ? ' (the season)' : ''}`
    return `${held === 'auto' ? `the room follows the clock, ${now} now` : `the room holds ${now}`}; ${told('sunrise', rise)}, ${told('sunset', set)}. Say /bedroom time auto, a phase (${PHASES.join(', ')}) or a time as HH:MM`
  }
  const phase = phaseOf(word, ...sunTimes(ctx))
  if (phase === undefined) return `say auto, a phase (${PHASES.join(', ')}, or late, midday, afternoon) or a time as HH:MM, as in /bedroom time noon or /bedroom time 14:30`
  await ctx.save({ time: phase })
  await ctx.send(`/bedroom time ${word}`, { hurry: true })
  if (phase === 'auto') return `the room follows the clock: ${PHASES[sunOf(ctx)]} now`
  return `the room holds ${phase}${word === phase ? '' : ` (${word})`} until /bedroom time auto; the VCR still shows the real time`
}

const DATE_USAGE = `say auto, a day as MM-DD or a season (${SEASONS.map(season => `${season} ${SEASON_DATES[season]}`).join(', ')}), as in /bedroom date 06-21`

/** /bedroom date: holds the room on a day of the year, or follows the real date; alone, says which. */
async function date(ctx: Ctx, args: readonly string[]): Promise<string> {
  const word = (args[0] ?? '').toLowerCase()
  const told = (): string => {
    const held = ctx.setting('date')
    const day = new Date(roomDate(ctx))
    const shown = `${String(day.getMonth() + 1).padStart(2, '0')}-${String(day.getDate()).padStart(2, '0')}`
    const [rise, set] = sunTimes(ctx)
    const why = held === 'auto' ? 'the real date' : held in SEASON_DATES ? `held for ${held} until /bedroom date auto` : 'held until /bedroom date auto'
    return `the room is on ${shown}, ${why}; sunrise ${hhmm(rise)}, sunset ${hhmm(set)}; the VCR still shows the real time`
  }
  if (word === '') return told()
  if (!accepts('date', word)) return DATE_USAGE
  await ctx.save({ date: word })
  await ctx.send(`/bedroom date ${word}`, { hurry: true })
  return told()
}

export const piece: Piece = {
  name: 'time',
  fields: ctx => ({ sun: sunOf(ctx) }),
  commands: { time, date },
}
