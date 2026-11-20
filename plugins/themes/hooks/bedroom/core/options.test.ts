import { expect, test } from 'claude-code/testing'

import { QUIET, startRoom } from './testing.js'

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
