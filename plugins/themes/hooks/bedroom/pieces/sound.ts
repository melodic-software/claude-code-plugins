import type { EngineInterface } from 'claude-code'

import { local, minuteOfHalfDay, nowMs } from '../core/clock.js'
import { ctxOf } from '../core/context.js'
import type { Ctx, On, Piece, Switch } from '../core/piece.js'
import { volumeOf, type Saved } from '../core/saved.js'
import { forcedStrikeAt, scheduledEventShows, strike } from '../core/schedule.js'
import { ACCEPT, BUILT, HURRY, WITHOUT, WORLD } from '../core/signals.gen.js'
import { flush } from '../core/telemetry.js'
import { worldMove } from '../core/values.js'
import { KINDS, OBJECTS, PURR, SILENCE, chosen, chosenName, lengthOf, namesOf, shotsOf, type Kind } from './sound-bank.js'
import { PING_MS, QUIET_MS, fileOf, linesOf, mixerScript, powershellArgv, type MixerCommand, type MixerVoice } from './sound-mixer.js'
import { rowStarts, sunTimes } from './time.js'
import { roll } from './weather.js'

/**
 * Sound, off by default (/bedroom sound): a bed (in dry weather cicadas from noon through dusk and the night insects from
 * evening until dawn, bedOf and levelOf; rain, a downpour or a storm), the television, the room's things, the cat, and thunder after each strike, from the bank in sound-bank.ts.
 * Nothing here calls the engine while sound is off.
 *
 * On Windows, and under WSL through Windows, one mixer process plays everything for as long as sound is on
 * (sound-mixer.ts): a one-shot is a line in its command file, so no process starts at the moment of a sound, and beds
 * cross-fade. Elsewhere each sound is a play of its own, through the engine (macOS) or a player found on PATH, and a bed
 * changes with a cut.
 */

/** A volume as the gain a player takes, 0 to 1: squared, so each step sounds about as far as the last. */
export const gainOf = (volume: number): number => (Math.min(100, Math.max(0, volume)) / 100) ** 2

/** The room's things play this much under the volume: they are small sounds in a quiet room. */
export const OBJECT_GAIN = 0.7
/** Fades, in ms: sound going off, a change of volume, a bed starting when sound comes on, a change of bank entry. */
export const OFF_FADE_MS = 150
export const LEVEL_FADE_MS = 400
export const START_FADE_MS = 1500
export const PICK_FADE_MS = 2000

/**
 * From a world send to the picture starting to move, in ms: the app starts easing a value about half a second after a
 * redraw is asked, and the shader takes a world code once it has held still ACCEPT.world s.
 */
export const PICTURE_LAG_MS = 500 + ACCEPT.world * 1000
/** How long the picture takes over a change of weather: hurried (a command), every lane moves at HURRY.pace a second. */
export const HURRIED_MS = Math.round(1000 / HURRY.pace)
/** Unhurried (the `auto` weather changing by itself, or the sun at the minute's turn), the weather lane moves 0.0111 a second (lights.ts). */
export const WEATHER_EASE_MS = 90_000
/** The sun eases over half an hour; the cicadas come and go over this much of it. */
export const SUN_FADE_MS = 30_000

/** The players looked for on PATH when the soundPlayer setting is empty, in this order. */
export const PLAYERS = ['powershell.exe', 'ffplay', 'paplay', 'aplay'] as const
export type PlayerName = (typeof PLAYERS)[number]

/** A found player's argument list for one play of a file, the path as that player reads it. */
export function argvOf(name: Exclude<PlayerName, 'powershell.exe'>, file: string, gain: number, loop: boolean): string[] {
  if (name === 'ffplay') return [name, '-nodisp', '-autoexit', '-loglevel', 'quiet', '-stats', '-volume', String(Math.round(gain * 100)), ...(loop ? ['-loop', '0'] : []), file]
  if (name === 'paplay') return [name, '--verbose', `--volume=${Math.round(gain * 65536)}`, file]
  return [name, '-V', 'mono', file]
}

/** The soundPlayer setting's command line for a file: {file} and {volume} (0 to 100) replaced, or the file put last when it names none. */
export function commandLineOf(command: string, file: string, gain = 1): string[] {
  const words = command.trim().split(/\s+/)
  const filled = words.map(word => word.replaceAll('{file}', file).replaceAll('{volume}', String(Math.round(gain * 100))))
  return words.some(word => word.includes('{file}')) ? filled : [...filled, file]
}

/**
 * How sound is played: the Windows mixer, reading the sounds folder by `root` (a Windows path) and its command file by
 * the path it names, converted with wslpath under WSL; the engine's own player (macOS); or a command for each play,
 * which may repeat a bed itself.
 */
type Player =
  | { kind: 'mixer'; name: string; root: string; wsl: boolean }
  | { kind: 'engine'; name: string }
  | { kind: 'spawn'; name: string; argv: (file: string, gain: number, loop: boolean) => string[]; loops: boolean }

/** Thunder follows the lightning, so it sounds only where the build draws lightning. */
const THUNDERS = BUILT.includes('weather') && !WITHOUT.includes('weather.lightning')

let finding: Promise<Player | undefined> | undefined
/** Set when a play failed: nothing plays until /bedroom sound on looks for the player again. */
let failure: string | undefined

async function onPath($: EngineInterface, dirs: readonly string[], name: string): Promise<boolean> {
  for (const dir of dirs) if (await $.fs.exists(`${dir.replace(/\/$/, '')}/${name}`)) return true
  return false
}

/** Finds the player; under WSL, Windows' mixer reads the sounds by their Windows path. */
async function find($: EngineInterface): Promise<Player | undefined> {
  const { platform } = await $.session.info()
  if (platform === 'macos') return { kind: 'engine', name: 'the engine (afplay)' }
  const folder = `${$.plugin.root}/sounds/bedroom`
  const command = ctxOf($).setting('soundPlayer').trim()
  if (command !== '') return { kind: 'spawn', name: command.split(/\s+/)[0] ?? command, argv: (file, gain) => commandLineOf(command, `${folder}/${file}`, gain), loops: false }
  const dirs = ((await $.env.get('PATH')) ?? '').split(platform === 'windows' ? ';' : ':').filter(dir => dir !== '')
  for (const name of PLAYERS) {
    if (!(await onPath($, dirs, name))) continue
    if (name !== 'powershell.exe') return { kind: 'spawn', name, argv: (file, gain, loop) => argvOf(name, `${folder}/${file}`, gain, loop), loops: name === 'ffplay' }
    if (platform === 'windows') return { kind: 'mixer', name: 'the Windows mixer (powershell.exe)', root: folder.replaceAll('/', '\\'), wsl: false }
    if (platform !== 'wsl' || !(await onPath($, dirs, 'wslpath'))) continue
    const converted = await $.process.run(['wslpath', '-w', folder])
    const windows = converted.stdout.trim()
    if (converted.exitCode === 0 && windows !== '') return { kind: 'mixer', name: 'the Windows mixer (powershell.exe)', root: windows, wsl: true }
  }
  return undefined
}

