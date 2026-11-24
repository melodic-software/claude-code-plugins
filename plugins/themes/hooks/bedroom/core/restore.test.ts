import { expect, test, type Engine, type Plugin } from 'claude-code/testing'

import { QUIET, startRoom } from './testing.js'

const FIREWORKS: Plugin = {
  name: 'fireworks',
  register(on) {
    on('command.run', { command: 'fireworks' }, async ($, e) => {
      if (e.args === 'show') await $.theme.set({ backdrop: { scene: 'fireworks' } })
      else await $.theme.clear()
      return { text: e.args }
    })
  },
}

const RIVAL: Plugin = {
  name: 'rival',
  register(on) {
    on('theme.clear', async ($, e, next) => {
      const cleared = await next(e)
      if (next.origin.plugin !== 'rival') await $.theme.set({ backdrop: { scene: 'rival' } })
      return cleared
    })
  },
}

async function fireworks($: Engine, args: 'show' | 'clear'): Promise<void> {
  await $.command.run({ command: 'fireworks', args, origin: { kind: 'composer' } as never, presentation: {} as never })
}

test('another mod clears the theme while the room is on: the room is set again once, shows alone for the hold, and nothing sets it after', { timeoutMs: 20000, options: QUIET, plugins: [FIREWORKS] }, async ($, on) => {
  const room = await startRoom($, on)
  const before = room.themes.length
  expect(await room.values()).toBeDefined()
  await fireworks($, 'clear')
  expect(room.themes.slice(before)).toEqual(['clear', 'set bedroom'])
  expect(await room.values()).toBeUndefined()
  await room.clock.advance(7300)
  expect(await room.values()).toBeDefined()
  await room.clock.advance(60_000)
  expect(room.themes.slice(before)).toEqual(['clear', 'set bedroom'])
  await fireworks($, 'clear')
  expect(room.themes.slice(before)).toEqual(['clear', 'set bedroom', 'clear', 'set bedroom'])
  await room.unmount()
})

test('another mod sets its own theme: it stands until cleared, and the room comes back only after the clear', { timeoutMs: 20000, options: QUIET, plugins: [FIREWORKS] }, async ($, on) => {
  const room = await startRoom($, on)
  const before = room.themes.length
  await fireworks($, 'show')
  await room.clock.advance(60_000)
  expect(room.themes.slice(before)).toEqual(['set fireworks'])
  await fireworks($, 'clear')
  expect(room.themes.slice(before)).toEqual(['set fireworks', 'clear', 'set bedroom'])
  await room.unmount()
})

test('another mod sets its theme over the room: status says covered, and /bedroom on sets the room again without clearing', { timeoutMs: 20000, options: QUIET, plugins: [FIREWORKS] }, async ($, on) => {
  const room = await startRoom($, on)
  expect(await room.run('status')).not.toContain('covered')
  await fireworks($, 'show')
  expect(await room.run('status')).toContain('the room is covered by the fireworks theme; /bedroom on puts it back.')
  const before = room.themes.length
  expect(await room.run('on')).toBe('the room is back')
  expect(room.themes.slice(before)).toEqual(['set bedroom'])
  expect(await room.run('status')).not.toContain('covered')
  await room.unmount()
})

test('while another mod covers the room the card says so, and its theme button sets the room again instead of clearing', { timeoutMs: 20000, options: QUIET, plugins: [FIREWORKS] }, async ($, on) => {
  const room = await startRoom($, on)
  await room.run('')
  const card = await $.ui.mount({ plugin: 'themes', surface: 'desktop', component: 'Placed', requestId: 'bedroom-card-1', props: { id: 'bedroom-card-1', plugin: 'themes' } } as never)
  expect((await card.find({ key: 'theme' }))?.props.label).toBe('theme: on')
  await fireworks($, 'show')
  expect((await card.find({ key: 'theme' }))?.props.label).toBe('theme: covered')
  const before = room.themes.length
  await card.press({ key: 'theme' })
  expect(room.themes.slice(before)).toEqual(['set bedroom'])
  expect((await card.find({ key: 'theme' }))?.props.label).toBe('theme: on')
  await card.unmount()
  await room.unmount()
})

test('a covering mod that then clears its theme brings the room back, and the open card says on again with a button that turns it off', { timeoutMs: 20000, options: QUIET, plugins: [FIREWORKS] }, async ($, on) => {
  const room = await startRoom($, on)
  await room.run('')
  const card = await $.ui.mount({ plugin: 'themes', surface: 'desktop', component: 'Placed', requestId: 'bedroom-card-1', props: { id: 'bedroom-card-1', plugin: 'themes' } } as never)
  await fireworks($, 'show')
  expect((await card.find({ key: 'theme' }))?.props.label).toBe('theme: covered')
  await fireworks($, 'clear')
  expect((await card.find({ key: 'theme' }))?.props.label).toBe('theme: on')
  const before = room.themes.length
  await card.press({ key: 'theme' })
  expect(room.themes.slice(before)).toEqual(['clear'])
  await card.unmount()
  await room.unmount()
})

test('/bedroom off clears the theme without setting it again, and a later clear by another mod leaves it off until /bedroom on', { timeoutMs: 20000, options: QUIET, plugins: [FIREWORKS] }, async ($, on) => {
  const room = await startRoom($, on)
  const before = room.themes.length
  await room.run('off')
  expect(room.themes.slice(before)).toEqual(['clear'])
  await fireworks($, 'clear')
  expect(room.themes.slice(before)).toEqual(['clear', 'clear'])
  await room.run('on')
  await fireworks($, 'clear')
  expect(room.themes.slice(before)).toEqual(['clear', 'clear', 'set bedroom', 'clear', 'set bedroom'])
  await room.unmount()
})

test('two mods that each set their look again on a clear: one clear brings one set from each, and neither answers the other', { timeoutMs: 20000, options: QUIET, plugins: [FIREWORKS, RIVAL] }, async ($, on) => {
  const room = await startRoom($, on)
  const before = room.themes.length
  await fireworks($, 'clear')
  await room.clock.advance(60_000)
  const after = room.themes.slice(before)
  expect(after.length).toBe(3)
  expect(after[0]).toBe('clear')
  expect([...after.slice(1)].sort()).toEqual(['set bedroom', 'set rival'])
  await room.unmount()
})
