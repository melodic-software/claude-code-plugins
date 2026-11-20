import type { EngineInterface } from 'claude-code'

import { minuteOfHalfDay } from '../core/clock.js'
import { ctxOf } from '../core/context.js'
import type { Ctx, Piece, Switch } from '../core/piece.js'
import { strike } from '../core/schedule.js'
import { BUILT, WITHOUT } from '../core/signals.gen.js'
import { flush } from '../core/telemetry.js'

/**
 * Sound: the television's click and fuzz, cicadas at dusk and night in dry weather, rain, and thunder after a scheduled
 * strike, off by default; /bedroom sound. Nothing here calls the engine while sound is off. Each file in
 * sounds/bedroom is made by code (no recording) and listed with its length in ms.
 */
export const LENGTH_MS = {
  'tv-on': 1200,
  'tv-off': 900,
  cicadas: 24000,
  rain: 26000,
  'thunder-1': 6000,
  'thunder-2': 7500,
  'thunder-3': 5000,
  silence: 400,
} as const
export type Sound = keyof typeof LENGTH_MS
type Loop = 'cicadas' | 'rain'

/** How long a player may run past its file's length: the default 30 s would cut a long clip. */
const SLACK_MS = 15_000
export const timeoutOf = (sound: Sound): number => LENGTH_MS[sound] + SLACK_MS

/** The players looked for on PATH when the soundPlayer setting is empty, in this order. */
export const PLAYERS = ['powershell.exe', 'ffplay', 'paplay', 'aplay'] as const
export type PlayerName = (typeof PLAYERS)[number]

/** A found player's argument list for a file, the path as that player reads it. */
export function argvOf(name: PlayerName, file: string): string[] {
  if (name === 'powershell.exe') {
    return [name, '-NoProfile', '-NonInteractive', '-Command', `(New-Object System.Media.SoundPlayer '${file.replaceAll("'", "''")}').PlaySync()`]
  }
  if (name === 'ffplay') return [name, '-nodisp', '-autoexit', '-loglevel', 'quiet', file]
  if (name === 'aplay') return [name, '-q', file]
  return [name, file]
}

/** The soundPlayer setting's command line for a file: {file} replaced, or the file put last when it names none. */
export function commandLineOf(command: string, file: string): string[] {
  const words = command.trim().split(/\s+/)
  return words.includes('{file}') ? words.map(word => (word === '{file}' ? file : word)) : [...words, file]
}

/** How a sound is played: the engine's own player (macOS), or a command run once per play. */
type Player = { name: string; argv?: (file: string) => string[] }

/** Thunder follows the lightning, so it sounds only where the build draws lightning. */
const THUNDERS = BUILT.includes('weather') && !WITHOUT.includes('weather.lightning')

let finding: Promise<Player | undefined> | undefined
/** Set when a play failed: nothing plays until /bedroom sound on looks for the player again. */
let failure: string | undefined
const looping = new Set<Loop>()
let tvPlaying = false
/** The minute chain this copy ticks under; a newer one held in $.state means this copy was reloaded. */
let chain: number | undefined

/** The loops the room wants now: rain in rain, downpour and storm; cicadas from dusk through night when dry. */
function wanted(ctx: Ctx): Loop[] {
  if (!ctx.setting('sound')) return []
  const { sun, weather } = ctx.fields()
  if (weather >= 2) return ['rain']
  return sun <= 2 ? ['cicadas'] : []
}

async function onPath($: EngineInterface, dirs: readonly string[], name: string): Promise<boolean> {
  for (const dir of dirs) if (await $.fs.exists(`${dir.replace(/\/$/, '')}/${name}`)) return true
  return false
}