/** Looks for the player again, forgetting a failure. */
function lookAgain($: EngineInterface): Promise<Player | undefined> {
  failure = undefined
  finding = find($).catch(error => {
    fail($, `looking for a player failed: ${error instanceof Error ? error.message : String(error)}`)
    return undefined
  })
  return finding
}

/**
 * One line in the debug log and everything playing stopped. A player that is missing or will not start plays nothing
 * until /bedroom sound on; a mixer that exits or stops answering is started again after RETRY_MS (`retry`).
 */
function fail($: EngineInterface, why: string, retry = false): void {
  if (failure !== undefined) return
  failure = why
  retryAt = retry ? nowMs() + RETRY_MS : undefined
  ctxOf($).note(`sound: ${why}; ${retry ? `the mixer starts again in ${RETRY_MS / 1000} s` : 'nothing plays until /bedroom sound on'}`)
  flush($)
  if (out !== undefined) endOut($, out, 0)
  out = undefined
  bed = undefined
}
export const RETRY_MS = 10_000
let retryAt: number | undefined

/** The player while sound is on and none has failed; looked for once, and again once a retried failure's wait is over. */
async function ready($: EngineInterface): Promise<Player | undefined> {
  if (failure !== undefined && retryAt !== undefined && (await $.clock.now()) >= retryAt) {
    failure = undefined
    retryAt = undefined
  }
  if (!ctxOf($).setting('sound') || failure !== undefined) return undefined
  const player = await (finding ?? lookAgain($))
  if (player === undefined) fail($, 'no player was found')
  return failure === undefined ? player : undefined
}

/** One play through the engine or a command: stop() ends it at once. */
type Play = { stopped: boolean; end?: () => void }
const stopPlay = (play: Play): void => {
  play.stopped = true
  play.end?.()
}

/** The mixer's side of the mod: the commands not yet answered, the command file once it is named, and its child's end. */
/**
 * The mixer's side of the mod: the commands not yet answered, the command file once it is named, its child's end, its
 * pid, when it last wrote anything (it writes a dot every BEAT_MS), and whether it has answered a command.
 */
type Mixer = {
  seq: number
  pending: { seq: number; command: MixerCommand }[]
  path?: string
  writing: Promise<void>
  kill?: () => void
  heard: number
  pid?: number
  heardAt: number
  answered: boolean
  asked?: { seq: number; answer: (voices: MixerVoice[]) => void }
}
/** The last file a mixer's player could not open, kept across mixers for /bedroom sound. */
let lastFailed: { name: string; text: string; at: number } | undefined
/** How long /bedroom sound waits for the mixer to report its voices. */
export const VOICES_WAIT_MS = 800
/** A mixer silent this long, its exit unseen (a reload can lose it, an app closed can kill it), is taken for gone. */
export const SILENT_MS = 10_000
type Out = { player: Player; isDone: boolean; mixer?: Mixer; bedPlay?: Play; shots: Set<Play> }
let out: Out | undefined
/**
 * The bed playing now: its file, the sky it was chosen for, the volume's gain and the sky's level (levelOf), when its
 * last fade ends, and, while the afternoon builds through the mixer, when that one long ease reaches the golden hour.
 */
let bed: { file: string | undefined; sky: Sky; gain: number; level: number; settledAt: number; aim?: number; evening?: boolean } | undefined

/**
 * This copy of the module, by when it loaded: a reload loads a newer copy. One player per session: the newest copy
 * holds it, in $.state themes.bedroom-mixer, and an older copy that sees a newer one there ends its own and opens none.
 * A copy taking it from an older one waits HANDOVER_MS first, for the older one to fade out (it looks every WATCH_MS).
 */
export const COPY = Date.now()
export const HANDOVER_MS = 1000
let claimedAt: number | undefined
async function holdsPlayer($: EngineInterface, now: number): Promise<boolean> {
  const { value } = await $.state.get({ plugin: 'themes', key: 'bedroom-mixer' })
  if (value === COPY) return claimedAt === undefined || now - claimedAt >= HANDOVER_MS
  if (value !== undefined && value > COPY) return false
  claimedAt = value === undefined ? undefined : now
  await $.state.set({ plugin: 'themes', key: 'bedroom-mixer' }, COPY)
  return claimedAt === undefined
}
async function newerHolds($: EngineInterface): Promise<boolean> {
  const { value } = await $.state.get({ plugin: 'themes', key: 'bedroom-mixer' })
  return value !== undefined && value > COPY
}

/**
 * Set while no desktop window shows the session (it detached, or the session ended): nothing plays then, so a session
 * left running after the app is closed is silent. A window attaching again lets the room's sound follow it.
 */
let away = false

/** The mixer reports this many one-shots' latency in the debug log, from the write to the player's position moving. */
const LATENCY_NOTES = 3

function openOut($: EngineInterface, player: Player): Out {
  const opened: Out = { player, isDone: false, shots: new Set() }
  if (player.kind === 'mixer') {
    opened.mixer = { seq: 0, pending: [], writing: Promise.resolve(), heard: 0, heardAt: nowMs(), answered: false }
    void runMixer($, opened, opened.mixer).catch(error => fail($, `the mixer failed: ${error instanceof Error ? error.message : String(error)}`))
    for (const name of shotsOf(ctxOf($).saved)) mixerSend($, opened, { verb: 'load', name })
    pingLater($, opened)
  }
  return opened
}

