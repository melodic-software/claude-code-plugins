import { expect, test } from 'claude-code/testing'

import { QUIET, startRoom } from './testing.js'

const SAVED = { state: { tv: true, tape: false, console: false, pc: true, light: false, lamp: false, lava: false, posters: 'plain' }, dim: 0, titles: { console: 'SOME GAME' } }

test('drawn before session.start with a stored room, the room shows alone for one hold, not two', { timeoutMs: 20000, options: QUIET }, async ($, on) => {
  const room = await startRoom($, on, { early: true, hold: false, saved: SAVED })
  await room.clock.advance(6900)
  expect(await room.values()).toBeUndefined()
  await room.clock.advance(400)
  expect(await room.values()).toBeDefined()
  expect(await room.source()).toContain('SOME GAME')
  await room.unmount()
})
