import { expect, test } from 'claude-code/testing'

import { bedroomSvg } from '../scene.js'
import { DEFAULT_STATE } from '../scene/lib.ts'
import { QUIET, startRoom } from './testing.js'

/** The room under the shader: the television and computer on, the ceiling light on, the console's title card on every screen. */
const LIT = { tv: true, tape: false, console: false, pc: true, light: true, lamp: false, lava: false, underShader: true } as const

test('with the shader on, the room sent is the lit one whatever the switches', { timeoutMs: 20000, options: QUIET }, async ($, on) => {
  const room = await startRoom($, on)
  const sent = await room.source()
  expect(sent).toBe(bedroomSvg({ ...DEFAULT_STATE, ...LIT, titles: {} }, 0))
  for (const word of ['tv off', 'lava on', 'pc off', 'lamp on', 'tape on', 'console on', 'light on']) await room.run(word)
  await room.clock.advance(7300)
  expect(await room.source()).toBe(sent)
  await room.unmount()
})
