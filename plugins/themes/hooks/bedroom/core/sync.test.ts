import { expect, test } from 'claude-code/testing'

import { QUIET, startRoom } from './testing.js'

const bit = (code: number | undefined, unit: number): number => Math.floor((code ?? 0) / unit) % 2

test('sync and reset show the room alone, then every name at its target', { timeoutMs: 20000, options: QUIET }, async ($, on) => {
  const room = await startRoom($, on)
  await room.run('tv off')
  await room.run('lamp on')
  await room.run('console on')
  await room.clock.advance(4000)

  expect(await room.run('sync')).toMatch(/^the room shows alone/)
  expect(await room.values()).toBeUndefined()
  await room.clock.advance(6900)
  expect(await room.values()).toBeUndefined()
  await room.clock.advance(400)
  const synced = await room.values()
  expect(synced).toMatchObject({ tv: 0, lava: 0, pc: 1, lamp: 1, light: 0, world: 0 })
  expect(bit(synced?.screen, 16)).toBe(1)
  expect(bit(synced?.screen, 4)).toBe(0)

  await room.run('reset')
  expect(await room.values()).toBeUndefined()
  await room.clock.advance(7300)
  const reset = await room.values()
  expect(reset).toMatchObject({ tv: 1, lava: 0, pc: 1, lamp: 0, light: 0, world: 0 })
  expect(bit(reset?.screen, 16)).toBe(0)
  expect(bit(reset?.screen, 4)).toBe(0)
  await room.unmount()
})
