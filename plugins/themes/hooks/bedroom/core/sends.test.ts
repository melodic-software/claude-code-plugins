import type { EngineInterface } from 'claude-code'
import { expect, test } from 'claude-code/testing'

import { DEFAULT_STATE } from '../scene/lib.ts'
import { CUES, WORLD } from './signals.gen.js'
import { HURRY_GAP_MS, REASK_MS, SCREEN_RESTS_MS, STALL_MS, confirmScreen, encodeWorld, nextValues, noteScreenClick, offerCue, pumpScreen, queueScreen, rebuild, restLeft, send, sendCue, sendMinute, slept, startShader } from './values.js'

const quiet = { sun: 0, weather: 0, work: 0, zone: 0, hall: 0 }
const fieldsOf = (code: number) => ({ hurry: code % 2, hall: (code >> 1) % 2, tape: (code >> 2) % 2, tapeSeq: (code >> 3) % 2, console: (code >> 4) % 2, consoleSeq: (code >> 5) % 2 })

/** Steps the queue in REASK_MS redraws for `ms`, calling `each` first; the times and values of each move of `name`. */
function run(name: 'screen' | 'world', from: number, ms: number, each: (now: number) => void = () => undefined): { at: number; value: number }[] {
  const moves: { at: number; value: number }[] = []
  for (let now = from; now <= from + ms; now += REASK_MS) {
    each(now)
    pumpScreen(now)
    const redraw = nextValues(now)
    if (redraw.moved.includes(name)) moves.push({ at: now, value: redraw.values[name] })
  }
  return moves
}

test('a tape or console command changes its own bit and sequence bit and nothing else; a start sends the bits alone', () => {
  startShader(DEFAULT_STATE, quiet, 480, -60_000)
  let before = fieldsOf(nextValues(0).values.screen)
  let now = 0
  for (const [name, target] of [['tape', 1], ['console', 1], ['tape', 0], ['tape', 0], ['console', 0]] as const) {
    now += 4000
    queueScreen({ field: name, value: target })
    const [move] = run('screen', now, 0)
    expect(move, `${name} ${target}`).toBeDefined()
    const after = fieldsOf(move!.value)
    const seq = name === 'tape' ? 'tapeSeq' : 'consoleSeq'
    expect(after, `${name} ${target}`).toEqual({ ...before, [name]: target, [seq]: 1 - before[seq] })
    before = after
  }
  startShader({ ...DEFAULT_STATE, tape: true, console: false }, quiet, 480, now)
  expect(fieldsOf(nextValues(now).values.screen)).toEqual({ hurry: 0, hall: 0, tape: 1, tapeSeq: 0, console: 0, consoleSeq: 0 })
})

test('two screen changes asked together reach the element at least 3.5 s apart, one field each', () => {
  startShader(DEFAULT_STATE, quiet, 480, -60_000)
  queueScreen({ field: 'tape', value: 1 })
  queueScreen({ field: 'console', value: 1 })
  const moves = run('screen', 0, 10_000)
  expect(moves.length).toBe(2)
  expect(moves[1]!.at - moves[0]!.at).toBeGreaterThanOrEqual(3500)
  expect(fieldsOf(moves[0]!.value)).toMatchObject({ tape: 1, console: 0 })
  expect(fieldsOf(moves[1]!.value)).toMatchObject({ tape: 1, console: 1 })
})

test('a click on the tape or the console while a change for it may still land sends its state once more, after each rest', () => {
  startShader(DEFAULT_STATE, quiet, 480, -60_000)
  const [first, last] = SCREEN_RESTS_MS
  const sent = (at: number, ms = 0) => run('screen', at, ms).map(move => fieldsOf(move.value))
  noteScreenClick('tape', true, 0)
  expect(restLeft(0)).toBeUndefined()
  queueScreen({ field: 'tape', value: 1 })
  queueScreen({ field: 'console', value: 1 })
  expect(sent(1000).length).toBe(1)
  noteScreenClick('console', false, 2000)
  expect(sent(4500)).toEqual([{ hurry: 0, hall: 0, tape: 1, tapeSeq: 1, console: 0, consoleSeq: 1 }])
  noteScreenClick('tape', false, 9000)
  expect(sent(9000, 3000)).toEqual([])
  expect(restLeft(4500 + first - 1)).toBe(1)
  confirmScreen(4500 + first)
  expect(sent(4500 + first)).toEqual([{ hurry: 0, hall: 0, tape: 1, tapeSeq: 1, console: 0, consoleSeq: 0 }])
  expect(restLeft(4500 + first)).toBe(first)
  confirmScreen(4500 + 2 * first)
  expect(sent(4500 + 2 * first)).toEqual([{ hurry: 0, hall: 0, tape: 0, tapeSeq: 0, console: 0, consoleSeq: 0 }])
  expect(restLeft(4500 + 2 * first)).toBe(last)
  confirmScreen(4500 + 2 * first + last)
  expect(sent(4500 + 2 * first + last, 4000)).toEqual([
    { hurry: 0, hall: 0, tape: 0, tapeSeq: 0, console: 0, consoleSeq: 1 },
    { hurry: 0, hall: 0, tape: 0, tapeSeq: 1, console: 0, consoleSeq: 1 },
  ])
  expect(restLeft(4500 + 2 * first + last)).toBeUndefined()
  startShader(DEFAULT_STATE, quiet, 480, -60_000)
  queueScreen({ field: 'tape', value: 1 })
  expect(sent(0).length).toBe(1)
  noteScreenClick('tape', false, 15_000)
  expect(restLeft(15_000)).toBe(first)
  noteScreenClick('tape', true, 15_300)
  expect(restLeft(15_300)).toBe(first)
})

