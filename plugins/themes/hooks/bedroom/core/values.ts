import type { EngineInterface, Timer } from 'claude-code'

import type { State } from '../scene/lib.ts'
import { readNow } from './clock.js'
import type { Fields } from './piece.js'
import { SCREEN, VALUES, WORLD } from './signals.gen.js'

/**
 * What the mod sends the shader, and when. Every value the Shader element gets comes from the queue here. Each redraw
 * hands the element the values last given, with at most three waiting names moved one step (the direction switches,
 * screen, world, then clock): the app folds calls that come together into one redraw, and clears the shader's buffers
 * once many values change.
 */
export type Name = keyof typeof VALUES
export const DIRECTION = ['tv', 'lava', 'pc', 'lamp', 'light'] as const
export type Direction = (typeof DIRECTION)[number]
const ORDER: readonly Name[] = [...DIRECTION, 'screen', 'world', 'clock']
/** Names moved in one redraw, at most. */
export const MOST_A_REDRAW = 3
/** While a name waits, the next redraw is asked this long after. */
export const REASK_MS = 300
/**
 * A name's second step comes no sooner than this after its first. Under a smoothstep of 8 s the number moves only 0.018
 * of the way to 0.5 in 0.9 s, under the shader's 0.02 threshold, so the first move would be lost; in 1.5 s it moves 0.046.
 */
export const SECOND_STEP_MS = 1500
/** Two screen sends are at least this far apart: the shader takes a code only once it has held still. */
export const SCREEN_GAP_MS = 3500
/** A changed world is sent at most once in this time. */
export const WORLD_GAP_MS = 6000
/** A hurried change this soon after the last flip sent flips nothing: that flip's 30 s, which stand still while world moves, cover it. */
export const HURRY_GAP_MS = 12_000

const zero = (): Record<Name, number> => Object.fromEntries(Object.keys(VALUES).map(name => [name, 0])) as Record<Name, number>
let given = zero()
const waiting = new Map<Name, { steps: number[]; firstAt?: number }>()

/** Sets what a name should become: one number, or two in order. */
export function want(name: Name, steps: number | readonly number[]): void {
  waiting.set(name, { steps: typeof steps === 'number' ? [steps] : [...steps] })
}

/** The values for one redraw, and whether any name still waits. */
export function nextValues(now: number): { values: Record<Name, number>; moved: Name[]; waits: boolean } {
  const moved: Name[] = []
  for (const name of ORDER) {
    if (moved.length === MOST_A_REDRAW) break
    const wait = waiting.get(name)
    if (wait === undefined || (wait.firstAt !== undefined && now - wait.firstAt < SECOND_STEP_MS)) continue
    given[name] = wait.steps.shift() ?? given[name]
    moved.push(name)
    if (wait.steps.length === 0) waiting.delete(name)
    else wait.firstAt = now
  }
  return { values: { ...given }, moved, waits: waiting.size > 0 }
}

/** The screen value's fields: the hurry bit, the hall bit, and the tape's and console's state with a sequence bit each. */
export type Screen = { hurry: number; hall: number; tape: number; tapeSeq: number; console: number; consoleSeq: number }
let screen: Screen = { hurry: 0, hall: 0, tape: 0, tapeSeq: 0, console: 0, consoleSeq: 0 }
export type ScreenChange = { field: 'hurry' } | { field: 'hall' | 'tape' | 'console'; value: number }
const screenQueue: ScreenChange[] = []
let screenAt = -Infinity
/** When a hurry flip was last sent since the shader started. */
let hurryAt = -Infinity
/** By when the shader can have taken the last screen code sent, under every ease the app may use. */
let takenBy = -Infinity
/**
 * By when the shader can have taken a code that holds the last flip sent. hurry is one bit, so a second flip sent before
 * then can turn the number back to the bit the shader holds, and neither lands. A tape, console or hall send after a flip
 * carries its bit, so it delays the flip's taking and never cancels it.
 */
let flipTakenBy = -Infinity
/** The tape and the console when a change for them has been sent since the shader started. */
const screenSent = new Set<'tape' | 'console'>()
/**
 * The tape and the console, with their saved state, the time of the last click on them and how many times the state
 * has been sent once more, when a click came while a change for them may not have landed.
 */
const unsure = new Map<'tape' | 'console', { value: number; clickedAt: number; sends: number }>()
/**
 * How long the screen number rests before a noted switch's state is sent once more: first when the eases that settle
 * soon have settled, then when every ease the app may use has (an exponential or a spring of 4 s takes about 30 s to
 * bring a jump of 60 codes to rest and hold it 3 s). Sends 3.5 s apart under an ease slower than 3 s keep the shader
 * from taking any code until they stop, so the rest counts from the last send, or from the last click on the switch if
 * that came later: a send never follows a click at once, where it could land over the next click.
 */
