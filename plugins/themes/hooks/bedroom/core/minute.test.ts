import { expect, test } from 'claude-code/testing'

import { QUIET, startRoom } from './testing.js'

const renders = (stats: string): number => Number(/renders: (\d+)/.exec(stats)?.[1])

test('one redraw a minute, and a second session start leaves one minute chain', { timeoutMs: 20000, options: QUIET }, async ($, on) => {
  const room = await startRoom($, on)
  const before = renders(await room.run('stats'))
  await room.clock.advance(3 * 60_000)
  expect(renders(await room.run('stats')) - before).toBe(3)
  expect((await room.values())?.clock).toBe(483)

  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  await room.clock.advance(1000)
  const after = renders(await room.run('stats'))
  await room.clock.advance(3 * 60_000)
  expect(renders(await room.run('stats')) - after).toBe(3)
  expect((await room.values())?.clock).toBe(486)
  await room.unmount()
})
