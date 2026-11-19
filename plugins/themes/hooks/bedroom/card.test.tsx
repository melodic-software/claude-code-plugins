import { expect, mock, test } from 'claude-code/testing'
import type { Engine, MockClock } from 'claude-code/testing'
import type { On } from 'claude-code'

import { CHANGE_MS } from './register.tsx'
import { bedroomSvg } from './scene.ts'
import { DEFAULT_STATE, type State } from './scene/lib.ts'

const SWITCHES = ['tv', 'tape', 'console', 'pc', 'light', 'lamp', 'lava'] as const
/** How long a changed room shows alone before the shader starts over it (SETTLE_MS in register.tsx). */
const SETTLE_MS = 7000
const STATUS = 'on: tv, pc. off: tape, console, light, lamp, lava. posters: plain. dim: 0'

/** Hooks that stand for the engine beneath the plugin. Answers the session's surfaces, records each placed row's id and each theme call. */
function engine(on: On, surfaces: readonly ('terminal' | 'desktop')[], placed: string[], themeCalls: string[] = []): MockClock {
  on('command.register', () => ({ value: { command: 'bedroom' } }))
  on('store.get', () => ({ value: undefined }))
  on('store.set', () => ({ value: undefined }))
  on('theme.set', () => {
    themeCalls.push('set')

    return { value: { isDrawn: true, requestId: 'backdrop' } }
  })
  on('theme.clear', () => {
    themeCalls.push('clear')

    return { value: { isDrawn: true, requestId: 'theme' } }
  })
  on('session.surfaces', () => ({ value: surfaces }))
  on('ui.place', (_, e) => {
    placed.push(e.id)

    return { value: { isPlaced: true, requestId: e.id } }
  })
  on('ui.log', () => ({ value: undefined }))
  on('ui.toast', () => ({ value: undefined }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))

  return mock.clock(on)
}

async function bedroom($: Engine, args: string): Promise<string> {
  const answer = await $.command.run({
    command: 'bedroom',
    args,
    origin: { kind: 'composer' },
    presentation: { isFullscreen: false, columns: 100 },
  })

  return 'text' in answer ? String(answer.text) : ''
}

function cardOf(id: string) {
  return { plugin: 'themes', surface: 'desktop', component: 'Placed', requestId: id, props: { id, plugin: 'themes' } } as const
}

const BACKDROP = {
  plugin: 'themes',
  surface: 'desktop',
  component: 'Backdrop',
  requestId: 'backdrop',
  props: { plugin: 'themes', scene: 'bedroom', glass: { blur: 0, opacity: 0 } },
} as const

/** The room drawn with every switch as it stands, as the mod draws it with no shader. */
function wholeRoom(state: Partial<State>, dim: number, titles: State['titles'] = {}): string {
  return bedroomSvg({ ...DEFAULT_STATE, ...state, titles }, dim)
}

/** The room the shader runs over: the ceiling light on, the things the shader draws as it expects them. */
function shaderRoom(dim: number, titles: State['titles'] = {}): string {
  return bedroomSvg({ ...DEFAULT_STATE, tv: true, lava: false, pc: true, lamp: false, tape: false, console: false, light: true, titles, underShader: true }, dim)
}

/** How many times the room has been sent, from /bedroom stats. */
async function roomSends($: Engine): Promise<number> {
  return Number(/room sent: (\d+)/.exec(await bedroom($, 'stats'))?.[1])
}

test('/bedroom alone keeps its answer and shows a card listing every switch with its state', async ($, on) => {
  const placed: string[] = []

  engine(on, ['desktop'], placed)
  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  await bedroom($, 'reset')

  const status = await bedroom($, 'status')

  expect(status).toBe(STATUS)
  expect(await bedroom($, '')).toBe(status)
  expect(placed).toHaveLength(1)

  const ui = await $.ui.mount(cardOf(placed[0]!))

  for (const name of SWITCHES) {
    const state = name === 'tv' || name === 'pc' ? 'on' : 'off'

    expect((await ui.find({ key: `switch-${name}` }))?.props.label).toBe(`${name}: ${state}`)
  }
  expect((await ui.find({ key: 'dim-up' }))?.props.label).toBe('+10')
  expect((await ui.find({ key: 'theme' }))?.props.label).toBe('theme: on')
  await ui.unmount()
})

