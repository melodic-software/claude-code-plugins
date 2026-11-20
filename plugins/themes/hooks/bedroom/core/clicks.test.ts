import type { EngineInterface } from 'claude-code'
import { expect, test } from 'claude-code/testing'

import { HITS } from '../scene/lib.ts'
import { handleClick } from './clicks.js'
import { STORE_KEY, current, load, type Saved } from './saved.js'
import { inWindow } from './testing.js'

const middle = (name: string): [number, number] => {
  const [left, top, width, height] = HITS[name]!
  return [left + width / 2, top + height / 2]
}

/**
 * A stand-in for a hook's `$`, with the calls a click can make. The kit cannot raise ui.pointer, and the `$` of a
 * test is the engine's (its calls take the event's whole input), so handleClick is run on this.
 */
function standIn(stored: Partial<Saved>): { $: EngineInterface; store: Map<string, unknown>; toasts: string[]; redraws: number[]; sent: number[] } {
  const store = new Map<string, unknown>([[STORE_KEY, stored]])
  const record = { toasts: [] as string[], redraws: [] as number[], sent: [] as number[] }
  const $ = {
    store: {
      get: async (key: string) => store.get(key),
      set: async (key: string, value: unknown) => void store.set(key, JSON.parse(JSON.stringify(value))),
    },
    ui: {
      toast: (text: string) => void record.toasts.push(text),
      invalidate: () => void record.redraws.push(1),
    },
    clock: { now: async () => 0, after: () => ({ cancel: () => undefined }) },
  }
  return { $: $ as unknown as EngineInterface, store, ...record }
}

test('a click flips the saved switch, mapped with the stored window shape; with no shader running yet, it is drawn into the room', async () => {
  const aspect = 2.1
  const room = standIn({ state: { tv: true, tape: false, console: false, pc: true, light: false, lamp: false, lava: false, posters: 'plain' }, aspect })
  await load(room.$)
  expect(current().aspect).toBe(aspect)

  const tv = inWindow(...middle('tv'), aspect)
  expect(await handleClick(room.$, tv)).toBe('tv')
  await Promise.resolve()
  expect((room.store.get(STORE_KEY) as Saved).state.tv).toBe(false)
  expect(await handleClick(room.$, tv)).toBe('tv')
  await Promise.resolve()
  expect((room.store.get(STORE_KEY) as Saved).state.tv).toBe(true)
  expect(await handleClick(room.$, inWindow(...middle('spine'), aspect))).toBe('tape')
  await Promise.resolve()
  expect((room.store.get(STORE_KEY) as Saved).state.tape).toBe(true)
  await Promise.resolve()
  expect(room.redraws).toEqual([1, 1, 1])

  expect(await handleClick(room.$, { x: 0.5, y: 0.5 })).toBeUndefined()
  expect(await handleClick(room.$, inWindow(...middle('cat'), aspect))).toBe('cat')
  expect(room.toasts).toEqual(['the cat purrs'])
  expect(room.redraws).toEqual([1, 1, 1])
})

test('where two click rectangles overlap a click flips both switches, as the shader does', async () => {
  const aspect = 1.6
  const room = standIn({ state: { tv: true, tape: false, console: false, pc: true, light: false, lamp: false, lava: false, posters: 'plain' }, aspect })
  await load(room.$)
  await handleClick(room.$, inWindow(1340, 560, aspect))
  await handleClick(room.$, inWindow(1399, 500, aspect))
  await Promise.resolve()
  expect((room.store.get(STORE_KEY) as Saved).state).toMatchObject({ console: true, tape: true, lava: true, light: true, tv: true, pc: true, lamp: false })
})

test('a click at each window shape lands where toViewBox puts it', async () => {
  for (const aspect of [1.6, 1.88, 2.48]) {
    const room = standIn({ aspect })
    await load(room.$)
    for (const name of ['tv', 'pc', 'lamp', 'lava', 'console', 'light']) {
      expect(await handleClick(room.$, inWindow(...middle(name), aspect)), `${name} at ${aspect}`).toBe(name)
    }
  }
})
