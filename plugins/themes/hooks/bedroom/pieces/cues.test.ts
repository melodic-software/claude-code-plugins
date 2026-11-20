import { expect, test } from 'claude-code/testing'

import { CUES, WORLD } from '../core/signals.gen.js'
import { QUIET, startRoom, type Room } from '../core/testing.js'
import { BUILT } from './index.js'

/** Runs /bedroom <args>, then reads the Shader element every 250 ms for `ms`: the reply, and each world code shown in order. */
async function track(room: Room, args: string, ms = 20_000): Promise<{ reply: string; codes: number[] }> {
  const codes = [(await room.values())?.world ?? -1]
  const reply = await room.run(args)
  for (let t = 0; t < ms; t += 250) {
    const code = (await room.values())?.world ?? -1
    if (codes.at(-1) !== code) codes.push(code)
    await room.clock.advance(250)
  }
  return { reply, codes }
}

const QUIET_BUT_HALL = { time: QUIET.time, weather: QUIET.weather, signal: QUIET.signal }

test('hall pass, hall light and weather strike each send their cue once, then the atmosphere again', { timeoutMs: 60000, options: QUIET_BUT_HALL }, async ($, on) => {
  if (!BUILT.includes('hallway') || !BUILT.includes('weather')) return
  const room = await startRoom($, on)
  const calm = (await room.values())?.world
  expect(calm).toBe(0)

  const pass = await track(room, 'hall pass')
  expect(pass.reply).toMatch(/^someone passes the door in about \d+ s$/)
  expect(pass.codes).toEqual([calm, WORLD.top + CUES.pass, calm])

  const light = await track(room, 'hall light')
  expect(light.reply).toMatch(/^the hall light turns on in about \d+ s/)
  expect(light.codes).toEqual([calm, WORLD.top + CUES.light, calm])

  expect(await room.run('weather strike')).toMatch(/^lightning comes only in a storm/)
  const storm = await track(room, 'weather storm', 8000)
  const stormy = storm.codes.at(-1)!
  expect(stormy).toBe(WORLD.sun * 4)

  const strike = await track(room, 'weather strike', 15_000)
  expect(strike.reply).toMatch(/^lightning strikes in about \d+ s$/)
  expect(strike.codes).toEqual([stormy, WORLD.top + CUES.strike, stormy])
  expect(await room.run('weather strike')).toMatch(/^one strike at a time/)

  await room.run('hall off')
  await room.clock.advance(8000)
  expect(await room.run('hall pass')).toMatch(/^the hallway is off/)
  await room.unmount()
})
