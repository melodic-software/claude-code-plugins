import { expect, test } from 'claude-code/testing'

import { QUIET, STORE_KEY, startRoom } from './testing.js'

const STATE = { tv: true, tape: false, console: false, pc: true, light: false, lamp: false, lava: false, posters: 'plain' }

test('/bedroom <switch>: already there, one move, or the middle first when the saved state turned since, read back from the Shader element', { timeoutMs: 20000, options: QUIET }, async ($, on) => {
  const room = await startRoom($, on, { saved: { state: STATE } })
  expect((await room.values())?.tv).toBe(1)

  expect(await room.run('tv on')).toMatch(/already on/)
  expect((await room.values())?.tv).toBe(1)

  await room.run('tv off')
  expect((await room.values())?.tv).toBe(0)
  await room.run('tv on')
  expect((await room.values())?.tv).toBe(1)

  room.store.set(STORE_KEY, { state: { ...STATE, tv: false } })
  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  expect(await room.run('')).toMatch(/off: tv/)
  await room.run('tv on')
  expect((await room.values())?.tv).toBe(0.5)
  await room.clock.advance(1350)
  expect((await room.values())?.tv).toBe(0.5)
  await room.clock.advance(450)
  expect((await room.values())?.tv).toBe(1)
  await room.unmount()
})