test('two world changes reach the element at least 6 s apart, and the later replaces one that waits', () => {
  startShader(DEFAULT_STATE, quiet, 480, -60_000)
  const asked = [
    { at: 0, fields: { ...quiet, sun: 6 } },
    { at: 1000, fields: { ...quiet, sun: 6, weather: 1 } },
    { at: 2000, fields: { ...quiet, sun: 6, weather: 2 } },
  ]
  let latest = quiet
  const moves = run('world', 0, 15_000, now => {
    for (const ask of asked) if (ask.at <= now) latest = ask.fields
    rebuild(latest, now)
  })
  expect(moves.map(move => move.value)).toEqual([encodeWorld(asked[0]!.fields), encodeWorld(asked[2]!.fields)])
  expect(moves[1]!.at - moves[0]!.at).toBeGreaterThanOrEqual(6000)
})

test('the same cue asked while its code still shows goes again once the atmosphere has shown between', () => {
  startShader(DEFAULT_STATE, quiet, 480, -60_000)
  const cue = WORLD.top + CUES.light
  const moves = run('world', 0, 33_000, now => {
    if (now === 0 || now === 4800) offerCue(CUES.light, now)
    rebuild(quiet, now)
  })
  expect(moves).toEqual([
    { at: 0, value: cue },
    { at: 12_000, value: 0 },
    { at: 18_000, value: cue },
    { at: 30_000, value: 0 },
  ])
})

test('one hurry flip a rebuild, none within 12 s of the last sent, and a flip changes the hurry bit alone', () => {
  startShader(DEFAULT_STATE, { ...quiet, sun: 1 }, 480, -60_000)
  const start = nextValues(0).values.screen
  rebuild({ ...quiet, sun: 5 }, 0, { stalled: true })
  expect(run('screen', 0, 10_000).map(move => move.value)).toEqual([start ^ 1])
  const asked = [
    { at: 21_000, fields: { ...quiet, sun: 6 } },
    { at: 24_900, fields: { ...quiet, sun: 6, weather: 2 } },
    { at: 21_000 + HURRY_GAP_MS + 600, fields: { ...quiet, sun: 6, weather: 1 } },
  ]
  const moves = run('screen', 21_000, 20_000, now => {
    for (const ask of asked) if (ask.at === now) rebuild(ask.fields, now, { hurry: true })
  })
  expect(moves).toEqual([
    { at: 21_000, value: start },
    { at: 21_000 + HURRY_GAP_MS + 600, value: start ^ 1 },
  ])
})

test('a minute tick after a stall flips the hurry bit with world unchanged', () => {
  startShader(DEFAULT_STATE, { ...quiet, sun: 1 }, 480, -60_000)
  const start = nextValues(0).values.screen
  rebuild({ ...quiet, sun: 1 }, 0, { stalled: true })
  expect(run('screen', 0, 10_000).map(move => move.value)).toEqual([start ^ 1])
})

test('a second flip waits, the other changes going first, until a code holding the first can have been taken', () => {
  const [, rest] = SCREEN_RESTS_MS
  const each = (asked: { at: number; run: () => void }[]) => (now: number) => {
    for (const ask of asked) if (ask.at === now) ask.run()
  }
  const console1 = 3 * 16
  startShader(DEFAULT_STATE, quiet, 480, -60_000)
  const start = nextValues(0).values.screen
  let moves = run('screen', 0, 45_000, each([
    { at: 0, run: () => rebuild({ ...quiet, sun: 6 }, 0, { hurry: true }) },
    { at: 2100, run: () => queueScreen({ field: 'console', value: 1 }) },
    { at: 13_200, run: () => rebuild({ ...quiet, sun: 2 }, 13_200, { hurry: true }) },
  ]))
  expect(moves.map(move => move.value)).toEqual([start ^ 1, (start ^ 1) + console1, start + console1])
  expect(moves[2]!.at - moves[1]!.at).toBeGreaterThanOrEqual(rest)
  expect(moves[2]!.at - moves[1]!.at).toBeLessThan(rest + REASK_MS)
  startShader(DEFAULT_STATE, quiet, 480, -60_000)
  moves = run('screen', 0, 50_000, each([
    { at: 0, run: () => queueScreen({ field: 'console', value: 1 }) },
    { at: 600, run: () => rebuild({ ...quiet, sun: 6 }, 600, { hurry: true }) },
    { at: 900, run: () => queueScreen({ field: 'tape', value: 1 }) },
    { at: 16_500, run: () => rebuild({ ...quiet, sun: 2 }, 16_500, { hurry: true }) },
  ]))
  const tape1 = 3 * 4
  expect(moves.map(move => move.value)).toEqual([start + console1, start + console1 + 1, start + console1 + 1 + tape1, start + console1 + tape1])
  expect(moves[3]!.at - moves[2]!.at).toBeGreaterThanOrEqual(rest)
  expect(moves[3]!.at - moves[2]!.at).toBeLessThan(rest + REASK_MS)
})

