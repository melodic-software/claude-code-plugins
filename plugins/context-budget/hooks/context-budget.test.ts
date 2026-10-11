import { expect, test } from 'claude-code/testing'

const PANE = 'context-budget-live'
const HEADER = '◆ context 90k of 1M · compacts at 955k 9%'

// A 1,000,000-token window with 90,000 in use: two used rows, the compaction buffer, the free
// space, and one deferred row that sits outside the window. The window rows sum to 1,000,000.
const CATEGORIES = [
  { name: 'System prompt', tokens: 10_000, color: 'promptBorder', isDeferred: false, kind: 'used' },
  { name: 'Messages', tokens: 80_000, color: 'permission', isDeferred: false, kind: 'used' },
  { name: 'Autocompact buffer', tokens: 45_000, color: 'warning', isDeferred: false, kind: 'buffer' },
  { name: 'Free space', tokens: 865_000, color: 'inactive', isDeferred: false, kind: 'free' },
  { name: 'MCP tools', tokens: 5_000, color: 'subtle', isDeferred: true, kind: 'deferred' },
]

type Usage = 'breakdown' | 'no-threshold' | 'no-breakdown' | 'rejected'

const breakdown = (threshold: boolean) => ({
  categories: CATEGORIES,
  totalTokens: 90_000,
  maxTokens: 1_000_000,
  rawMaxTokens: 1_000_000,
  autocompactSource: 'model',
  percentage: 9,
  gridRows: [],
  model: 'Opus 5.5',
  memoryFiles: [],
  mcpTools: [],
  agents: [],
  ...(threshold ? { autoCompactThreshold: 955_000 } : {}),
  isAutoCompactEnabled: threshold,
  apiUsage: null,
})

// The engine beneath the plugin, and a second plugin's band row beneath this one's.
const world = (on: any, usage: Usage = 'breakdown') => {
  const w = { open: [] as string[], registered: [] as unknown[], usageCalls: 0 }
  on('session.usage', () => {
    w.usageCalls += 1
    if (usage === 'rejected') return { deny: 'usage unavailable' }
    const context = { window: 1_000_000, tokens: 88_000, percent: 9 }
    return {
      value: {
        startedAt: 0,
        rateLimits: [],
        context: usage === 'no-breakdown' ? context : { ...context, breakdown: breakdown(usage === 'breakdown') },
      },
    }
  })
  on('ui.open', ($: unknown, e: { id: string }) => {
    if (!w.open.includes(e.id)) w.open.push(e.id)
    return { value: { isPlaced: true } }
  })
  on('ui.close', ($: unknown, e: { id: string }) => {
    w.open = w.open.filter(id => id !== e.id)
    return { value: undefined }
  })
  on('ui.panes', () => ({
    value: w.open.map(id => ({ id, title: id, isShown: true, isFocused: false, isPlaced: true })),
  }))
  on('ui.toast', () => ({ value: undefined }))
  on('command.register', ($: unknown, e: { name: string }) => {
    w.registered.push(e)
    return { value: { command: e.name } }
  })
  on('session.start', () => ({ cwd: '/work' }))
  on('session.end', ($: unknown, e: { sessionId: string }) => ({ sessionId: e.sessionId }))
  on('session.measure', ($: unknown, e: { changed: string[] }) => ({ changed: e.changed }))
  on('ui.render', { component: 'AbovePrompt' }, () => h('Text', {}, 'other plugin row'))
  return w
}

const run = ($: any, args: string) => $.command.run({ command: 'context-budget', args })
const live = ($: any) => run($, 'live')
const measure = ($: any, changed: string[] = ['context']) =>
  $.session.measure({ context: { window: 1_000_000, tokens: 88_000, percent: 9 }, rateLimits: [], changed })

type Found = { type: string; text: string; props: Record<string, unknown>; children: unknown[] }

const mountPane = ($: any, surface: 'terminal' | 'desktop' = 'terminal') =>
  $.ui.mount({
    plugin: 'context-budget',
    surface,
    component: 'Pane',
    requestId: PANE,
    props: { title: 'Context', isFocused: false, bodyColumns: 60, placement: 'dock', scroll: { offset: 0, bodyRows: 20 }, view: {} },
  })

const mountBand = ($: any, { bodyColumns = 60, hasSurvey = false, surface = 'terminal' } = {}) =>
  $.ui.mount({
    plugin: 'context-budget',
    surface,
    component: 'AbovePrompt',
    props: { hasSurvey, isWorking: false, maxRows: 12, bodyColumns, scroll: { offset: 0, bodyRows: 12 }, view: {} },
  })

