import { expect, test } from 'claude-code/testing'

import { bedroomSvg } from '../scene.ts'
import { savedOf } from './saved.js'
import { QUIET, STORE_KEY, startRoom } from './testing.js'

/** What themes 0.2.1 stored under `bedroom:saved`, exactly in its shape: switches, dim, window shape, panels and the four titles. */
const OLD = {
  state: { tv: false, tape: true, console: true, pc: false, light: true, lamp: true, lava: true, posters: 'plain' },
  dim: 0.3,
  aspect: 2.37,
  glass: 0.4,
  blur: 8,
  titles: { console: 'Moth $& Hour', tape: 'Night <Drive>', pennant: 'SILVER FOXES', 'pennant-top': 'PINE HOLLOW' },
} as const

const bit = (code: number | undefined, unit: number): number => Math.floor((code ?? 0) / unit) % 2

test('a value stored by 0.2.1 reads back whole, with nothing added', () => {
  expect(savedOf(OLD)).toEqual(OLD)
  expect(savedOf(JSON.parse(JSON.stringify(OLD)))).toEqual(OLD)
})

test('settings stored by 0.2.1 load with switches, dim, titles, panels and window shape intact', { timeoutMs: 20000, options: QUIET }, async ($, on) => {
  const room = await startRoom($, on, { saved: JSON.parse(JSON.stringify(OLD)), hold: false })
  const titles = { ...OLD.titles }

  expect(await room.run('status')).toBe('on: tape, console, light, lamp, lava. off: tv, pc. posters: plain. dim: 30')
  expect(await room.values()).toBeUndefined()
  expect(await room.source()).toBe(bedroomSvg({ ...OLD.state, titles }, OLD.dim))

  await room.clock.advance(7300)
  const values = await room.values()
  expect(values).toMatchObject({ tv: 0, lava: 1, pc: 0, lamp: 1, light: 1 })
  expect(bit(values?.screen, 4)).toBe(1)
  expect(bit(values?.screen, 16)).toBe(1)
  const lit = await room.source()
  expect(lit).toBe(bedroomSvg({ ...OLD.state, tv: true, lava: false, pc: true, lamp: false, tape: false, console: false, light: true, titles, underShader: true }, OLD.dim))
  for (const drawn of ['Moth $&amp; Hour', 'Night &lt;Drive&gt;', '>SILVER FOXES</text>', '>PINE HOLLOW</text>']) expect(lit).toContain(drawn)

  expect(await room.run('title')).toContain('console "Moth $& Hour", tape "Night <Drive>", pennant "SILVER FOXES", pennant-top "PINE HOLLOW"')
  expect(await room.run('glass')).toContain('(now 40); blur is how much they blur it (now 8)')

  await room.run('weather rain')
  expect(room.store.get(STORE_KEY)).toEqual({ ...OLD, weather: 'rain' })

  await room.run('')
  const card = await $.ui.mount({ plugin: 'themes', surface: 'desktop', component: 'Placed', requestId: 'bedroom-card-1', props: { id: 'bedroom-card-1', plugin: 'themes' } })
  for (const text of ['dim 30', 'glass 40', 'blur 8']) expect((await card.find({ type: 'Text', text }))?.text).toBe(text)
  expect((await card.find({ key: 'switch-tv' }))?.props.label).toBe('tv: off')
  expect((await card.find({ key: 'switch-lava' }))?.props.label).toBe('lava: on')
  expect((await card.find({ key: 'title-pennant' }))?.props.value).toBe('SILVER FOXES')
  await card.unmount()
  await room.unmount()
})
