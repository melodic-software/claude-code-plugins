import { expect, test } from 'claude-code/testing'

import { QUIET, startRoom } from './testing.js'

test('drawn before session.start, the room shows alone for 7 s from the session start, a command inside the hold too', { timeoutMs: 20000, options: QUIET }, async ($, on) => {
  const room = await startRoom($, on, { early: true, hold: false })
  expect(await room.values()).toBeUndefined()
  await room.clock.advance(1000)
  await room.run('lava')
  expect(await room.values()).toBeUndefined()
  await room.clock.advance(5900)
  expect(await room.values()).toBeUndefined()
  await room.clock.advance(400)
  expect((await room.values())?.lava).toBe(1)
  await room.unmount()
})