const texts = async (ui: any): Promise<string[]> => {
  const found: Found[] = await ui.findAll({ type: 'Text' })
  await ui.unmount()
  return found.map(t => t.text)
}

// The bar's segments: the Texts drawn of block characters alone, in order.
const segments = (found: Found[]) => found.filter(t => /^[█░]+$/.test(t.text))

for (const surface of ['terminal', 'desktop'] as const) {
  test(`pane: /context-budget live opens a pane headed with used, window, threshold and percent (${surface})`, async ($, on) => {
    const w = world(on)
    await live($)
    expect(w.open).toEqual([PANE])
    expect(await texts(await mountPane($, surface))).toContain(HEADER)
  })
}

test('pane: the legend lists every category with tokens and percent, each swatch in its row theme key', async ($, on) => {
  world(on)
  await live($)
  const ui = await mountPane($)
  const found: Found[] = await ui.findAll({ type: 'Text' })
  await ui.unmount()
  const shown = found.map(t => t.text)
  expect(shown).toContain('System prompt 10k 1%')
  expect(shown).toContain('Messages 80k 8%')
  expect(shown).toContain('Autocompact buffer 45k 5%')
  expect(shown).toContain('Free space 865k 87%')
  expect(shown).toContain('MCP tools 5k deferred')
  const swatches = found.filter(t => t.text === '■ ').map(t => t.props.color)
  expect(swatches).toEqual(['promptBorder', 'permission', 'warning', 'inactive', 'subtle'])
})

test('pane: the bar leaves out the deferred row, fills the body width and dims the free space', async ($, on) => {
  world(on)
  await live($)
  const ui = await mountPane($)
  const bar = segments(await ui.findAll({ type: 'Text' }))
  await ui.unmount()
  expect(bar.map(s => s.props.color)).toEqual(['promptBorder', 'permission', 'warning', 'inactive'])
  expect(bar.map(s => s.text).join('')).toHaveLength(60)
  expect(bar[3]?.props.dimColor).toBe(true)
  expect(bar[0]?.props.dimColor).not.toBe(true)
})

test('pane: no "compacts at" clause when auto-compaction has no threshold', async ($, on) => {
  world(on, 'no-threshold')
  await live($)
  const shown = await texts(await mountPane($))
  expect(shown).toContain('◆ context 90k of 1M 9%')
  expect(shown.join('\n')).not.toContain('compacts at')
})

test('pane: before any measurement the pane says it is waiting for the next response', async ($, on) => {
  world(on)
  expect(await texts(await mountPane($))).toContain('waiting for next response')
})

test('pane: usage with no breakdown shows a one-line error under the window figures', async ($, on) => {
  world(on, 'no-breakdown')
  await live($)
  const shown = await texts(await mountPane($))
  expect(shown).toContain('◆ context 88k of 1M 9%')
  expect(shown.filter(t => t.startsWith('usage unavailable:'))).toHaveLength(1)
})

test('pane: a rejected usage call shows a one-line error', async ($, on) => {
  world(on, 'rejected')
  await live($)
  const shown = await texts(await mountPane($))
  expect(shown.filter(t => t.startsWith('usage unavailable:'))).toHaveLength(1)
  expect(shown.join('\n')).not.toContain('waiting for next response')
})

test('pane: a second /context-budget live closes the open pane', async ($, on) => {
  const w = world(on)
  await live($)
  await live($)
  expect(w.open).toEqual([])
})

test('pane: after the person closes the pane, /context-budget live opens it again', async ($, on) => {
  const w = world(on)
  await live($)
  // The person's close (ui.close, origin person) is the engine's: its pane list drops the pane.
  w.open = []
  await live($)
  expect(w.open).toEqual([PANE])
})

test('pane: a measurement refreshes only while the pane is open and only when the context moved', async ($, on) => {
  const w = world(on)
  await measure($)
  expect(w.usageCalls).toBe(0)
  await live($)
  const opened = w.usageCalls
  await measure($, ['cost'])
  expect(w.usageCalls).toBe(opened)
  await measure($)
  expect(w.usageCalls).toBe(opened + 1)
})

