import { expect, test } from 'claude-code/testing'

import { EVENTS, CUES, WORLD } from '../core/signals.gen.js'
import { QUIET, startRoom, type Room } from '../core/testing.js'
import { BUILT, WITHOUT } from './index.js'
import { LIGHTNING, SLOT_S, extraStrikes } from './weather.js'

const STRIKE_CODE = WORLD.top + CUES.strike
const BUILT_IN = BUILT.includes('weather') && !WITHOUT.includes('weather.lightning')

/**
 * Reads the Shader element every READ_MS for `ms`: the times a strike cue first shows, in ms from the start of the read.
 * A cue's code holds CUE_HOLD_MS (12 s), so a read every 3 s sees each one.
 */
const READ_MS = 3000
async function strikes(room: Room, ms: number): Promise<number[]> {
  const start = room.clock.now()
  const at: number[] = []
  let was = (await room.values())?.world
  for (let t = 0; t < ms; t += READ_MS) {
    await room.clock.advance(READ_MS)
    const code = (await room.values())?.world
    if (code === STRIKE_CODE && was !== STRIKE_CODE) at.push(room.clock.now() - start)
    was = code
  }
  return at
}

const TEN_MINUTES = 10 * 60_000

for (const [setting, low, high] of [['rare', 0, 0], ['normal', 13, 22], ['often', 22, 34]] as const) {
  test(`a held storm at lightning ${setting} sends ${low} to ${high} extra strikes in ten minutes, never within ${SLOT_S} s of each other`, { timeoutMs: 60000, options: { ...QUIET, weather: 'storm', lightning: setting } }, async ($, on) => {
    if (!BUILT_IN) return
    const room = await startRoom($, on)
    const at = await strikes(room, TEN_MINUTES)
    expect(at.length).toBeGreaterThanOrEqual(low)
    expect(at.length).toBeLessThanOrEqual(high)
    for (let i = 1; i < at.length; i++) expect(at[i]! - at[i - 1]!).toBeGreaterThanOrEqual(SLOT_S * 1000 - READ_MS)
    expect(new Set(at.slice(1).map((t, i) => Math.round((t - at[i]!) / 1000))).size).toBeGreaterThanOrEqual(at.length > 4 ? 3 : 0)
    await room.unmount()
  })
}

test('no extra strike outside a storm, in the shader\'s first seconds, or with the shader off; a hall pass still goes through at often', { timeoutMs: 60000, options: { ...QUIET, weather: 'rain', lightning: 'often', hall: true } }, async ($, on) => {
  if (!BUILT_IN || !BUILT.includes('hallway')) return
  const room = await startRoom($, on, { hold: false })
  expect(await strikes(room, 3 * 60_000)).toEqual([])
  await room.run('weather storm')
  await room.run('shader off')
  expect(await strikes(room, 2 * 60_000)).toEqual([])
  await room.run('shader on')
  const first = await strikes(room, 3 * 60_000)
  expect(first.length).toBeGreaterThan(0)
  expect(first[0]!).toBeGreaterThanOrEqual(EVENTS.after * 1000)
  const reply = await room.run('hall pass')
  expect(reply).toMatch(/^someone passes the door in about \d+ s$/)
  expect(Number(/about (\d+) s/.exec(reply)![1])).toBeLessThanOrEqual(20)
  await room.unmount()
})

test('/bedroom weather lightning says and sets the setting; default follows the plugin setting again', { timeoutMs: 20000, options: QUIET }, async ($, on) => {
  const room = await startRoom($, on)
  expect(await room.run('weather lightning')).toBe('lightning is normal: about two strikes a minute in a storm')
  expect(await room.run('weather lightning often')).toBe('lightning is often: about three strikes a minute in a storm')
  expect(await room.run('weather lightning loud')).toMatch(/^say rare, normal, often or default/)
  expect(await room.run('lightning default')).toMatch(/^lightning follows its setting again \(now normal\)/)
  expect(extraStrikes(1000, LIGHTNING.rare)).toEqual([])
  expect(extraStrikes(1000, LIGHTNING.often).length).toBe(3)
  await room.unmount()
})
