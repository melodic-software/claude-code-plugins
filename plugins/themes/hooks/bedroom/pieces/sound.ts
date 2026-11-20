import type { EngineInterface } from 'claude-code'

import { minuteOfHalfDay } from '../core/clock.js'
import { ctxOf } from '../core/context.js'
import type { Ctx, Piece, Switch } from '../core/piece.js'
import { volumeOf, type Saved } from '../core/saved.js'
import { strike } from '../core/schedule.js'
import { BUILT, WITHOUT } from '../core/signals.gen.js'
import { flush } from '../core/telemetry.js'

/**
 * Sound: the television's click, cicadas at dusk and night in dry weather, rain, a downpour, a storm, and thunder after a
 * scheduled strike, off by default; /bedroom sound. Nothing here calls the engine while sound is off. The loops and the
 * thunder are cut from recordings (sounds/bedroom/SOURCES.md), two to choose from for each kind; the television's are
 * made by code. Each file is listed with its length in ms.
 */
export const LENGTH_MS = {
  'tv-on': 1400,
  'tv-off': 1100,
  'cicadas-1': 20000,
  'cicadas-2': 20000,
  'rain-1': 20000,
  'rain-2': 20000,
  'downpour-1': 20000,
  'downpour-2': 20000,
  'storm-1': 20000,
  'storm-2': 20000,
  'thunder-1-1': 8000,
  'thunder-1-2': 8000,
  'thunder-1-3': 8000,
  'thunder-2-1': 8000,
  'thunder-2-2': 8000,
  'thunder-2-3': 8000,
  silence: 400,
} as const
export type Sound = keyof typeof LENGTH_MS

/** The loops, one at a time: cicadas when dry, and one for each wet weather, heavier in turn. */
export const LOOPS = ['cicadas', 'rain', 'downpour', 'storm'] as const
export type Loop = (typeof LOOPS)[number]
/** The kinds with two recordings to choose between, by ear. */
export const KINDS = [...LOOPS, 'thunder'] as const
export type Kind = (typeof KINDS)[number]
/** The chosen recording of a kind: 1 unless 2 is saved. */
export const pickOf = (saved: Saved, kind: Kind): 1 | 2 => (saved.picks?.[kind] === 2 ? 2 : 1)
/** A volume as the gain a player takes, 0 to 1: squared, so each step sounds about as far as the last. */
export const gainOf = (volume: number): number => (Math.min(100, Math.max(0, volume)) / 100) ** 2

/** How long a player may run past its file's length: a run that never ends is a player stuck, not a sound. */
const SLACK_MS = 15_000
export const timeoutOf = (sound: Sound): number => LENGTH_MS[sound] + SLACK_MS

/** The players looked for on PATH when the soundPlayer setting is empty, in this order. */
export const PLAYERS = ['powershell.exe', 'ffplay', 'paplay', 'aplay'] as const
export type PlayerName = (typeof PLAYERS)[number]

/** How often the Windows player writes a dot, in ms: a pull on its output never waits longer, so a stop lands that soon. */
export const BEAT_MS = 200

/**
 * The Windows player: WPF's MediaPlayer at the gain, writing a dot every BEAT_MS while it plays. A loop starts the file
 * again when its position reaches the end. It exits 3 when the file does not open in 5 s.
 */
