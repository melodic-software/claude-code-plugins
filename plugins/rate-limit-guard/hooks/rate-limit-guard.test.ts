import { expect, mock, test } from 'claude-code/testing'

// Fixture times, computed by hand: 2026-10-03T18:00:00Z is 1791050400 s, 21:00Z is 1791061200 s,
// 2026-10-08T09:00:00Z is 1791450000 s.
const T0 = 1_791_050_400_000
const FIVE_RESET = '2026-10-03T21:00:00Z'
const SEVEN_RESET = '2026-10-08T09:00:00Z'
const HOME = '/home/u'
const TARGET = '/home/u/.claude/rate-limit-guard/rate-limits.json'
const STATE_FILE = '/home/u/.claude.json'
const SOURCE = '(a measurement from the last API response)'

type Limit = { kind: string; percentUsed: number; resetsAt?: string }
type World = {
  limits: Limit[]
  sid: string
  surfaces: string[]
  turns: number
  box: string
  shown: boolean
  files: Record<string, { text: string; mtimeMs: number }>
  runs: { argv: readonly string[]; stdin?: string }[]
  suggested: string[]
  below: string[]
}

const limits = (five?: number, seven = 7): Limit[] => [
  ...(five === undefined ? [] : [{ kind: 'five_hour', percentUsed: five, resetsAt: FIVE_RESET }]),
  { kind: 'seven_day', percentUsed: seven, resetsAt: SEVEN_RESET },
]

// The world beneath the plugin: usage, files, processes and the prompt box are inputs; process
// runs, suggestions and the context returned are what the tests read.
const world = (stub: any, init: Partial<World> = {}, env: Record<string, string> = { HOME }, omit: string[] = []) => {
  const on = (event: string, ...rest: unknown[]) => (omit.includes(event) ? undefined : stub(event, ...rest))
  const w: World = {
    limits: limits(20),
    sid: 'sess-1',
    surfaces: ['terminal'],
    turns: 0,
    box: '',
    shown: true,
    files: {},
    runs: [],
    suggested: [],
    below: [],
    ...init,
  }
  const clock = mock.clock(stub, { now: T0 })
  mock.env(stub, env)
  on('session.usage', () => ({ value: { startedAt: 0, context: { window: 200_000 }, rateLimits: w.limits } }))
  on('session.id', () => ({ value: w.sid }))
  on('session.surfaces', () => ({ value: w.surfaces }))
  on('session.model', () => ({ value: 'Opus 5.5' }))
  on('session.turns', () => ({ value: w.turns }))
  on('fs.read', ($: unknown, e: { path: string }) => {
    const file = w.files[e.path]
    if (file === undefined) throw new Error(`ENOENT: ${e.path}`)
    return { value: file.text }
  })
  on('fs.stat', ($: unknown, e: { path: string }) => {
    const file = w.files[e.path]
    if (file === undefined) throw new Error(`ENOENT: ${e.path}`)
    return { value: { kind: 'file', size: file.text.length, mtimeMs: file.mtimeMs, isLink: false } }
  })
  on('process.run', ($: unknown, e: { argv: readonly string[]; init?: { stdin?: string } }) => {
    w.runs.push({ argv: e.argv, stdin: e.init?.stdin })
    if (e.init?.stdin !== undefined) w.files[e.argv[2]] = { text: e.init.stdin, mtimeMs: clock.now() }
    return { value: { exitCode: 0, stdout: '', stderr: '' } }
  })
  on('ui.invalidate', () => ({ value: undefined }))
  on('ui.log', () => ({ value: undefined }))
  on('prompt.read', () => ({ value: { text: w.box, cursor: w.box.length } }))
  on('prompt.suggest', ($: unknown, e: { text: string }) => {
    if (w.shown && w.box === '') w.suggested.push(e.text)
    return { isShown: w.shown && w.box === '' }
  })
  on('tool.register', ($: unknown, e: { name: string }) => ({ value: { tool: `mcp__rate-limit-guard__${e.name}` } }))
  on('command.register', ($: unknown, e: { name: string }) => ({ value: { command: e.name } }))
  on('tool.call', () => ({ result: { stdout: 'ok' }, text: 'ok', context: w.below.length ? w.below : undefined }))
  on('prompt.submit', ($: unknown, e: { text: string; context?: readonly string[] }) => ({ text: e.text, context: e.context }))
  on('session.measure', ($: unknown, e: { changed: string[] }) => ({ changed: e.changed }))
  on('session.compact', ($: unknown, e: { messages: unknown[] }) => ({ messages: e.messages }))
  on('session.end', ($: unknown, e: { sessionId: string }) => ({ sessionId: e.sessionId }))
  on('session.start', () => ({ cwd: '/work' }))
  on('turn.start', ($: unknown, e: { turnId: string }) => ({ turnId: e.turnId }))
  on('turn.complete', () => ({ text: 'done' }))
  on('ui.render', () => ({ type: 'Text', props: {}, children: ['drawn beneath'] }))
  return { w, clock }
}

