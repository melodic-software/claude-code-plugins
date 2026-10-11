import { expect, test } from 'claude-code/testing'

const PANE = 'context-budget-live'

// The engine beneath the plugin. Usage follows the published SessionContextBreakdown shape: a
// 1,000,000-token window with 90,000 in use, which the header writes as 90k of 1M.
const world = (on: any) => {
  const w = { open: [] as string[], opened: [] as unknown[], registered: [] as unknown[] }
  on('session.usage', () => ({
    value: {
      startedAt: 0,
      rateLimits: [],
      context: {
        window: 1_000_000,
        tokens: 88_000,
        percent: 9,
        breakdown: {
          categories: [
            { name: 'System prompt', tokens: 10_000, color: 'promptBorder', isDeferred: false, kind: 'used' },
            { name: 'Messages', tokens: 80_000, color: 'permission', isDeferred: false, kind: 'used' },
            { name: 'Free space', tokens: 910_000, color: 'inactive', isDeferred: false, kind: 'free' },
          ],
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
          isAutoCompactEnabled: false,
          apiUsage: null,
        },
      },
    },
  }))
  on('ui.open', ($: unknown, e: { id: string }) => {
    w.opened.push(e)
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
  return w
}

const live = ($: any) => $.command.run({ command: 'context-budget', args: 'live' })

const paneText = async ($: any, surface: 'terminal' | 'desktop') => {
  const ui = await $.ui.mount({
    plugin: 'context-budget',
    surface,
    component: 'Pane',
    requestId: PANE,
    props: { title: 'Context', isFocused: false, bodyColumns: 60, placement: 'dock', scroll: { offset: 0, bodyRows: 20 }, view: {} },
  })
  const texts = (await ui.findAll({ type: 'Text' })).map((t: { text: string }) => t.text).join('\n')
  await ui.unmount()
  return texts
}

for (const surface of ['terminal', 'desktop'] as const) {
  test(`live: /context-budget live opens a pane headed with the used and window figures (${surface})`, async ($, on) => {
    const w = world(on)
    await live($)
    expect(w.open).toEqual([PANE])
    const text = await paneText($, surface)
    expect(text).toContain('context')
    expect(text).toContain('90k of 1M')
  })
}

test('live: a second /context-budget live closes the open pane', async ($, on) => {
  const w = world(on)
  await live($)
  await live($)
  expect(w.open).toEqual([])
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
