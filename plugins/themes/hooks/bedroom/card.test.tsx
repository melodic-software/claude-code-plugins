import { expect, mock, test } from 'claude-code/testing'
import type { Engine, MockClock } from 'claude-code/testing'
import type { On } from 'claude-code'

import { EVENT_BUTTONS, TIME_ORDER } from './card.tsx'
import { PHASES } from './core/settings.js'
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

/** Shows the four title fields, behind the card's titles button. */
async function showTitles(ui: { find: (q: { key: string }) => Promise<unknown>; press: (q: { key: string }) => Promise<unknown> }): Promise<void> {
  if ((await ui.find({ key: 'title-console' })) === undefined) await ui.press({ key: 'titles' })
}

/** How many times the room has been sent, from /bedroom stats. */
async function roomSends($: Engine): Promise<number> {
  return Number(/room sent: (\d+)/.exec(await bedroom($, 'stats'))?.[1])
}

/**
 * The two card tests below take 0.9 to 1.1 s and 0.4 to 0.7 s on an idle machine under claude plugin test, and ran past the
 * default limit while the plugin started on a loaded one; this keeps that room.
 */
const CARD_START_MS = 20_000

test('/bedroom alone keeps its answer and shows a card listing every switch with its state', { timeoutMs: CARD_START_MS }, async ($, on) => {
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

/**
 * A row's width in the app, in px, estimated from the owner's screenshot of the card at about 1,130 px: a button is 30 px
 * and 8.5 px a character ("console: off" 135 px, "reset" 73 px), a text 8.5 px a character, 14 px between items and 40
 * px between groups. The card's rows have 1,105 px inside its border.
 */
function widthOf(row: unknown): number {
  let px = 0
  let items = 0
  let groups = 0
  const walk = (node: unknown): void => {
    if (Array.isArray(node)) return node.forEach(walk)
    if (typeof node !== 'object' || node === null) return
    const n = node as { type?: string; props?: { label?: unknown; children?: unknown; columnGap?: unknown }; text?: unknown; children?: unknown }
    if (n.type === 'Button') {
      px += 30 + 8.5 * String(n.props?.label ?? '').length
      items += 1
      return
    }
    if (n.type === 'Input') {
      const input = n.props as { label?: string; placeholder?: string; submitLabel?: string }
      px += fieldPx(String(input.label ?? '').length, Number(/up to (\d+)/.exec(String(input.placeholder ?? ''))?.[1] ?? 0), String(input.submitLabel ?? '').length)
      items += 1
      return
    }
    if (n.type === 'Text') {
      if (n.props?.children !== undefined && typeof n.props.children !== 'string') return
      px += 8.5 * String(n.text ?? n.props?.children ?? '').length
      items += 1
      return
    }
    if (n.type === 'Box' && n.props?.columnGap === 'lg') groups += 1
    walk(n.props?.children)
    walk(n.children)
  }
  walk(row)
  return px + 14 * Math.max(0, items - 1) + 26 * groups
}
const INSIDE_PX = 1105
/**
 * A title field's width: its label above or beside a text box that holds its longest title at 8.5 px a character with
 * 24 px of padding, and its submit button as any button (30 px and 8.5 px a character), 14 px apart.
 */
const fieldPx = (label: number, longest: number, submit: number): number => 8.5 * label + 14 + (24 + 8.5 * longest) + 14 + (30 + 8.5 * submit)

test('the card is six rows with titles or the sound bank open: no row or field wider than the card, the time from earliest to latest, no shader button', { timeoutMs: CARD_START_MS }, async ($, on) => {
  const placed: string[] = []

  engine(on, ['desktop'], placed)
  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  await bedroom($, 'sound volume 100')
  await bedroom($, '')

  const ui = await $.ui.mount(cardOf(placed[0]!))
  const rowsOf = async (): Promise<unknown[]> => {
    const drawn = await ui.drawn()
    return 'children' in drawn ? ((drawn.children ?? []) as unknown[]) : []
  }
  const keysOf = async (): Promise<string[]> => (await rowsOf()).map(row => /"key":"([^"]+)"/.exec(JSON.stringify(row))?.[1] ?? '')

  expect(await keysOf()).toEqual(['head', 'switches', 'time', 'weather', 'look', 'sound'])
  expect(await ui.find({ type: 'Text', text: STATUS })).toBeUndefined()
  expect(await ui.find({ key: 'toggle-shader' })).toBeUndefined()
  expect(JSON.stringify(await rowsOf())).not.toContain('shader')

  const head = JSON.stringify(await ui.find({ key: 'head' }))
  for (const key of ['theme', 'reset', 'calibrate', 'titles', 'close']) expect(head).toContain(`"key":"${key}"`)
  const look = JSON.stringify(await ui.find({ key: 'look' }))
  for (const key of ['dim-down', 'dim-up', 'glass-down', 'glass-up', 'blur-down', 'blur-up', 'toggle-signal', 'toggle-hall']) expect(look).toContain(`"key":"${key}"`)
  const sound = JSON.stringify(await ui.find({ key: 'sound' }))
  for (const key of ['toggle-sound', 'volume-down', 'volume-up', 'sounds', 'said-box']) expect(sound).toContain(`"key":"${key}"`)
  expect((await ui.find({ type: 'Text', text: 'bed: off' }))?.text).toBe('bed: off')
  expect(widthOf(await ui.find({ key: 'sound-controls' })) <= INSIDE_PX - 300).toBe(true)

  const time = JSON.stringify(await ui.find({ key: 'time' }))
  const order = ['auto', 'predawn', 'dawn', 'morning', 'noon', 'golden', 'dusk', 'evening', 'night']
  expect(order.map(word => time.indexOf(`"key":"time-${word}"`))).toEqual([...order.map(word => time.indexOf(`"key":"time-${word}"`))].sort((a, b) => a - b))
  for (const word of order) expect((await ui.find({ key: `time-${word}` }))?.props.label).toBe(word === 'auto' ? 'auto ✓' : word)
  for (const word of ['auto', 'clear', 'overcast', 'rain', 'downpour', 'storm']) {
    expect((await ui.find({ key: `weather-${word}` }))?.props.label).toBe(word === 'auto' ? 'auto ✓' : word)
  }
  expect((await ui.find({ key: 'toggle-sound' }))?.props.label).toBe('sound: off')
  expect((await ui.find({ type: 'Text', text: 'volume 100' }))?.text).toBe('volume 100')

  const widths: Record<string, number> = Object.fromEntries(((await rowsOf()) as unknown[]).slice(0, 5).map((row, i) => [['head', 'switches', 'time', 'weather', 'look'][i], Math.round(widthOf(row))]))
  for (const [key, px] of Object.entries(widths)) expect([key, px <= INSIDE_PX]).toEqual([key, true])
  const switches = JSON.stringify(await ui.find({ key: 'switches' }))
  for (const { key, label } of EVENT_BUTTONS) {
    expect(switches).toContain(`"key":"${key}"`)
    expect(label.length <= 5).toBe(true)
  }

  await ui.press({ key: 'calibrate' })
  await ui.press({ key: 'titles' })
  expect(await keysOf()).toEqual(['head', 'switches', 'title-row-1', 'title-row-2', 'look', 'sound'])
  expect((await ui.find({ key: 'titles' }))?.props.label).toBe('titles: hide')
  const caps = { console: 24, tape: 24, pennant: 12, 'pennant-top': 16 } as const
  for (const [row, keys] of [['title-row-1', ['console', 'tape']], ['title-row-2', ['pennant', 'pennant-top']]] as const) {
    const drawn = await ui.find({ key: row })
    const text = JSON.stringify(drawn)
    for (const key of keys) expect(text).toContain(`"key":"title-${key}"`)
    expect(widthOf(drawn) <= INSIDE_PX).toBe(true)
    for (const key of keys) {
      const field = await ui.find({ key: `title-${key}` })
      expect(field?.props.placeholder).toBe(`up to ${caps[key]}`)
      expect([key, fieldPx(key.length, caps[key], 'set'.length) <= (INSIDE_PX - 14) / 2]).toEqual([key, true])
    }
  }
  expect(fieldPx('console'.length, 24, 3) > INSIDE_PX / 4).toBe(true)
  const said = JSON.stringify(await ui.find({ key: 'said-box' }))
  expect(said).toContain('click the bottom-left corner of the front of the dresser')
  expect(said).toContain('"maxLines":1')

  await ui.press({ key: 'sounds' })
  expect(await keysOf()).toEqual(['head', 'switches', 'bank-row-1', 'bank-row-2', 'look', 'sound'])
  expect((await ui.find({ key: 'titles' }))?.props.label).toBe('titles: show')
  expect((await ui.find({ key: 'sounds' }))?.props.label).toBe('sounds: hide')
  for (const row of ['bank-row-1', 'bank-row-2']) expect(widthOf(await ui.find({ key: row })) <= INSIDE_PX).toBe(true)
  expect((await ui.find({ key: 'pick-cicadas-auto' }))?.props.label).toBe('auto ✓')
  expect((await ui.find({ key: 'pick-night-auto' }))?.props.label).toBe('auto ✓')
  expect((await ui.find({ key: 'pick-cicadas-chorus' }))?.props.label).toBe('chorus')
  await ui.press({ key: 'pick-cicadas-river' })
  expect((await ui.find({ key: 'pick-cicadas-river' }))?.props.label).toBe('river ✓')
  expect(await bedroom($, 'sound')).toMatch(/bank: cicadas river, night auto, rain roof, thunder storm, tv tube/)
  await ui.press({ key: 'toggle-objects' })
  expect((await ui.find({ key: 'toggle-objects' }))?.props.label).toBe('objects: off')
  await bedroom($, 'sound pick cicadas chorus')
  await bedroom($, 'sound objects on')
  await ui.press({ key: 'sounds' })
  expect(await keysOf()).toEqual(['head', 'switches', 'time', 'weather', 'look', 'sound'])
  await ui.unmount()
})

test('the time row reorders only the buttons: each phase keeps its own number for the shader', async () => {
  expect([...TIME_ORDER].sort()).toEqual([...PHASES].sort())
  expect(PHASES.indexOf('dusk')).toBe(0)
  expect(PHASES.indexOf('night')).toBe(2)
})

test('the volume steps by ten from 0 to 100 through /bedroom sound volume, saved with the settings', async ($, on) => {
  const placed: string[] = []

  engine(on, ['desktop'], placed)
  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  await bedroom($, 'sound volume 90')
  await bedroom($, '')

  const ui = await $.ui.mount(cardOf(placed[0]!))

  await ui.press({ key: 'volume-up' })
  expect((await ui.find({ type: 'Text', text: 'volume 100' }))?.text).toBe('volume 100')
  await ui.press({ key: 'volume-up' })
  expect(await bedroom($, 'sound')).toMatch(/^sound is off, volume 100,/)
  for (let i = 0; i < 11; i++) await ui.press({ key: 'volume-down' })
  expect(await bedroom($, 'sound')).toMatch(/^sound is off, volume 0,/)
  expect((await ui.find({ type: 'Text', text: 'volume 0' }))?.text).toBe('volume 0')
  await bedroom($, 'sound volume 70')
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

test('pass, door and bolt run the hallway\'s and the storm\'s commands, each dim while its command would only say why not', async ($, on) => {
  const placed: string[] = []

  engine(on, ['desktop'], placed)
  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  await bedroom($, 'hall on')
  await bedroom($, 'weather clear')
  await bedroom($, '')

  const ui = await $.ui.mount(cardOf(placed[0]!))
  const said = async (): Promise<string> => JSON.stringify(await ui.find({ key: 'said-box' }))

  expect(EVENT_BUTTONS.map(({ words }) => words)).toEqual(['hall pass', 'hall light', 'weather strike'])
  expect((await ui.find({ key: 'event-pass' }))?.props.dimColor).toBe(false)
  expect((await ui.find({ key: 'event-door' }))?.props.dimColor).toBe(false)
  expect((await ui.find({ key: 'event-bolt' }))?.props.dimColor).toBe(true)
  await ui.press({ key: 'event-bolt' })
  expect(await said()).toContain('lightning comes only in a storm, and the weather is clear')
  await ui.press({ key: 'event-pass' })
  expect(await said()).toMatch(/someone passes the door|not now: the shader/)

  await bedroom($, 'weather storm')
  expect((await ui.find({ key: 'event-bolt' }))?.props.dimColor).toBe(false)
  await bedroom($, 'hall off')
  expect((await ui.find({ key: 'event-door' }))?.props.dimColor).toBe(true)
  await ui.press({ key: 'event-door' })
  expect(await said()).toContain('the hallway is off')
  await bedroom($, 'weather clear')
  await bedroom($, 'hall on')
  await ui.unmount()
})

test('door is the hall light\'s switch: checked while the light is on, and the next press turns it off; pass and bolt stay plain', { timeoutMs: CARD_START_MS }, async ($, on) => {
  const placed: string[] = []
  const clock = engine(on, ['desktop'], placed)
  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  await bedroom($, 'hall on')
  await bedroom($, 'weather storm')
  await bedroom($, '')
  const room = await $.ui.mount(BACKDROP)
  const ui = await $.ui.mount(cardOf(placed[0]!))
  const label = async (key: string): Promise<unknown> => (await ui.find({ key }))?.props.label
  await clock.advance(60_000)

  expect(await label('event-door')).toBe('door')
  await ui.press({ key: 'event-door' })
  expect(await label('event-door')).toBe('door ✓')
  await ui.press({ key: 'event-pass' })
  await ui.press({ key: 'event-bolt' })
  expect([await label('event-pass'), await label('event-bolt')]).toEqual(['pass', 'bolt'])
  await clock.advance(30_000)
  expect(await label('event-door')).toBe('door ✓')
  await ui.press({ key: 'event-door' })
  expect(await label('event-door')).toBe('door')
  await ui.press({ key: 'event-door' })
  expect(await label('event-door')).toBe('door ✓')
  await clock.advance(4 * 60_000)
  await bedroom($, 'status')
  expect(await label('event-door')).toBe('door')
  await bedroom($, 'weather clear')
  await ui.unmount()
  await room.unmount()
})

test('a pressed switch moves the shader\'s number once, straight to the end, and a typed order to the state it is in sends nothing', async ($, on) => {
  const placed: string[] = []
  const clock = engine(on, ['desktop'], placed)

  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  await bedroom($, 'reset')
  await bedroom($, '')

  const room = await $.ui.mount(BACKDROP)
  const ui = await $.ui.mount(cardOf(placed[0]!))
  const tv = async (): Promise<unknown> => ((await room.find({ type: 'Shader' }))?.props.values as Record<string, number> | undefined)?.tv

  await clock.advance(SETTLE_MS)
  expect(await tv()).toBe(1)

  await ui.press({ key: 'switch-tv' })
  expect(await tv()).toBe(0)
  await clock.advance(1000)
  expect(await tv()).toBe(0)

  expect(await bedroom($, 'tv off')).toContain('the tv is already off')
  expect(await tv()).toBe(0)
  await clock.advance(1500)
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

  await showTitles(ui)
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

  await showTitles(ui)
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
  await showTitles(ui)
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

  await showTitles(ui)
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

  await showTitles(ui)
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
