import { expect, test } from 'claude-code/testing'

import { QUIET, STORE_KEY, startRoom, type Room } from '../core/testing.js'
import { BUILT } from './index.js'

const HALL = 2

async function track(room: Room, args: string): Promise<{ reply: string; codes: number[] }> {
  const codes = [(await room.values())?.screen ?? -1]
  const reply = await room.run(args)
  for (let t = 0; t < 6000; t += 100) {
    const code = (await room.values())?.screen ?? -1
    if (codes.at(-1) !== code) codes.push(code)
    await room.clock.advance(100)
  }
  return { reply, codes }
}

const QUIET_BUT_HALL = { time: QUIET.time, weather: QUIET.weather, signal: QUIET.signal }

test('hall on and off change the hall bit alone by one screen send, and a stored choice holds through a reload', { timeoutMs: 30000, options: QUIET_BUT_HALL }, async ($, on) => {
  if (!BUILT.includes('hallway')) return
  const room = await startRoom($, on, { saved: { hall: false } })
  const world = (await room.values())?.world
  expect((await room.values())?.screen).toBe(0)
  expect(await room.run('hall')).toMatch(/^the hallway's events are off/)

  const turnedOn = await track(room, 'hall on')
  expect(turnedOn.reply).toMatch(/^the hallway is on/)
  expect(turnedOn.codes).toEqual([0, HALL])
  expect((room.store.get(STORE_KEY) as { hall?: boolean }).hall).toBe(true)

  const turnedOff = await track(room, 'hall off')
  expect(turnedOff.reply).toMatch(/^the hallway is off/)
  expect(turnedOff.codes).toEqual([HALL, 0])
  expect((room.store.get(STORE_KEY) as { hall?: boolean }).hall).toBe(false)
  expect((await room.values())?.world).toBe(world)

  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  await room.clock.advance(7300)
  expect((await room.values())?.screen).toBe(0)
  expect(await room.run('hall')).toMatch(/^the hallway's events are off/)

  const byDefault = await track(room, 'hall default')
  expect(byDefault.reply).toMatch(/^hall follows its setting again \(now true\)/)
  expect(byDefault.codes).toEqual([0, HALL])
  await room.unmount()
})
