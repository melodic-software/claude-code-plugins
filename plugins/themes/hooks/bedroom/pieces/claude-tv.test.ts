import { expect, test } from 'claude-code/testing'

import { QUIET, startRoom, type Room } from '../core/testing.js'
import { HOLD_MS, zoneOf } from './claude-tv.js'
import { BUILT } from './index.js'

const workOf = (world: number) => Math.floor(world / 40) % 2
const zoneIn = (world: number) => Math.floor(world / 80)

async function watch(room: Room, ms: number, changes: { at: number; world: number }[]): Promise<void> {
  for (let gone = 0; gone <= ms; gone += 100) {
    if (gone > 0) await room.clock.advance(100)
    const world = (await room.values())?.world
    if (world !== undefined && world !== changes.at(-1)?.world) changes.push({ at: room.clock.now(), world })
  }
}

test('a zone starts at 50% and 75% and falls back 2 points lower', () => {
  if (!BUILT.includes('claude-tv')) return
  expect(zoneOf(10, 0)).toBe(0)
  expect(zoneOf(49, 0)).toBe(0)
  expect(zoneOf(50, 0)).toBe(1)
  expect(zoneOf(49, 1)).toBe(1)
  expect(zoneOf(48, 1)).toBe(0)
  expect(zoneOf(74, 1)).toBe(1)
  expect(zoneOf(75, 1)).toBe(2)
  expect(zoneOf(74, 2)).toBe(2)
  expect(zoneOf(73, 2)).toBe(1)
  expect(zoneOf(80, 0)).toBe(2)
  expect(zoneOf(10, 2)).toBe(0)
})

test('the main turn sets work, a subagent turn does not, work holds 4 s, world goes at most once in 6 s, signal off sends 0', { timeoutMs: 60000, options: { ...QUIET, signal: true } }, async ($, on) => {
  if (!BUILT.includes('claude-tv')) return
  on('turn.start', (_, e) => ({ turnId: e.turnId }))
  on('turn.complete', (_, e) => ({ text: e.answer }))
  on('session.measure', (_, e) => ({ changed: e.changed }))
  on('session.stop', (_, e) => ({ isTurnRunning: e.isTurnRunning }))
  const room = await startRoom($, on)
  const start = (turnId: string, agentId?: string) => $.turn.start({ text: '', turnId, ...(agentId === undefined ? {} : { agentId }) })
  const complete = (turnId: string, agentId?: string) =>
    $.turn.complete({ answer: '', durationMs: 1000, isAborted: false, turnId, reason: 'answer', ...(agentId === undefined ? {} : { agentId }) })
  const measure = (percent: number) => $.session.measure({ context: { window: 200_000, tokens: percent * 2000, percent }, rateLimits: [], changed: ['context'] })
  const now = async (): Promise<number> => (await room.values())?.world ?? -1
  const changes: { at: number; world: number }[] = []
  await watch(room, 7000, changes)
  expect(workOf(await now())).toBe(0)

  await start('s1', 'a1')
  await watch(room, 7000, changes)
  await complete('s1', 'a1')
  expect(workOf(await now())).toBe(0)
  const quiet = changes.length

  await start('m1')
  await watch(room, 1000, changes)
  expect(changes.length).toBe(quiet + 1)
  expect(workOf(changes.at(-1)!.world)).toBe(1)
  await complete('m1')
  await watch(room, 1000, changes)
  await start('m2')
  await watch(room, 2000, changes)
  await complete('m2')
  const ended = room.clock.now()
  await watch(room, HOLD_MS - 300, changes)
  expect(changes.length).toBe(quiet + 1)
  await watch(room, 700, changes)
  expect(changes.length).toBe(quiet + 2)
  expect(workOf(changes.at(-1)!.world)).toBe(0)
  expect(changes.at(-1)!.at - ended).toBeGreaterThanOrEqual(HOLD_MS)
  expect(changes.at(-1)!.at - ended).toBeLessThanOrEqual(HOLD_MS + 300)

  await watch(room, 7000, changes)
  await start('m3')
  await watch(room, 300, changes)
  const sent = changes.at(-1)!
  expect(workOf(sent.world)).toBe(1)
  await watch(room, 200, changes)
  await complete('m3')
  await watch(room, 8000, changes)
  expect(workOf(changes.at(-1)!.world)).toBe(0)
  expect(changes.at(-1)!.at - sent.at).toBeGreaterThanOrEqual(6000)
  expect(changes.at(-1)!.at - sent.at).toBeLessThanOrEqual(6400)

  for (const [percent, zone] of [[49, 0], [50, 1], [49, 1], [48, 0], [74, 1], [75, 2], [74, 2], [73, 1], [48, 0], [80, 2]] as const) {
    await measure(percent)
    await watch(room, 7000, changes)
    expect(zoneIn(await now()), `${percent}%`).toBe(zone)
  }

  await start('m4')
  await watch(room, 7000, changes)
  expect([workOf(await now()), zoneIn(await now())]).toEqual([1, 2])
  expect(await room.run('signal off')).toMatch(/no longer reacts/)
  await watch(room, 7000, changes)
  expect([workOf(await now()), zoneIn(await now())]).toEqual([0, 0])
  expect(await room.run('signal on')).toMatch(/^the television reacts/)
  await watch(room, 7000, changes)
  expect([workOf(await now()), zoneIn(await now())]).toEqual([1, 2])
  await $.session.stop({ isTurnRunning: true })
  await watch(room, 7000, changes)
  expect([workOf(await now()), zoneIn(await now())]).toEqual([0, 2])
  await complete('m4')

  for (let i = 1; i < changes.length; i++) expect(changes[i]!.at - changes[i - 1]!.at, `change ${i}`).toBeGreaterThanOrEqual(6000)
  await room.unmount()
})