export const SCREEN_RESTS_MS = [10_000, 32_000] as const
/** How long a noted switch's next rest has run. */
const restedFor = (entry: { clickedAt: number }, now: number): number => now - Math.max(screenAt, entry.clickedAt)

export const encodeScreen = (s: Screen): number =>
  s.hurry * SCREEN.hurry + s.hall * SCREEN.hall + (s.tape + 2 * s.tapeSeq) * SCREEN.tape + (s.console + 2 * s.consoleSeq) * SCREEN.console
export const encodeWorld = (f: Fields): number => f.sun + WORLD.sun * (f.weather + WORLD.weather * (f.work + WORLD.work * f.zone))

function applyChange(s: Screen, change: ScreenChange): Screen {
  if (change.field === 'hurry') return { ...s, hurry: 1 - s.hurry }
  if (change.field === 'hall') return { ...s, hall: change.value }
  if (change.field === 'tape') return { ...s, tape: change.value, tapeSeq: 1 - s.tapeSeq }
  return { ...s, console: change.value, consoleSeq: 1 - s.consoleSeq }
}

/** One field changes for each send: a command for the tape or the console flips its sequence bit. */
export function queueScreen(change: ScreenChange): void {
  if (change.field === 'hall') {
    const ahead = screenQueue.reduce(applyChange, screen)
    if (ahead.hall === change.value) return
  }
  screenQueue.push(change)
}

/**
 * Sends the next screen change if its time has come; the milliseconds until the next can go, if one waits. A flip waits,
 * and the other changes go before it, until a code holding the last flip can have been taken: 10 s after a flip sent
 * onto a number at rest, 32 s after any other send (SCREEN_RESTS_MS).
 */
export function pumpScreen(now: number): number | undefined {
  const held = now < flipTakenBy
  const next = screenQueue.findIndex(change => change.field !== 'hurry' || !held)
  if (next === -1) return screenQueue.length > 0 ? flipTakenBy - now : undefined
  if (now - screenAt < SCREEN_GAP_MS) return SCREEN_GAP_MS - (now - screenAt)
  const [change] = screenQueue.splice(next, 1) as [ScreenChange]
  screen = applyChange(screen, change)
  if (change.field === 'tape' || change.field === 'console') screenSent.add(change.field)
  const lone = change.field === 'hurry' && now >= takenBy
  takenBy = now + SCREEN_RESTS_MS[lone ? 0 : 1]
  if (change.field === 'hurry') hurryAt = now
  if (change.field === 'hurry' || held) flipTakenBy = takenBy
  screenAt = now
  want('screen', encodeScreen(screen))
  return screenQueue.length > 0 ? SCREEN_GAP_MS : undefined
}

let worldSent = 0
let worldAt = -Infinity
let worldWaiting: number | undefined
let sunSent = 0

/** Sends world if 6 s have passed since the last send, else keeps it waiting (a later one replaces it). */
function offerWorld(code: number, now: number): number | undefined {
  if (code === worldSent) {
    worldWaiting = undefined
    return undefined
  }
  if (now - worldAt >= WORLD_GAP_MS) {
    worldSent = code
    worldWaiting = undefined
    worldAt = now
    want('world', code)
    return undefined
  }
  worldWaiting = code
  return WORLD_GAP_MS - (now - worldAt)
}

/** The number last sent for each direction switch. The shader turns a switch the way its number moves, so a click in the room never changes it. */
let sent: Record<Direction, number> = { tv: 0, lava: 0, pc: 0, lamp: 0, light: 0 }

/**
 * A /bedroom command for a direction switch. Already where the mod believes it: nothing is sent. The number last sent
 * differs from the target: it is sent, and moves the right way once. Otherwise (a click turned the switch since) the
 * number goes to the middle and then to the target SECOND_STEP_MS later, so its first move orders the state already drawn.
 */
export function commandSwitch(name: Direction, target: number, belief: boolean): 'already' | 'sent' | 'turned' {
  if ((belief ? 1 : 0) === target) return 'already'
  const isTurned = sent[name] === target
  want(name, isTurned ? [0.5, target] : target)
  sent[name] = target
  return isTurned ? 'turned' : 'sent'
}

