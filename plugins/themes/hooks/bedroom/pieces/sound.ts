import type { EngineInterface } from 'claude-code'

import { minuteOfHalfDay } from '../core/clock.js'
import { ctxOf } from '../core/context.js'
import type { Ctx, Piece, Switch } from '../core/piece.js'
import { volumeOf, type Saved } from '../core/saved.js'
import { strike } from '../core/schedule.js'
import { ACCEPT, BUILT, HURRY, WITHOUT, WORLD } from '../core/signals.gen.js'
import { flush } from '../core/telemetry.js'
import { worldMove } from '../core/values.js'
import { KINDS, OBJECTS, PURR, SILENCE, chosen, chosenName, lengthOf, namesOf, shotsOf, type Kind } from './sound-bank.js'
import { PING_MS, fileOf, linesOf, mixerScript, type MixerCommand } from './sound-mixer.js'

/**
 * Sound, off by default (/bedroom sound): a bed (cicadas from dusk through night in dry weather; rain, a downpour or a
 * storm), the television, the room's things, the cat, and thunder after each strike, from the bank in sound-bank.ts.
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

/** One line in the debug log, everything playing stopped, and no sound until /bedroom sound on. */
function fail($: EngineInterface, why: string): void {
  if (failure !== undefined) return
  failure = why
  ctxOf($).note(`sound: ${why}; nothing plays until /bedroom sound on`)
  flush($)
  if (out !== undefined) endOut($, out, 0)
  out = undefined
  bed = undefined
}

/** The player while sound is on and none has failed; looked for once. */
async function ready($: EngineInterface): Promise<Player | undefined> {
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
type Mixer = { seq: number; pending: { seq: number; command: MixerCommand }[]; path?: string; writing: Promise<void>; kill?: () => void; heard: number }
type Out = { player: Player; isDone: boolean; mixer?: Mixer; bedPlay?: Play; shots: Set<Play> }
let out: Out | undefined
/** The bed playing now: its file, the sky it was chosen for and its gain. */
let bed: { file: string | undefined; sky: Sky; gain: number } | undefined

/** The mixer reports this many one-shots' latency in the debug log, from the write to the player's position moving. */
const LATENCY_NOTES = 3

function openOut($: EngineInterface, player: Player): Out {
  const opened: Out = { player, isDone: false, shots: new Set() }
  if (player.kind === 'mixer') {
    opened.mixer = { seq: 0, pending: [], writing: Promise.resolve(), heard: 0 }
    void runMixer($, opened, opened.mixer).catch(error => fail($, `the mixer failed: ${error instanceof Error ? error.message : String(error)}`))
    for (const name of shotsOf(ctxOf($).saved)) mixerSend($, opened, { verb: 'load', name })
    pingLater($, opened)
  }
  return opened
}

/** The mixer's child, read for its life: its lines, then how it ended. Leaving the loop ends the child. */
async function runMixer($: EngineInterface, o: Out, m: Mixer): Promise<void> {
  if (o.player.kind !== 'mixer') return
  const child = $.process.spawn({ argv: ['powershell.exe', '-NoProfile', '-NonInteractive', '-Command', mixerScript(o.player.root)] })
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
    const read = linesOf(rest + piece.text)
    rest = read.rest
    for (const line of read.lines) {
      if (line.kind === 'ready') {
        m.path = o.player.wsl ? (await $.process.run(['wslpath', '-u', line.path])).stdout.trim() : line.path
        writeCommands($, m)
      } else if (line.kind === 'ok') {
        m.pending = m.pending.filter(entry => entry.seq > line.seq)
      } else if (line.kind === 'sounding' && m.heard < LATENCY_NOTES) {
        m.heard += 1
        const sent = sentAt.get(line.seq)
        if (sent !== undefined) ctxOf($).note(`sound: ${sent.name} sounding ${Math.round((await $.clock.now()) - sent.at)} ms after it was sent`)
        flush($)
      } else if (line.kind === 'error') {
        said = line.text
      }
    }
  }
  if (o.isDone) return
  const { code } = await child.result
  const last = said.split(/[\r\n]+/).filter(line => line.trim() !== '').at(-1)?.trim() ?? ''
  fail($, `the mixer exited ${code}${last === '' ? '' : `: ${last.slice(0, 160)}`}`)
}
/** When each of the last one-shots was sent, by seq, for the latency notes. */
const sentAt = new Map<number, { name: string; at: number }>()