const bash = ($: any, agentId?: string) => $.tool.call({ tool: 'Bash', command: 'true', ...(agentId ? { agentId } : {}) })
const prompt = ($: any, kind = 'sdk', extra: object = {}) =>
  $.prompt.submit({ text: 'go', wait: false, origin: { kind }, ...extra })
const ownLines = (context: readonly string[] | undefined) => (context ?? []).filter(c => c.startsWith('rate-limit-guard:'))
const bodies = (w: World) => w.runs.map(r => JSON.parse(String(r.stdin)))
const resultText = (r: any) => String(r.result)

const BAND = {
  plugin: 'rate-limit-guard',
  component: 'AbovePrompt',
  viewport: { columns: 120, rows: 40 },
  props: { hasSurvey: false, isWorking: false, maxRows: 10, bodyColumns: 120, scroll: { offset: 0, bodyRows: 9 }, view: {} },
} as const

const MESSAGES = [{ role: 'user', text: 'hello', toolUses: [] }]
const STEP = { turnId: 't', index: 0, model: 'm', messageCount: 1 }
const STEP_ANSWER = { turnId: 't', index: 0, answer: 'ok', toolUses: [], stopReason: 'end_turn', usage: null }
const answerStep = (on: any, $: any) => {
  on('turn.step', async function* () {
    return STEP_ANSWER
  })
  return (async () => {
    for await (const chunk of $.turn.step(STEP)) void chunk
  })()
}
const NO_WRITES = { options: { rate_limit_guard_enabled: false } }

test('lines: one approach line at 85, one at the 90% edge, one at the reset, appended after the context beneath', NO_WRITES, async ($, on) => {
  const { w } = world(on, { limits: limits(84), below: ['below'] })
  const seen: (readonly string[] | undefined)[] = []
  for (const five of [84, 85, 89.9, 90, 91]) {
    w.limits = limits(five)
    seen.push((await bash($)).context)
  }
  w.limits = limits(undefined)
  seen.push((await bash($)).context)
  w.limits = limits(2)
  seen.push((await bash($)).context)

  expect(seen).toEqual([
    ['below'],
    ['below', `rate-limit-guard: the 5-hour window is approaching the 90% pause edge, resets at 2026-10-03 21:00 UTC ${SOURCE}`],
    ['below'],
    ['below', `rate-limit-guard: the 5-hour window is at the 90% pause edge, resets at 2026-10-03 21:00 UTC ${SOURCE}`],
    ['below'],
    ['below', `rate-limit-guard: the 5-hour window reset and is below the 90% pause edge ${SOURCE}`],
    ['below'],
  ])
})

for (const data of ['percent', 'window', 'reset', '', 'bogus']) {
  test(`lines: the verdict stays in every line with line data "${data}"`, { options: { rate_limit_guard_enabled: false, rate_limit_line_data: data } }, async ($, on) => {
    const { w } = world(on, { limits: limits(92) })
    const edge = ownLines((await bash($)).context)
    w.limits = limits(undefined)
    const reset = ownLines((await bash($)).context)
    expect(edge).toHaveLength(1)
    expect(reset).toHaveLength(1)
    expect(edge[0]).toContain('at the 90% pause edge')
    expect(reset[0]).toContain('reset and is below the 90% pause edge')
    expect(`${edge[0]} ${reset[0]}`).not.toContain('undefined')
  })
}