/** The mixer's child, read for its life: its lines, then how it ended. Leaving the loop ends the child. */
async function runMixer($: EngineInterface, o: Out, m: Mixer): Promise<void> {
  if (o.player.kind !== 'mixer') return
  const started = await $.clock.now()
  const child = $.process.spawn({ argv: powershellArgv(mixerScript(o.player.root)) })
  child.result.catch(() => undefined)
  m.kill = () => void child.return(undefined as never).catch(() => undefined)
  if (o.isDone) m.kill()
  let rest = ''
  let said = ''
  for await (const piece of child) {
    if (piece.stream === 'stderr') {
      said = (said + piece.text).slice(-600)
      continue
    }
    m.heardAt = await $.clock.now()
    const read = linesOf(rest + piece.text)
    rest = read.rest
    for (const line of read.lines) {
      if (line.kind === 'ready') {
        m.path = o.player.wsl ? (await $.process.run(['wslpath', '-u', line.path])).stdout.trim() : line.path
        writeCommands($, m)
      } else if (line.kind === 'ok') {
        m.answered = true
        m.pending = m.pending.filter(entry => entry.seq > line.seq)
      } else if (line.kind === 'sounding' && m.heard < LATENCY_NOTES) {
        m.heard += 1
        const sent = sentAt.get(line.seq)
        if (sent !== undefined) ctxOf($).note(`sound: ${sent.name} sounding ${Math.round((await $.clock.now()) - sent.at)} ms after it was sent`)
        flush($)
      } else if (line.kind === 'pid') {
        m.pid = line.pid
        ctxOf($).note(`sound: the Windows mixer runs as powershell.exe process ${line.pid}`)
        flush($)
      } else if (line.kind === 'error') {
        said = line.text
      } else if (line.kind === 'failed') {
        lastFailed = { name: line.name, text: line.text, at: await $.clock.now() }
        ctxOf($).note(`sound: the mixer could not open ${line.name}: ${line.text}`)
        flush($)
      } else if (line.kind === 'voices' && m.asked?.seq === line.seq) {
        m.asked.answer(line.voices)
        m.asked = undefined
      }
    }
  }
  if (o.isDone || out !== o) return
  const { code } = await child.result
  if (code === 0 && (await $.clock.now()) - started >= QUIET_MS) {
    o.isDone = true
    if (out === o) {
      out = undefined
      bed = undefined
    }
    ctxOf($).note(`sound: the mixer stopped after ${QUIET_MS / 1000} s with no command; the next sound starts it again`)
    flush($)
    return
  }
  const last = said.split(/[\r\n]+/).filter(line => line.trim() !== '').at(-1)?.trim() ?? ''
  fail($, `the mixer exited ${code}${last === '' ? '' : `: ${last.slice(0, 160)}`}`, m.answered)
}
/** When each of the last one-shots was sent, by seq, for the latency notes. */
const sentAt = new Map<number, { name: string; at: number }>()

/** Writes the command file whole: every command not yet answered. Writes go one after another. */
function writeCommands($: EngineInterface, m: Mixer): void {
  const path = m.path
  if (path === undefined) return
  m.writing = m.writing
    .then(() => $.fs.write(path, fileOf(m.pending)))
    .catch(error => fail($, `writing the mixer's commands to ${path} failed: ${error instanceof Error ? error.message : String(error)}`, m.answered))
}

function mixerSend($: EngineInterface, o: Out, command: MixerCommand): void {
  const m = o.mixer
  if (m === undefined || o.isDone) return
  m.seq += 1
  const seq = m.seq
  m.pending.push({ seq, command })
  writeCommands($, m)
  if (command.verb !== 'shot' || m.heard >= LATENCY_NOTES) return
  const name = command.name
  void $.clock.now().then(now => sentAt.set(seq, { name, at: now }))
}

/** A ping every PING_MS while the mixer runs: it stops by itself once none has come for QUIET_MS. */
function pingLater($: EngineInterface, o: Out): void {
  $.clock.after(PING_MS, () => {
    if (o.isDone) return
    mixerSend($, o, { verb: 'ping' })
    pingLater($, o)
  })
}

