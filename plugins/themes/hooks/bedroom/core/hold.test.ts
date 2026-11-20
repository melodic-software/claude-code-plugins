import { expect, test } from 'claude-code/testing'

import { QUIET, startRoom } from './testing.js'

test('at load the room shows alone for 7 s, then the shader starts with every name at its target', { options: QUIET }, async ($, on) => {
  const room = await startRoom($, on, { hold: false })
  expect(await room.values()).toBeUndefined()
  await room.clock.advance(3000)
  await room.run('lava')
  expect(await room.values()).toBeUndefined()
  await room.clock.advance(3900)
  expect(await room.values()).toBeUndefined()
  await room.clock.advance(400)
  expect(await room.values()).toEqual({ tv: 1, lava: 1, pc: 1, lamp: 0, light: 0, clock: 480, screen: 0, world: 0 })
  await room.unmount()
})