test('lines: the default line names each window, one line per window when both cross', NO_WRITES, async ($, on) => {
  const { w } = world(on)
  await bash($)
  w.limits = limits(20, 91)
  expect(ownLines((await bash($)).context)).toEqual([
    `rate-limit-guard: the 7-day window is at the 90% pause edge, resets at 2026-10-08 09:00 UTC ${SOURCE}`,
  ])
  w.limits = limits(95, 91)
  expect(ownLines((await bash($)).context)).toEqual([
    `rate-limit-guard: the 5-hour window is at the 90% pause edge, resets at 2026-10-03 21:00 UTC ${SOURCE}`,
  ])
})

test('lines: both windows crossing together get a named line each', NO_WRITES, async ($, on) => {
  const { w } = world(on)
  await bash($)
  w.limits = limits(92, 90)
  expect(ownLines((await bash($)).context)).toEqual([
    `rate-limit-guard: the 5-hour window is at the 90% pause edge, resets at 2026-10-03 21:00 UTC ${SOURCE}`,
    `rate-limit-guard: the 7-day window is at the 90% pause edge, resets at 2026-10-08 09:00 UTC ${SOURCE}`,
  ])
})

test('lines: a dip below the threshold or the approach mark sends nothing and re-arms nothing', NO_WRITES, async ($, on) => {
  const { w } = world(on, { limits: limits(80) })
  const lines: string[] = []
  for (const five of [80, 85, 84.9, 85, 90, 89.9, 90, 91]) {
    w.limits = limits(five)
    lines.push(...ownLines((await bash($)).context))
  }
  expect(lines).toEqual([
    `rate-limit-guard: the 5-hour window is approaching the 90% pause edge, resets at 2026-10-03 21:00 UTC ${SOURCE}`,
    `rate-limit-guard: the 5-hour window is at the 90% pause edge, resets at 2026-10-03 21:00 UTC ${SOURCE}`,
  ])
})

test('lines: main-thread calls dispatched together after a crossing carry one line between them', NO_WRITES, async ($, on) => {
  const { w } = world(on)
  await bash($)
  w.limits = limits(93)
  const results = await Promise.all([bash($), bash($), bash($)])
  expect(results.flatMap(r => ownLines(r.context))).toHaveLength(1)
})

test('lines: a reading only session.measure carries reaches Claude at the next carrier', NO_WRITES, async ($, on) => {
  world(on)
  await bash($)
  await $.session.measure({ context: { window: 200_000 }, rateLimits: limits(90), changed: ['rateLimits'] })
  expect(ownLines((await prompt($)).context)).toEqual([
    `rate-limit-guard: the 5-hour window is at the 90% pause edge, resets at 2026-10-03 21:00 UTC ${SOURCE}`,
  ])
})

test('lines: a subagent tool call carries no line, and the next main-thread call does', NO_WRITES, async ($, on) => {
  const { w } = world(on)
  await bash($)
  w.limits = limits(95)
  expect(ownLines((await bash($, 'agent-1')).context)).toEqual([])
  expect(ownLines((await bash($)).context)).toHaveLength(1)
})

test('lines: a window whose reset time has passed counts as reset', NO_WRITES, async ($, on) => {
  const { w, clock } = world(on, { limits: limits(92) })
  expect(ownLines((await bash($)).context)[0]).toContain('is at the 90% pause edge')
  await clock.set(Date.parse(FIVE_RESET) + 1000)
  expect(ownLines((await bash($)).context)).toEqual([`rate-limit-guard: the 5-hour window reset and is below the 90% pause edge ${SOURCE}`])
  expect(w.runs).toEqual([])
})

test('lines: an ordinary call or prompt with nothing crossed carries no line', NO_WRITES, async ($, on) => {
  world(on)
  for (let i = 0; i < 5; i += 1) {
    expect(ownLines((await bash($)).context)).toEqual([])
    expect(ownLines((await prompt($)).context)).toEqual([])
  }
})

test('lines: a crossing seen at session.measure reaches Claude at the next prompt', NO_WRITES, async ($, on) => {
  const { w } = world(on)
  w.limits = limits(90)
  await $.session.measure({ context: { window: 200_000 }, rateLimits: w.limits, changed: ['rateLimits'] })
  expect(ownLines((await prompt($)).context)).toEqual([
    `rate-limit-guard: the 5-hour window is at the 90% pause edge, resets at 2026-10-03 21:00 UTC ${SOURCE}`,
  ])
})