/** A bed through the engine or a command: one play that repeats the file, or a chain of plays for a player that cannot. */
async function runBed($: EngineInterface, o: Out, file: string, gain: number, play: Play): Promise<void> {
  while (!play.stopped && !o.isDone) {
    const startedAt = await $.clock.now()
    if (!(await playThrough($, o, file, gain, play, true))) return
    if (o.player.kind === 'engine' || (o.player.kind === 'spawn' && o.player.loops)) return
    const rest = lengthOf(file) - ((await $.clock.now()) - startedAt)
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
 * One play of a file through the engine or a command, until it ends or is stopped. A started command is the engine's
 * child for as long as its output is read: a stop leaves the read, which ends the child, and so does the module
 * unloading. Answers whether it ended on its own with no failure.
 */
async function playThrough($: EngineInterface, o: Out, file: string, gain: number, play: Play, loop: boolean): Promise<boolean> {
  const player = o.player
  try {
    if (player.kind === 'engine') {
      const abort = new AbortController()
      play.end = () => abort.abort()
      if (play.stopped) return false
      await $.audio.play({ asset: `sounds/bedroom/${file}` }, loop ? { shouldLoop: true, gain, signal: abort.signal } : { gain, signal: abort.signal })
      return !play.stopped
    }
    if (player.kind !== 'spawn') return false
    const child = $.process.spawn({ argv: player.argv(file, gain, loop && player.loops) })
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
    fail($, `${player.name} exited ${code}${signal === null ? '' : ` (${signal})`} playing ${file}${last === '' ? '' : `: ${last.slice(0, 160)}`}`)
  } catch (error) {
    if (!play.stopped) fail($, `${player.name} failed playing ${file}: ${error instanceof Error ? error.message : String(error)}`)
  }
  return false
}

/** Changes the bed: a cross-fade of fadeMs through the mixer, the new bed rising from `from`; a cut elsewhere. */
function outBed($: EngineInterface, o: Out, file: string | undefined, gain: number, fadeMs: number, from?: number): void {
  if (o.mixer !== undefined) return mixerSend($, o, { verb: 'bed', name: file, gain, fadeMs, from })
  if (o.bedPlay !== undefined) stopPlay(o.bedPlay)
  o.bedPlay = undefined
  if (file === undefined) return
  const play: Play = { stopped: false }
  o.bedPlay = play
  void runBed($, o, file, gain, play).catch(error => fail($, `the bed failed: ${String(error)}`))
}

/** The bed's level: a fade of fadeMs through the mixer; elsewhere the bed starts again at it. */
function outLevel($: EngineInterface, o: Out, file: string | undefined, gain: number, fadeMs: number): void {
  if (o.mixer !== undefined) return mixerSend($, o, { verb: 'level', gain, fadeMs })
  outBed($, o, file, gain, 0)
}

/** The last one-shot sent and when, for /bedroom sound. */
let lastShot: { file: string; at: number } | undefined

function outShot($: EngineInterface, o: Out, file: string, gain: number): void {
  void $.clock.now().then(at => void (lastShot = { file, at }))
  if (o.mixer !== undefined) return mixerSend($, o, { verb: 'shot', name: file, gain })
  const play: Play = { stopped: false }
  o.shots.add(play)
  void playThrough($, o, file, gain, play, false)
    .catch(error => fail($, `${file} failed: ${String(error)}`))
    .finally(() => o.shots.delete(play))
}

/** Ends everything: the mixer fades out over fadeMs and its child is ended just after; every other play stops at once. */
function endOut($: EngineInterface, o: Out, fadeMs: number): void {
  if (o.isDone) return
  if (o.mixer !== undefined) {
    const m = o.mixer
    mixerSend($, o, { verb: 'quit', fadeMs })
    o.isDone = true
    $.clock.after(fadeMs + 250, () => m.kill?.())
    return
  }
  o.isDone = true
  if (o.bedPlay !== undefined) stopPlay(o.bedPlay)
  for (const play of [...o.shots]) stopPlay(play)
}

export type Sky = { sun: number; weather: number }

/** The phases by their number in the sun field (core/settings.ts PHASES). */
const DUSK = 0
const EVENING = 1
const NIGHT = 2
const PREDAWN = 3
const NOON = 6
const GOLDEN = 7

/**
 * The bed for a sky: in rain, a downpour or a storm that weather's; when dry, cicadas from mid-afternoon through the
 * golden hour and dusk, the night insects from evening until dawn, and nothing at dawn, in the morning and at noon
 * before the cicadas start. `afternoon` is how far the cicadas' build has gone at noon (afternoonOf), undefined before it
 * starts or while noon is held. The night's `auto` entry plays its evening loop (crickets and katydids) in the evening
 * and its late loop (crickets alone) at night and before dawn; another entry plays one loop at all three.
 */
export function bedOf(saved: Saved, sky: Sky, afternoon?: number): string | undefined {
  if (sky.weather >= 2) {
    const rain = chosen(saved, 'rain')
    return sky.weather === 2 ? rain.rain : sky.weather === 3 ? rain.downpour : rain.storm
  }
  if (sky.sun === NOON) return afternoon === undefined ? undefined : chosen(saved, 'cicadas').bed
  if (sky.sun === GOLDEN || sky.sun === DUSK) return chosen(saved, 'cicadas').bed
  if (sky.sun === EVENING) return chosen(saved, 'night').evening
  if (sky.sun === NIGHT || sky.sun === PREDAWN) return chosen(saved, 'night').late
  return undefined
}

/**
 * How loud a dry bed plays, times the volume's gain: cicadas full at the golden hour and dusk, and through the
 * afternoon's build from BUILD_LEVEL to full (`afternoon`, 0 to 1); the night insects settling as it gets late, under
 * the cicadas at EVENING_LEVEL, NIGHT_LEVEL and PREDAWN_LEVEL. Rain is full.
 */
export const BUILD_LEVEL = 0.25
export const EVENING_LEVEL = 0.5
export const NIGHT_LEVEL = 0.4
export const PREDAWN_LEVEL = 0.3
export function levelOf(sky: Sky, afternoon = 0, continuous = false): number {
  if (sky.weather >= 2) return 1
  const share = Math.min(1, Math.max(0, afternoon))
  if (sky.sun === NOON) return BUILD_LEVEL + (1 - BUILD_LEVEL) * (continuous ? share : Math.floor(share * AFTERNOON_STEPS) / AFTERNOON_STEPS)
  if (sky.sun === EVENING) return EVENING_LEVEL
  if (sky.sun === NIGHT) return NIGHT_LEVEL
  if (sky.sun === PREDAWN) return PREDAWN_LEVEL
  return 1
}
/**
 * The cicadas of a summer dusk start in mid-afternoon: the scissor-grinder "often remains quiet all day, singing from
 * about 3 or 4 P. M. until dark" (W. T. Davis, at https://www.bugguide.net/node/view/6967). They start BUILD_FROM_MIN
 * before sunset and build to full by the golden hour, 90 minutes before it. Where a player cannot ease one level into
 * another over hours the build moves in AFTERNOON_STEPS steps, each over SUN_FADE_MS; through the mixer it is one ease.
 */
export const BUILD_FROM_MIN = 270
export const AFTERNOON_STEPS = 12
/** Evening lasts 75 minutes (pieces/time.ts rowStarts): the cicadas give way to the night insects across all of it. */
export const EVENING_FADE_MS = 75 * 60_000

/** A local clock time as minutes of its day, with the seconds as a fraction. */
const minuteOfDay = (now: number): number => {
  const { hours, minutes } = local(now)
  return hours * 60 + minutes + (now % 60_000) / 60_000
}

/**
 * How far `now` is through the stretch of the day from the start of row `from` to the start of row `to`, 0 to 1, and
 * the ms left of it; undefined while a phase is held, when the clock does not move the room.
 */
function stretchOf(ctx: Ctx, now: number, from: number, to: number): { share: number; leftMs: number } | undefined {
  if (ctx.setting('time') !== 'auto') return undefined
  const starts = rowStarts(...sunTimes(ctx))
  const span = (starts[to]! - starts[from]! + 1440) % 1440 || 1440
  const gone = Math.min(span, (minuteOfDay(now) - starts[from]! + 1440) % 1440)
  return { share: gone / span, leftMs: (span - gone) * 60_000 }
}

/**
 * How far the cicadas' afternoon build has gone at `now`, 0 to 1, and the ms left of it: from BUILD_FROM_MIN before the
 * room's sunset to the golden hour's start. Undefined before it starts, and while a phase is held.
 */
export function afternoonOf(ctx: Ctx, now: number): { share: number; leftMs: number } | undefined {
  if (ctx.setting('time') !== 'auto') return undefined
  const [, sunset] = sunTimes(ctx)
  const golden = rowStarts(...sunTimes(ctx))[GOLDEN]!
  const from = sunset - BUILD_FROM_MIN
  const minute = minuteOfDay(now)
  if (minute < from) return undefined
  const span = golden - from
  return { share: Math.min(1, (minute - from) / span), leftMs: Math.max(0, golden - minute) * 60_000 }
}

/**
 * The sky the picture shows or is about to, when it starts to move there and how long it takes: from the last world code
 * sent, PICTURE_LAG_MS after it went, over HURRIED_MS when a hurry flip goes with it (a command) and WEATHER_EASE_MS or
 * SUN_FADE_MS when not. Before the shader has started (no code sent) the fields stand, at once, over START_FADE_MS.
 * undefined while world holds a code that is not the atmosphere (a cue), so the bed stays as it is.
 */
export function shownOf(move: ReturnType<typeof worldMove>, fields: Sky, was: Sky | undefined, now: number): { sky: Sky; at: number; fadeMs: number } | undefined {
  if (move.at === -Infinity) return { sky: { sun: fields.sun, weather: fields.weather }, at: now, fadeMs: START_FADE_MS }
  if (move.code > WORLD.top) return undefined
  const sky = { sun: move.code % WORLD.sun, weather: Math.floor(move.code / WORLD.sun) % WORLD.weather }
  const hurried = move.hurryWaits || move.hurryAt >= move.at || move.at - move.hurryAt < HURRY.seconds * 1000
  const weatherMoved = was === undefined || was.weather !== sky.weather
  return { sky, at: move.at + PICTURE_LAG_MS, fadeMs: hurried ? HURRIED_MS : weatherMoved ? WEATHER_EASE_MS : SUN_FADE_MS }
}

let stepping: Promise<void> = Promise.resolve()
let waitTimer: { at: number; cancel: () => void } | undefined

/**
 * Brings what plays in line with the settings and the picture: called by each /bedroom sound word, after every other
 * /bedroom word, each minute, and every WATCH_MS while sound is on. Steps run one at a time.
 */
/** Ends what plays, fading out over OFF_FADE_MS. */
function silence($: EngineInterface): void {
  swell?.timer.cancel()
  swell = undefined
  if (out !== undefined) endOut($, out, OFF_FADE_MS)
  out = undefined
  bed = undefined
}

export function follow($: EngineInterface): Promise<void> {
  if (ctxOf($).setting('sound')) watch($)
  stepping = stepping.then(() => step($)).catch(error => fail($, `following the room failed: ${error instanceof Error ? error.message : String(error)}`))
  return stepping
}

async function step($: EngineInterface): Promise<void> {
  await stepBeds($)
  await swellStep($)
}

async function stepBeds($: EngineInterface): Promise<void> {
  const ctx = ctxOf($)
  if (!ctx.setting('sound') || volumeOf(ctx.saved) === 0 || away || (await newerHolds($))) return silence($)
  await forcedThunder($)
  const player = await ready($)
  if (player === undefined) return
  if (out?.mixer !== undefined && !out.isDone && (await $.clock.now()) - out.mixer.heardAt > SILENT_MS) {
    ctx.note(`sound: the mixer has said nothing for ${SILENT_MS / 1000} s; starting another`)
    flush($)
    out.mixer.kill?.()
    out.isDone = true
    out = undefined
  }
  if (out === undefined || out.isDone) {
    if (!(await holdsPlayer($, await $.clock.now()))) return
    out = openOut($, player)
    bed = undefined
  }
  const gain = gainOf(volumeOf(ctx.saved))
  const now = await $.clock.now()
  const shown = shownOf(worldMove(), ctx.fields(), bed?.sky, now)
  if (shown === undefined) return
  const dry = shown.sky.weather < 2
  const mixer = out.mixer !== undefined
  const afternoon = dry && shown.sky.sun === NOON ? afternoonOf(ctx, now) : undefined
  const file = bedOf(ctx.saved, shown.sky, afternoon?.share)
  const ramp = mixer && afternoon !== undefined
  const level = levelOf(shown.sky, afternoon?.share ?? 0, ramp)
  const evening = mixer && dry && shown.sky.sun === EVENING ? stretchOf(ctx, now, EVENING, NIGHT) : undefined
  const cicadas = chosen(ctx.saved, 'cicadas').bed
  const cross = (ease: number): void => {
    if (evening === undefined || out?.mixer === undefined || file === undefined) return
    const turn = (Math.min(1, evening.share + ease / EVENING_FADE_MS) * Math.PI) / 2
    const rest = Math.max(0, evening.leftMs - ease)
    mixerSend($, out, { verb: 'to', name: cicadas, gain: gain * Math.cos(turn), fadeMs: ease, then: 0, thenMs: rest })
    mixerSend($, out, { verb: 'to', name: file, gain: gain * level * Math.sin(turn), fadeMs: ease, then: gain * level, thenMs: rest })
    bed = { file, sky: shown.sky, gain, level, settledAt: now + ease, evening: true }
  }
  if (bed === undefined) {
    if (evening !== undefined) return cross(START_FADE_MS)
    outBed($, out, file, gain * level, START_FADE_MS)
    bed = { file, sky: shown.sky, gain, level, settledAt: now + START_FADE_MS }
    return
  }
  const skyMoved = shown.sky.sun !== bed.sky.sun || shown.sky.weather !== bed.sky.weather
  if (skyMoved && now < shown.at && (file !== bed.file || level !== bed.level || evening !== undefined || bed.evening === true)) return waitUntil($, shown.at, now)
  const ease = skyMoved ? Math.max(OFF_FADE_MS, shown.fadeMs - (now - shown.at)) : HURRIED_MS
  if (evening !== undefined) {
    const walked = bed.sky.sun === DUSK && bed.file === cicadas && shown.fadeMs === SUN_FADE_MS
    if (walked && !bed.evening) {
      outBed($, out, file, gain * level, Math.max(OFF_FADE_MS, EVENING_FADE_MS - (now - shown.at)))
      bed = { file, sky: shown.sky, gain, level, settledAt: now, evening: true }
      return
    }
    if (!bed.evening || gain !== bed.gain || file !== bed.file) return cross(gain !== bed.gain && !skyMoved ? LEVEL_FADE_MS : ease)
    bed.sky = shown.sky
    return
  }
  if (bed.evening && out.mixer !== undefined) {
    for (const gone of new Set([cicadas, bed.file])) {
      if (gone !== undefined && gone !== file) mixerSend($, out, { verb: 'to', name: gone, gain: 0, fadeMs: ease, then: 0, thenMs: 0 })
    }
    if (file !== undefined) mixerSend($, out, { verb: 'to', name: file, gain: gain * level, fadeMs: ease, then: gain * level, thenMs: 0 })
    else outBed($, out, undefined, 0, ease)
    bed = { file, sky: shown.sky, gain, level, settledAt: now + ease }
    return
  }
  if (file !== bed.file) {
    const fadeMs = skyMoved ? ease : PICK_FADE_MS
    outBed($, out, file, gain * level, fadeMs)
    bed = { file, sky: shown.sky, gain, level, settledAt: now + fadeMs }
    return
  }
  bed.sky = shown.sky
  if (gain !== bed.gain) {
    outLevel($, out, bed.file, gain * level, LEVEL_FADE_MS)
    Object.assign(bed, { gain, level, aim: undefined, settledAt: now + LEVEL_FADE_MS })
    return
  }
  if (ramp && afternoon !== undefined) {
    const aim = now + afternoon.leftMs
    if (now < bed.settledAt || (bed.aim !== undefined && Math.abs(bed.aim - aim) < 60_000)) return
    outLevel($, out, bed.file, gain, afternoon.leftMs)
    Object.assign(bed, { level, aim })
    return
  }
  if (level !== bed.level || bed.aim !== undefined) {
    const fadeMs = skyMoved ? ease : SUN_FADE_MS
    outLevel($, out, bed.file, gain * level, fadeMs)
    Object.assign(bed, { level, aim: undefined, settledAt: now + fadeMs })
  }
}

/** Follows again when the picture starts to move. */
function waitUntil($: EngineInterface, at: number, now: number): void {
  if (waitTimer !== undefined && waitTimer.at === at) return
  waitTimer?.cancel()
  const timer = $.clock.after(Math.max(0, at - now), () => {
    waitTimer = undefined
    void follow($)
  })
  waitTimer = { at, cancel: () => timer.cancel() }
}

/**
 * While sound is on, what plays is checked against the settings and the picture this often, in ms: a change no sound
 * hook sees (reset, `<setting> default`, a click in the room) takes no longer than this.
 */
export const WATCH_MS = 300
let watching = false
/** The minute chain this copy ticks under; a newer one held in $.state means this copy was reloaded. */
let chain: number | undefined
function watch($: EngineInterface): void {
  if (watching) return
  watching = true
  $.clock.after(WATCH_MS, () => {
    watching = false
    void reloaded($).then(isOld => {
      if (isOld) {
        if (out !== undefined) endOut($, out, OFF_FADE_MS)
        out = undefined
        return
      }
      void follow($)
      if (ctxOf($).setting('sound')) watch($)
    })
  })
}
async function reloaded($: EngineInterface): Promise<boolean> {
  if (chain === undefined) return false
  const { value } = await $.state.get({ plugin: 'themes', key: 'bedroom-chain' })
  return value !== undefined && value > chain
}

/** Plays one file now, or after delayMs, at the volume times factor; nothing while sound is off or at volume 0. */
function shoot($: EngineInterface, file: string, factor: number, delayMs = 0): void {
  const fire = (): void => {
    const ctx = ctxOf($)
    if (!ctx.setting('sound') || volumeOf(ctx.saved) === 0 || failure !== undefined || away) return
    void ready($).then(async player => {
      if (player === undefined) return
      if (out === undefined || out.isDone) {
        if (!(await holdsPlayer($, await $.clock.now()))) return
        out = openOut($, player)
        bed = undefined
        void follow($)
      }
      outShot($, out, file, Math.min(1, gainOf(volumeOf(ctxOf($).saved)) * factor))
    })
  }
  if (delayMs <= 0) return fire()
  $.clock.after(delayMs, fire)
}

/**
 * A change made by a command or a card press shows once the app eases the switch's number, about half a second after the
 * redraw is asked; the tape's and the console's go through screen, which the shader takes after ACCEPT.screen s more. A
 * click in the room is answered by the shader in the same frame, so its sound plays at once.
 */
export const COMMAND_LAG_MS = { direction: 510, screen: 510 + ACCEPT.screen * 1000 } as const

/** Whether the room's things make their sounds: on unless /bedroom sound objects off. */
const objectsOn = (saved: Saved): boolean => saved.objects !== false

export function engineSwitched($: EngineInterface, ctx: Ctx, name: Switch, isOn: boolean, by: 'click' | 'command'): void {
  if (!ctx.setting('sound')) return
  const lag = by === 'click' ? 0 : name === 'tape' || name === 'console' ? COMMAND_LAG_MS.screen : COMMAND_LAG_MS.direction
  if (name === 'tv') {
    const tv = chosen(ctx.saved, 'tv')
    return shoot($, isOn ? tv.on : tv.off, 1, lag)
  }
  if (name === 'lava' || !objectsOn(ctx.saved)) return
  const [on, off] = OBJECTS[name]
  shoot($, isOn ? on : off, OBJECT_GAIN, lag)
}

/** The cat purrs when clicked: core/clicks.ts calls this. */
export function purr($: EngineInterface): void {
  const ctx = ctxOf($)
  if (!BUILT.includes('sound') || !ctx.setting('sound') || !objectsOn(ctx.saved)) return
  shoot($, PURR, OBJECT_GAIN)
}

/** A strike the picture shows: when, in ms on the mod's clock, and how far, as the seconds its thunder takes to come (1 to 6). */
export type Strike = { at: number; delayS: number }

/**
 * The thunder for a strike: near (under 2 s), mid (under 4 s) or far, one of its set's files chosen by the strike's
 * second, its gain THUNDER_LIFT times the volume's at 1 s and falling to half that at 6 s, due delayS after the strike.
 */
export function thunderOf(saved: Saved, given: Strike): { file: string; factor: number; at: number } {
  const delayS = Math.min(6, Math.max(1, given.delayS))
  const set = chosen(saved, 'thunder')
  const files: readonly string[] = delayS < 2 ? set.near : delayS < 4 ? set.mid : set.far
  const file = files[Math.floor(given.at / 1000) % files.length] ?? files[0]!
  return { file, factor: THUNDER_LIFT * (1 - 0.1 * (delayS - 1)), at: given.at + delayS * 1000 }
}

/**
 * Thunder plays this many times the volume's gain, and the bed dips to DUCK of its level while it rolls: its recordings
 * hold most of their weight under 250 Hz, where small speakers give little, and at the bed's own level the storm's rain
 * covered them.
 */
export const THUNDER_LIFT = 2
export const DUCK = 0.5
export const DUCK_FADE_MS = { down: 300, up: 1500 } as const

/** Plays a strike's thunder when it is due: each minute's scheduled strike and each one /bedroom weather strike asks for come through it. */
export async function thunderFor($: EngineInterface, given: Strike): Promise<void> {
  const ctx = ctxOf($)
  if (!THUNDERS || !ctx.setting('sound')) return
  const { file, factor, at } = thunderOf(ctx.saved, given)
  const delayMs = at - (await $.clock.now())
  shoot($, file, factor, delayMs)
  $.clock.after(Math.max(0, delayMs), () => duck($, lengthOf(file)))
}

/** Through the mixer, the bed dips under a roll of thunder for `ms` and comes back to its level; elsewhere it plays on. */
function duck($: EngineInterface, ms: number): void {
  const o = out
  if (o?.mixer === undefined || o.isDone || bed === undefined) return
  const ducked = ducks > 0
  ducks += 1
  endSwell($, DUCK_FADE_MS.down)
  if (!ducked) mixerSend($, o, { verb: 'level', gain: bed.gain * bed.level * DUCK, fadeMs: DUCK_FADE_MS.down })
  $.clock.after(ms, () => {
    ducks -= 1
    if (ducks === 0 && out === o && bed !== undefined) mixerSend($, o, { verb: 'level', gain: bed.gain * bed.level, fadeMs: DUCK_FADE_MS.up })
  })
}
/** How many rolls of thunder are sounding: the bed comes back only when the last one ends. */
let ducks = 0

/**
 * Under a cicadas entry with a swell, through the mixer, a nearer cicada now and then over the chorus: the swell loop rises over
 * SWELL.inMs, holds, and falls over SWELL.outMs, SWELL.minMs to SWELL.maxMs in all, at SWELL.peak of the chorus, after
 * a gap of SWELL.gapMin to SWELL.gapMax minutes hashed from the minute (the first one too, so never in the bed's first
 * minute). Only while the chorus plays at full level at the golden hour or dusk, the bed not ducked: anything else (the
 * bed changing, a change of volume, thunder) fades one out.
 */
export const SWELL = { inMs: 5000, outMs: 8000, minMs: 25_000, maxMs: 45_000, peak: 0.6, gapMin: 3, gapMax: 8 } as const
let swell: { file: string; gain: number; o: Out; timer: { cancel: () => void } } | undefined
let nextSwellAt: number | undefined

/** The gap before the next swell from `at`, in ms, and a swell's whole length, each a whole-number hash of the minute. */
export function swellGapMs(at: number): number {
  return (SWELL.gapMin + ((SWELL.gapMax - SWELL.gapMin) * roll(Math.floor(at / 60_000), 1, 13)) / 99) * 60_000
}
export function swellLengthMs(at: number): number {
  return SWELL.minMs + ((SWELL.maxMs - SWELL.minMs) * roll(Math.floor(at / 60_000), 2, 13)) / 99
}

/** Fades a swell in progress out over fadeMs. */
function endSwell($: EngineInterface, fadeMs: number): void {
  if (swell === undefined) return
  swell.timer.cancel()
  if (out === swell.o && !swell.o.isDone) mixerSend($, swell.o, { verb: 'to', name: swell.file, gain: 0, fadeMs, then: 0, thenMs: 0 })
  swell = undefined
}

/** After each step: starts a swell when one is due and allowed, and ends one that is no longer allowed. */
async function swellStep($: EngineInterface): Promise<void> {
  const entry = chosen(ctxOf($).saved, 'cicadas')
  const now = await $.clock.now()
  const o = out
  const allowed =
    o?.mixer !== undefined && !o.isDone && entry.swell !== undefined && bed !== undefined && bed.file === entry.bed && bed.level >= 1 &&
    bed.sky.weather < 2 && (bed.sky.sun === GOLDEN || bed.sky.sun === DUSK) && bed.evening !== true && ducks === 0
  if (!allowed || o === undefined || bed === undefined || entry.swell === undefined) {
    endSwell($, Math.max(OFF_FADE_MS, (bed?.settledAt ?? now) - now))
    nextSwellAt = undefined
    return
  }
  if (swell !== undefined && swell.gain !== bed.gain) endSwell($, LEVEL_FADE_MS)
  nextSwellAt ??= now + swellGapMs(now)
  if (swell !== undefined || now < nextSwellAt) return
  const length = swellLengthMs(now)
  const peak = bed.gain * bed.level * SWELL.peak
  const hold = length - SWELL.inMs - SWELL.outMs
  mixerSend($, o, { verb: 'to', name: entry.swell, gain: peak, fadeMs: SWELL.inMs, then: peak, thenMs: hold })
  const file = entry.swell
  const timer = $.clock.after(SWELL.inMs + hold, () => {
    if (swell?.file === file && out === o && !o.isDone) mixerSend($, o, { verb: 'to', name: file, gain: 0, fadeMs: SWELL.outMs, then: 0, thenMs: 0 })
    swell = undefined
  })
  swell = { file, gain: bed.gain, o, timer }
  nextSwellAt = now + length + swellGapMs(now + length)
}

/**
 * From the tick to the shader taking the minute it sends: the app starts easing a value about 510 ms after a redraw
 * is asked, and the clock column takes a minute once it has stood still 0.4 s.
 */
export const TAKEN_MS = 910

/** How far a minute's scheduled strike is, as its thunder's delay in seconds: 1 to 6, from the minute alone, so the shader can dim a far flash by the same integers. */
export function strikeDelayS(minute: number): number {
  return 1 + ((minute * 7919) % 5001) / 1000
}

/** How far a strike asked for with /bedroom weather strike is, as its thunder's delay in seconds: 1 to 4, from its second. */
export const forcedDelayS = (at: number): number => 1 + (Math.floor(at / 1000) % 4)

/** When the strike asked for last brought its thunder, so each one brings one. */
let heardForced: number | undefined

/** The thunder of the strike /bedroom weather strike asked for, once, unless it has already rolled. */
async function forcedThunder($: EngineInterface): Promise<void> {
  const at = forcedStrikeAt()
  if (at === undefined || at === heardForced) return
  heardForced = at
  const delayS = forcedDelayS(at)
  if ((await $.clock.now()) <= at + delayS * 1000) await thunderFor($, { at, delayS })
}

/**
 * In a storm, this minute's scheduled strike, if it has one, counted from when the shader takes the minute, and only
 * when the shader draws it: none in its first seconds, nor while it hurries after a command.
 */
async function scheduledStrike($: EngineInterface, ctx: Ctx): Promise<void> {
  if (ctx.fields().weather !== 4) return
  const minute = minuteOfHalfDay(ctx.nowMs)
  const second = strike(minute)
  if (second === undefined) return
  const at = ctx.nowMs + TAKEN_MS + second * 1000
  if (!scheduledEventShows(at, worldMove().hurryAt)) return
  await thunderFor($, { at, delayS: strikeDelayS(minute) })
}

export const piece: Piece = { name: 'sound' }

/**
 * The session's ends, which no other part of the mod hears: a desktop window detaching (the app closed while the
 * session runs on) and the session ending, unless a new one follows in this process (clear, resume), fade everything
 * out and keep it silent; a desktop window attaching lets the sound follow the room again.
 */
export function hooks(on: On): void {
  on('session.detach', ($, e, next) => {
    if (e.surface === 'desktop') {
      away = true
      silence($)
    }
    return next(e)
  })
  on('session.attach', ($, e, next) => {
    if (e.surface === 'desktop' && away) {
      away = false
      void follow($)
    }
    return next(e)
  })
  on('session.end', ($, e, next) => {
    if (e.reason !== 'clear' && e.reason !== 'resume') away = true
    silence($)
    return next(e)
  })
}

async function minute($: EngineInterface, ctx: Ctx): Promise<void> {
  chain = (await $.state.get({ plugin: 'themes', key: 'bedroom-chain' })).value
  if ((await ready($)) === undefined) return
  await follow($)
  watch($)
  await scheduledStrike($, ctx)
}

/** Not awaited by the minute: looking for a player must not hold the clock's redraw. */
export async function engineTick($: EngineInterface, ctx: Ctx): Promise<void> {
  if (ctx.setting('sound')) void minute($, ctx).catch(error => fail($, `the minute's sound failed: ${String(error)}`))
}

/** /bedroom sound volume N: 0 to 100, saved; the bed fades to it. */
async function setVolume(ctx: Ctx, word: string | undefined): Promise<string> {
  const amount = Number(word)
  if (word === undefined || word === '' || !Number.isInteger(amount) || amount < 0 || amount > 100) {
    return `give a whole number from 0 to 100, as in /bedroom sound volume 40 (now ${volumeOf(ctx.saved)}); 0 plays nothing`
  }
  await ctx.save({ volume: amount })
  return `volume ${amount}${amount === 0 ? ': nothing plays' : ''}`
}

const bankWords = (saved: Saved): string => KINDS.map(kind => `${kind} ${chosenName(saved, kind)}`).join(', ')

/** /bedroom sound pick KIND NAME: which entry of the bank a kind plays, saved; the bed fades to it. */
async function setPick(ctx: Ctx, kind: string | undefined, name: string | undefined): Promise<string> {
  const known = KINDS.includes(kind as Kind) ? (kind as Kind) : undefined
  const names = known === undefined ? [] : namesOf(known)
  const picked = name === undefined ? undefined : /^\d$/.test(name) ? names[Number(name) - 1] : names.find(entry => entry === name)
  if (known === undefined || picked === undefined) {
    const kinds = KINDS.map(each => `${each}: ${namesOf(each).join(' or ')}`).join('; ')
    return `say a kind and one of its sounds, as in /bedroom sound pick cicadas river. ${kinds}. Now: ${bankWords(ctx.saved)}`
  }
  await ctx.save({ bank: { ...ctx.saved.bank, [known]: picked } })
  return `${known} plays ${picked}`
}

/** The voices the running mixer reports, waited for VOICES_WAIT_MS; undefined when it does not answer in time. */
function askVoices($: EngineInterface, o: Out, m: Mixer): Promise<MixerVoice[] | undefined> {
  return new Promise(resolve => {
    const timer = $.clock.after(VOICES_WAIT_MS, () => {
      if (m.asked?.answer === answer) m.asked = undefined
      resolve(undefined)
    })
    const answer = (voices: MixerVoice[]): void => {
      timer.cancel()
      resolve(voices)
    }
    mixerSend($, o, { verb: 'voices' })
    m.asked = { seq: m.seq, answer }
  })
}

const voiceWords = (v: MixerVoice): string =>
  `${v.name} volume ${v.volume.toFixed(4)} at ${Math.round(v.atMs)} ms, length ${v.lengthKnown ? 'known' : 'unknown'}${v.drop ? ', ending' : ''}`

/** The end of /bedroom sound: the mixer's own report of its voices, how long since it last wrote, and the last file it could not open. */
async function mixerWords($: EngineInterface): Promise<string> {
  const now = await $.clock.now()
  const failed = lastFailed === undefined ? '' : ` last open failure: ${lastFailed.name} ${Math.round((now - lastFailed.at) / 1000)} s ago: ${lastFailed.text}.`
  const o = out
  if (o?.mixer === undefined || o.isDone) return failed
  const m = o.mixer
  const voices = await askVoices($, o, m)
  const said = voices === undefined ? 'no answer' : voices.length === 0 ? 'none' : voices.map(voiceWords).join('; ')
  return ` mixer last heard ${Math.max(0, Math.round((await $.clock.now()) - m.heardAt))} ms ago; its voices: ${said}.${failed}`
}

const WHAT ='the television, the room\'s things, cicadas from mid-afternoon through dusk and crickets and katydids from evening until dawn in dry weather, rain, a downpour and a storm'

/**
 * /bedroom sound on|off|test|volume N|pick KIND NAME|objects on|off. test plays only the silent file, and looks without
 * forgetting a failure. Another word (the weather, the time) is answered after this returns, so the sound follows it
 * on the next turn of the clock.
 */
export async function engineCommand($: EngineInterface, ctx: Ctx, word: string, args: readonly string[]): Promise<string | undefined> {
  if (word !== 'sound') {
    if (ctx.setting('sound')) $.clock.after(0, () => void follow($))
    return undefined
  }
  const what = (args[0] ?? '').toLowerCase()
  const none = `no player was found (looked for ${PLAYERS.join(', ')} on PATH; the soundPlayer setting names one, with {file} for the file and {volume} for 0 to 100)`
  try {
    if (what === 'off') {
      await ctx.save({ sound: false })
      await follow($)
      return 'sound is off: what was playing has faded out'
    }
    if (what === 'on') {
      const player = await lookAgain($)
      if (player === undefined) return `${none}, so sound stays off`
      chain = (await $.state.get({ plugin: 'themes', key: 'bedroom-chain' })).value
      await ctx.save({ sound: true })
      await follow($)
      watch($)
      return `sound is on, played by ${player.name} at volume ${volumeOf(ctx.saved)}: ${WHAT}${THUNDERS ? ' with thunder' : ''}`
    }
    if (what === 'volume' || what === 'pick') {
      const answer = what === 'volume' ? await setVolume(ctx, args[1]) : await setPick(ctx, args[1]?.toLowerCase(), args[2]?.toLowerCase())
      if (what === 'pick' && out !== undefined) for (const name of shotsOf(ctx.saved)) mixerSend($, out, { verb: 'load', name })
      await follow($)
      return answer
    }
    if (what === 'objects') {
      const value = (args[1] ?? '').toLowerCase()
      if (value !== 'on' && value !== 'off') return `say on or off, as in /bedroom sound objects off (now ${objectsOn(ctx.saved) ? 'on' : 'off'})`
      await ctx.save({ objects: value === 'on' })
      return `the room's things ${value === 'on' ? 'make their sounds' : 'are quiet'}: the lamp, the light, the monitor, the console, the tape and the cat`
    }
    if (what === 'test') {
      const player = await find($)
      if (player === undefined) return none
      if (player.kind === 'engine') {
        await $.audio.play({ asset: `sounds/bedroom/${SILENCE}` })
        return `${player.name} played ${SILENCE}`
      }
      if (player.kind === 'mixer') {
        const { exitCode } = await $.process.run(powershellArgv('Add-Type -AssemblyName PresentationCore'), { timeoutMs: 20_000 })
        return `${player.name} loaded its player and exited ${exitCode}`
      }
      const { exitCode } = await $.process.run(player.argv(SILENCE, 0, false), { timeoutMs: lengthOf(SILENCE) + 15_000 })
      return `${player.name} played ${SILENCE} and exited ${exitCode}`
    }
    if (what !== '') return 'say on, off, test, volume N, pick KIND NAME or objects on|off, as in /bedroom sound on'
    const player = finding === undefined ? 'not looked for yet' : ((await finding)?.name ?? 'none found')
    const last = lastShot === undefined ? 'none yet' : `${lastShot.file.replace(/\.wav$/, '')} ${Math.round(((await $.clock.now()) - lastShot.at) / 1000)} s ago`
    const now = await $.clock.now()
    const silent =
      failure !== undefined
        ? `${failure}${retryAt === undefined ? '; say /bedroom sound on to try again' : `; the mixer starts again in ${Math.max(0, Math.ceil((retryAt - now) / 1000))} s`}`
        : away
          ? 'no desktop window shows this session'
          : (await newerHolds($))
            ? 'a newer copy of the mod plays it'
            : out === undefined || out.isDone
              ? 'no player is running yet; it starts within a second'
              : undefined
    const state = !ctx.setting('sound') ? 'off' : silent === undefined ? 'on' : `on but nothing plays: ${silent}`
    return `sound is ${state}, volume ${volumeOf(ctx.saved)}, objects ${objectsOn(ctx.saved) ? 'on' : 'off'}. bank: ${bankWords(ctx.saved)}. player: ${player}${out?.mixer?.pid === undefined ? '' : ` (powershell.exe process ${out.mixer.pid})`}${failure === undefined ? '' : `, stopped: ${failure}`}. last one-shot sent: ${last}. Say on, off, test, volume N, pick KIND NAME or objects on|off${await mixerWords($).then(words => (words === '' ? '' : `.${words}`))}`
  } catch (error) {
    return `sound could not answer: ${error instanceof Error ? error.message : String(error)}`
  }
}

/** The bed playing now, as the card names it: cicadas, night insects, rain, downpour, storm, or quiet. */
export function bedName(): string {
  if (bed?.file === undefined) return 'quiet'
  if (bed.file.startsWith('cicadas/')) return 'cicadas'
  if (bed.file.startsWith('crickets/')) return 'night insects'
  return bed.file.match(/-(rain|downpour|storm)\.wav$/)?.[1] ?? 'rain'
}