/** Finds the player; under WSL, Windows' player reads the file by its Windows path. */
async function find($: EngineInterface): Promise<Player | undefined> {
  const { platform } = await $.session.info()
  if (platform === 'macos') return { name: 'the engine (afplay)' }
  const folder = `${$.plugin.root}/sounds/bedroom`
  const command = ctxOf($).setting('soundPlayer').trim()
  if (command !== '') return { name: command.split(/\s+/)[0] ?? command, argv: file => commandLineOf(command, `${folder}/${file}`) }
  const dirs = ((await $.env.get('PATH')) ?? '').split(platform === 'windows' ? ';' : ':').filter(dir => dir !== '')
  for (const name of PLAYERS) {
    if (!(await onPath($, dirs, name))) continue
    if (name !== 'powershell.exe' || platform === 'windows') return { name, argv: file => argvOf(name, `${folder}/${file}`) }
    if (platform !== 'wsl' || !(await onPath($, dirs, 'wslpath'))) continue
    const converted = await $.process.run(['wslpath', '-w', folder])
    const windows = converted.stdout.trim()
    if (converted.exitCode === 0 && windows !== '') return { name, argv: file => argvOf(name, `${windows}\\${file}`) }
  }
  return undefined
}

/** Looks for the player again, forgetting a failure. */
function lookAgain($: EngineInterface): Promise<Player | undefined> {
  failure = undefined
  finding = find($).catch(error => {
    stop($, `looking for a player failed: ${error instanceof Error ? error.message : String(error)}`)
    return undefined
  })
  return finding
}

/** One line in the debug log, and no sound until /bedroom sound on. */
function stop($: EngineInterface, why: string): void {
  if (failure !== undefined) return
  failure = why
  ctxOf($).note(`sound: ${why}; nothing plays until /bedroom sound on`)
  flush($)
}

/** The player while sound is on and none has failed; looked for once. */
async function ready($: EngineInterface): Promise<Player | undefined> {
  if (!ctxOf($).setting('sound') || failure !== undefined) return undefined
  const player = await (finding ?? lookAgain($))
  if (player === undefined) stop($, 'no player was found')
  return failure === undefined ? player : undefined
}

/** Plays a file once and resolves when the player has exited; a player that fails stops all sound. */
async function playOnce($: EngineInterface, player: Player, sound: Sound): Promise<boolean> {
  try {
    if (player.argv === undefined) {
      await $.audio.play({ asset: `sounds/bedroom/${sound}.wav` })
      return true
    }
    const { exitCode, stderr } = await $.process.run(player.argv(`${sound}.wav`), { timeoutMs: timeoutOf(sound) })
    if (exitCode === 0) return true
    stop($, `${player.name} exited ${exitCode} playing ${sound}${stderr.trim() === '' ? '' : `: ${stderr.trim().slice(0, 160)}`}`)
  } catch (error) {
    stop($, `${player.name} failed playing ${sound}: ${error instanceof Error ? error.message : String(error)}`)
  }
  return false
}

async function playWhenReady($: EngineInterface, sound: Sound): Promise<void> {
  const player = await ready($)
  if (player !== undefined) await playOnce($, player, sound)
}

async function reloaded($: EngineInterface): Promise<boolean> {
  if (chain === undefined) return false
  const { value } = await $.state.get({ plugin: 'themes', key: 'bedroom-chain' })
  return value !== undefined && value > chain
}

/**
 * A loop is a chain of single plays: the next starts only while the loop is still wanted, and not before the last
 * one's length has passed, so a player that returns at once cannot spin. Nothing is left running if the module reloads.
 */
async function loop($: EngineInterface, name: Loop): Promise<void> {
  looping.add(name)
  try {
    while (wanted(ctxOf($)).includes(name) && !(await reloaded($))) {
      const player = await ready($)
      if (player === undefined) return
      const startedAt = await $.clock.now()
      if (!(await playOnce($, player, name))) return
      const rest = LENGTH_MS[name] - ((await $.clock.now()) - startedAt)
      if (rest > 0) await new Promise<void>(resolve => void $.clock.after(rest, resolve))
    }
  } finally {
    looping.delete(name)
  }
}

function startLoops($: EngineInterface, ctx: Ctx): void {
  for (const name of wanted(ctx)) if (!looping.has(name)) void loop($, name).catch(error => stop($, `the ${name} loop failed: ${String(error)}`))
}

/**
 * From the tick to the shader taking the minute it sends: the app starts easing a value about 510 ms after a redraw
 * is asked, and the clock column takes a minute once it has stood still 0.4 s. The ease itself is not counted, so
 * thunder errs late.
 */