test('lines: restated after a compaction, not after a precompute one', NO_WRITES, async ($, on) => {
  world(on)
  await bash($)
  await $.session.compact({ trigger: 'precompute', messages: MESSAGES } as any)
  expect(ownLines((await prompt($)).context)).toEqual([])
  await $.session.compact({ trigger: 'manual', messages: MESSAGES } as any)
  expect(ownLines((await prompt($)).context)).toEqual([
    `rate-limit-guard: the 5-hour window is below the 90% pause edge, resets at 2026-10-03 21:00 UTC ${SOURCE}`,
    `rate-limit-guard: the 7-day window is below the 90% pause edge, resets at 2026-10-08 09:00 UTC ${SOURCE}`,
  ])
  expect(ownLines((await prompt($)).context)).toEqual([])
})

test('lines: restated once after a resume', NO_WRITES, async ($, on) => {
  const { w } = world(on, { limits: limits(91) })
  await bash($)
  await $.session.end({ reason: 'resume', sessionId: 'sess-1', resume: { id: 'sess-1' } } as any)
  w.sid = 'sess-2'
  expect(ownLines((await prompt($)).context)).toEqual([
    `rate-limit-guard: the 5-hour window is at the 90% pause edge, resets at 2026-10-03 21:00 UTC ${SOURCE}`,
    `rate-limit-guard: the 7-day window is below the 90% pause edge, resets at 2026-10-08 09:00 UTC ${SOURCE}`,
  ])
  expect(ownLines((await prompt($)).context)).toEqual([])
})

// session.start with earlier turns is a fresh load in a running session: a reload, a worker respawn,
// an enable, or a --resume launch, which session.start cannot tell apart.
test('lines: a load with earlier turns and quiet windows sends nothing', NO_WRITES, async ($, on) => {
  world(on, { turns: 3 })
  await $.session.start({ surface: 'terminal', isInteractive: true, cwd: '/work' })
  expect(ownLines((await prompt($)).context)).toEqual([])
  expect(ownLines((await bash($)).context)).toEqual([])
})

test('lines: a load with earlier turns and a window at the approach mark sends nothing', NO_WRITES, async ($, on) => {
  world(on, { turns: 3, limits: limits(87) })
  await $.session.start({ surface: 'terminal', isInteractive: true, cwd: '/work' })
  expect(ownLines((await prompt($)).context)).toEqual([])
})

test('lines: a load with earlier turns restates a window at the edge once', NO_WRITES, async ($, on) => {
  world(on, { turns: 3, limits: limits(92) })
  await $.session.start({ surface: 'terminal', isInteractive: true, cwd: '/work' })
  expect(ownLines((await prompt($)).context)).toEqual([
    `rate-limit-guard: the 5-hour window is at the 90% pause edge, resets at 2026-10-03 21:00 UTC ${SOURCE}`,
  ])
  expect(ownLines((await prompt($)).context)).toEqual([])
})

test('lines: a window that leaves the reading at the approach mark gets no reset line', NO_WRITES, async ($, on) => {
  const { w } = world(on, { limits: limits(87) })
  expect(ownLines((await bash($)).context)[0]).toContain('approaching')
  w.limits = limits(undefined)
  expect(ownLines((await bash($)).context)).toEqual([])
})

for (const data of ['', 'bogus']) {
  test(`line data: the fallback for "${data}" names the window`, { options: { rate_limit_guard_enabled: false, rate_limit_line_data: data } }, async ($, on) => {
    world(on, { limits: limits(92) })
    expect(ownLines((await bash($)).context)).toEqual([
      `rate-limit-guard: the 5-hour window is at the 90% pause edge, resets at 2026-10-03 21:00 UTC ${SOURCE}`,
    ])
  })
}

test('lines: /clear, then the first prompt: nothing when below the threshold', NO_WRITES, async ($, on) => {
  const { w } = world(on)
  await bash($)
  await $.session.end({ reason: 'clear', sessionId: 'sess-1', resume: { id: 'sess-1' } } as any)
  w.sid = 'sess-2'
  expect(ownLines((await prompt($, 'composer')).context)).toEqual([])
})

test('lines: /clear, then the first prompt: the verdict when at the threshold', NO_WRITES, async ($, on) => {
  const { w } = world(on, { limits: limits(93) })
  await bash($)
  await $.session.end({ reason: 'clear', sessionId: 'sess-1', resume: { id: 'sess-1' } } as any)
  w.sid = 'sess-2'
  expect(ownLines((await prompt($, 'composer')).context)).toEqual([
    `rate-limit-guard: the 5-hour window is at the 90% pause edge, resets at 2026-10-03 21:00 UTC ${SOURCE}`,
  ])
})

