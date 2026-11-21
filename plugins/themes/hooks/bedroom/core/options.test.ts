import { expect, test } from 'claude-code/testing'

import { SCREEN } from './signals.gen.js'
import { QUIET, STORE_KEY, startRoom } from './testing.js'

test('a setting given in userConfig is read, and a stored override goes before it', { timeoutMs: 20000, options: { ...QUIET, shader: false } }, async ($, on) => {
  const room = await startRoom($, on)
  expect(await room.values()).toBeUndefined()
  expect(await room.run('stats')).toMatch(/shader: off/)
  expect(await room.run('shader on')).toMatch(/^the shader is on/)
  await room.clock.advance(7300)
  expect(await room.values()).toBeDefined()
  expect(await room.run('shader default')).toMatch(/^shader follows its setting again \(now false\)/)
  expect(await room.values()).toBeUndefined()
  await room.unmount()
})

test('shader off is for this session only: it is never stored, and one stored before loads with the shader on', { timeoutMs: 20000, options: QUIET }, async ($, on) => {
  const room = await startRoom($, on, { saved: { state: {}, dim: 0, glass: 0, blur: 0, titles: {}, shader: false, volume: 30 } })
  expect(await room.run('stats')).toMatch(/shader: on/)
  expect(await room.values()).toBeDefined()
  expect(await room.run('shader off')).toMatch(/^the shader is off for this session, for diagnosis/)
  expect(await room.run('stats')).toMatch(/shader: off/)
  expect(room.store.get(STORE_KEY)).not.toHaveProperty('shader')
  expect(room.store.get(STORE_KEY)).toMatchObject({ volume: 30 })
  await room.run('shader on')
  await room.unmount()
})

test('with the tape and the console both in, the screen the shader is sent holds both: the shader gives the tape the screen', { timeoutMs: 30000, options: QUIET }, async ($, on) => {
  const room = await startRoom($, on)
  await room.run('tv on')
  await room.run('console on')
  await room.run('tape on')
  await room.clock.advance(40_000)
  const screen = (await room.values())?.screen ?? -1
  const field = (unit: number): number => Math.floor(screen / unit) % 2
  expect({ tape: field(SCREEN.tape), console: field(SCREEN.console) }).toEqual({ tape: 1, console: 1 })
  expect((await room.values())?.tv).toBe(1)
  await room.run('reset')
  await room.unmount()
})