test('the card is five rows: title and actions, switches, dim glass and blur together, and the titles two to a row', async ($, on) => {
  const placed: string[] = []

  engine(on, ['desktop'], placed)
  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  await bedroom($, '')

  const ui = await $.ui.mount(cardOf(placed[0]!))
  const rows = (await ui.drawn()).children ?? []

  expect(rows).toHaveLength(5)
  expect(await ui.find({ type: 'Text', text: STATUS })).toBeUndefined()

  const head = await ui.find({ key: 'head' })
  const look = await ui.find({ key: 'look' })

  for (const key of ['theme', 'reset', 'calibrate', 'close']) {
    expect(JSON.stringify(head)).toContain(`"key":"${key}"`)
  }
  for (const key of ['dim-down', 'dim-up', 'glass-down', 'glass-up', 'blur-down', 'blur-up']) {
    expect(JSON.stringify(look)).toContain(`"key":"${key}"`)
  }
  expect(JSON.stringify(await ui.find({ key: 'titles-console' }))).toContain('"key":"title-tape"')
  expect(JSON.stringify(await ui.find({ key: 'titles-pennant' }))).toContain('"key":"title-pennant-top"')
  await ui.unmount()
})

test('a pressed switch is inactive until its change has had time to finish, then answers again', async ($, on) => {
  const placed: string[] = []
  const clock = engine(on, ['desktop'], placed)

  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  await bedroom($, 'reset')
  await bedroom($, '')

  const ui = await $.ui.mount(cardOf(placed[0]!))

  await ui.press({ key: 'switch-tv' })
  expect(await bedroom($, 'status')).toBe('on: pc. off: tv, tape, console, light, lamp, lava. posters: plain. dim: 0')
  expect((await ui.find({ key: 'switch-tv' }))?.props.label).toBe('tv: off…')
  expect((await ui.find({ key: 'switch-tv' }))?.props.dimColor).toBe(true)

  await ui.press({ key: 'switch-tv' })
  expect(await bedroom($, 'status')).toContain('off: tv,')

  await clock.advance(CHANGE_MS.tv[0] - 1)
  expect((await ui.find({ key: 'switch-tv' }))?.props.label).toBe('tv: off…')
  await clock.advance(1)
  expect((await ui.find({ key: 'switch-tv' }))?.props.label).toBe('tv: off')
  expect((await ui.find({ key: 'switch-tv' }))?.props.dimColor).toBe(false)

  await ui.press({ key: 'switch-console' })
  await clock.advance(CHANGE_MS.console[1] - 1)
  expect((await ui.find({ key: 'switch-console' }))?.props.label).toBe('console: on…')
  await clock.advance(1)
  expect((await ui.find({ key: 'switch-console' }))?.props.label).toBe('console: on')

  await ui.press({ key: 'switch-tv' })
  expect(await bedroom($, 'status')).toContain('on: tv,')
  await ui.unmount()
})

test('a pressed switch moves the shader\'s number once, straight to the end, and a typed order the same way turns it back first', async ($, on) => {
  const placed: string[] = []
  const clock = engine(on, ['desktop'], placed)

  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  await bedroom($, 'reset')
  await bedroom($, '')

  const room = await $.ui.mount(BACKDROP)
  const ui = await $.ui.mount(cardOf(placed[0]!))
  const tv = async (): Promise<unknown> => (await room.find({ type: 'Shader' }))?.props.values?.tv

  await clock.advance(SETTLE_MS)
  expect(await tv()).toBe(1)

  await ui.press({ key: 'switch-tv' })
  expect(await tv()).toBe(0)
  await clock.advance(1000)
  expect(await tv()).toBe(0)

  await bedroom($, 'tv off')
  expect(await tv()).toBe(0.5)
  await clock.advance(700)
  expect(await tv()).toBe(0)
  await ui.unmount()
  await room.unmount()
})