test('line data: window and percent are carried when configured, never the email or session name', { options: { rate_limit_guard_enabled: false, rate_limit_line_data: 'verdict, percent, window' } }, async ($, on) => {
  const { w } = world(on, {
    files: { [STATE_FILE]: { text: JSON.stringify({ oauthAccount: { emailAddress: 'me@example.com' } }), mtimeMs: 0 } },
  })
  await bash($)
  w.limits = limits(90.5)
  const line = ownLines((await bash($)).context)
  expect(line).toEqual([`rate-limit-guard: the 5-hour window is at the 90% pause edge (90.5% used) ${SOURCE}`])
  expect(line[0]).not.toContain('@')
  expect(line[0]).not.toContain('sess-1')
})

test('line data: a lowered threshold and approach mark move the lines', { options: { rate_limit_guard_enabled: false, rate_limit_line_threshold: 70, rate_limit_approach_pct: 60 } }, async ($, on) => {
  const { w } = world(on, { limits: limits(50) })
  await bash($)
  w.limits = limits(60)
  expect(ownLines((await bash($)).context)[0]).toContain('is approaching the 70% line threshold')
  w.limits = limits(70)
  expect(ownLines((await bash($)).context)[0]).toContain('is at the 70% line threshold')
})

test('origin: a notification delivered into a running turn does not relabel it', async ($, on) => {
  const { w } = world(on)
  await prompt($, 'composer')
  await prompt($, 'task-notification', { turnId: 'turn-1' })
  w.limits = limits(30)
  await bash($)
  expect(w.runs).toHaveLength(1)
})

test('origin: a peer message delivered into an operator-mode typed turn keeps the line held', { options: { rate_limit_guard_enabled: false, rate_limit_report_mode: 'operator' } }, async ($, on) => {
  const { w } = world(on)
  await prompt($, 'composer')
  await prompt($, 'peer', { turnId: 'turn-1' })
  w.limits = limits(92)
  expect(ownLines((await bash($)).context)).toEqual([])
})

test('operator mode: a typed turn holds the line and offers it at turn end with an empty box, with a band notice', { options: { rate_limit_guard_enabled: false, rate_limit_report_mode: 'operator' } }, async ($, on) => {
  const { w } = world(on)
  await prompt($, 'composer')
  w.limits = limits(91)
  expect(ownLines((await bash($)).context)).toEqual([])
  await $.turn.complete({ text: 'done', reason: 'answer' } as any)
  const offered = `FYI, rate-limit-guard: the 5-hour window is at the 90% pause edge, resets at 2026-10-03 21:00 UTC ${SOURCE}`
  expect(w.suggested).toEqual([offered])
  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ ...BAND, surface })
    expect((await ui.find({ type: 'Text', text: /notice/ }))?.text).toBe(`rate-limit-guard notice: ${offered}`)
    await ui.unmount()
  }
  expect(ownLines((await prompt($, 'composer')).context)).toEqual([])
})

test('operator mode: with text in the box only the notice shows, and the offer comes back once the box empties', { options: { rate_limit_guard_enabled: false, rate_limit_report_mode: 'operator' } }, async ($, on) => {
  const { w, clock } = world(on, { box: 'half typed' })
  await prompt($, 'composer')
  w.limits = limits(91)
  await bash($)
  await $.turn.complete({ text: 'done', reason: 'answer' } as any)
  expect(w.suggested).toEqual([])
  w.box = ''
  await clock.advance(5_000)
  expect(w.suggested).toHaveLength(1)
  await clock.advance(20_000)
  expect(w.suggested).toHaveLength(1)
})

test('operator mode: a Remote Control bridge turn counts as a person', { options: { rate_limit_guard_enabled: false, rate_limit_report_mode: 'operator' } }, async ($, on) => {
  const { w } = world(on)
  await prompt($, 'bridge')
  w.limits = limits(91)
  expect(ownLines((await bash($)).context)).toEqual([])
  await $.turn.complete({ text: 'done', reason: 'answer' } as any)
  expect(w.suggested).toHaveLength(1)
})