export const TAKEN_MS = 910

/** In a storm, thunder 1 to 4 s after this minute's strike, counted from when the shader takes the minute. */
async function thunderAfterStrike($: EngineInterface, ctx: Ctx): Promise<void> {
  if (!THUNDERS || ctx.fields().weather !== 4) return
  const minute = minuteOfHalfDay(ctx.nowMs)
  const at = strike(minute)
  if (at === undefined) return
  const due = ctx.nowMs + TAKEN_MS + at * 1000 + 1000 + ((minute * 7919) % 3001)
  const sound: Sound = minute % 3 === 0 ? 'thunder-1' : minute % 3 === 1 ? 'thunder-2' : 'thunder-3'
  $.clock.after(Math.max(due - (await $.clock.now()), 0), () => {
    if (ctxOf($).fields().weather === 4) void playWhenReady($, sound).catch(error => stop($, `thunder failed: ${String(error)}`))
  })
}

export const piece: Piece = { name: 'sound' }

async function minute($: EngineInterface, ctx: Ctx): Promise<void> {
  chain = (await $.state.get({ plugin: 'themes', key: 'bedroom-chain' })).value
  if ((await ready($)) === undefined) return
  startLoops($, ctx)
  await thunderAfterStrike($, ctx)
}

/** Not awaited by the minute: looking for a player must not hold the clock's redraw. */
export async function engineTick($: EngineInterface, ctx: Ctx): Promise<void> {
  if (ctx.setting('sound')) void minute($, ctx).catch(error => stop($, `the minute's sound failed: ${String(error)}`))
}

export function engineSwitched($: EngineInterface, ctx: Ctx, name: Switch, isOn: boolean, _by: 'click' | 'command'): void {
  if (name !== 'tv' || tvPlaying || !ctx.setting('sound')) return
  tvPlaying = true
  void playWhenReady($, isOn ? 'tv-on' : 'tv-off')
    .catch(error => stop($, `the television's sound failed: ${String(error)}`))
    .finally(() => {
      tvPlaying = false
    })
}

/** /bedroom sound on|off|test; test plays only the silent file, and looks without forgetting a failure. */
export async function engineCommand($: EngineInterface, ctx: Ctx, word: string, args: readonly string[]): Promise<string | undefined> {
  if (word !== 'sound') return undefined
  const what = (args[0] ?? '').toLowerCase()
  const none = `no player was found (looked for ${PLAYERS.join(', ')} on PATH; the soundPlayer setting names one, with {file} for the file)`
  try {
    if (what === 'off') {
      await ctx.save({ sound: false })
      return 'sound is off: a clip playing now ends, and nothing starts after it'
    }
    if (what === 'on') {
      const player = await lookAgain($)
      if (player === undefined) return `${none}, so sound stays off`
      await ctx.save({ sound: true })
      chain = (await $.state.get({ plugin: 'themes', key: 'bedroom-chain' })).value
      startLoops($, ctxOf($))
      return `sound is on, played by ${player.name}: the television, cicadas from dusk through night in dry weather, rain${THUNDERS ? ', and thunder in a storm' : ''}`
    }
    if (what === 'test') {
      const player = await find($)
      if (player === undefined) return none
      if (player.argv === undefined) {
        await $.audio.play({ asset: 'sounds/bedroom/silence.wav' })
        return `${player.name} played silence.wav`
      }
      const { exitCode } = await $.process.run(player.argv('silence.wav'), { timeoutMs: timeoutOf('silence') })
      return `${player.name} played silence.wav and exited ${exitCode}`
    }
    if (what !== '') return 'say on, off or test, as in /bedroom sound on'
    const player = finding === undefined ? 'not looked for yet' : ((await finding)?.name ?? 'none found')
    return `sound is ${ctx.setting('sound') ? 'on' : 'off'}. player: ${player}${failure === undefined ? '' : `, stopped: ${failure}`}. Say on, off or test`
  } catch (error) {
    return `sound could not answer: ${error instanceof Error ? error.message : String(error)}`
  }
}
