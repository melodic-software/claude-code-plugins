import { expect, mock, test } from 'claude-code/testing'

// Fixture times, computed by hand: 2026-10-03T18:00:00Z is 1791050400 s, 21:00Z is 1791061200 s,
// 2026-10-08T09:00:00Z is 1791450000 s.
const T0 = 1_791_050_400_000
const FIVE_RESET = '2026-10-03T21:00:00Z'
const SEVEN_RESET = '2026-10-08T09:00:00Z'
const HOME = '/srv/u'
const TARGET = '/srv/u/.claude/rate-limit-guard/rate-limits.json'
const STATE_FILE = '/srv/u/.claude.json'

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
  logs: { text: string; to: string }[]
  toasts: string[]
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
    logs: [],
    toasts: [],
    ...init,
  }
  const clock = mock.clock(stub, { now: T0 })
  mock.env(stub, env)
  on('session.usage', () => ({ value: { startedAt: 0, context: { window: 200_000 }, rateLimits: w.limits } }))
  on('session.id', () => ({ value: w.sid }))
  on('session.surfaces', () => ({ value: w.surfaces }))
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
  on('ui.log', ($: unknown, e: { text: string; to: string }) => (w.logs.push({ text: e.text, to: e.to }), { value: undefined }))
  on('ui.toast', ($: unknown, e: { text: string }) => (w.toasts.push(e.text), { value: undefined }))
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

test('lines: one approach line at 90, one at the 95% edge, one at the reset, appended after the context beneath', NO_WRITES, async ($, on) => {
  const { w } = world(on, { limits: limits(89), below: ['below'] })
  const seen: (readonly string[] | undefined)[] = []
  for (const five of [89, 90, 94.9, 95, 96]) {
    w.limits = limits(five)
    seen.push((await bash($)).context)
  }
  w.limits = limits(undefined)
  seen.push((await bash($)).context)
  w.limits = limits(2)
  seen.push((await bash($)).context)

  expect(seen).toEqual([
    ['below'],
    ['below', `rate-limit-guard: 5-hour window at or above 90% (90% used), resets at 2026-10-03 21:00 UTC.`],
    ['below'],
    ['below', `rate-limit-guard: 5-hour window at or above 95% (95% used), resets at 2026-10-03 21:00 UTC.`],
    ['below'],
    ['below', `rate-limit-guard: 5-hour window reset, now below 95%.`],
    ['below'],
  ])
})

for (const data of ['percent', 'window', 'reset', '', 'bogus']) {
  test(`lines: the verdict stays in every line with line data "${data}"`, { options: { rate_limit_guard_enabled: false, rate_limit_line_data: data } }, async ($, on) => {
    const { w } = world(on, { limits: limits(97) })
    const edge = ownLines((await bash($)).context)
    w.limits = limits(undefined)
    const reset = ownLines((await bash($)).context)
    expect(edge).toHaveLength(1)
    expect(reset).toHaveLength(1)
    expect(edge[0]).toContain('at or above 95%')
    expect(reset[0]).toContain('reset, now below 95%')
    expect(`${edge[0]} ${reset[0]}`).not.toContain('undefined')
  })
}

test('lines: the default line names each window, one line per window when both cross', NO_WRITES, async ($, on) => {
  const { w } = world(on)
  await bash($)
  w.limits = limits(20, 96)
  expect(ownLines((await bash($)).context)).toEqual([
    `rate-limit-guard: 7-day window at or above 95% (96% used), resets at 2026-10-08 09:00 UTC.`,
  ])
  w.limits = limits(100, 96)
  expect(ownLines((await bash($)).context)).toEqual([
    `rate-limit-guard: 5-hour window at or above 95% (100% used), resets at 2026-10-03 21:00 UTC.`,
  ])
})

test('lines: both windows crossing together get a named line each', NO_WRITES, async ($, on) => {
  const { w } = world(on)
  await bash($)
  w.limits = limits(97, 95)
  expect(ownLines((await bash($)).context)).toEqual([
    `rate-limit-guard: 5-hour window at or above 95% (97% used), resets at 2026-10-03 21:00 UTC.`,
    `rate-limit-guard: 7-day window at or above 95% (95% used), resets at 2026-10-08 09:00 UTC.`,
  ])
})

test('lines: a dip below the threshold or the approach mark sends nothing and re-arms nothing', NO_WRITES, async ($, on) => {
  const { w } = world(on, { limits: limits(85) })
  const lines: string[] = []
  for (const five of [85, 90, 89.9, 90, 95, 94.9, 95, 96]) {
    w.limits = limits(five)
    lines.push(...ownLines((await bash($)).context))
  }
  expect(lines).toEqual([
    `rate-limit-guard: 5-hour window at or above 90% (90% used), resets at 2026-10-03 21:00 UTC.`,
    `rate-limit-guard: 5-hour window at or above 95% (95% used), resets at 2026-10-03 21:00 UTC.`,
  ])
})

test('lines: main-thread calls dispatched together after a crossing carry one line between them', NO_WRITES, async ($, on) => {
  const { w } = world(on)
  await bash($)
  w.limits = limits(98)
  const results = await Promise.all([bash($), bash($), bash($)])
  expect(results.flatMap(r => ownLines(r.context))).toHaveLength(1)
})

test('lines: a reading only session.measure carries reaches Claude at the next carrier', NO_WRITES, async ($, on) => {
  world(on)
  await bash($)
  await $.session.measure({ context: { window: 200_000 }, rateLimits: limits(95), changed: ['rateLimits'] })
  expect(ownLines((await prompt($)).context)).toEqual([
    `rate-limit-guard: 5-hour window at or above 95% (95% used), resets at 2026-10-03 21:00 UTC.`,
  ])
})

test('lines: a crossing delivered after the live reading dips below the threshold states the crossing percent', NO_WRITES, async ($, on) => {
  const { w } = world(on)
  await bash($)
  w.limits = limits(97)
  await $.session.measure({ context: { window: 200_000 }, rateLimits: w.limits, changed: ['rateLimits'] })
  w.limits = limits(93)
  expect(ownLines((await prompt($)).context)).toEqual([
    `rate-limit-guard: 5-hour window at or above 95% (97% used), resets at 2026-10-03 21:00 UTC.`,
  ])
  await $.session.compact({ trigger: 'manual', messages: MESSAGES } as any)
  expect(ownLines((await prompt($)).context)).toEqual([
    `rate-limit-guard: 5-hour window at or above 95% (97% used), resets at 2026-10-03 21:00 UTC.`,
  ])
})

test('lines: a reset delivered after the live reading changes states the percent of the reading that reset it', NO_WRITES, async ($, on) => {
  const { w, clock } = world(on, { limits: limits(97) })
  await bash($)
  await clock.set(Date.parse(FIVE_RESET) + 1000)
  const newWindow = (percentUsed: number) => [{ kind: 'five_hour', percentUsed, resetsAt: '2026-10-04T02:00:00Z' }]
  w.limits = newWindow(12)
  await $.session.measure({ context: { window: 200_000 }, rateLimits: w.limits, changed: ['rateLimits'] })
  w.limits = newWindow(41)
  expect(ownLines((await prompt($)).context)).toEqual([`rate-limit-guard: 5-hour window reset, now below 95% (12% used).`])
})

test('lines: a subagent tool call carries no line, and the next main-thread call does', NO_WRITES, async ($, on) => {
  const { w } = world(on)
  await bash($)
  w.limits = limits(100)
  expect(ownLines((await bash($, 'agent-1')).context)).toEqual([])
  expect(ownLines((await bash($)).context)).toHaveLength(1)
})

test('lines: a window whose reset time has passed counts as reset', NO_WRITES, async ($, on) => {
  const { w, clock } = world(on, { limits: limits(97) })
  expect(ownLines((await bash($)).context)[0]).toContain('at or above 95%')
  await clock.set(Date.parse(FIVE_RESET) + 1000)
  expect(ownLines((await bash($)).context)).toEqual([`rate-limit-guard: 5-hour window reset, now below 95%.`])
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
  w.limits = limits(95)
  await $.session.measure({ context: { window: 200_000 }, rateLimits: w.limits, changed: ['rateLimits'] })
  expect(ownLines((await prompt($)).context)).toEqual([
    `rate-limit-guard: 5-hour window at or above 95% (95% used), resets at 2026-10-03 21:00 UTC.`,
  ])
})

