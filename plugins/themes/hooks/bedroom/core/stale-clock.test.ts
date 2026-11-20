import { expect, test } from 'claude-code/testing'

import { QUIET, startRoom } from './testing.js'

test('sync 20 s after the last redraw shows the room alone', { timeoutMs: 20000, options: QUIET }, async ($, on) => {
  const room = await startRoom($, on)
  expect(await room.values()).toBeDefined()
  await room.clock.advance(20000)
  expect(await room.run('sync')).toMatch(/^the room shows alone/)
  expect(await room.values()).toBeUndefined()
  await room.unmount()
})

test('reset 20 s after the last redraw shows the room alone', { timeoutMs: 20000, options: QUIET }, async ($, on) => {
  const room = await startRoom($, on)
  await room.run('lamp on')
  await room.run('lava on')
  await room.run('light on')
  await room.run('tv off')
  await room.clock.advance(20000)
  expect(await room.values()).toBeDefined()
  expect(await room.run('reset')).toBe('on: tv, pc. off: tape, console, light, lamp, lava. posters: plain. dim: 0')
  expect(await room.values()).toBeUndefined()
  await room.unmount()
})