export function windowsScript(file: string, gain: number, loop: boolean): string {
  return [
    "$ErrorActionPreference='Stop'",
    'Add-Type -AssemblyName PresentationCore',
    '$p=New-Object System.Windows.Media.MediaPlayer',
    `$p.Volume=${gain.toFixed(4)}`,
    `$p.Open([Uri]'${file.replaceAll("'", "''")}')`,
    '$w=[Diagnostics.Stopwatch]::StartNew()',
    'while(-not $p.NaturalDuration.HasTimeSpan -and $w.ElapsedMilliseconds -lt 5000){Start-Sleep -Milliseconds 20}',
    "if(-not $p.NaturalDuration.HasTimeSpan){[Console]::Error.Write('the file did not open');exit 3}",
    '$d=$p.NaturalDuration.TimeSpan.TotalMilliseconds',
    '$p.Play()',
    '$w.Restart()',
    `while($true){try{[Console]::Out.Write('.');[Console]::Out.Flush()}catch{break};$at=$p.Position.TotalMilliseconds;if($at -le 0){$at=$w.ElapsedMilliseconds};$left=$d-$at;if($left -le 15){if(${loop ? '$true' : '$false'}){$p.Position=[TimeSpan]::Zero;$p.Play();$w.Restart();continue};break};Start-Sleep -Milliseconds ([Math]::Min(${BEAT_MS},[Math]::Max(1,[int]$left-10)))}`,
    '$p.Close()',
  ].join(';')
}

/** A found player's argument list for a file, the path as that player reads it; `loops` when it repeats the file itself. */
export function argvOf(name: PlayerName, file: string, gain: number, loop: boolean): string[] {
  if (name === 'powershell.exe') return [name, '-NoProfile', '-NonInteractive', '-Command', windowsScript(file, gain, loop)]
  if (name === 'ffplay') return [name, '-nodisp', '-autoexit', '-loglevel', 'quiet', '-stats', '-volume', String(Math.round(gain * 100)), ...(loop ? ['-loop', '0'] : []), file]
  if (name === 'paplay') return [name, '--verbose', `--volume=${Math.round(gain * 65536)}`, file]
  return [name, '-V', 'mono', file]
}
const LOOPING: readonly string[] = ['powershell.exe', 'ffplay']

/** The soundPlayer setting's command line for a file: {file} and {volume} (0 to 100) replaced, or the file put last when it names none. */
export function commandLineOf(command: string, file: string, gain = 1): string[] {
  const words = command.trim().split(/\s+/)
  const filled = words.map(word => word.replaceAll('{file}', file).replaceAll('{volume}', String(Math.round(gain * 100))))
  return words.some(word => word.includes('{file}')) ? filled : [...filled, file]
}

/** How a sound is played: the engine's own player (macOS), or a command started for each play, which may repeat a loop itself. */
type Player = { name: string; argv?: (file: string, gain: number, loop: boolean) => string[]; loops: boolean }

/** Thunder follows the lightning, so it sounds only where the build draws lightning. */
const THUNDERS = BUILT.includes('weather') && !WITHOUT.includes('weather.lightning')

let finding: Promise<Player | undefined> | undefined
/** Set when a play failed: nothing plays until /bedroom sound on looks for the player again. */
let failure: string | undefined
/** One play, the loop's or a single sound's; stop() ends it at once. */
type Play = { stopped: boolean; end?: () => void; stop: () => void }
const playing = new Set<Play>()
/** The loop playing now, by file and volume, so a change of either starts it over. */
let loop: { key: string; play: Play } | undefined
let tvPlaying = false
/** The minute chain this copy ticks under; a newer one held in $.state means this copy was reloaded. */
let chain: number | undefined

const newPlay = (): Play => {
  const play: Play = {
    stopped: false,
    stop: () => {
      play.stopped = true
      play.end?.()
    },
  }
  return play
}

/** The loop the room wants now: one weather's in rain, downpour and storm; cicadas from dusk through night when dry. */
export function wanted(ctx: Ctx): Loop | undefined {
  if (!ctx.setting('sound') || volumeOf(ctx.saved) === 0) return undefined
  const { sun, weather } = ctx.fields()
  if (weather >= 2) return weather === 2 ? 'rain' : weather === 3 ? 'downpour' : 'storm'
  return sun <= 2 ? 'cicadas' : undefined
}

async function onPath($: EngineInterface, dirs: readonly string[], name: string): Promise<boolean> {
  for (const dir of dirs) if (await $.fs.exists(`${dir.replace(/\/$/, '')}/${name}`)) return true
  return false
}