/** Every name at its target, from the saved state and the fields: at load and when the room-alone hold ends. */
export function startShader(state: State, fields: Fields, minute: number, now: number): void {
  sent = { tv: state.tv ? 1 : 0, lava: state.lava ? 1 : 0, pc: state.pc ? 1 : 0, lamp: state.lamp ? 1 : 0, light: state.light ? 1 : 0 }
  screen = { hurry: 0, hall: fields.hall, tape: state.tape ? 1 : 0, tapeSeq: 0, console: state.console ? 1 : 0, consoleSeq: 0 }
  screenQueue.length = 0
  screenSent.clear()
  unsure.clear()
  screenAt = now
  hurryAt = -Infinity
  takenBy = now + SCREEN_RESTS_MS[1]
  flipTakenBy = -Infinity
  worldSent = encodeWorld(fields)
  worldWaiting = undefined
  worldAt = now
  sunSent = fields.sun
  given = { ...sent, clock: minute, screen: encodeScreen(screen), world: worldSent }
  waiting.clear()
}

let cause = 'load'
let screenTimer: { at: number; timer: Timer } | undefined
let worldTimer = false

/** Why the last redraw was asked. */
export function lastCause(): string {
  return cause
}

/** Reads the clock, then asks for a redraw; the render reads the time kept. */
export async function ask($: EngineInterface, why: string): Promise<void> {
  cause = why
  await readNow($)
  $.ui.invalidate('ui.render')
}

/**
 * Rebuilds world and screen from the fields, within the limits above: what waits goes out when its turn comes. hurry:
 * the change came from a command, so the shader moves to it fast; it also hurries when the sun moves other than one
 * row forward, and after a stall (the minute tick came more than 5 minutes after the last). One flip at most, and none
 * while one waits or within HURRY_GAP_MS of the last sent. Returns the milliseconds until world and screen can next
 * move, where one waits.
 */
export function rebuild(fields: Fields, now: number, options: { hurry?: boolean; stalled?: boolean } = {}): { world?: number; screen?: number } {
  queueScreen({ field: 'hall', value: fields.hall })
  let hurries = options.stalled === true
  const code = encodeWorld(fields)
  if (code !== (worldWaiting ?? worldSent)) {
    const jumps = fields.sun !== sunSent && fields.sun !== (sunSent + 1) % WORLD.sun
    hurries ||= options.hurry === true || jumps
    sunSent = fields.sun
  }
  if (hurries && !screenQueue.some(change => change.field === 'hurry') && now - hurryAt >= HURRY_GAP_MS) queueScreen({ field: 'hurry' })
  return { world: offerWorld(code, now), screen: pumpScreen(now) }
}

/** A minute tick more than this after the last means the clock stalled (the machine slept, or the app was hidden). */
export const STALL_MS = 5 * 60_000

/**
 * The clock ran `ms` with no frame drawn, so the shader took nothing meanwhile. The times by which it can have taken a
 * code, and the last screen send, move on by that much; counting more than it slept only holds a flip longer. The last
 * flip's time is forgotten instead: its 30 s may have run out before the sleep, so the 12 s rule would drop a flip that
 * is needed, and the hold sends it once the last can have been taken.
 */
export function slept(ms: number): void {
  takenBy += ms
  flipTakenBy += ms
  screenAt += ms
  for (const entry of unsure.values()) entry.clickedAt += ms
  hurryAt = -Infinity
}

/**
 * The minute tick's send, `gap` after the last tick. After a stall the shader catches up fast, and none of the gap is
 * counted as drawn: the machine may have slept from just after the last tick.
 */
export function sendMinute($: EngineInterface, fields: Fields, gap: number): Promise<void> {
  const stalled = gap > STALL_MS
  if (stalled) slept(gap)
  return send($, 'the minute turning', fields, { stalled })
}

/** Rebuilds world and screen, arms what waits, and asks for a redraw. */
export async function send($: EngineInterface, why: string, fields: Fields, options: { hurry?: boolean; stalled?: boolean } = {}): Promise<void> {
  const now = await readNow($)
  const delay = rebuild(fields, now, options)
  if (delay.world !== undefined && !worldTimer) armWorld($, delay.world)
  if (delay.screen !== undefined) armScreen($, now, delay.screen)
  await ask($, why)
}

/** Offers the world that waits once its 6 s have passed; a shader start since the timer was armed moves them later. */
function armWorld($: EngineInterface, delay: number): void {
  worldTimer = true
  $.clock.after(delay, () => {
    worldTimer = false
    void readNow($).then(later => {
      const again = worldWaiting === undefined ? undefined : offerWorld(worldWaiting, later)
      if (again === undefined) return ask($, 'world waited its 6 s')
      armWorld($, again)
      return undefined
    })
  })
}