test('a minute tick more than 5 minutes after the last flips the hurry bit, and one at 5 minutes does not', async () => {
  let now = 0
  const $ = {
    clock: { now: async () => now, after: () => ({ cancel: () => undefined }) },
    ui: { invalidate: () => undefined },
  } as unknown as EngineInterface
  startShader(DEFAULT_STATE, quiet, 480, -1_000_000)
  const start = nextValues(0).values.screen
  await sendMinute($, quiet, STALL_MS)
  expect(nextValues(now).values.screen).toBe(start)
  now = STALL_MS + 1
  await sendMinute($, quiet, STALL_MS + 1)
  expect(nextValues(now).values.screen).toBe(start ^ 1)
})

test('after a sleep the waking flip waits until a code holding the flip before it can have been taken', () => {
  const [first] = SCREEN_RESTS_MS
  startShader(DEFAULT_STATE, quiet, 480, -60_000)
  const start = nextValues(0).values.screen
  const tick = -2000
  rebuild({ ...quiet, sun: 6 }, 0, { hurry: true })
  expect(run('screen', 0, 0).map(move => move.value)).toEqual([start ^ 1])
  const wake = 1500 + 30_000_000
  slept(wake - tick)
  rebuild({ ...quiet, sun: 2 }, wake, { stalled: true })
  let moves = run('screen', wake, 20_000)
  expect(moves.map(move => move.value)).toEqual([start])
  expect(moves[0]!.at - wake).toBe(first - tick)
  startShader(DEFAULT_STATE, { ...quiet, sun: 1 }, 480, -60_000)
  const wake1 = 4 * 3_600_000
  slept(wake1)
  rebuild({ ...quiet, sun: 2 }, wake1, { stalled: true })
  expect(run('screen', wake1, 2700).map(move => move.value)).toEqual([start ^ 1])
  const wake2 = wake1 + 2900 + 5 * 3_600_000
  slept(wake2 - wake1)
  rebuild({ ...quiet, sun: 5 }, wake2, { stalled: true })
  moves = run('screen', wake2, 20_000)
  expect(moves.map(move => move.value)).toEqual([start])
  expect(moves[0]!.at - wake2).toBeGreaterThanOrEqual(first)
  expect(moves[0]!.at - wake2).toBeLessThan(first + REASK_MS)
})

test('a world change asked just after a shader start goes out once 6 s from the start have passed', async () => {
  let now = 0
  const timers: { at: number; run: () => void }[] = []
  const $ = {
    clock: { now: async () => now, after: (ms: number, run: () => void) => void timers.push({ at: now + ms, run }) },
    ui: { invalidate: () => undefined },
  } as unknown as EngineInterface
  /** Runs the timers due up to `to`, letting each one's reads of the clock finish. */
  const advance = async (to: number) => {
    for (;;) {
      timers.sort((a, b) => a.at - b.at)
      const due = timers[0]
      if (due === undefined || due.at > to) break
      timers.shift()
      now = due.at
      due.run()
      for (let i = 0; i < 10; i++) await Promise.resolve()
    }
    now = to
  }
  const noon = { ...quiet, sun: 6 }
  const rain = { ...noon, weather: 2 }
  startShader(DEFAULT_STATE, quiet, 480, 0)
  now = 1000
  await send($, 'noon', noon)
  await advance(3000)
  startShader(DEFAULT_STATE, noon, 480, 3000)
  await advance(4000)
  await send($, 'rain', rain)
  await advance(8900)
  expect(nextValues(8900).values.world).toBe(encodeWorld(noon))
  await advance(9000)
  expect(nextValues(9000).values.world).toBe(encodeWorld(rain))
})

test('the same cue asked again during its hold answers the time it really goes: after the hold, then a world gap', async () => {
  let now = 0
  const $ = {
    clock: { now: async () => now, after: () => ({ cancel: () => undefined }) },
    ui: { invalidate: () => undefined },
  } as unknown as EngineInterface
  startShader(DEFAULT_STATE, quiet, 480, -60_000)
  expect(await sendCue($, CUES.light, 'first')).toBe(0)
  now = 4800
  expect(await sendCue($, CUES.light, 'again')).toBe(18_000 - 4800)
  startShader(DEFAULT_STATE, quiet, 480, -60_000)
  now = 0
  await sendCue($, CUES.light, 'first')
  now = 4800
  expect(await sendCue($, CUES.pass, 'another')).toBe(12_000 - 4800)
})