test('operator mode: SDK, loop and notification turns get the automatic line', { options: { rate_limit_guard_enabled: false, rate_limit_report_mode: 'operator' } }, async ($, on) => {
  const { w } = world(on)
  const steps = [
    ['sdk', limits(91)],
    ['scheduled-trigger', limits(91, 91)],
    ['task-notification', limits(undefined, 91)],
  ] as const
  for (const [kind, next] of steps) {
    await prompt($, kind)
    w.limits = [...next]
    expect(ownLines((await bash($)).context)).toHaveLength(1)
  }
})

test('operator mode: a typed turn with no drawing surface gets the automatic line', { options: { rate_limit_guard_enabled: false, rate_limit_report_mode: 'operator' } }, async ($, on) => {
  const { w } = world(on, { surfaces: [] })
  await prompt($, 'composer')
  w.limits = limits(91)
  expect(ownLines((await bash($)).context)).toHaveLength(1)
})

test('operator mode: a suggestion that cannot show goes to Claude at the next prompt', { options: { rate_limit_guard_enabled: false, rate_limit_report_mode: 'operator' } }, async ($, on) => {
  const { w } = world(on, { shown: false })
  await prompt($, 'composer')
  w.limits = limits(91)
  await bash($)
  await $.turn.complete({ text: 'done', reason: 'answer' } as any)
  expect(ownLines((await prompt($, 'composer')).context)[0]).toContain('is at the 90% pause edge')
})

test('band: dashes before a reading, figures after, kept above what is drawn beneath', NO_WRITES, async ($, on) => {
  const { w } = world(on, { limits: [] })
  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ ...BAND, surface })
    expect((await ui.find({ type: 'Text', text: / 5h / }))?.text).toBe('[Opus 5.5] 5h - | 7d -')
    await ui.unmount()
  }
  w.limits = limits(23.5)
  await bash($)
  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ ...BAND, surface })
    expect((await ui.find({ type: 'Text', text: / 5h / }))?.text).toBe('[Opus 5.5] 5h 23.5% | 7d 7%')
    expect(await ui.find({ type: 'Text', text: 'drawn beneath' })).toBeDefined()
    await ui.unmount()
  }
})

test('band: the model label falls back to Claude when the model cannot be read', NO_WRITES, async ($, on) => {
  world(on, {}, { HOME }, ['session.model'])
  on('session.model', () => {
    throw new Error('no model')
  })
  await bash($)
  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect((await ui.find({ type: 'Text', text: / 5h / }))?.text).toBe('[Claude] 5h 20% | 7d 7%')
  await ui.unmount()
})

test('band: the option hides it and the band command shows and hides it', { options: { rate_limit_guard_enabled: false, rate_limit_guard_band: false } }, async ($, on) => {
  world(on)
  const row = async () => {
    const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
    const found = await ui.find({ type: 'Text', text: / 5h / })
    await ui.unmount()
    return found
  }
  expect(await row()).toBeUndefined()
  expect((await $.command.run({ command: 'band', args: 'show' } as any)).text).toBe('rate-limit-guard: band row shown for this session')
  expect(await row()).toBeDefined()
  await $.command.run({ command: 'band', args: '' } as any)
  expect(await row()).toBeUndefined()
})

test('session.start registers the status tool and the band command', NO_WRITES, async ($, on) => {
  const registered: string[] = []
  world(on, {}, { HOME }, ['tool.register', 'command.register'])
  on('tool.register', ($: unknown, e: { name: string }) => (registered.push(e.name), { value: { tool: e.name } }))
  on('command.register', ($: unknown, e: { name: string }) => (registered.push(`/${e.name}`), { value: { command: e.name } }))
  await $.session.start({ surface: 'terminal', isInteractive: true, cwd: '/work' })
  expect(registered.sort()).toEqual(['/band', 'status'])
})

test('pull tool: latest figures, verdicts and the spend limit, with no line attached', NO_WRITES, async ($, on) => {
  world(on, { limits: [...limits(91), { kind: 'spend_limit', percentUsed: 104.5 }] })
  const answer = await $.tool.call({ tool: 'mcp__rate-limit-guard__status' } as any)
  expect(answer.context).toBeUndefined()
  expect(JSON.parse(resultText(answer))).toEqual({
    source: 'the last API response',
    windows: {
      five_hour: { used_percentage: 91, resets_at: FIVE_RESET, verdict: 'edge' },
      seven_day: { used_percentage: 7, resets_at: SEVEN_RESET, verdict: 'quiet' },
    },
    verdict: 'edge',
    line_threshold: 90,
    approach_pct: 85,
    lanes_pause_edge: 90,
    spend_limit: { used_percentage: 104.5, resets_at: null },
  })
})