for (const surface of ['terminal', 'desktop'] as const) {
  test(`band: a bordered band of header, bar and legend, five rows, above other plugins' rows (${surface})`, async ($, on) => {
    world(on)
    await run($, 'live band')
    await measure($)
    const ui = await mountBand($, { surface })
    const boxes: Found[] = await ui.findAll({ type: 'Box' })
    const found: Found[] = await ui.findAll({ type: 'Text' })
    await ui.unmount()
    const framed = boxes.filter(b => b.props.borderStyle !== undefined)
    expect(framed).toHaveLength(1)
    // Border top and bottom plus three rows inside: five rows.
    expect(framed[0]?.children).toHaveLength(3)
    const shown = found.map(t => t.text)
    expect(shown).toContain(HEADER)
    expect(shown).toContain('other plugin row')
    const bar = segments(found)
    expect(bar.map(s => s.props.color)).toEqual(['promptBorder', 'permission', 'warning', 'inactive'])
    // 60 columns less the two border cells.
    expect(bar.map(s => s.text).join('')).toHaveLength(58)
    const legend = shown.find(t => t.startsWith('System prompt'))
    expect(legend).toBe('System prompt 10k 1%  Messages 80k 8%  Autocompact buffer 45k 5%  Free space 865k 87%')
  })
}

test('band: a narrow band shrinks the bar to the body and truncates header and legend', async ($, on) => {
  world(on)
  await run($, 'live band')
  await measure($)
  const ui = await mountBand($, { bodyColumns: 20 })
  const found: Found[] = await ui.findAll({ type: 'Text' })
  await ui.unmount()
  expect(segments(found).map(s => s.text).join('')).toHaveLength(18)
  const header = found.find(t => t.text === HEADER)
  const legend = found.find(t => t.text.startsWith('System prompt'))
  expect(header?.props.wrap).toBe('truncate')
  expect(legend?.props.wrap).toBe('truncate')
})

test('band: yields to a survey, leaving the other rows', async ($, on) => {
  world(on)
  await run($, 'live band')
  await measure($)
  const shown = await texts(await mountBand($, { hasSurvey: true }))
  expect(shown).toEqual(['other plugin row'])
})

test('band: draws nothing before any measurement', { options: { live_display: 'band' } }, async ($, on) => {
  world(on)
  expect(await texts(await mountBand($))).toEqual(['other plugin row'])
})

test('band: draws nothing when the usage call is rejected', async ($, on) => {
  world(on, 'rejected')
  await run($, 'live band')
  await measure($)
  expect(await texts(await mountBand($))).toEqual(['other plugin row'])
})

test('band: draws nothing when usage carries no breakdown', async ($, on) => {
  world(on, 'no-breakdown')
  await run($, 'live band')
  await measure($)
  expect(await texts(await mountBand($))).toEqual(['other plugin row'])
})

test('band: the live_display option band draws the band from the first measurement', { options: { live_display: 'band' } }, async ($, on) => {
  world(on)
  await measure($)
  expect(await texts(await mountBand($))).toContain(HEADER)
})

test('off: the live_display option off draws nothing and makes no usage call', { options: { live_display: 'off' } }, async ($, on) => {
  const w = world(on)
  await $.session.start({ cwd: '/work' } as any)
  await measure($)
  expect(w.usageCalls).toBe(0)
  expect(await texts(await mountBand($))).toEqual(['other plugin row'])
})

test('off: /context-budget live off closes the pane and stops refreshing', async ($, on) => {
  const w = world(on)
  await live($)
  await run($, 'live off')
  expect(w.open).toEqual([])
  const calls = w.usageCalls
  await measure($)
  expect(w.usageCalls).toBe(calls)
})

test('mode: a session choice survives the session.start a hot reload raises again', { options: { live_display: 'pane' } }, async ($, on) => {
  world(on)
  await $.session.start({ cwd: '/work' } as any)
  await run($, 'live band')
  await $.session.start({ cwd: '/work' } as any)
  await measure($)
  expect(await texts(await mountBand($))).toContain(HEADER)
})

test('command: session.start registers /context-budget to run mid-turn', async ($, on) => {
  const w = world(on)
  await $.session.start({ cwd: '/work' } as any)
  expect(w.registered).toEqual([expect.objectContaining({ name: 'context-budget', immediate: true })])
})

test('command: a /clear registers /context-budget again', async ($, on) => {
  const w = world(on)
  await $.session.end({ reason: 'clear', sessionId: 's1', resume: { id: 's1' } } as any)
  expect(w.registered).toEqual([expect.objectContaining({ name: 'context-budget' })])
})

test('command: a session that ends for another reason registers nothing', async ($, on) => {
  const w = world(on)
  await $.session.end({ reason: 'prompt_input_exit', sessionId: 's1', resume: { id: 's1' } } as any)
  expect(w.registered).toEqual([])
})
