import type { EngineInterface } from 'claude-code'
import { expect, test } from 'claude-code/testing'

import { ctxOf, usePieces } from './context.js'
import { HITS } from '../scene/lib.ts'
import { handleClick } from './clicks.js'
import { runCommand } from './commands.js'
import type { Piece, Switch } from './piece.js'
import { load } from './saved.js'
import { flush } from './telemetry.js'
import { inWindow } from './testing.js'
import { encodeWorld, nextValues } from './values.js'

const heard: [Switch, boolean, string][] = []
const standIn: Piece = {
  name: 'stand-in',
  fields: () => ({ sun: 6, weather: 2 }),
  switched: (_, name, isOn, by) => void heard.push([name, isOn, by]),
}
/** The stand-in's own hook, as a turn event would call it. */
async function onTurn($: EngineInterface): Promise<void> {
  await ctxOf($).send('a turn starting', { hurry: true })
}
const throwing: Piece = {
  name: 'throwing',
  fields: () => {
    throw new Error('boom')
  },
}

/** A hook's `$` with the calls these make: the store, a redraw, the clock and the debug log. */
function engine(): { $: EngineInterface; log: string[] } {
  const store = new Map<string, unknown>()
  const log: string[] = []
  const $ = {
    plugin: { root: '/bedroom' },
    store: {
      get: async (key: string) => store.get(key),
      set: async (key: string, value: unknown) => void store.set(key, value),
    },
    ui: { toast: () => undefined, invalidate: () => undefined, log: (text: string) => void log.push(text) },
    theme: { set: async () => ({ isDrawn: true }) },
    clock: { now: async () => 120_000, after: () => ({ cancel: () => undefined }) },
  }
  return { $: $ as unknown as EngineInterface, log }
}

test('a piece that makes its Ctx with ctxOf gets its fields sent, and hears clicks and commands', async () => {
  const { $, log } = engine()
  await load($)
  usePieces([standIn, throwing])
  expect(ctxOf($).fields()).toEqual({ sun: 6, weather: 2, work: 0, zone: 0, hall: 0 })
  await onTurn($)
  expect(nextValues(120_000).values.world).toBe(encodeWorld({ sun: 6, weather: 2, work: 0, zone: 0, hall: 0 }))
  const [left, top, width, height] = HITS.tv!
  expect(await handleClick($, inWindow(left + width / 2, top + height / 2, ctxOf($).saved.aspect))).toBe('tv')
  await runCommand($, 'lamp on')
  expect(heard).toEqual([
    ['tv', false, 'click'],
    ['lamp', true, 'command'],
  ])
  flush($)
  await Promise.resolve()
  expect(log.filter(line => line.includes("the throwing piece's fields failed: boom")).length).toBe(1)
})