test('with the ceiling light off, a dim step or a title never draws the lit room: the room shows as it stands, then the shader takes it over', async ($, on) => {
  const placed: string[] = []
  const clock = engine(on, ['desktop'], placed)

  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  await bedroom($, 'reset')
  await bedroom($, '')

  const room = await $.ui.mount(BACKDROP)
  const ui = await $.ui.mount(cardOf(placed[0]!))
  const shown = async (): Promise<{ isShader: boolean; source: unknown }> => ({
    isShader: (await room.find({ type: 'Shader' })) !== undefined,
    source: (await room.find({ type: 'Svg' }))?.props.source,
  })

  expect(await shown()).toEqual({ isShader: false, source: wholeRoom({}, 0) })
  await clock.advance(SETTLE_MS)
  expect(await shown()).toEqual({ isShader: true, source: shaderRoom(0) })

  await ui.press({ key: 'dim-up' })
  expect(await shown()).toEqual({ isShader: false, source: wholeRoom({}, 0.1) })
  expect((await shown()).source).not.toBe(shaderRoom(0.1))
  await clock.advance(SETTLE_MS - 1)
  expect((await shown()).isShader).toBe(false)
  await clock.advance(1)
  expect(await shown()).toEqual({ isShader: true, source: shaderRoom(0.1) })

  await ui.input({ key: 'title-console', text: 'Moth Hour' })
  expect(await shown()).toEqual({ isShader: false, source: wholeRoom({}, 0.1, { console: 'Moth Hour' }) })
  await clock.advance(SETTLE_MS)
  expect(await shown()).toEqual({ isShader: true, source: shaderRoom(0.1, { console: 'Moth Hour' }) })

  await bedroom($, 'dim 30')
  expect(await shown()).toEqual({ isShader: false, source: wholeRoom({}, 0.3, { console: 'Moth Hour' }) })
  await clock.advance(SETTLE_MS)
  expect((await shown()).isShader).toBe(true)

  await bedroom($, 'title console')
  await ui.unmount()
  await room.unmount()
})

test('a switch sends no room while the shader runs; a title sends the room once', async ($, on) => {
  const placed: string[] = []
  const clock = engine(on, ['desktop'], placed)

  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  await bedroom($, 'reset')
  await bedroom($, '')

  const room = await $.ui.mount(BACKDROP)
  const ui = await $.ui.mount(cardOf(placed[0]!))

  await clock.advance(SETTLE_MS)
  const before = await roomSends($)

  expect(before).toBeGreaterThan(0)
  await bedroom($, 'lamp')
  await room.find({ type: 'Svg' })
  expect(await roomSends($)).toBe(before)

  await ui.press({ key: 'switch-lava' })
  await room.find({ type: 'Svg' })
  expect(await roomSends($)).toBe(before)

  await ui.input({ key: 'title-tape', text: 'Moth Hour Tape' })
  await room.find({ type: 'Svg' })
  expect(await roomSends($)).toBe(before + 1)
  await ui.unmount()
  await room.unmount()
})

test('reset on the card puts the switches, dim, glass and blur back, keeps the titles, and holds the switches it changed', async ($, on) => {
  const placed: string[] = []
  const clock = engine(on, ['desktop'], placed)

  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  await bedroom($, 'reset')
  await bedroom($, 'lamp on')
  await bedroom($, 'tv off')
  await bedroom($, 'dim 40')
  await bedroom($, 'glass 30')
  await bedroom($, 'title tape Night Drive')
  await bedroom($, '')

  const ui = await $.ui.mount(cardOf(placed[0]!))

  await ui.press({ key: 'reset' })
  expect(await bedroom($, 'status')).toBe(STATUS)
  expect((await ui.find({ type: 'Text', text: 'dim 0' }))?.text).toBe('dim 0')
  expect((await ui.find({ type: 'Text', text: 'glass 0' }))?.text).toBe('glass 0')
  expect((await ui.find({ key: 'title-tape' }))?.props.value).toBe('Night Drive')
  expect((await ui.find({ key: 'switch-lamp' }))?.props.label).toBe('lamp: off…')
  expect((await ui.find({ key: 'switch-tv' }))?.props.label).toBe('tv: on…')
  expect((await ui.find({ key: 'switch-pc' }))?.props.label).toBe('pc: on')
  await clock.advance(Math.max(CHANGE_MS.lamp[0], CHANGE_MS.tv[1]))
  expect((await ui.find({ key: 'switch-lamp' }))?.props.label).toBe('lamp: off')
  await bedroom($, 'title tape')
  await ui.unmount()
})

test('calibrate on the card asks for the click on the dresser and leaves the switches alone', async ($, on) => {
  const placed: string[] = []

  engine(on, ['desktop'], placed)
  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  await bedroom($, 'reset')
  await bedroom($, '')

  const ui = await $.ui.mount(cardOf(placed[0]!))
  const prompt = 'click the bottom-left corner of the front of the dresser'

  await ui.press({ key: 'calibrate' })
  expect((await ui.find({ type: 'Text', text: prompt }))?.text).toBe(prompt)
  expect(await bedroom($, 'status')).toBe(STATUS)
  await ui.unmount()
})

