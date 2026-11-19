import { expect, mock, test } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'
import type { On } from 'claude-code'

const SWITCHES = ['tv', 'tape', 'console', 'pc', 'light', 'lamp', 'lava']

/** Hooks that stand for the engine beneath the plugin. Answers the session's surfaces, and records each placed row's id. */
function engine(on: On, surfaces: readonly ('terminal' | 'desktop')[], placed: string[]): void {
  on('command.register', () => ({ value: { command: 'bedroom' } }))
  on('store.get', () => ({ value: undefined }))
  on('store.set', () => ({ value: undefined }))
  on('theme.set', () => ({ value: { isDrawn: true, requestId: 'backdrop' } }))
  on('theme.clear', () => ({ value: { isDrawn: true, requestId: 'theme' } }))
  on('session.surfaces', () => ({ value: surfaces }))
  on('ui.place', (_, e) => {
    placed.push(e.id)

    return { value: { isPlaced: true, requestId: e.id } }
  })
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  mock.clock(on)
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

test('/bedroom alone keeps its answer and shows a card listing every switch with its state', async ($, on) => {
  const placed: string[] = []

  engine(on, ['desktop'], placed)
  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  await bedroom($, 'reset')

  const status = await bedroom($, 'status')

  expect(status).toBe('on: tv, pc. off: tape, console, light, lamp, lava. posters: plain. dim: 0')
  expect(await bedroom($, '')).toBe(`${status}. The settings card is below.`)
  expect(placed).toHaveLength(1)

  const ui = await $.ui.mount(cardOf(placed[0]!))

  expect((await ui.find({ type: 'Text', text: status }))?.text).toBe(status)
  for (const name of SWITCHES) {
    const state = name === 'tv' || name === 'pc' ? 'on' : 'off'

    expect((await ui.find({ key: `switch-${name}` }))?.props.label).toBe(`${name}: ${state}`)
  }
  expect((await ui.find({ key: 'dim-up' }))?.props.label).toBe('+10')
  expect((await ui.find({ key: 'theme' }))?.props.label).toBe('theme: on')
  await ui.unmount()
})

test('a press flips the same state the command flips, and a typed command shows on the card', async ($, on) => {
  const placed: string[] = []

  engine(on, ['desktop'], placed)
  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  await bedroom($, 'reset')
  await bedroom($, '')

  const ui = await $.ui.mount(cardOf(placed[0]!))

  await ui.press({ key: 'switch-tv' })
  expect(await bedroom($, 'status')).toBe('on: pc. off: tv, tape, console, light, lamp, lava. posters: plain. dim: 0')
  expect((await ui.find({ key: 'switch-tv' }))?.props.label).toBe('tv: off')

  await bedroom($, 'tv on')
  expect((await ui.find({ key: 'switch-tv' }))?.props.label).toBe('tv: on')

  await ui.press({ key: 'dim-up' })
  expect(await bedroom($, 'status')).toBe('on: tv, pc. off: tape, console, light, lamp, lava. posters: plain. dim: 10')
  expect((await ui.find({ type: 'Text', text: 'dim 10' }))?.text).toBe('dim 10')

  await ui.press({ key: 'theme' })
  expect((await ui.find({ key: 'theme' }))?.props.label).toBe('theme: off')
  expect((await ui.find({ type: 'Text', text: 'the theme is cleared' }))?.text).toBe('the theme is cleared')

  await bedroom($, 'on')
  expect((await ui.find({ key: 'theme' }))?.props.label).toBe('theme: on')
  expect(await ui.find({ type: 'Text', text: 'the theme is cleared' })).toBeUndefined()
  await ui.unmount()
})

/** How many times the room has been sent, from /bedroom stats. */
async function roomSends($: Engine): Promise<number> {
  return Number(/room sent: (\d+)/.exec(await bedroom($, 'stats'))?.[1])
}

test('a switch pressed on the card sends the room no more than the typed command; a title sends it once', async ($, on) => {
  const placed: string[] = []

  engine(on, ['desktop'], placed)
  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  await bedroom($, 'reset')
  await bedroom($, '')

  const room = await $.ui.mount({
    plugin: 'themes',
    surface: 'desktop',
    component: 'Backdrop',
    requestId: 'backdrop',
    props: { plugin: 'themes', scene: 'bedroom', glass: { blur: 0, opacity: 0 } },
  })
  const ui = await $.ui.mount(cardOf(placed[0]!))
  const before = await roomSends($)

  expect(before).toBeGreaterThan(0)
  await bedroom($, 'lamp')
  await room.find({ type: 'Svg' })
  expect(await roomSends($)).toBe(before)

  await ui.press({ key: 'switch-lamp' })
  await room.find({ type: 'Svg' })
  expect(await roomSends($)).toBe(before)

  await ui.input({ key: 'title-tape', text: 'Moth Hour Tape' })
  await room.find({ type: 'Svg' })
  expect(await roomSends($)).toBe(before + 1)
  await ui.unmount()
  await room.unmount()
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

test('away from the desktop /bedroom answers with text alone and draws no card', async ($, on) => {
  const placed: string[] = []

  engine(on, ['terminal'], placed)
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  await bedroom($, 'reset')

  expect(await bedroom($, '')).toBe('on: tv, pc. off: tape, console, light, lamp, lava. posters: plain. dim: 0')
  expect(placed).toHaveLength(0)

  const ui = await $.ui.mount({ ...cardOf('bedroom-card-1'), surface: 'terminal' })

  expect(await ui.find({ type: 'Button' })).toBeUndefined()
  await ui.unmount()
})