test('snapshot: body on stdin and argv, no spend limit, no session name, no account without a response time', async ($, on) => {
  const { w } = world(on, { limits: [...limits(23.5), { kind: 'spend_limit', percentUsed: 40 }] })
  await bash($)
  expect(w.runs.map(r => r.argv)).toEqual([
    ['node', expect.stringMatching(/\/lib\/write-snapshot\.mjs$/), TARGET, '--preserve-key', 'rate_limits'],
  ])
  expect(w.runs[0].stdin).toBe(
    JSON.stringify({
      captured_at: '2026-10-03T18:00:00Z',
      session_id: 'sess-1',
      rate_limits: {
        five_hour: { used_percentage: 23.5, resets_at: 1_791_061_200 },
        seven_day: { used_percentage: 7, resets_at: 1_791_450_000 },
      },
    }),
  )
})

test('snapshot: a session with no windows writes the windowless body', async ($, on) => {
  const { w } = world(on, { limits: [] })
  await bash($)
  expect(bodies(w)).toEqual([{ captured_at: '2026-10-03T18:00:00Z', session_id: 'sess-1' }])
})

test('snapshot: falls back to USERPROFILE when HOME is unset', async ($, on) => {
  const { w } = world(on, {}, { USERPROFILE: 'C:/Users/u' })
  await bash($)
  expect(w.runs[0].argv[2]).toBe('C:/Users/u/.claude/rate-limit-guard/rate-limits.json')
})

test('budget: no process on events that write nothing, one per write', async ($, on) => {
  const { w } = world(on)
  await bash($)
  expect(w.runs).toHaveLength(1)
  for (let i = 0; i < 50; i += 1) await bash($)
  expect(w.runs).toHaveLength(1)
  w.limits = limits(21)
  await bash($)
  expect(w.runs).toHaveLength(2)
})

test('floor: a sub-point move waits 300 s and then writes floor-bound; a whole-point move writes at once', async ($, on) => {
  const { w, clock } = world(on)
  await bash($)
  w.limits = limits(20.4)
  await clock.advance(299_000)
  await bash($)
  expect(w.runs).toHaveLength(1)
  await clock.advance(1_000)
  await bash($)
  expect(w.runs[1].argv.slice(-2)).toEqual(['--floor', '300'])
  w.limits = limits(21.1)
  await bash($)
  expect(w.runs).toHaveLength(3)
  expect(w.runs[2].argv).not.toContain('--floor')
})

test('snapshot: a window that leaves or whose reset time passes writes at once with no floor', async ($, on) => {
  const { w, clock } = world(on)
  await bash($)
  await clock.advance(10_000)
  w.limits = [{ kind: 'five_hour', percentUsed: 20, resetsAt: FIVE_RESET }]
  await bash($)
  await clock.set(Date.parse(FIVE_RESET) + 1_000)
  await bash($)
  expect(w.runs.map(r => r.argv.slice(3))).toEqual([
    ['--preserve-key', 'rate_limits'],
    ['--preserve-key', 'rate_limits'],
    ['--preserve-key', 'rate_limits'],
  ])
  expect(bodies(w)[2].rate_limits).toBeUndefined()
})

test('snapshot: never written from a turn a task notification started', async ($, on) => {
  const { w } = world(on)
  await prompt($, 'task-notification')
  await bash($)
  await $.session.measure({ context: { window: 200_000 }, rateLimits: limits(40), changed: ['rateLimits'] })
  expect(w.runs).toEqual([])
})

test('snapshot: session.end writes what the floor held back', async ($, on) => {
  const { w, clock } = world(on)
  await bash($)
  await clock.advance(301_000)
  await $.session.end({ reason: 'other', sessionId: 'sess-1', resume: { id: 'sess-1' } } as any)
  expect(w.runs).toHaveLength(2)
})

test('timer: rewrites every 60 s inside a turn once the floor passes, never outside one', async ($, on) => {
  const { w, clock } = world(on)
  await bash($)
  await clock.advance(600_000)
  expect(w.runs).toHaveLength(1)
  await $.turn.start({ text: 'go', turnId: 'turn-1' })
  await clock.advance(60_000)
  expect(w.runs).toHaveLength(2)
  await $.turn.complete({ text: 'done', reason: 'answer' } as any)
  await clock.advance(600_000)
  expect(w.runs).toHaveLength(2)
})