test('the theme button clears the theme and sets it again, and says which on the card', async ($, on) => {
  const placed: string[] = []
  const themeCalls: string[] = []

  engine(on, ['desktop'], placed, themeCalls)
  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  await bedroom($, '')

  const ui = await $.ui.mount(cardOf(placed[0]!))

  themeCalls.length = 0
  await ui.press({ key: 'theme' })
  expect(themeCalls).toEqual(['clear'])
  expect((await ui.find({ key: 'theme' }))?.props.label).toBe('theme: off')
  expect((await ui.find({ type: 'Text', text: 'the theme is cleared' }))?.text).toBe('the theme is cleared')

  await ui.press({ key: 'theme' })
  expect(themeCalls).toEqual(['clear', 'set'])
  expect((await ui.find({ key: 'theme' }))?.props.label).toBe('theme: on')
  expect((await ui.find({ type: 'Text', text: 'the room is on' }))?.text).toBe('the room is on')
  await ui.unmount()
})

test('a press flips the same state the command flips, and a typed command shows on the card', async ($, on) => {
  const placed: string[] = []

  engine(on, ['desktop'], placed)
  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  await bedroom($, 'reset')
  await bedroom($, '')

  const ui = await $.ui.mount(cardOf(placed[0]!))

  await ui.press({ key: 'switch-lamp' })
  expect(await bedroom($, 'status')).toBe('on: tv, pc, lamp. off: tape, console, light, lava. posters: plain. dim: 0')

  await bedroom($, 'pc off')
  expect((await ui.find({ key: 'switch-pc' }))?.props.label).toBe('pc: off')

  await ui.press({ key: 'dim-up' })
  expect(await bedroom($, 'status')).toContain('dim: 10')
  expect((await ui.find({ type: 'Text', text: 'dim 10' }))?.text).toBe('dim 10')
  await ui.unmount()
})

test('the titles row: a field a title, Enter setting it as /bedroom title does', async ($, on) => {
  const placed: string[] = []

  engine(on, ['desktop'], placed)
  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  await bedroom($, '')

  const ui = await $.ui.mount(cardOf(placed[0]!))

  for (const key of ['console', 'tape', 'pennant', 'pennant-top']) {
    expect((await ui.find({ key: `title-${key}` }))?.type).toBe('Input')
  }
  await ui.input({ key: 'title-pennant', text: 'silver foxes of the far north' })
  expect((await ui.find({ key: 'title-pennant' }))?.props.value).toBe('SILVER FOXES')
  expect(await bedroom($, 'title')).toContain('pennant "SILVER FOXES"')

  await ui.input({ key: 'title-pennant', text: '' })
  expect(await bedroom($, 'title')).toContain('pennant "default"')
  await ui.unmount()
})

test('a title typed and not yet set survives a redraw of the card, and a typed /bedroom title replaces it', async ($, on) => {
  const placed: string[] = []

  engine(on, ['desktop'], placed)
  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  await bedroom($, '')

  const ui = await $.ui.mount(cardOf(placed[0]!))

  await ui.input({ key: 'title-console', text: 'Half Typed', kind: 'change' })
  await ui.press({ key: 'switch-lamp' })
  expect((await ui.find({ key: 'title-console' }))?.props.value).toBe('Half Typed')

  await bedroom($, 'title console Set By Command')
  expect((await ui.find({ key: 'title-console' }))?.props.value).toBe('Set By Command')

  await bedroom($, 'title console')
  await ui.unmount()
})

test('away from the desktop /bedroom answers with text alone and its row draws no card', async ($, on) => {
  const placed: string[] = []

  engine(on, ['terminal'], placed)
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  await bedroom($, 'reset')

  expect(await bedroom($, '')).toBe(STATUS)
  expect(placed).toHaveLength(1)

  const ui = await $.ui.mount({ ...cardOf(placed[0]!), surface: 'terminal' })

  expect(await ui.find({ type: 'Button' })).toBeUndefined()
  await ui.unmount()
})

test('the desktop draws the card whatever the session says of its surfaces', async ($, on) => {
  const placed: string[] = []

  engine(on, [], placed)
  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  await bedroom($, '')

  const ui = await $.ui.mount(cardOf(placed[0]!))

  expect((await ui.find({ key: 'switch-tv' }))?.type).toBe('Button')
  await ui.unmount()
})