test('lines: a compaction restates no quiet window', NO_WRITES, async ($, on) => {
  world(on)
  await bash($)
  await $.session.compact({ trigger: 'manual', messages: MESSAGES } as any)
  expect(ownLines((await prompt($)).context)).toEqual([])
  expect(ownLines((await bash($)).context)).toEqual([])
})

test('lines: a window past quiet is restated once after a compaction, not after a precompute one', NO_WRITES, async ($, on) => {
  const { w } = world(on)
  await bash($)
  w.limits = limits(96)
  expect(ownLines((await bash($)).context)).toEqual([EDGE_5H])
  await $.session.compact({ trigger: 'precompute', messages: MESSAGES } as any)
  expect(ownLines((await prompt($)).context)).toEqual([])
  await $.session.compact({ trigger: 'manual', messages: MESSAGES } as any)
  expect(ownLines((await prompt($)).context)).toEqual([EDGE_5H])
  expect(ownLines((await prompt($)).context)).toEqual([])
})

test('lines: restated once after a resume, with no quiet window', NO_WRITES, async ($, on) => {
  const { w } = world(on, { limits: limits(96) })
  await bash($)
  await $.session.end({ reason: 'resume', sessionId: 'sess-1', resume: { id: 'sess-1' } } as any)
  w.sid = 'sess-2'
  expect(ownLines((await prompt($)).context)).toEqual([EDGE_5H])
  expect(ownLines((await prompt($)).context)).toEqual([])
})

test('lines: a resume with only quiet windows restates nothing', NO_WRITES, async ($, on) => {
  const { w } = world(on)
  await bash($)
  await $.session.end({ reason: 'resume', sessionId: 'sess-1', resume: { id: 'sess-1' } } as any)
  w.sid = 'sess-2'
  expect(ownLines((await prompt($)).context)).toEqual([])
  expect(ownLines((await bash($)).context)).toEqual([])
})

test('debug mirror: each line sent to Claude is written to the debug log as sent', NO_WRITES, async ($, on) => {
  const { w } = world(on)
  await bash($)
  w.limits = limits(96)
  const atTool = ownLines((await bash($)).context)
  w.limits = limits(96, 97)
  const atPrompt = ownLines((await prompt($)).context)
  expect([...atTool, ...atPrompt]).toEqual([EDGE_5H, EDGE_7D_97])
  expect(w.logs.filter(l => l.to === 'debug' && l.text.includes(' window ')).map(l => l.text)).toEqual([...atTool, ...atPrompt])
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
  world(on, { turns: 3, limits: limits(92) })
  await $.session.start({ surface: 'terminal', isInteractive: true, cwd: '/work' })
  expect(ownLines((await prompt($)).context)).toEqual([])
})

test('lines: a load with earlier turns restates a window at the edge once', NO_WRITES, async ($, on) => {
  world(on, { turns: 3, limits: limits(97) })
  await $.session.start({ surface: 'terminal', isInteractive: true, cwd: '/work' })
  expect(ownLines((await prompt($)).context)).toEqual([
    EDGE_5H_97,
  ])
  expect(ownLines((await prompt($)).context)).toEqual([])
})

test('lines: a window that leaves the reading at the approach mark gets no reset line', NO_WRITES, async ($, on) => {
  const { w } = world(on, { limits: limits(92) })
  expect(ownLines((await bash($)).context)[0]).toContain('at or above 90%')
  w.limits = limits(undefined)
  expect(ownLines((await bash($)).context)).toEqual([])
})