/** Writes the command file whole: every command not yet answered. Writes go one after another. */
function writeCommands($: EngineInterface, m: Mixer): void {
  const path = m.path
  if (path === undefined) return
  m.writing = m.writing
    .then(() => $.fs.write(path, fileOf(m.pending)))
    .catch(error => fail($, `writing the mixer's commands failed: ${error instanceof Error ? error.message : String(error)}`))
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

/** Changes the bed: a cross-fade of fadeMs through the mixer, a cut elsewhere. */
function outBed($: EngineInterface, o: Out, file: string | undefined, gain: number, fadeMs: number): void {
  if (o.mixer !== undefined) return mixerSend($, o, { verb: 'bed', name: file, gain, fadeMs })
  if (o.bedPlay !== undefined) stopPlay(o.bedPlay)
  o.bedPlay = undefined
  if (file === undefined) return
  const play: Play = { stopped: false }
  o.bedPlay = play
  void runBed($, o, file, gain, play).catch(error => fail($, `the bed failed: ${String(error)}`))
}

/** The bed's level: a fade through the mixer; elsewhere the bed starts again at it. */
function outLevel($: EngineInterface, o: Out, file: string | undefined, gain: number): void {
  if (o.mixer !== undefined) return mixerSend($, o, { verb: 'level', gain, fadeMs: LEVEL_FADE_MS })
  outBed($, o, file, gain, 0)
}

function outShot($: EngineInterface, o: Out, file: string, gain: number): void {
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

/** The bed for a sky: one weather's in rain, downpour and storm; cicadas from dusk through night when dry. */
export function bedOf(saved: Saved, sky: Sky): string | undefined {
  if (sky.weather >= 2) {
    const rain = chosen(saved, 'rain')
    return sky.weather === 2 ? rain.rain : sky.weather === 3 ? rain.downpour : rain.storm
  }
  return sky.sun <= 2 ? chosen(saved, 'cicadas').bed : undefined
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
export function follow($: EngineInterface): Promise<void> {
  stepping = stepping.then(() => step($)).catch(error => fail($, `following the room failed: ${error instanceof Error ? error.message : String(error)}`))
  return stepping
}

async function step($: EngineInterface): Promise<void> {
  const ctx = ctxOf($)
  if (!ctx.setting('sound') || volumeOf(ctx.saved) === 0) {
    if (out !== undefined) endOut($, out, OFF_FADE_MS)
    out = undefined
    bed = undefined
    return
  }
  const player = await ready($)
  if (player === undefined) return
  if (out === undefined || out.isDone) {
    out = openOut($, player)
    bed = undefined
  }
  const gain = gainOf(volumeOf(ctx.saved))
  const now = await $.clock.now()
  const shown = shownOf(worldMove(), ctx.fields(), bed?.sky, now)
  if (shown === undefined) return
  const file = bedOf(ctx.saved, shown.sky)
  if (bed === undefined) {
    outBed($, out, file, gain, START_FADE_MS)
    bed = { file, sky: shown.sky, gain }
    return
  }
  if (file !== bed.file) {
    const skyMoved = shown.sky.sun !== bed.sky.sun || shown.sky.weather !== bed.sky.weather
    if (skyMoved && now < shown.at) return waitUntil($, shown.at, now)
    const fadeMs = skyMoved ? Math.max(OFF_FADE_MS, shown.fadeMs - (now - shown.at)) : PICK_FADE_MS
    outBed($, out, file, gain, fadeMs)
    bed = { file, sky: shown.sky, gain }
    return
  }
  bed.sky = shown.sky
  if (gain !== bed.gain) {
    outLevel($, out, bed.file, gain)
    bed.gain = gain
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
    if (!ctx.setting('sound') || volumeOf(ctx.saved) === 0 || failure !== undefined) return
    void ready($).then(player => {
      if (player === undefined) return
      if (out === undefined || out.isDone) {
        out = openOut($, player)
        bed = undefined
        void follow($)
      }
      outShot($, out, file, gainOf(volumeOf(ctxOf($).saved)) * factor)
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
 * second, its gain falling from 1 at 1 s to 0.35 at 6 s, due delayS after the strike.
 */
export function thunderOf(saved: Saved, given: Strike): { file: string; factor: number; at: number } {
  const delayS = Math.min(6, Math.max(1, given.delayS))
  const set = chosen(saved, 'thunder')
  const files: readonly string[] = delayS < 2 ? set.near : delayS < 4 ? set.mid : set.far
  const file = files[Math.floor(given.at / 1000) % files.length] ?? files[0]!
  return { file, factor: Math.max(0.35, 1 - 0.13 * (delayS - 1)), at: given.at + delayS * 1000 }
}

/** Plays a strike's thunder when it is due. The picture calls this for each strike it shows; the minute's scheduled ones come through it too. */
export async function thunderFor($: EngineInterface, given: Strike): Promise<void> {
  const ctx = ctxOf($)
  if (!THUNDERS || !ctx.setting('sound')) return
  const { file, factor, at } = thunderOf(ctx.saved, given)
  shoot($, file, factor, at - (await $.clock.now()))
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

/** In a storm, this minute's scheduled strike, if it has one, counted from when the shader takes the minute. */
async function scheduledStrike($: EngineInterface, ctx: Ctx): Promise<void> {
  if (ctx.fields().weather !== 4) return
  const minute = minuteOfHalfDay(ctx.nowMs)
  const at = strike(minute)
  if (at === undefined) return
  await thunderFor($, { at: ctx.nowMs + TAKEN_MS + at * 1000, delayS: strikeDelayS(minute) })
}

export const piece: Piece = { name: 'sound' }

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

const WHAT = 'the television, the room\'s things, cicadas from dusk through night in dry weather, rain, a downpour and a storm'

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
        const { exitCode } = await $.process.run(['powershell.exe', '-NoProfile', '-NonInteractive', '-Command', 'Add-Type -AssemblyName PresentationCore'], { timeoutMs: 20_000 })
        return `${player.name} loaded its player and exited ${exitCode}`
      }
      const { exitCode } = await $.process.run(player.argv(SILENCE, 0, false), { timeoutMs: lengthOf(SILENCE) + 15_000 })
      return `${player.name} played ${SILENCE} and exited ${exitCode}`
    }
    if (what !== '') return 'say on, off, test, volume N, pick KIND NAME or objects on|off, as in /bedroom sound on'
    const player = finding === undefined ? 'not looked for yet' : ((await finding)?.name ?? 'none found')
    return `sound is ${ctx.setting('sound') ? 'on' : 'off'}, volume ${volumeOf(ctx.saved)}, objects ${objectsOn(ctx.saved) ? 'on' : 'off'}. bank: ${bankWords(ctx.saved)}. player: ${player}${failure === undefined ? '' : `, stopped: ${failure}`}. Say on, off, test, volume N, pick KIND NAME or objects on|off`
  } catch (error) {
    return `sound could not answer: ${error instanceof Error ? error.message : String(error)}`
  }
}

/** The bed playing now, as the card names it: cicadas, rain, downpour, storm, or quiet. */
export function bedName(): string {
  if (bed?.file === undefined) return 'quiet'
  return bed.file.startsWith('cicadas/') ? 'cicadas' : (bed.file.match(/-(rain|downpour|storm)\.wav$/)?.[1] ?? 'rain')
}