/** Finds the player; under WSL, Windows' player reads the file by its Windows path. */
async function find($: EngineInterface): Promise<Player | undefined> {
  const { platform } = await $.session.info()
  if (platform === 'macos') return { name: 'the engine (afplay)', loops: true }
  const folder = `${$.plugin.root}/sounds/bedroom`
  const command = ctxOf($).setting('soundPlayer').trim()
  if (command !== '') return { name: command.split(/\s+/)[0] ?? command, argv: (file, gain) => commandLineOf(command, `${folder}/${file}`, gain), loops: false }
  const dirs = ((await $.env.get('PATH')) ?? '').split(platform === 'windows' ? ';' : ':').filter(dir => dir !== '')
  for (const name of PLAYERS) {
    if (!(await onPath($, dirs, name))) continue
    const loops = LOOPING.includes(name)
    if (name !== 'powershell.exe' || platform === 'windows') return { name, argv: (file, gain, isLoop) => argvOf(name, `${folder}/${file}`, gain, isLoop), loops }
    if (platform !== 'wsl' || !(await onPath($, dirs, 'wslpath'))) continue
    const converted = await $.process.run(['wslpath', '-w', folder])
    const windows = converted.stdout.trim()
    if (converted.exitCode === 0 && windows !== '') return { name, argv: (file, gain, isLoop) => argvOf(name, `${windows}\\${file}`, gain, isLoop), loops }
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

/**
 * Plays a file through the player until it ends or the play is stopped; repeats it when `isLoop` and the player can. A
 * started command is the engine's child for as long as its output is read: a stop leaves the read, which ends the child,
 * and so does the module unloading. Answers whether it ended on its own with no failure.
 */
async function playThrough($: EngineInterface, player: Player, sound: Sound, play: Play, isLoop: boolean): Promise<boolean> {
  const gain = gainOf(volumeOf(ctxOf($).saved))
  const file = `${sound}.wav`
  playing.add(play)
  try {
    if (player.argv === undefined) {
      const abort = new AbortController()
      play.end = () => abort.abort()
      if (play.stopped) return false
      await $.audio.play({ asset: `sounds/bedroom/${file}` }, isLoop ? { shouldLoop: true, gain, signal: abort.signal } : { gain, signal: abort.signal })
      return !play.stopped
    }
    const child = $.process.spawn({ argv: player.argv(file, gain, isLoop && player.loops) })
    child.result.catch(() => undefined)
    play.end = () => void child.return(undefined as never).catch(() => undefined)
    let said = ''
    for await (const piece of child) {
      if (play.stopped) break
      if (piece.stream === 'stderr') said = (said + piece.text).slice(-600)
    }
    if (play.stopped) return false
    const { code, signal } = await child.result
    if (code === 0) return true
    if (code === null) return false
    const last = said.split(/[\r\n]+/).filter(line => line.trim() !== '').at(-1)?.trim() ?? ''
    stop($, `${player.name} exited ${code}${signal === null ? '' : ` (${signal})`} playing ${sound}${last === '' ? '' : `: ${last.slice(0, 160)}`}`)
  } catch (error) {
    if (!play.stopped) stop($, `${player.name} failed playing ${sound}: ${error instanceof Error ? error.message : String(error)}`)
  } finally {
    playing.delete(play)
  }
  return false
}

/** Plays one sound to its end, unless stopped; at volume 0, nothing. */
async function playOnce($: EngineInterface, sound: Sound): Promise<void> {
  if (volumeOf(ctxOf($).saved) === 0) return
  const player = await ready($)
  if (player === undefined) return
  await playThrough($, player, sound, newPlay(), false)
}

async function reloaded($: EngineInterface): Promise<boolean> {
  if (chain === undefined) return false
  const { value } = await $.state.get({ plugin: 'themes', key: 'bedroom-chain' })
  return value !== undefined && value > chain
}

/**
 * A loop: one play that repeats the file, or, with a player that cannot, a chain of plays, the next started only while
 * this loop is the one wanted and not before the last one's length has passed, so a player that returns at once cannot
 * spin.
 */
async function runLoop($: EngineInterface, sound: Sound, play: Play): Promise<void> {
  while (!play.stopped && !(await reloaded($))) {
    const player = await ready($)
    if (player === undefined || play.stopped) return
    const startedAt = await $.clock.now()
    if (!(await playThrough($, player, sound, play, true))) return
    const rest = LENGTH_MS[sound] - ((await $.clock.now()) - startedAt)
    if (rest > 0 && !play.stopped) {
      await new Promise<void>(resolve => {
        const timer = $.clock.after(rest, resolve)
        play.end = () => {
          timer.cancel()
          resolve()
        }
      })
    }
  }
}

/**
 * Brings what plays in line with the settings, at once: called by each /bedroom sound word, after every other /bedroom
 * word, each minute, and every WATCH_MS while sound is on. Sound off stops everything playing; a change of loop,
 * recording or volume stops the loop playing and starts the one wanted.
 */
export function follow($: EngineInterface): void {
  const ctx = ctxOf($)
  if (!ctx.setting('sound')) {
    for (const play of [...playing]) play.stop()
    loop?.play.stop()
    loop = undefined
    return
  }
  const name = wanted(ctx)
  const sound = name === undefined ? undefined : (`${name}-${pickOf(ctx.saved, name)}` as Sound)
  const key = sound === undefined ? undefined : `${sound} ${volumeOf(ctx.saved)}`
  if (loop !== undefined && loop.key === key && !loop.play.stopped) return
  loop?.play.stop()
  loop = undefined
  if (sound === undefined || key === undefined || failure !== undefined) return
  const play = newPlay()
  const started = { key, play }
  loop = started
  void runLoop($, sound, play)
    .catch(error => stop($, `the ${name} loop failed: ${String(error)}`))
    .finally(() => {
      if (loop === started) loop = undefined
    })
}

/**
 * While sound is on, what plays is checked against the settings this often, in ms: a change no sound hook sees (reset,
 * `<setting> default`, a click in the room) takes no longer than this. The check calls nothing of the engine's but the
 * timer.
 */
export const WATCH_MS = 300
let watching = false
function watch($: EngineInterface): void {
  if (watching) return
  watching = true
  $.clock.after(WATCH_MS, () => {
    watching = false
    follow($)
    if (ctxOf($).setting('sound')) watch($)
  })
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
  const sound = `thunder-${pickOf(ctx.saved, 'thunder')}-${(minute % 3) + 1}` as Sound
  $.clock.after(Math.max(due - (await $.clock.now()), 0), () => {
    if (ctxOf($).fields().weather === 4) void playOnce($, sound).catch(error => stop($, `thunder failed: ${String(error)}`))
  })
}

export const piece: Piece = { name: 'sound' }

async function minute($: EngineInterface, ctx: Ctx): Promise<void> {
  chain = (await $.state.get({ plugin: 'themes', key: 'bedroom-chain' })).value
  if ((await ready($)) === undefined) return
  follow($)
  watch($)
  await thunderAfterStrike($, ctx)
}

/** Not awaited by the minute: looking for a player must not hold the clock's redraw. */
export async function engineTick($: EngineInterface, ctx: Ctx): Promise<void> {
  if (ctx.setting('sound')) void minute($, ctx).catch(error => stop($, `the minute's sound failed: ${String(error)}`))
}

export function engineSwitched($: EngineInterface, ctx: Ctx, name: Switch, isOn: boolean, _by: 'click' | 'command'): void {
  if (name !== 'tv' || tvPlaying || !ctx.setting('sound')) return
  tvPlaying = true
  void playOnce($, isOn ? 'tv-on' : 'tv-off')
    .catch(error => stop($, `the television's sound failed: ${String(error)}`))
    .finally(() => {
      tvPlaying = false
    })
}

const KIND_WORDS = KINDS.join(', ')

/** /bedroom sound volume N: 0 to 100, saved; the loop playing starts over at it. */
async function setVolume(ctx: Ctx, word: string | undefined): Promise<string> {
  const amount = Number(word)
  if (word === undefined || word === '' || !Number.isInteger(amount) || amount < 0 || amount > 100) {
    return `give a whole number from 0 to 100, as in /bedroom sound volume 40 (now ${volumeOf(ctx.saved)}); 0 plays nothing`
  }
  await ctx.save({ volume: amount })
  return `volume ${amount}${amount === 0 ? ': nothing plays' : ''}`
}

/** /bedroom sound pick KIND 1|2: which recording of a kind plays; the loop playing starts over with it. */
async function setPick(ctx: Ctx, kind: string | undefined, which: string | undefined): Promise<string> {
  const picks = KINDS.map(name => `${name} ${pickOf(ctx.saved, name)}`).join(', ')
  if (kind === undefined || !(KINDS as readonly string[]).includes(kind) || (which !== '1' && which !== '2')) {
    return `say which recording of ${KIND_WORDS}, as in /bedroom sound pick cicadas 2. Now: ${picks}`
  }
  await ctx.save({ picks: { ...ctx.saved.picks, [kind]: which === '2' ? 2 : 1 } })
  return `${kind} plays recording ${which}`
}

/**
 * /bedroom sound on|off|test|volume N|pick KIND 1|2; test plays only the silent file, and looks without forgetting a
 * failure. Another word (the weather, the time) is answered after this returns, so the sound follows it on the next
 * turn of the clock.
 */
export async function engineCommand($: EngineInterface, ctx: Ctx, word: string, args: readonly string[]): Promise<string | undefined> {
  if (word !== 'sound') {
    if (ctx.setting('sound')) $.clock.after(0, () => follow($))
    return undefined
  }
  const what = (args[0] ?? '').toLowerCase()
  const none = `no player was found (looked for ${PLAYERS.join(', ')} on PATH; the soundPlayer setting names one, with {file} for the file and {volume} for 0 to 100)`
  try {
    if (what === 'off') {
      await ctx.save({ sound: false })
      follow($)
      return 'sound is off: what was playing has stopped'
    }
    if (what === 'on') {
      const player = await lookAgain($)
      if (player === undefined) return `${none}, so sound stays off`
      chain = (await $.state.get({ plugin: 'themes', key: 'bedroom-chain' })).value
      await ctx.save({ sound: true })
      follow($)
      watch($)
      return `sound is on, played by ${player.name} at volume ${volumeOf(ctx.saved)}: the television, cicadas from dusk through night in dry weather, rain, a downpour and a storm${THUNDERS ? ' with thunder' : ''}`
    }
    if (what === 'volume' || what === 'pick') {
      const answer = what === 'volume' ? await setVolume(ctx, args[1]) : await setPick(ctx, args[1]?.toLowerCase(), args[2])
      follow($)
      return answer
    }
    if (what === 'test') {
      const player = await find($)
      if (player === undefined) return none
      if (player.argv === undefined) {
        await $.audio.play({ asset: 'sounds/bedroom/silence.wav' })
        return `${player.name} played silence.wav`
      }
      const { exitCode } = await $.process.run(player.argv('silence.wav', 0, false), { timeoutMs: timeoutOf('silence') })
      return `${player.name} played silence.wav and exited ${exitCode}`
    }
    if (what !== '') return 'say on, off, test, volume N or pick KIND 1|2, as in /bedroom sound on'
    const player = finding === undefined ? 'not looked for yet' : ((await finding)?.name ?? 'none found')
    const picks = KINDS.map(name => `${name} ${pickOf(ctx.saved, name)}`).join(', ')
    return `sound is ${ctx.setting('sound') ? 'on' : 'off'}, volume ${volumeOf(ctx.saved)}. recordings: ${picks}. player: ${player}${failure === undefined ? '' : `, stopped: ${failure}`}. Say on, off, test, volume N or pick KIND 1|2`
  } catch (error) {
    return `sound could not answer: ${error instanceof Error ? error.message : String(error)}`
  }
}
