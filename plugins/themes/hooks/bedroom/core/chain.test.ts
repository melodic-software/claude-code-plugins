import { expect, test } from 'claude-code/testing'

import { QUIET, startRoom } from './testing.js'

const renders = (stats: string): number => Number(/renders: (\d+)/.exec(stats)?.[1])

test('the minute chain carries on when the host loses its $.state value', { timeoutMs: 20000, options: QUIET }, async ($, on) => {
  let lost = 0
  on('state.get', async (_, e, next) => {
    if (lost === 0) return next(e)
    lost -= 1
    return { value: { value: undefined, version: 0 } }
  })
  const room = await startRoom($, on)
  const before = renders(await room.run('stats'))
  lost = 1
  await room.clock.advance(3 * 60_000)
  expect(lost).toBe(0)
  expect(renders(await room.run('stats')) - before).toBe(3)
  expect((await room.values())?.clock).toBe(483)
  await room.unmount()
})