for (const data of ['', 'bogus']) {
  test(`line data: the fallback for "${data}" names the window`, { options: { rate_limit_guard_enabled: false, rate_limit_line_data: data } }, async ($, on) => {
    world(on, { limits: limits(97) })
    expect(ownLines((await bash($)).context)).toEqual([EDGE_5H_97])
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
  const { w } = world(on, { limits: limits(98) })
  await bash($)
  await $.session.end({ reason: 'clear', sessionId: 'sess-1', resume: { id: 'sess-1' } } as any)
  w.sid = 'sess-2'
  expect(ownLines((await prompt($, 'composer')).context)).toEqual([
    `rate-limit-guard: 5-hour window at or above 95% (98% used), resets at 2026-10-03 21:00 UTC.`,
  ])
})

test('line data: window and percent are carried when configured, never the email or session name', { options: { rate_limit_guard_enabled: false, rate_limit_line_data: 'verdict, percent, window' } }, async ($, on) => {
  const { w } = world(on, {
    files: { [STATE_FILE]: { text: JSON.stringify({ oauthAccount: { emailAddress: 'me@example.com' } }), mtimeMs: 0 } },
  })
  await bash($)
  w.limits = limits(95.5)
  const line = ownLines((await bash($)).context)
  expect(line).toEqual([`rate-limit-guard: 5-hour window at or above 95% (95.5% used).`])
  expect(line[0]).not.toContain('@')
  expect(line[0]).not.toContain('sess-1')
})

test('line data: a lowered threshold and approach mark move the lines', { options: { rate_limit_guard_enabled: false, rate_limit_line_threshold: 70, rate_limit_approach_pct: 60 } }, async ($, on) => {
  const { w } = world(on, { limits: limits(50) })
  await bash($)
  w.limits = limits(60)
  expect(ownLines((await bash($)).context)[0]).toContain('at or above 60%')
  w.limits = limits(70)
  expect(ownLines((await bash($)).context)[0]).toContain('at or above 70%')
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
  w.limits = limits(97)
  expect(ownLines((await bash($)).context)).toEqual([])
})

// A notice row: the operator offer (FYI, ...) or a window change shown off the terminal.
const NOTICE = /^(FYI, )?rate-limit-guard: /

test('operator mode: a typed turn holds the line and offers it at turn end with an empty box, with one notice row on every surface and no toast', { options: { rate_limit_guard_enabled: false, rate_limit_report_mode: 'operator' } }, async ($, on) => {
  const { w } = world(on)
  await prompt($, 'composer')
  w.limits = limits(96)
  expect(ownLines((await bash($)).context)).toEqual([])
  await $.turn.complete({ text: 'done', reason: 'answer' } as any)
  const offered = `FYI, ${EDGE_5H}`
  expect(w.suggested).toEqual([offered])
  for (const surface of ['terminal', 'desktop', 'vscode'] as const) {
    const ui = await $.ui.mount({ ...BAND, surface })
    const rows = await ui.findAll({ type: 'Text', text: NOTICE })
    expect(rows.map((r: any) => r.text)).toEqual([offered])
    await ui.unmount()
  }
  expect(w.toasts).toEqual([])
  expect(ownLines((await prompt($, 'composer')).context)).toEqual([])
})

test('operator mode: with text in the box only the notice shows, and the offer comes back once the box empties', { options: { rate_limit_guard_enabled: false, rate_limit_report_mode: 'operator' } }, async ($, on) => {
  const { w, clock } = world(on, { box: 'half typed' })
  await prompt($, 'composer')
  w.limits = limits(96)
  await bash($)
  await $.turn.complete({ text: 'done', reason: 'answer' } as any)
  expect(w.suggested).toEqual([])
  expect(await noticeText($)).toBe(`FYI, ${EDGE_5H}`)
  w.box = ''
  await clock.advance(5_000)
  expect(w.suggested).toHaveLength(1)
  await clock.advance(20_000)
  expect(w.suggested).toHaveLength(1)
})

test('operator mode: a Remote Control bridge turn counts as a person', { options: { rate_limit_guard_enabled: false, rate_limit_report_mode: 'operator' } }, async ($, on) => {
  const { w } = world(on)
  await prompt($, 'bridge')
  w.limits = limits(96)
  expect(ownLines((await bash($)).context)).toEqual([])
  await $.turn.complete({ text: 'done', reason: 'answer' } as any)
  expect(w.suggested).toHaveLength(1)
})

test('operator mode: SDK, loop and notification turns get the automatic line', { options: { rate_limit_guard_enabled: false, rate_limit_report_mode: 'operator' } }, async ($, on) => {
  const { w } = world(on)
  const steps = [
    ['sdk', limits(96)],
    ['scheduled-trigger', limits(96, 96)],
    ['task-notification', limits(undefined, 96)],
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
  w.limits = limits(96)
  expect(ownLines((await bash($)).context)).toHaveLength(1)
})

test('operator mode: a suggestion that cannot show goes to Claude at the next prompt', { options: { rate_limit_guard_enabled: false, rate_limit_report_mode: 'operator' } }, async ($, on) => {
  const { w } = world(on, { shown: false })
  await prompt($, 'composer')
  w.limits = limits(96)
  await bash($)
  await $.turn.complete({ text: 'done', reason: 'answer' } as any)
  expect(ownLines((await prompt($, 'composer')).context)[0]).toContain('at or above 95%')
})

const OPERATOR = { options: { rate_limit_guard_enabled: false, rate_limit_report_mode: 'operator' } }
const EDGE_5H = `rate-limit-guard: 5-hour window at or above 95% (96% used), resets at 2026-10-03 21:00 UTC.`
const EDGE_5H_97 = `rate-limit-guard: 5-hour window at or above 95% (97% used), resets at 2026-10-03 21:00 UTC.`
const EDGE_7D_96 = `rate-limit-guard: 7-day window at or above 95% (96% used), resets at 2026-10-08 09:00 UTC.`
const EDGE_7D_97 = `rate-limit-guard: 7-day window at or above 95% (97% used), resets at 2026-10-08 09:00 UTC.`
const shownInTypedTurn = async ($: any, w: World, next = limits(96)) => {
  await prompt($, 'composer')
  w.limits = next
  await bash($)
  await $.turn.complete({ text: 'done', reason: 'answer' } as any)
  expect(w.suggested).toHaveLength(1)
}
const noticeText = async ($: any) => {
  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  const found = await ui.find({ type: 'Text', text: NOTICE })
  await ui.unmount()
  return found?.text
}

for (const kind of ['scheduled-trigger', 'task-notification', 'sdk']) {
  test(`operator mode: a shown suggestion not taken goes to Claude at the next ${kind} turn, once`, OPERATOR, async ($, on) => {
    const { w } = world(on)
    await shownInTypedTurn($, w)
    expect((await prompt($, kind, { context: ['theirs'] })).context).toEqual(['theirs', EDGE_5H])
    expect(await noticeText($)).toBeUndefined()
    expect(ownLines((await prompt($, kind)).context)).toEqual([])
  })
}

for (const kind of ['composer', 'bridge']) {
  test(`operator mode: a new ${kind} turn clears a shown suggestion unsent`, OPERATOR, async ($, on) => {
    const { w } = world(on)
    await shownInTypedTurn($, w)
    expect(ownLines((await prompt($, kind)).context)).toEqual([])
    expect(await noticeText($)).toBeUndefined()
    expect(ownLines((await prompt($, 'scheduled-trigger')).context)).toEqual([])
  })
}

test('operator mode: a prompt delivered into a running turn leaves a shown suggestion pending', OPERATOR, async ($, on) => {
  const { w } = world(on)
  await shownInTypedTurn($, w)
  expect(ownLines((await prompt($, 'task-notification', { turnId: 'turn-1' })).context)).toEqual([])
  expect(await noticeText($)).toBe(`FYI, ${EDGE_5H}`)
  expect(ownLines((await prompt($, 'sdk')).context)).toEqual([EDGE_5H])
})

test('operator mode: a hand-off and a restatement due at the same prompt send each window once', OPERATOR, async ($, on) => {
  const { w } = world(on)
  await shownInTypedTurn($, w, limits(96, 91))
  await $.session.end({ reason: 'clear', sessionId: 'sess-1', resume: { id: 'sess-1' } } as any)
  expect(ownLines((await prompt($, 'sdk')).context)).toEqual([
    EDGE_5H,
    `rate-limit-guard: 7-day window at or above 90% (91% used), resets at 2026-10-08 09:00 UTC.`,
  ])
})

test('automatic mode: a typed turn gets the line at once, offers nothing and hands nothing off', NO_WRITES, async ($, on) => {
  const { w } = world(on)
  await prompt($, 'composer')
  w.limits = limits(96)
  expect(ownLines((await bash($)).context)).toEqual([EDGE_5H])
  await $.turn.complete({ text: 'done', reason: 'answer' } as any)
  expect(w.suggested).toEqual([])
  expect(ownLines((await prompt($, 'sdk')).context)).toEqual([])
})

const BAND_ON = { options: { rate_limit_guard_enabled: false, rate_limit_guard_band: true } }
const BAND_ROW = /^5h /
// Every Text the AbovePrompt mount drew, in order.
const drawn = async ($: any, surface: 'terminal' | 'desktop' | 'vscode') => {
  const ui = await $.ui.mount({ ...BAND, surface })
  const texts = (await ui.findAll({ type: 'Text' })).map((t: any) => t.text)
  await ui.unmount()
  return texts
}
const command = ($: any, args?: string, name = 'rate-limit-guard') =>
  $.command.run({ command: name, ...(args === undefined ? {} : { args }) } as any)

test('band: off by default, so a terminal mount returns only what is drawn beneath', NO_WRITES, async ($, on) => {
  world(on)
  await bash($)
  expect(await drawn($, 'terminal')).toEqual(['drawn beneath'])
})

test('band: dashes before a reading, figures after, with no model id, kept above what is drawn beneath', BAND_ON, async ($, on) => {
  const { w } = world(on, { limits: [] })
  for (const surface of ['terminal', 'desktop'] as const) expect(await drawn($, surface)).toEqual(['5h - | 7d -', 'drawn beneath'])
  w.limits = limits(23.5)
  await bash($)
  for (const surface of ['terminal', 'desktop'] as const) expect(await drawn($, surface)).toEqual(['5h 23.5% | 7d 7%', 'drawn beneath'])
})

test('command: band on, band off and a bare band set and toggle the row for the session', NO_WRITES, async ($, on) => {
  world(on)
  await bash($)
  const row = async () => (await drawn($, 'terminal')).find(t => BAND_ROW.test(t))
  expect(await row()).toBeUndefined()
  expect((await command($, 'band on')).text).toBe('Band row on for this session')
  expect(await row()).toBe('5h 20% | 7d 7%')
  expect((await command($, 'band off')).text).toBe('Band row off for this session')
  expect(await row()).toBeUndefined()
  await command($, 'band')
  expect(await row()).toBeDefined()
  await command($, 'BAND')
  expect(await row()).toBeUndefined()
})

test('command: no argument returns the status and details', async ($, on) => {
  world(on, { limits: limits(92) })
  expect((await command($)).text).toBe(
    [
      'From the last API response:',
      '5-hour window: 92% used, at or above 90%, resets at 2026-10-03 21:00 UTC',
      '7-day window: 7% used, below 95%, resets at 2026-10-08 09:00 UTC',
      'Line threshold 95%, approach mark 90%.',
      'Band row off, window-change toast on. Set the row with /rate-limit-guard band [on|off].',
      `Snapshot: ${TARGET}`,
      'README: https://github.com/melodic-software/claude-code-plugins/blob/main/plugins/rate-limit-guard/README.md',
    ].join('\n'),
  )
})

test('command: the status says when a window has no reading and when snapshot writes are off', { options: { rate_limit_guard_enabled: false, rate_limit_guard_toast: false } }, async ($, on) => {
  world(on, { limits: limits(undefined) })
  const text = (await command($, '')).text
  expect(text).toContain('5-hour window: no reading\n')
  expect(text).toContain('window-change toast off')
  expect(text).toContain('Snapshot: off (rate_limit_guard_enabled is false)')
})

test('command: any other argument gets the usage line', NO_WRITES, async ($, on) => {
  world(on)
  for (const args of ['bands', 'band show', 'band on now', 'status']) {
    expect((await command($, args)).text).toBe('Usage: /rate-limit-guard [band [on|off]]')
  }
  expect((await drawn($, 'terminal')).some(t => BAND_ROW.test(t))).toBe(false)
})

for (const name of ['band', 'context-guard']) {
  test(`command: /${name} is not this guard's and reaches the hook beneath`, NO_WRITES, async ($, on) => {
    const seen: string[] = []
    world(on)
    on('command.run', ($: unknown, e: { command: string }) => (seen.push(e.command), { text: 'beneath' }))
    expect((await command($, 'on', name)).text).toBe('beneath')
    expect(seen).toEqual([name])
    expect((await drawn($, 'terminal')).some(t => BAND_ROW.test(t))).toBe(false)
  })
}

test('session.start registers the status tool and one command, named after the plugin', NO_WRITES, async ($, on) => {
  const registered: string[] = []
  world(on, {}, { HOME }, ['tool.register', 'command.register'])
  on('tool.register', ($: unknown, e: { name: string }) => (registered.push(e.name), { value: { tool: e.name } }))
  on('command.register', ($: unknown, e: { name: string; argumentHint?: string }) => (registered.push(`/${e.name} ${e.argumentHint}`), { value: { command: e.name } }))
  await $.session.start({ surface: 'terminal', isInteractive: true, cwd: '/work' })
  expect(registered.sort()).toEqual(['/rate-limit-guard [band [on|off]]', 'status'])
})

// The person's channel: a toast and one transcript line when a window rises from a known level or resets.
const TOAST_EDGE = '5h at the 95% pause edge · resets 21:00 UTC'
const LOG_EDGE = `rate-limit-guard: ${TOAST_EDGE} · more: /rate-limit-guard`
const crossingLogs = (w: World) => w.logs.filter(l => l.text.endsWith('· more: /rate-limit-guard'))

test('toast: approach, edge and reset each toast once, with one transcript line each', NO_WRITES, async ($, on) => {
  const { w } = world(on, { limits: limits(89) })
  for (const five of [89, 90, 91, 95, 96]) {
    w.limits = limits(five)
    await bash($)
  }
  w.limits = limits(undefined)
  await bash($)
  w.limits = limits(2)
  await bash($)
  expect(w.toasts).toEqual(['5h nearing the 95% pause edge · resets 21:00 UTC', TOAST_EDGE, '5h reset, below the 95% pause edge'])
  expect(crossingLogs(w)).toEqual(w.toasts.map(t => ({ text: `rate-limit-guard: ${t} · more: /rate-limit-guard`, to: 'transcript' })))
})

test('toast: the 7-day window names its reset date', NO_WRITES, async ($, on) => {
  const { w } = world(on)
  await bash($)
  w.limits = limits(20, 97)
  await bash($)
  expect(w.toasts).toEqual(['7d at the 95% pause edge · resets 2026-10-08 09:00 UTC'])
})

test('toast: a rise seen at session.measure toasts at once', NO_WRITES, async ($, on) => {
  const { w } = world(on)
  await bash($)
  await $.session.measure({ context: { window: 200_000 }, rateLimits: limits(95), changed: ['rateLimits'] })
  expect(w.toasts).toEqual([TOAST_EDGE])
})

test('toast: the option set to false drops the toast and keeps the transcript line', { options: { rate_limit_guard_enabled: false, rate_limit_guard_toast: false } }, async ($, on) => {
  const { w } = world(on)
  await bash($)
  w.limits = limits(96)
  expect(ownLines((await bash($)).context)).toEqual([EDGE_5H])
  expect(w.toasts).toEqual([])
  expect(crossingLogs(w)).toEqual([{ text: LOG_EDGE, to: 'transcript' }])
})

test('toast: a fresh session whose first reading is already past the approach mark does not toast', NO_WRITES, async ($, on) => {
  const { w } = world(on, { limits: limits(97, 92) })
  await $.session.start({ surface: 'terminal', isInteractive: true, cwd: '/work' })
  expect(ownLines((await bash($)).context)).toHaveLength(2)
  expect(w.toasts).toEqual([])
  expect(crossingLogs(w)).toEqual([])
})

test('toast: a restatement after /clear with a window at the edge does not toast', NO_WRITES, async ($, on) => {
  const { w } = world(on)
  await bash($)
  w.limits = limits(98)
  await bash($)
  expect(w.toasts).toHaveLength(1)
  await $.session.end({ reason: 'clear', sessionId: 'sess-1', resume: { id: 'sess-1' } } as any)
  w.sid = 'sess-2'
  expect(ownLines((await prompt($, 'composer')).context)).toHaveLength(1)
  expect(w.toasts).toHaveLength(1)
})

test('toast: a mid-session load restates the edge without a toast, and a later rise of the other window toasts once', NO_WRITES, async ($, on) => {
  const { w } = world(on, { turns: 3, limits: limits(97, 50) })
  await $.session.start({ surface: 'terminal', isInteractive: true, cwd: '/work' })
  expect(ownLines((await prompt($)).context)).toEqual([EDGE_5H_97])
  expect(w.toasts).toEqual([])
  w.limits = limits(97, 96)
  expect(ownLines((await bash($)).context)).toEqual([EDGE_7D_96])
  expect(w.toasts).toEqual(['7d at the 95% pause edge · resets 2026-10-08 09:00 UTC'])
})

test('operator mode: a held line whose suggestion cannot show reaches the person with Claude\'s line', { options: { rate_limit_guard_enabled: false, rate_limit_report_mode: 'operator' } }, async ($, on) => {
  const { w } = world(on, { shown: false })
  await prompt($, 'composer')
  w.limits = limits(96)
  expect(ownLines((await bash($)).context)).toEqual([])
  await $.turn.complete({ text: 'done', reason: 'answer' } as any)
  expect(w.toasts).toEqual([])
  expect(ownLines((await prompt($, 'composer')).context)).toEqual([EDGE_5H])
  expect(w.toasts).toEqual([TOAST_EDGE])
  expect(crossingLogs(w)).toEqual([{ text: LOG_EDGE, to: 'transcript' }])
})

test('operator mode: a shown suggestion is the person\'s channel, so the held change is never toasted later', { options: { rate_limit_guard_enabled: false, rate_limit_report_mode: 'operator' } }, async ($, on) => {
  const { w } = world(on)
  await prompt($, 'composer')
  w.limits = limits(96)
  await bash($)
  await $.turn.complete({ text: 'done', reason: 'answer' } as any)
  expect(w.suggested).toHaveLength(1)
  expect(ownLines((await prompt($, 'sdk')).context)).toEqual([EDGE_5H])
  expect(w.toasts).toEqual([])
  expect(crossingLogs(w)).toEqual([])
})

test('operator mode: a notice row the person saw before typing again is never toasted later', { options: { rate_limit_guard_enabled: false, rate_limit_report_mode: 'operator' } }, async ($, on) => {
  const { w } = world(on, { box: 'half typed' })
  await prompt($, 'composer')
  w.limits = limits(96)
  await bash($)
  await $.turn.complete({ text: 'done', reason: 'answer' } as any)
  expect(await noticeText($)).toBe(`FYI, ${EDGE_5H}`)
  await prompt($, 'composer')
  w.surfaces = []
  await bash($)
  expect(w.toasts).toEqual([])
  expect(crossingLogs(w)).toEqual([])
})

test('notice: a row wraps rather than truncating', NO_WRITES, async ($, on) => {
  const { w } = world(on)
  await bash($)
  w.limits = limits(97, 95)
  await bash($)
  const ui = await $.ui.mount({ ...BAND, surface: 'desktop' })
  const row = await ui.find({ type: 'Text', text: NOTICE })
  await ui.unmount()
  expect(row?.props.wrap).toBe('wrap')
})

test('toast: with lines to Claude off, a rise to the edge still toasts and Claude gets no line', { options: { rate_limit_guard_enabled: false, rate_limit_lines_enabled: false } }, async ($, on) => {
  const { w } = world(on)
  await bash($)
  w.limits = limits(100)
  expect(ownLines((await bash($)).context)).toEqual([])
  expect(w.toasts).toEqual(['5h at the 95% pause edge · resets 21:00 UTC'])
})

// The engine drops a refused or throwing toast itself; it never throws into the module.
test('toast: a refused toast leaves the line to Claude, the transcript line and the notice row, and the tool runs once', NO_WRITES, async ($, on) => {
  let runs = 0
  const { w } = world(on, {}, { HOME }, ['ui.toast', 'tool.call'])
  on('ui.toast', () => ({ deny: 'no toasts here' }))
  on('tool.call', () => (runs += 1, { result: { stdout: 'ok' }, text: 'ok' }))
  await bash($)
  w.limits = limits(96)
  expect(ownLines((await bash($)).context)).toEqual([EDGE_5H])
  expect(runs).toBe(2)
  expect(crossingLogs(w)).toEqual([{ text: LOG_EDGE, to: 'transcript' }])
  expect((await drawn($, 'desktop')).filter(t => NOTICE.test(t))).toEqual([LOG_EDGE])
})

const prefixes = (text: string) => text.split('rate-limit-guard:').length - 1

test('notice: two windows changing together share one row with the plugin prefix once', NO_WRITES, async ($, on) => {
  const { w } = world(on)
  await bash($)
  w.limits = limits(97, 95)
  expect(ownLines((await bash($)).context)).toEqual([EDGE_5H_97, EDGE_7D])
  expect(crossingLogs(w).map(l => l.text)).toEqual([LOG_EDGE, 'rate-limit-guard: 7d at the 95% pause edge · resets 2026-10-08 09:00 UTC · more: /rate-limit-guard'])
  const rows = (await drawn($, 'desktop')).filter(t => NOTICE.test(t))
  expect(rows).toEqual(['rate-limit-guard: 5h at the 95% pause edge · resets 21:00 UTC; 7d at the 95% pause edge · resets 2026-10-08 09:00 UTC · more: /rate-limit-guard'])
  expect(prefixes(rows[0])).toBe(1)
})

test('operator mode: two windows held together are offered in one notice with the plugin prefix once', OPERATOR, async ($, on) => {
  const { w } = world(on)
  await prompt($, 'composer')
  w.limits = limits(97, 95)
  await bash($)
  await $.turn.complete({ text: 'done', reason: 'answer' } as any)
  const offered =
    'FYI, rate-limit-guard: 5-hour window at or above 95% (97% used), resets at 2026-10-03 21:00 UTC. 7-day window at or above 95% (95% used), resets at 2026-10-08 09:00 UTC.'
  expect(w.suggested).toEqual([offered])
  for (const surface of ['terminal', 'desktop'] as const) {
    expect((await drawn($, surface)).filter(t => NOTICE.test(t))).toEqual([offered])
  }
  expect(prefixes(offered)).toBe(1)
  expect(ownLines((await prompt($, 'sdk')).context)).toEqual([EDGE_5H_97, EDGE_7D])
})

test('toast: a rise the /rate-limit-guard command or the status tool reads is shown at once', NO_WRITES, async ($, on) => {
  const { w } = world(on)
  await bash($)
  w.limits = limits(96)
  await command($)
  expect(w.toasts).toEqual([TOAST_EDGE])
  w.limits = limits(undefined, 96)
  await $.tool.call({ tool: 'mcp__rate-limit-guard__status' } as any)
  expect(w.toasts).toEqual([TOAST_EDGE, '5h reset, below the 95% pause edge', '7d at the 95% pause edge · resets 2026-10-08 09:00 UTC'])
})

test('notice: after a window change a terminal mount returns only what is drawn beneath; desktop and vscode draw one row', NO_WRITES, async ($, on) => {
  const { w } = world(on)
  await bash($)
  w.limits = limits(96)
  await bash($)
  expect(await drawn($, 'terminal')).toEqual(['drawn beneath'])
  for (const surface of ['desktop', 'vscode'] as const) expect(await drawn($, surface)).toEqual([LOG_EDGE, 'drawn beneath'])
  await prompt($, 'composer')
  expect(await drawn($, 'desktop')).toEqual(['drawn beneath'])
})

test('pull tool: latest figures, verdicts and the spend limit, with no line attached', NO_WRITES, async ($, on) => {
  world(on, { limits: [...limits(96), { kind: 'spend_limit', percentUsed: 104.5 }] })
  const answer = await $.tool.call({ tool: 'mcp__rate-limit-guard__status' } as any)
  expect(answer.context).toBeUndefined()
  expect(JSON.parse(resultText(answer))).toEqual({
    source: 'the last API response',
    windows: {
      five_hour: { used_percentage: 96, resets_at: FIVE_RESET, verdict: 'edge' },
      seven_day: { used_percentage: 7, resets_at: SEVEN_RESET, verdict: 'quiet' },
    },
    verdict: 'edge',
    line_threshold: 95,
    approach_pct: 90,
    lanes_pause_edge: 95,
    spend_limit: { used_percentage: 104.5, resets_at: null },
  })
})

test('snapshot: body on stdin and argv, no spend limit, no session name, no account before any response', async ($, on) => {
  const { w } = world(on, {
    limits: [...limits(23.5), { kind: 'spend_limit', percentUsed: 40 }],
    files: { [STATE_FILE]: { text: JSON.stringify({ oauthAccount: { emailAddress: 'me@example.com' } }), mtimeMs: 0 } },
  })
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
  const { w } = world(on, {}, { USERPROFILE: 'C:/profiles/u' })
  await bash($)
  expect(w.runs[0].argv[2]).toBe('C:/profiles/u/.claude/rate-limit-guard/rate-limits.json')
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
  w.limits = limits(100)
  expect(ownLines((await bash($)).context)).toHaveLength(1)
  expect(w.runs).toEqual([])
})

test('switch: rate_limit_lines_enabled false stops lines while writes continue', { options: { rate_limit_lines_enabled: false } }, async ($, on) => {
  const { w } = world(on)
  await bash($)
  w.limits = limits(100)
  expect(ownLines((await bash($)).context)).toEqual([])
  expect(w.runs).toHaveLength(2)
})

test('account: attributed while the identity matches the one at the last response, omitted after a switch, even at an equal mtime', async ($, on) => {
  const { w, clock } = world(on, {
    files: { [STATE_FILE]: { text: JSON.stringify({ oauthAccount: { emailAddress: 'me@example.com' } }), mtimeMs: T0 - 1 } },
  })
  await answerStep(on, $)
  await bash($)
  expect(bodies(w)[0].account).toEqual({ email: 'me@example.com' })

  w.files[STATE_FILE] = { text: JSON.stringify({ oauthAccount: { emailAddress: 'other@example.com' } }), mtimeMs: T0 }
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

test('account: read from CLAUDE_CONFIG_DIR when it is set, not from HOME', async ($, on) => {
  const { w } = world(
    on,
    {
      files: {
        '/cfg/.claude.json': { text: JSON.stringify({ oauthAccount: { emailAddress: 'cfg@example.com' } }), mtimeMs: 0 },
        [STATE_FILE]: { text: JSON.stringify({ oauthAccount: { emailAddress: 'home@example.com' } }), mtimeMs: 0 },
      },
    },
    { HOME, CLAUDE_CONFIG_DIR: '/cfg' },
  )
  await answerStep(on, $)
  await bash($)
  expect(bodies(w)[0].account).toEqual({ email: 'cfg@example.com' })
})

const stateFile = (email: string, mtimeMs: number, extra: object = {}) => ({
  text: JSON.stringify({ ...extra, oauthAccount: { emailAddress: email } }),
  mtimeMs,
})
const MEASURE = { context: { window: 200_000 }, rateLimits: limits(20), changed: ['rateLimits'] }

test('account: the first write after a startup measurement, before any step, carries the account', async ($, on) => {
  const { w } = world(on, { files: { [STATE_FILE]: stateFile('me@example.com', T0 - 1) } })
  await $.session.measure(MEASURE as any)
  expect(bodies(w)).toHaveLength(1)
  expect(bodies(w)[0].account).toEqual({ email: 'me@example.com' })
})

test('account: a timer write during a long call keeps the account when .claude.json was rewritten with the same identity', async ($, on) => {
  const { w, clock } = world(on, { files: { [STATE_FILE]: stateFile('me@example.com', T0 - 1) } })
  await answerStep(on, $)
  await $.turn.start({ text: 'go', turnId: 'turn-1' })
  await bash($)
  w.files[STATE_FILE] = stateFile('me@example.com', T0 + 30_000, { numStartups: 318 })
  await clock.advance(300_000)
  expect(bodies(w)).toHaveLength(2)
  expect(bodies(w)[1].account).toEqual({ email: 'me@example.com' })
})

test('account: omitted when the identity changed between the last response and the write (a /login)', async ($, on) => {
  const { w } = world(on, { files: { [STATE_FILE]: stateFile('a@example.com', T0 - 1) } })
  await answerStep(on, $)
  w.files[STATE_FILE] = stateFile('b@example.com', T0 - 1, { numStartups: 2 })
  await bash($)
  expect(bodies(w)).toHaveLength(1)
  expect(bodies(w)[0].account).toBeUndefined()
})

for (const [label, after] of [
  ['unreadable', undefined],
  ['malformed JSON', { text: '{"oauthAccount": {', mtimeMs: T0 + 1 }],
] as const) {
  test(`account: omitted when the state file is ${label} at the write, after a response that read it`, async ($, on) => {
    const { w } = world(on, { files: { [STATE_FILE]: stateFile('me@example.com', T0 - 1) } })
    await answerStep(on, $)
    if (after === undefined) delete w.files[STATE_FILE]
    else w.files[STATE_FILE] = after
    await bash($)
    expect(bodies(w)).toHaveLength(1)
    expect(bodies(w)[0].account).toBeUndefined()
  })
}

test('account: omitted when the state file was unreadable at the response and readable at the write', async ($, on) => {
  const { w } = world(on)
  await answerStep(on, $)
  w.files[STATE_FILE] = stateFile('me@example.com', T0 - 1)
  await bash($)
  expect(bodies(w)[0].account).toBeUndefined()
})

test('account: an unchanged state file is read once, and read again when its mtime or size changes', async ($, on) => {
  const reads: string[] = []
  const { w } = world(on, { files: { [STATE_FILE]: stateFile('me@example.com', T0 - 1) } }, { HOME }, ['fs.read'])
  on('fs.read', ($: unknown, e: { path: string }) => {
    reads.push(e.path)
    const file = w.files[e.path]
    if (file === undefined) throw new Error(`ENOENT: ${e.path}`)
    return { value: file.text }
  })
  await answerStep(on, $)
  await bash($)
  w.limits = limits(30)
  await bash($)
  expect(reads.filter(p => p === STATE_FILE)).toHaveLength(1)
  expect(bodies(w).map(b => b.account)).toEqual([{ email: 'me@example.com' }, { email: 'me@example.com' }])
  w.files[STATE_FILE] = stateFile('me@example.com', T0 + 5, { numStartups: 3 })
  w.limits = limits(40)
  await bash($)
  expect(reads.filter(p => p === STATE_FILE)).toHaveLength(2)
  expect(bodies(w)[2].account).toEqual({ email: 'me@example.com' })
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
  w.limits = limits(100)
  const called = await bash($)
  expect(called.text).toBe('ok')
  expect(ownLines(called.context)).toHaveLength(1)
})

// The helper's outcomes by run number: 'exit' is its exit 1 for a rename refused 3 times, 'throw'
// a spawn that never ran, 'skip' its exit 3; anything else writes the file and exits 0.
type Outcome = 'exit' | 'throw' | 'skip' | undefined
const scriptedWrites = (stub: any, outcome: (run: number) => Outcome) => {
  const logs: string[] = []
  const { w, clock } = world(stub, {}, { HOME }, ['process.run', 'ui.log'])
  stub('ui.log', ($: unknown, e: { text: string }) => (logs.push(e.text), { value: undefined }))
  stub('process.run', ($: unknown, e: { argv: readonly string[]; init?: { stdin?: string } }) => {
    w.runs.push({ argv: e.argv, stdin: e.init?.stdin })
    const how = outcome(w.runs.length)
    if (how === 'throw') throw new Error('spawn refused')
    if (how === 'exit') return { value: { exitCode: 1, stdout: '', stderr: 'write-snapshot: rename failed after 3 tries: EPERM' } }
    if (how === 'skip') return { value: { exitCode: 3, stdout: 'skip lock', stderr: '' } }
    w.files[e.argv[2]] = { text: String(e.init?.stdin), mtimeMs: clock.now() }
    return { value: { exitCode: 0, stdout: '', stderr: '' } }
  })
  return { w, clock, logs }
}
// The engine reports a stub's throw in its own words, so the thrown case matches the mod's prefix.
const FAILURE_LOG = {
  exit: /^rate-limit-guard: snapshot write failed \(exit 1\): write-snapshot: rename failed after 3 tries: EPERM$/,
  throw: /^rate-limit-guard: snapshot write did not run: \S/,
}
// One of each carrier: a tool call, a measurement, the in-turn timer, and the session.end flush.
const everyCarrier = async ($: any, w: World, clock: any, runsAfter: number[]) => {
  await bash($)
  runsAfter.push(w.runs.length)
  await $.session.measure({ context: { window: 200_000 }, rateLimits: w.limits, changed: ['rateLimits'] })
  runsAfter.push(w.runs.length)
  await $.turn.start({ text: 'go', turnId: 'turn-1' })
  await clock.advance(60_000)
  await $.turn.complete({ text: 'done', reason: 'answer' } as any)
  runsAfter.push(w.runs.length)
  await $.session.end({ reason: 'other', sessionId: 'sess-1', resume: { id: 'sess-1' } } as any)
  runsAfter.push(w.runs.length)
}

for (const how of ['exit', 'throw'] as const) {
  test(`retry: a write that failed (${how}) is tried again at the next carrier, and a landed one dedupes`, async ($, on) => {
    const { w } = scriptedWrites(on, run => (run === 1 ? how : undefined))
    await bash($)
    await bash($)
    await bash($)
    expect(w.runs).toHaveLength(2)
    expect(bodies(w)[1].rate_limits.five_hour.used_percentage).toBe(20)
  })

  test(`retry: a write that keeps failing (${how}) is tried once at every carrier and logged once`, async ($, on) => {
    const { w, clock, logs } = scriptedWrites(on, () => how)
    const runsAfter: number[] = []
    await everyCarrier($, w, clock, runsAfter)
    expect(runsAfter).toEqual([1, 2, 3, 4])
    expect(logs).toHaveLength(1)
    expect(logs[0]).toMatch(FAILURE_LOG[how])
  })
}

test('retry: session.end flushes the reading a failed write left unwritten', async ($, on) => {
  const { w } = scriptedWrites(on, run => (run === 1 ? 'exit' : undefined))
  await bash($)
  await $.session.end({ reason: 'other', sessionId: 'sess-1', resume: { id: 'sess-1' } } as any)
  expect(w.runs).toHaveLength(2)
  expect(w.files[TARGET]?.text).toBe(w.runs[1].stdin)
})

for (const how of [undefined, 'skip'] as const) {
  test(`retry: a ${how === 'skip' ? 'write the helper skipped by rule' : 'landed write'} is not repeated by any later carrier inside the floor`, async ($, on) => {
    const { w, clock } = scriptedWrites(on, () => how)
    const runsAfter: number[] = []
    await everyCarrier($, w, clock, runsAfter)
    expect(runsAfter).toEqual([1, 1, 1, 1])
  })
}

test('pull tool: a refused registration logs one line, and lines, band and writes carry on', { options: { rate_limit_guard_band: true, rate_limit_guard_toast: false } }, async ($, on) => {
  const logs: string[] = []
  const { w } = world(on, {}, { HOME }, ['tool.register', 'ui.log'])
  on('tool.register', () => {
    throw new Error('refused by policy')
  })
  on('ui.log', ($: unknown, e: { text: string }) => (logs.push(e.text), { value: undefined }))
  await $.session.start({ surface: 'terminal', isInteractive: true, cwd: '/work' })
  w.limits = limits(96)
  expect(ownLines((await bash($)).context)).toEqual([EDGE_5H])
  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect((await ui.find({ type: 'Text', text: BAND_ROW }))?.text).toBe('5h 96% | 7d 7%')
  await ui.unmount()
  expect(bodies(w).map(b => b.rate_limits.five_hour.used_percentage)).toEqual([96])
  const failures = logs.filter(l => l.startsWith('rate-limit-guard: the status pull tool'))
  expect(failures).toHaveLength(1)
  expect(failures[0]).toMatch(/^rate-limit-guard: the status pull tool could not register: \S/)
})

test('pull tool: a registration refused at every session start is logged once', NO_WRITES, async ($, on) => {
  const logs: string[] = []
  world(on, {}, { HOME }, ['tool.register', 'ui.log'])
  on('tool.register', () => {
    throw new Error('refused by policy')
  })
  on('ui.log', ($: unknown, e: { text: string }) => (logs.push(e.text), { value: undefined }))
  await $.session.start({ surface: 'terminal', isInteractive: true, cwd: '/work' })
  await $.session.start({ surface: 'terminal', isInteractive: true, cwd: '/work' })
  expect(logs.filter(l => l.startsWith('rate-limit-guard: the status pull tool could not register: '))).toHaveLength(1)
})

test('operator mode: a carrier with nothing due leaves a shown notice in place', OPERATOR, async ($, on) => {
  const { w } = world(on)
  await shownInTypedTurn($, w)
  w.surfaces = []
  expect(ownLines((await bash($)).context)).toEqual([])
  expect(await noticeText($)).toBe(`FYI, ${EDGE_5H}`)
  expect(ownLines((await prompt($, 'sdk')).context)).toEqual([EDGE_5H])
})

for (const kind of ['sdk', 'scheduled-trigger']) {
  test(`operator mode: a held line sent to Claude at a ${kind} turn clears the notice and offers nothing later`, OPERATOR, async ($, on) => {
    const { w, clock } = world(on, { box: 'half typed' })
    await prompt($, 'composer')
    w.limits = limits(96)
    await bash($)
    await $.turn.complete({ text: 'done', reason: 'answer' } as any)
    expect(await noticeText($)).toBe(`FYI, ${EDGE_5H}`)
    expect(ownLines((await prompt($, kind)).context)).toEqual([EDGE_5H])
    expect(w.toasts).toEqual([])
    expect(crossingLogs(w)).toEqual([])
    expect(await noticeText($)).toBeUndefined()
    w.box = ''
    await clock.advance(20_000)
    expect(w.suggested).toEqual([])
  })
}

test('operator mode: a re-offer that cannot show, after the row was seen, sends the line to Claude with no toast', OPERATOR, async ($, on) => {
  const { w, clock } = world(on, { box: 'half typed', shown: false })
  await prompt($, 'composer')
  w.limits = limits(96)
  await bash($)
  await $.turn.complete({ text: 'done', reason: 'answer' } as any)
  expect(await noticeText($)).toBe(`FYI, ${EDGE_5H}`)
  w.box = ''
  await clock.advance(5_000)
  expect(await noticeText($)).toBeUndefined()
  expect(ownLines((await prompt($, 'composer')).context)).toEqual([EDGE_5H])
  expect(w.toasts).toEqual([])
  expect(crossingLogs(w)).toEqual([])
})

test('operator mode: a row a survey hid was never seen, so the line sent to Claude brings the toast', OPERATOR, async ($, on) => {
  const { w } = world(on, { box: 'half typed' })
  await prompt($, 'composer')
  w.limits = limits(96)
  await bash($)
  await $.turn.complete({ text: 'done', reason: 'answer' } as any)
  const ui = await $.ui.mount({ ...BAND, surface: 'terminal', props: { ...BAND.props, hasSurvey: true } })
  await ui.unmount()
  expect(ownLines((await prompt($, 'sdk')).context)).toEqual([EDGE_5H])
  expect(w.toasts).toEqual([TOAST_EDGE])
})

const EDGE_7D = `rate-limit-guard: 7-day window at or above 95% (95% used), resets at 2026-10-08 09:00 UTC.`

test('operator mode: a newer reading than the shown suggestion goes to Claude instead of the handed-off one', OPERATOR, async ($, on) => {
  const { w } = world(on)
  await shownInTypedTurn($, w, limits(92))
  w.limits = limits(97)
  await $.session.measure({ context: { window: 200_000 }, rateLimits: w.limits, changed: ['rateLimits'] })
  expect(ownLines((await prompt($, 'sdk')).context)).toEqual([EDGE_5H_97])
})

test('operator mode: a handed-off crossing states the percent shown, not the live reading', OPERATOR, async ($, on) => {
  const { w } = world(on)
  await shownInTypedTurn($, w, limits(96))
  w.limits = limits(92)
  await $.session.measure({ context: { window: 200_000 }, rateLimits: w.limits, changed: ['rateLimits'] })
  expect(ownLines((await prompt($, 'sdk')).context)).toEqual([EDGE_5H])
})

test('operator mode: a handed-off window that left the reading sends no line', OPERATOR, async ($, on) => {
  const { w } = world(on)
  await shownInTypedTurn($, w, limits(92))
  w.limits = limits(undefined)
  await $.session.measure({ context: { window: 200_000 }, rateLimits: w.limits, changed: ['rateLimits'] })
  expect(ownLines((await prompt($, 'sdk')).context)).toEqual([])
})

test('operator mode: a second shown suggestion keeps the first one handed off', OPERATOR, async ($, on) => {
  const { w } = world(on)
  await shownInTypedTurn($, w)
  await prompt($, 'task-notification', { turnId: 'turn-1' })
  w.limits = limits(96, 97)
  expect(ownLines((await bash($)).context)).toEqual([])
  await $.turn.complete({ text: 'done', reason: 'answer' } as any)
  expect(w.suggested).toEqual([`FYI, ${EDGE_5H}`, `FYI, ${EDGE_7D_97}`])
  expect(ownLines((await prompt($, 'sdk')).context)).toEqual([EDGE_5H, EDGE_7D_97])
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
    w.limits = limits(100)
    const context = (await bash($)).context ?? []
    expect(context).toContain('other-mod line')
    expect(ownLines(context)).toHaveLength(1)
  },
)

// A bad option value: the module still loads, the option reads as its default, and one line says so.
const optionLogs = (w: World) => w.logs.filter(l => l.text.startsWith('rate-limit-guard: option '))

for (const value of [101, 0, -5, 1e9]) {
  test(`options: line threshold ${value} reads as 95, writes go on, one line names it`, { options: { rate_limit_line_threshold: value } }, async ($, on) => {
    const { w } = world(on, { limits: limits(94) })
    expect(ownLines((await bash($)).context)).toHaveLength(1)
    w.limits = limits(97)
    expect(ownLines((await bash($)).context)).toEqual([EDGE_5H_97])
    expect(bodies(w).at(-1)?.rate_limits?.five_hour?.used_percentage).toBe(97)
    expect(optionLogs(w)).toHaveLength(1)
    expect(optionLogs(w)[0].text).toContain('rate_limit_line_threshold')
    expect(optionLogs(w)[0].text).toContain(String(value))
    expect(optionLogs(w)[0].text).toContain('default, 95')
    expect(optionLogs(w)[0].to).toBe('transcript')
  })
}

test('options: approach mark 150 reads as 90, one line names it', { options: { rate_limit_guard_enabled: false, rate_limit_approach_pct: 150 } }, async ($, on) => {
  const { w } = world(on, { limits: limits(89) })
  expect(ownLines((await bash($)).context)).toEqual([])
  w.limits = limits(91)
  expect(ownLines((await bash($)).context)[0]).toContain('at or above 90%')
  expect(optionLogs(w).map(l => l.text)).toEqual([expect.stringContaining('rate_limit_approach_pct')])
  expect(optionLogs(w)[0].text).toContain('default, 90')
})

test('options: line data naming no known item reads as the default, and the line echoes 40 characters at most', { options: { rate_limit_guard_enabled: false, rate_limit_line_data: `bogus,${'x'.repeat(60)}` } }, async ($, on) => {
  const { w } = world(on, { limits: limits(97) })
  expect(ownLines((await bash($)).context)).toEqual([EDGE_5H_97])
  expect(optionLogs(w)).toHaveLength(1)
  const text = optionLogs(w)[0].text
  expect(text).toContain('rate_limit_line_data')
  expect(text).toContain('default, verdict,percent,window,reset')
  expect(text).toContain(`bogus,${'x'.repeat(34)}`)
  expect(text).not.toContain('x'.repeat(35))
})

test('options: line data with one unknown item reads as the default, not a partial list', { options: { rate_limit_guard_enabled: false, rate_limit_line_data: 'percent,precent' } }, async ($, on) => { // spellchecker:disable-line
  const { w } = world(on, { limits: limits(97) })
  expect(ownLines((await bash($)).context)).toEqual([EDGE_5H_97])
  expect(optionLogs(w).map(l => l.text)).toEqual([expect.stringContaining('rate_limit_line_data')])
})

test('options: a report mode outside the list loads as automatic and the module adds no line', { options: { rate_limit_guard_enabled: false, rate_limit_report_mode: 'loud' } }, async ($, on) => {
  const { w } = world(on, { limits: limits(97) })
  expect(ownLines((await prompt($, 'composer')).context)).toEqual([EDGE_5H_97])
  expect(optionLogs(w)).toEqual([])
})

test('options: two bad options give two lines, and no more on later events or a fresh start', { options: { rate_limit_line_threshold: 250, rate_limit_approach_pct: -1 } }, async ($, on) => {
  const { w } = world(on, { limits: limits(91) })
  await $.session.start({ surface: 'terminal', isInteractive: true, cwd: '/work' })
  expect(ownLines((await bash($)).context)[0]).toContain('at or above 90%')
  w.limits = limits(97)
  expect(ownLines((await prompt($)).context)).toEqual([EDGE_5H_97])
  await bash($)
  await $.session.start({ surface: 'terminal', isInteractive: true, cwd: '/work' })
  await prompt($)
  expect(optionLogs(w).map(l => l.text)).toEqual([expect.stringContaining('rate_limit_line_threshold'), expect.stringContaining('rate_limit_approach_pct')])
})

test('options: good values log no option line', { options: { rate_limit_line_threshold: 80, rate_limit_approach_pct: 70, rate_limit_line_data: 'Percent, window' } }, async ($, on) => {
  const { w } = world(on, { limits: limits(81) })
  await $.session.start({ surface: 'terminal', isInteractive: true, cwd: '/work' })
  expect(ownLines((await bash($)).context)).toEqual([`rate-limit-guard: 5-hour window at or above 80% (81% used).`])
  expect(optionLogs(w)).toEqual([])
})

test('options: line threshold 100 and approach mark 1, the ends of the range, are used as given with no option line', { options: { rate_limit_guard_enabled: false, rate_limit_line_threshold: 100, rate_limit_approach_pct: 1 } }, async ($, on) => {
  const { w } = world(on, { limits: limits(1, 0) })
  expect(ownLines((await bash($)).context)).toEqual([
    `rate-limit-guard: 5-hour window at or above 1% (1% used), resets at 2026-10-03 21:00 UTC.`,
  ])
  w.limits = limits(99, 0)
  expect(ownLines((await bash($)).context)).toEqual([])
  w.limits = limits(100, 0)
  expect(ownLines((await bash($)).context)).toEqual([
    `rate-limit-guard: 5-hour window at or above 100% (100% used), resets at 2026-10-03 21:00 UTC.`,
  ])
  expect(optionLogs(w)).toEqual([])
})

test('options: line threshold 1 and approach mark 100 are used as given with no option line', { options: { rate_limit_guard_enabled: false, rate_limit_line_threshold: 1, rate_limit_approach_pct: 100 } }, async ($, on) => {
  const { w } = world(on, { limits: limits(0.5, 0) })
  expect(ownLines((await bash($)).context)).toEqual([])
  w.limits = limits(1, 0)
  expect(ownLines((await bash($)).context)).toEqual([
    `rate-limit-guard: 5-hour window at or above 1% (1% used), resets at 2026-10-03 21:00 UTC.`,
  ])
  expect(optionLogs(w)).toEqual([])
})

test('options: an empty line data value reads as the default with no option line, as an unset one does', { options: { rate_limit_guard_enabled: false, rate_limit_line_data: '' } }, async ($, on) => {
  const { w } = world(on, { limits: limits(97) })
  expect(ownLines((await bash($)).context)).toEqual([EDGE_5H_97])
  expect(optionLogs(w)).toEqual([])
})

test('account: a state file rewritten at the same size with another identity and a new mtime is read again', async ($, on) => {
  const reads: string[] = []
  const { w } = world(on, { files: { [STATE_FILE]: stateFile('me@example.com', T0 - 1) } }, { HOME }, ['fs.read'])
  on('fs.read', ($: unknown, e: { path: string }) => {
    reads.push(e.path)
    const file = w.files[e.path]
    if (file === undefined) throw new Error(`ENOENT: ${e.path}`)
    return { value: file.text }
  })
  await answerStep(on, $)
  await bash($)
  expect(bodies(w)[0].account).toEqual({ email: 'me@example.com' })
  const size = w.files[STATE_FILE].text.length
  w.files[STATE_FILE] = stateFile('us@example.com', T0 + 5)
  expect(w.files[STATE_FILE].text.length).toBe(size)
  w.limits = limits(30)
  await bash($)
  expect(reads.filter(p => p === STATE_FILE)).toHaveLength(2)
  expect(bodies(w)).toHaveLength(2)
  expect(bodies(w)[1].account).toBeUndefined()
})

// An empty reading (no window reported, as before a session's first response) is no reading, not a reset.
test('lines: a carrier with an empty reading sends no reset line and keeps the levels, so the same reading again sends nothing', async ($, on) => {
  const { w } = world(on, { limits: limits(96) })
  expect(ownLines((await bash($)).context)).toEqual([EDGE_5H])
  w.limits = []
  expect(ownLines((await bash($)).context)).toEqual([])
  expect(ownLines((await prompt($)).context)).toEqual([])
  w.limits = limits(96)
  expect(ownLines((await bash($)).context)).toEqual([])
  // A windowless body still goes to the helper with the key it must keep from a file that has windows.
  expect(w.runs.filter(r => !String(r.stdin).includes('rate_limits')).every(r => r.argv.join(' ').includes('--preserve-key rate_limits'))).toBe(true)
})

test('lines: a reading whose every window has passed its reset time still sends one reset line', NO_WRITES, async ($, on) => {
  const { clock } = world(on, { limits: [{ kind: 'five_hour', percentUsed: 97, resetsAt: FIVE_RESET }] })
  expect(ownLines((await bash($)).context)).toEqual([EDGE_5H_97])
  await clock.set(Date.parse(FIVE_RESET) + 1000)
  expect(ownLines((await bash($)).context)).toEqual([`rate-limit-guard: 5-hour window reset, now below 95%.`])
  expect(ownLines((await bash($)).context)).toEqual([])
})

// A /branch or an in-process /resume: the new session's first prompt can come before any reading.
const BRANCH = { reason: 'resume', sessionId: 'sess-1', resume: { id: 'sess-2' } } as any

test('lines: after a branch, a carrier with no reading keeps the restatement, and the first carrier with one restates each window past quiet once', NO_WRITES, async ($, on) => {
  const { w } = world(on, { limits: limits(96) })
  await bash($)
  await $.session.end(BRANCH)
  w.sid = 'sess-2'
  w.limits = []
  expect(ownLines((await prompt($)).context)).toEqual([])
  w.limits = limits(96)
  expect(ownLines((await bash($)).context)).toEqual([EDGE_5H])
  expect(ownLines((await bash($)).context)).toEqual([])
})

test('snapshot: the first write after a branch carries the new session id, inside the floor and with the reading unchanged', async ($, on) => {
  const { w } = world(on, { limits: limits(96) })
  await bash($)
  await $.session.end(BRANCH)
  w.sid = 'sess-2'
  w.limits = []
  await prompt($)
  w.limits = limits(96)
  await bash($)
  expect(bodies(w).map(b => b.session_id)).toEqual(['sess-1', 'sess-2'])
  await bash($)
  expect(bodies(w)).toHaveLength(2)
})