test('switch: rate_limit_guard_enabled false stops writes while lines continue', NO_WRITES, async ($, on) => {
  const { w } = world(on)
  await bash($)
  w.limits = limits(95)
  expect(ownLines((await bash($)).context)).toHaveLength(1)
  expect(w.runs).toEqual([])
})

test('switch: rate_limit_lines_enabled false stops lines while writes continue', { options: { rate_limit_lines_enabled: false } }, async ($, on) => {
  const { w } = world(on)
  await bash($)
  w.limits = limits(95)
  expect(ownLines((await bash($)).context)).toEqual([])
  expect(w.runs).toHaveLength(2)
})

test('account: attributed when the state file is older than the last response, omitted otherwise', async ($, on) => {
  const { w, clock } = world(on, {
    files: { [STATE_FILE]: { text: JSON.stringify({ oauthAccount: { emailAddress: 'me@example.com' } }), mtimeMs: T0 - 1 } },
  })
  await answerStep(on, $)
  await bash($)
  expect(bodies(w)[0].account).toEqual({ email: 'me@example.com' })

  w.files[STATE_FILE].mtimeMs = T0
  w.limits = limits(30)
  await bash($)
  expect(bodies(w)[1].account).toBeUndefined()

  w.files[STATE_FILE] = { text: JSON.stringify({ oauthAccount: { emailAddress: 'no-at-sign' } }), mtimeMs: 0 }
  await clock.advance(1_000)
  w.limits = limits(40)
  await bash($)
  expect(bodies(w)[2].account).toBeUndefined()
  expect(w.runs.every(r => !r.argv.join(' ').includes('@'))).toBe(true)
})

test('account: read from CLAUDE_CONFIG_DIR when it is set', async ($, on) => {
  const { w } = world(
    on,
    { files: { '/cfg/.claude.json': { text: JSON.stringify({ oauthAccount: { emailAddress: 'cfg@example.com' } }), mtimeMs: 0 } } },
    { HOME, CLAUDE_CONFIG_DIR: '/cfg' },
  )
  await answerStep(on, $)
  await bash($)
  expect(bodies(w)[0].account).toEqual({ email: 'cfg@example.com' })
})

test('fail open: a throw after the tool ran leaves its result and the context beneath, and the tool runs once', async ($, on) => {
  let runs = 0
  world(on, {}, { HOME }, ['session.usage', 'tool.call'])
  on('session.usage', () => {
    throw new Error('usage unavailable')
  })
  on('tool.call', () => {
    runs += 1
    return { result: { stdout: 'ran once' }, text: 'ran once', context: ['below'] }
  })
  const called = await bash($)
  expect(runs).toBe(1)
  expect(called.text).toBe('ran once')
  expect(called.context).toEqual(['below'])
})

test('fail open: a prompt passes through with its context when the hook throws before next', async ($, on) => {
  world(on, {}, { HOME }, ['session.usage'])
  on('session.usage', () => {
    throw new Error('usage unavailable')
  })
  const submitted = await prompt($, 'sdk', { context: ['theirs'] })
  expect(submitted.context).toEqual(['theirs'])
})

test('fail open: a failing write leaves the tool result and the line', async ($, on) => {
  const { w } = world(on, {}, { HOME }, ['process.run'])
  on('process.run', () => {
    throw new Error('no host processes')
  })
  await bash($)
  w.limits = limits(95)
  const called = await bash($)
  expect(called.text).toBe('ok')
  expect(ownLines(called.context)).toHaveLength(1)
})

test(
  'composition: a second plugin beneath adds its own line and both arrive',
  {
    options: { rate_limit_guard_enabled: false },
    plugins: [
      {
        name: 'other-mod',
        register(on) {
          on('tool.call', async ($, e, next) => {
            const result = await next(e)
            return { ...result, context: [...(result.context ?? []), 'other-mod line'] } as any
          })
        },
      },
    ],
  },
  async ($, on) => {
    const { w } = world(on)
    await bash($)
    w.limits = limits(95)
    const context = (await bash($)).context ?? []
    expect(context).toContain('other-mod line')
    expect(ownLines(context)).toHaveLength(1)
  },
)