/** Arms one timer for the next screen send; a sooner one replaces a later (a held flip's can be 32 s off). */
function armScreen($: EngineInterface, now: number, delay: number): void {
  const at = now + delay
  if (screenTimer !== undefined && screenTimer.at <= at) return
  screenTimer?.timer.cancel()
  const timer = $.clock.after(delay, () => {
    screenTimer = undefined
    void readNow($).then(later => {
      const again = pumpScreen(later)
      if (again !== undefined) armScreen($, later, again)
      return ask($, 'a screen change waited its turn')
    })
  })
  screenTimer = { at, timer }
}

/**
 * After a click turned the tape or the console. The shader has answered it, but a change for that switch sent while
 * the screen number has not rested can land after the click and turn it back, or carry a field the shader already holds
 * from an older code and change nothing. So a change for it that still waits takes the click's state, and after each
 * rest of SCREEN_RESTS_MS, counted from the last send or the last click on it, the saved state is sent once more
 * (confirmScreen): a change of one field from the last code, as a command is. Nothing is sent at a click, so the number
 * never turns back toward an older code while it moves, and a send never lands over a click just after it.
 */
export function noteScreenClick(name: 'tape' | 'console', isOn: boolean, now: number): void {
  const value = isOn ? 1 : 0
  const queued = screenQueue.find(change => change.field === name)
  if (queued !== undefined && queued.field !== 'hurry') queued.value = value
  const moving = screenSent.has(name) && now - screenAt < SCREEN_RESTS_MS[1]
  if (queued !== undefined || unsure.has(name) || moving) unsure.set(name, { value, clickedAt: now, sends: 0 })
}

/** The milliseconds until the next noted switch's rest has come (0 or less: it has), if one is noted. */
export function restLeft(now: number): number | undefined {
  let left: number | undefined
  for (const entry of unsure.values()) {
    const due = SCREEN_RESTS_MS[entry.sends]! - restedFor(entry, now)
    left = Math.min(left ?? due, due)
  }
  return left
}

/** Queues each noted switch whose rest has come. */
export function confirmScreen(now: number): void {
  for (const [field, entry] of unsure) {
    if (SCREEN_RESTS_MS[entry.sends]! > restedFor(entry, now)) continue
    screenQueue.push({ field, value: entry.value })
    entry.sends += 1
    if (entry.sends === SCREEN_RESTS_MS.length) unsure.delete(field)
  }
}

let confirmTimer: { at: number; timer: Timer } | undefined
/** Arms one timer for the next rest; a sooner rest, after a new click, replaces a later one. A send starts the rest again. */
function armConfirm($: EngineInterface, now: number): void {
  const left = restLeft(now)
  if (left === undefined) return
  const at = now + Math.max(0, left)
  if (confirmTimer !== undefined && confirmTimer.at <= at) return
  confirmTimer?.timer.cancel()
  const timer = $.clock.after(at - now, () => {
    confirmTimer = undefined
    void readNow($).then(later => {
      confirmScreen(later)
      const queued = screenQueue.length
      const again = pumpScreen(later)
      if (again !== undefined) armScreen($, later, again)
      armConfirm($, later)
      if (screenQueue.length < queued) return ask($, 'a clicked switch sent once more')
      return undefined
    })
  })
  confirmTimer = { at, timer }
}

/** Notes a click on the tape or the console, and arms the send once more where one is due. */
export function clickScreen($: EngineInterface, name: 'tape' | 'console', isOn: boolean, now: number): void {
  noteScreenClick(name, isOn, now)
  armConfirm($, now)
}

/** Queues a command for the tape or the console and sends it when screen's turn comes; answers how long until it goes, in ms. */
export async function commandScreen($: EngineInterface, name: 'tape' | 'console', target: number, why: string): Promise<number> {
  const noted = unsure.get(name)
  if (noted !== undefined) noted.value = target
  queueScreen({ field: name, value: target })
  const now = await readNow($)
  const waitsBefore = screenQueue.length
  const delay = pumpScreen(now)
  if (delay !== undefined) armScreen($, now, delay)
  await ask($, why)
  return screenQueue.length < waitsBefore ? 0 : (delay ?? 0)
}

/**
 * The last world code sent and when (-Infinity before the shader starts), when a hurry flip last went and whether one
 * waits to go: what the sound reads to change its bed with the picture, not with the command.
 */
export function worldMove(): { code: number; at: number; hurryAt: number; hurryWaits: boolean } {
  return { code: worldSent, at: worldAt, hurryAt, hurryWaits: screenQueue.some(change => change.field === 'hurry') }
}
