import { expect, mock, test } from 'claude-code/testing'

// Fixture time, computed by hand: 2026-10-03T18:00:00Z is 1791050400 s.
const T0 = 1_791_050_400_000
const HOME = '/home/u'
const CTX = '/home/u/.claude/context-guard/context'
const ZONES = '/home/u/.claude/context-guard/zones.json'
const SRC = '(a measurement from the last API response)'
const STEER =
  "A zone is a measurement, not an instruction: degradation shows in the work itself (drift, repetition, dropped constraints), never in a zone word, and continuation is the operator's call."
const SAVE = 'context-guard (default for the dumb zone): compaction distance is short, so each expensive conclusion goes to a durable note as it stabilizes.'
const crossing = (from: string, to: string) => `context-guard: this session crossed from the ${from} into the ${to} context zone ${SRC}. ${STEER}`
const DEGRADED = 'dumb (evidence-degraded: this session was compacted)'

type World = {
  percent: number | undefined
  tokens: number | undefined
  output: number
  window: number
  version: string
  sid: string
  surfaces: string[]
  turns: number
  box: string
  shown: boolean
  isError: boolean
  files: Record<string, { text: string; mtimeMs: number }>
  runs: { argv: readonly string[]; stdin?: string }[]
  suggested: string[]
  logs: string[]
  below: string[]
  ran: string[]
}

// The world beneath the plugin. `percent` drives the reading; tokens follow it on a 200000 window
// unless a test sets them, so the token shape agrees with the percentage shape.
const world = (stub: any, init: Partial<World> = {}, env: Record<string, string> = { HOME }, omit: string[] = []) => {
  const on = (event: string, ...rest: unknown[]) => (omit.includes(event) ? undefined : stub(event, ...rest))
  const w: World = {
    percent: 30,
    tokens: undefined,
    output: 0,
    window: 200_000,
    version: '2.1.288',
    sid: 'sess-1',
    surfaces: ['terminal'],
    turns: 0,
    box: '',
    shown: true,
    isError: false,
    files: {},
    runs: [],
    suggested: [],
    logs: [],
    below: [],
    ran: [],
    ...init,
  }
  const clock = mock.clock(stub, { now: T0 })
  mock.env(stub, env)
  on('session.usage', () => {
    const known = w.percent !== undefined
    const tokens = w.tokens ?? (known ? Math.round(((w.percent as number) * w.window) / 100) : undefined)
    return {
      value: {
        startedAt: 0,
        rateLimits: [],
        context: {
          window: w.window,
          ...(known ? { percent: w.percent, tokens } : {}),
          breakdown: { apiUsage: known ? { input_tokens: 5, output_tokens: w.output, cache_read_input_tokens: 0, cache_creation_input_tokens: 0 } : null },
        },
      },
    }
  })
  on('session.id', () => ({ value: w.sid }))
  on('session.version', () => ({ value: { version: w.version } }))
  on('session.surfaces', () => ({ value: w.surfaces }))
  on('session.model', () => ({ value: 'Opus 5.5' }))
  on('session.turns', () => ({ value: w.turns }))
  on('session.root', () => ({ value: '/repo' }))
  on('fs.exists', ($: unknown, e: { path: string }) => ({ value: w.files[e.path] !== undefined }))
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
    return { value: { exitCode: 0, stdout: '', stderr: '' } }
  })
  on('ui.invalidate', () => ({ value: undefined }))
  on('ui.log', ($: unknown, e: { text: string; to?: string }) => {
    if (e.to !== 'debug') w.logs.push(e.text)
    return { value: undefined }
  })
  on('prompt.read', () => ({ value: { text: w.box, cursor: w.box.length } }))
  on('prompt.suggest', ($: unknown, e: { text: string }) => {
    if (w.shown && w.box === '') w.suggested.push(e.text)
    return { isShown: w.shown && w.box === '' }
  })
  on('tool.register', ($: unknown, e: { name: string }) => ({ value: { tool: `mcp__context-guard__${e.name}` } }))
  on('tool.list', () => ({ value: [{ name: 'mcp__context-guard__status' }] }))
  on('command.register', ($: unknown, e: { name: string }) => ({ value: { command: e.name } }))
  on('tool.call', ($: unknown, e: { tool: string }) => {
    w.ran.push(e.tool)
    return { result: { stdout: 'ok' }, text: 'ok', ...(w.isError ? { isError: true } : {}), context: w.below.length ? w.below : undefined }
  })
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
const write = ($: any, file_path = '/work/a.ts', agentId?: string) =>
  $.tool.call({ tool: 'Write', file_path, content: 'x', ...(agentId ? { agentId } : {}) })
const prompt = ($: any, kind = 'sdk', extra: object = {}) => $.prompt.submit({ text: 'go', wait: false, origin: { kind }, ...extra })
const own = (context: readonly string[] | undefined) => (context ?? []).filter(c => c.startsWith('context-guard'))
// Steps the reading through each percentage, one Bash call each, and returns each call's own lines.
const walk = async ($: any, w: World, steps: (number | undefined)[]) => {
  const seen: string[][] = []
  for (const p of steps) {
    w.percent = p
    seen.push(own((await bash($)).context))
  }
  return seen
}
const MESSAGES = [{ role: 'user', text: 'hello', toolUses: [] }]
const BAND = {
  plugin: 'context-guard',
  component: 'AbovePrompt',
  viewport: { columns: 120, rows: 40 },
  props: { hasSurvey: false, isWorking: false, maxRows: 10, bodyColumns: 120, scroll: { offset: 0, bodyRows: 9 }, view: {} },
} as const

// ---- Crossing lines and the once-per-zone cycle ----------------------------------------------

test('lines: one line at each crossing into a worse zone, appended after the context beneath', async ($, on) => {
  const { w } = world(on, { below: ['below'] })
  const seen: (readonly string[] | undefined)[] = []
  for (const p of [30, 60, 62, 80, 85]) {
    w.percent = p
    seen.push((await bash($)).context)
  }
  expect(seen).toEqual([
    ['below'],
    ['below', crossing('smart', 'acceptable')],
    ['below'],
    ['below', `${crossing('acceptable', 'dumb')} ${SAVE}`],
    ['below'],
  ])
})

test('lines: a first reading already past smart crosses from unobserved', async ($, on) => {
  const { w } = world(on)
  expect(await walk($, w, [80])).toEqual([[`${crossing('unobserved', 'dumb')} ${SAVE}`]])
})

test('lines: a dip below a boundary is not a new cycle', async ($, on) => {
  const { w } = world(on)
  expect((await walk($, w, [30, 60, 80, 70, 80, 60, 80])).flat()).toEqual([crossing('smart', 'acceptable'), `${crossing('acceptable', 'dumb')} ${SAVE}`])
})

test('lines: a return to smart opens a new cycle, and the line names the zone it came from', async ($, on) => {
  const { w } = world(on)
  expect((await walk($, w, [30, 60, 30, 60, 80, 30, 80])).flat()).toEqual([
    crossing('smart', 'acceptable'),
    crossing('smart', 'acceptable'),
    `${crossing('acceptable', 'dumb')} ${SAVE}`,
    `${crossing('smart', 'dumb')} ${SAVE}`,
  ])
})

test('lines: an unknown reading sends nothing and leaves the last zone as it was', async ($, on) => {
  const { w } = world(on)
  expect(await walk($, w, [30, 60, undefined, 60, undefined, 80])).toEqual([
    [],
    [crossing('smart', 'acceptable')],
    [],
    [],
    [],
    [`${crossing('acceptable', 'dumb')} ${SAVE}`],
  ])
})

test('lines: main-thread calls dispatched together after a crossing carry one line between them', async ($, on) => {
  const { w } = world(on)
  await bash($)
  w.percent = 60
  const results = await Promise.all([bash($), bash($), bash($)])
  expect(results.flatMap(r => own(r.context))).toEqual([crossing('smart', 'acceptable')])
})

test('lines: a subagent tool call carries no line, and the next main-thread call does', async ($, on) => {
  const { w } = world(on)
  await bash($)
  w.percent = 60
  expect(own((await bash($, 'agent-1')).context)).toEqual([])
  expect(own((await bash($)).context)).toEqual([crossing('smart', 'acceptable')])
})

test('lines: a failed tool result carries no line, and the next call does', async ($, on) => {
  const { w } = world(on)
  await bash($)
  w.percent = 60
  w.isError = true
  expect(own((await bash($)).context)).toEqual([])
  w.isError = false
  expect(own((await bash($)).context)).toEqual([crossing('smart', 'acceptable')])
})

test('lines: a crossing seen at a prompt is appended to the prompt context', async ($, on) => {
  const { w } = world(on)
  await prompt($)
  w.percent = 60
  expect((await prompt($, 'sdk', { context: ['theirs'] })).context).toEqual(['theirs', crossing('smart', 'acceptable')])
})

test('lines: a reading session.measure carries reaches Claude at the next carrier', async ($, on) => {
  const { w } = world(on)
  await bash($)
  w.percent = 60
  await $.session.measure({ context: { window: 200_000, percent: 60, tokens: 120_000 }, rateLimits: [], changed: ['context'] } as any)
  // The prompt itself reads nothing, so only the measure can have seen the crossing.
  w.percent = undefined
  expect(own((await prompt($)).context)).toEqual([crossing('smart', 'acceptable')])
})

test('lines: the default line carries the verdict and no number, session id or path', async ($, on) => {
  const { w } = world(on)
  const lines = (await walk($, w, [60, 80])).flat()
  expect(lines).toHaveLength(2)
  for (const line of lines) {
    expect(line).not.toMatch(/\d/)
    expect(line).not.toContain('sess-1')
    expect(line).toContain('context zone')
  }
})

test(
  'composition: a second plugin beneath adds its own line and both arrive',
  {
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
    w.percent = 60
    const context = (await bash($)).context ?? []
    expect(context).toContain('other-mod line')
    expect(own(context)).toEqual([crossing('smart', 'acceptable')])
  },
)

// ---- Approach lines, zones.json additions and line data --------------------------------------

const approach = (zone: string, toward: string) => `context-guard: this session is in the ${zone} context zone, approaching ${toward} ${SRC}.`
const zonesFile = (w: World, zones: unknown, mtimeMs = 1) => {
  w.files[ZONES] = { text: typeof zones === 'string' ? zones : JSON.stringify(zones), mtimeMs }
}

test('approach: one line 5 points before each boundary, then the crossing', async ($, on) => {
  const { w } = world(on)
  expect(await walk($, w, [30, 45, 47, 60, 70, 72, 76])).toEqual([
    [],
    [approach('smart', 'the acceptable zone')],
    [],
    [crossing('smart', 'acceptable')],
    [approach('acceptable', 'the dumb zone')],
    [],
    [`${crossing('acceptable', 'dumb')} ${SAVE}`],
  ])
})

test('approach: once per boundary per cycle; a return to smart opens it again', async ($, on) => {
  const { w } = world(on)
  expect((await walk($, w, [46, 44, 46, 60, 30, 46])).flat()).toEqual([
    approach('smart', 'the acceptable zone'),
    crossing('smart', 'acceptable'),
    approach('smart', 'the acceptable zone'),
  ])
})

test('approach: a reading that jumps past a boundary gets only the crossing', async ($, on) => {
  const { w } = world(on)
  expect((await walk($, w, [30, 60])).flat()).toEqual([crossing('smart', 'acceptable')])
})

test('zones.json: approach_margin moves the approach line, and 0 turns it off', async ($, on) => {
  const { w } = world(on)
  zonesFile(w, { approach_margin: 10 })
  expect((await walk($, w, [30, 39, 41])).flat()).toEqual([approach('smart', 'the acceptable zone')])
  zonesFile(w, { approach_margin: 0 }, 2)
  expect((await walk($, w, [70, 74, 75])).flat()).toEqual([crossing('smart', 'acceptable')])
})

test('zones.json: custom edges move the crossings, and a later edit takes effect at the next call', async ($, on) => {
  const { w } = world(on)
  zonesFile(w, { smart_max_used_percentage: 30, acceptable_max_used_percentage: 60 })
  expect((await walk($, w, [20, 31])).flat()).toEqual([crossing('smart', 'acceptable')])
  zonesFile(w, { smart_max_used_percentage: 10, acceptable_max_used_percentage: 20 }, 2)
  expect((await walk($, w, [31])).flat()).toEqual([`${crossing('acceptable', 'dumb')} ${SAVE}`])
  delete w.files[ZONES]
  expect((await walk($, w, [20, 31])).flat()).toEqual([])
})

test('zones.json: an action at the acceptable zone appears at that crossing and not before', async ($, on) => {
  const { w } = world(on)
  zonesFile(w, { actions: { acceptable: { action: 'handoff' } } })
  expect(await walk($, w, [30, 46, 60])).toEqual([
    [],
    [approach('smart', 'the acceptable zone')],
    [`${crossing('smart', 'acceptable')} context-guard (operator setting for the acceptable zone): hand off at the next clean stopping point.`],
  ])
})

test('zones.json: text replaces the default wording', async ($, on) => {
  const { w } = world(on)
  zonesFile(w, { actions: { dumb: { action: 'save-state', text: 'the plan state goes to PLAN.md' } } })
  expect((await walk($, w, [30, 80])).flat()).toEqual([
    `${crossing('smart', 'dumb')} context-guard (operator setting for the dumb zone): the plan state goes to PLAN.md.`,
  ])
})

test('zones.json: action none at the dumb zone drops the save-state note', async ($, on) => {
  const { w } = world(on)
  zonesFile(w, { actions: { dumb: { action: 'none' } } })
  expect((await walk($, w, [30, 80])).flat()).toEqual([crossing('smart', 'dumb')])
})

test('zones.json: an extra threshold gets its approach line and its line once per cycle', async ($, on) => {
  const { w } = world(on)
  zonesFile(w, { thresholds: [{ at_percent: 60, action: 'handoff' }] })
  const passed = `context-guard: this session passed an operator threshold in the acceptable context zone ${SRC}. ${STEER} context-guard (operator setting for a threshold): hand off at the next clean stopping point.`
  expect(await walk($, w, [30, 52, 56, 60, 58, 61, 30, 61])).toEqual([
    [],
    [crossing('smart', 'acceptable')],
    [approach('acceptable', 'an operator threshold')],
    [passed],
    [],
    [],
    [],
    [crossing('smart', 'acceptable'), passed],
  ])
})

test('zones.json: invalid additions fall back to the defaults', async ($, on) => {
  const { w } = world(on)
  zonesFile(w, { approach_margin: -3, actions: { dumb: { action: 'explode' } }, thresholds: [{ at_percent: 'x', action: 'handoff' }, { at_percent: 40 }] })
  expect((await walk($, w, [30, 45, 80])).flat()).toEqual([approach('smart', 'the acceptable zone'), `${crossing('smart', 'dumb')} ${SAVE}`])
})

test('line data: percent, tokens and window are carried when configured', { options: { zone_line_data: 'zone, percent, tokens, window' } }, async ($, on) => {
  const { w } = world(on)
  expect((await walk($, w, [30, 60])).flat()).toEqual([
    `context-guard: this session crossed from the smart into the acceptable context zone, 60% of the window used, 120000 tokens in context, a 200000-token window ${SRC}. ${STEER}`,
  ])
})

for (const data of ['', 'bogus', 'zone']) {
  test(`line data: "${data}" carries the verdict alone`, { options: { zone_line_data: data } }, async ($, on) => {
    const { w } = world(on)
    expect((await walk($, w, [30, 60])).flat()).toEqual([crossing('smart', 'acceptable')])
  })
}

test('switch: zone_lines_enabled false sends no line', { options: { zone_lines_enabled: false } }, async ($, on) => {
  const { w } = world(on)
  expect((await walk($, w, [30, 45, 60, 80])).flat()).toEqual([])
})

test('switch: context_guard_hooks_enabled false sends no line', { options: { context_guard_hooks_enabled: false } }, async ($, on) => {
  const { w } = world(on)
  expect((await walk($, w, [30, 45, 60, 80])).flat()).toEqual([])
})

// ---- Restatement: compaction, resume, reload, /clear -------------------------------------------

const restated = (zone: string, tail = '') => `context-guard: this session is in the ${zone} context zone ${SRC}. ${STEER}${tail}`
const compact = ($: any, trigger: string, extra: object = {}) => $.session.compact({ trigger, messages: MESSAGES, ...extra } as any)

test('compaction: the verdict is restated once as the evidence-degraded dumb zone, with the save-state note', async ($, on) => {
  const { w } = world(on)
  await walk($, w, [30, 60])
  await compact($, 'manual')
  w.percent = undefined
  expect(own((await prompt($)).context)).toEqual([restated(DEGRADED, ` ${SAVE}`)])
  expect(own((await prompt($)).context)).toEqual([])
  expect(own((await bash($)).context)).toEqual([])
  await compact($, 'auto')
  expect(own((await bash($)).context)).toEqual([restated(DEGRADED, ` ${SAVE}`)])
})

test('compaction: a precompute dispatch restates nothing and degrades nothing', async ($, on) => {
  const { w } = world(on)
  await walk($, w, [30])
  await compact($, 'precompute')
  expect(own((await prompt($)).context)).toEqual([])
  expect((await walk($, w, [60])).flat()).toEqual([crossing('smart', 'acceptable')])
})

test('compaction: a subagent compaction restates nothing', async ($, on) => {
  const { w } = world(on)
  await walk($, w, [30])
  await compact($, 'auto', { agentId: 'agent-1' })
  expect(own((await prompt($)).context)).toEqual([])
})

test('compaction: a compaction a hook skipped restates nothing', async ($, on) => {
  world(on, {}, { HOME }, ['session.compact'])
  on('session.compact', () => ({ skip: 'kept as it is' }))
  await bash($)
  await compact($, 'manual')
  expect(own((await prompt($)).context)).toEqual([])
})

test('compaction: the settings hook marker alone forces the degraded dumb zone, reported once', async ($, on) => {
  const { w } = world(on)
  await walk($, w, [30])
  w.files[`${CTX}/sess-1.compacted`] = { text: '{}', mtimeMs: 1 }
  expect((await walk($, w, [10, 12])).flat()).toEqual([`${crossing('smart', DEGRADED)} ${SAVE}`])
})

test('resume: the verdict is restated once after an in-process resume', async ($, on) => {
  const { w } = world(on)
  await walk($, w, [30])
  await $.session.end({ reason: 'resume', sessionId: 'sess-1', resume: { id: 'sess-1' } } as any)
  w.sid = 'sess-2'
  expect(own((await prompt($)).context)).toEqual([restated('smart')])
  expect(own((await prompt($)).context)).toEqual([])
})

// session.start with earlier turns is a fresh load in a running session: a reload, a worker respawn,
// an enable, or a --resume launch, which session.start cannot tell apart.
test('reload: a load with earlier turns in the smart zone sends nothing', async ($, on) => {
  world(on, { turns: 3 })
  await $.session.start({ surface: 'terminal', isInteractive: true, cwd: '/work' })
  expect(own((await prompt($)).context)).toEqual([])
  expect(own((await bash($)).context)).toEqual([])
})

test('reload: a load with earlier turns past smart restates the verdict once, with no crossing line', async ($, on) => {
  const { w } = world(on, { turns: 3, percent: 60 })
  await $.session.start({ surface: 'terminal', isInteractive: true, cwd: '/work' })
  expect(own((await prompt($)).context)).toEqual([restated('acceptable')])
  expect((await walk($, w, [62])).flat()).toEqual([])
  expect((await walk($, w, [80])).flat()).toEqual([`${crossing('acceptable', 'dumb')} ${SAVE}`])
})

test('reload: the first load of a session sends nothing', async ($, on) => {
  world(on, { turns: 0, percent: 60 })
  await $.session.start({ surface: 'terminal', isInteractive: true, cwd: '/work' })
  expect(own((await prompt($)).context)).toEqual([crossing('unobserved', 'acceptable')])
})

test('/clear: nothing on the first prompt, and the new session starts a fresh cycle', async ($, on) => {
  const { w } = world(on)
  await walk($, w, [30, 80])
  await $.session.end({ reason: 'clear', sessionId: 'sess-1', resume: { id: 'sess-1' } } as any)
  w.sid = 'sess-2'
  w.percent = 2
  expect(own((await prompt($, 'composer')).context)).toEqual([])
  expect((await walk($, w, [60])).flat()).toEqual([crossing('smart', 'acceptable')])
})

// ---- The gate: blocking mode in the mod -----------------------------------------------------

const BLOCKING = (grace: number, extra: object = {}) => ({ options: { zone_hook_mode: 'blocking', zone_gate_grace_calls: grace, ...extra } })
const denial = (tool: string, grace: number) =>
  `context-guard blocking mode (operator setting for the dumb zone): this session is in the dumb context zone and the grace budget of ${grace} matched calls is spent, so new ${tool} work is denied. Handoff-path writes, read-only tools, Bash and Skill calls stay allowed; /session-flow:handoff (if installed) writes a save-point this gate exempts. zone_hook_mode advisory turns the gate off.`
const writes = async ($: any, n: number, path?: string) => {
  const out: (string | undefined)[] = []
  for (let i = 0; i < n; i += 1) out.push((await write($, path)).deny)
  return out
}

test('gate: a typed turn in the dumb zone allows the grace budget, then denies with the reason', BLOCKING(2), async ($, on) => {
  const { w } = world(on, { percent: 80 })
  await prompt($, 'composer')
  expect(await writes($, 3)).toEqual([undefined, undefined, denial('Write', 2)])
  expect(w.ran.filter(t => t === 'Write')).toHaveLength(2)
})

test('gate: Edit, NotebookEdit, Agent and Workflow are gated; Bash, Read and Skill are not and do not count', BLOCKING(0), async ($, on) => {
  const { w } = world(on, { percent: 80 })
  await prompt($, 'composer')
  for (const tool of ['Bash', 'Read', 'Skill']) expect((await $.tool.call({ tool, command: 'x', file_path: '/a' } as any)).deny).toBeUndefined()
  for (const tool of ['Edit', 'NotebookEdit', 'Agent', 'Workflow']) {
    expect((await $.tool.call({ tool, file_path: '/a.ts', notebook_path: '/a.ipynb', prompt: 'x' } as any)).deny).toBe(denial(tool, 0))
  }
  expect(w.ran).toEqual(['Bash', 'Read', 'Skill'])
})

test('gate: writes to a handoff path are allowed and not counted', BLOCKING(1), async ($, on) => {
  world(on, { percent: 80 })
  await prompt($, 'composer')
  expect(await writes($, 3, '/work/.claude/HANDOFF-2026.md')).toEqual([undefined, undefined, undefined])
  expect((await $.tool.call({ tool: 'NotebookEdit', notebook_path: '/n/handoff.ipynb' } as any)).deny).toBeUndefined()
  expect(await writes($, 2)).toEqual([undefined, denial('Write', 1)])
})

test('gate: advisory mode never denies', async ($, on) => {
  world(on, { percent: 95 })
  await prompt($, 'composer')
  expect(await writes($, 25)).toEqual(Array(25).fill(undefined))
})

test('gate: calls dispatched together never overspend the budget', BLOCKING(2), async ($, on) => {
  const { w } = world(on, { percent: 80 })
  await prompt($, 'composer')
  const results = await Promise.all([1, 2, 3, 4, 5].map(() => write($)))
  expect(results.filter(r => r.deny !== undefined)).toHaveLength(3)
  expect(w.ran.filter(t => t === 'Write')).toHaveLength(2)
})

test('gate: leaving the dumb zone or an unknown reading resets the budget', BLOCKING(1), async ($, on) => {
  const { w } = world(on, { percent: 80 })
  await prompt($, 'composer')
  expect(await writes($, 2)).toEqual([undefined, denial('Write', 1)])
  w.percent = 60
  expect(await writes($, 1)).toEqual([undefined])
  w.percent = 80
  expect(await writes($, 2)).toEqual([undefined, denial('Write', 1)])
  w.percent = undefined
  expect(await writes($, 2)).toEqual([undefined, undefined])
  w.percent = 80
  expect(await writes($, 2)).toEqual([undefined, denial('Write', 1)])
})

// ---- Bad option values: the module loads, uses the default and says so once -----------------

// A session raises session.start once per load of the module; the kit leaves it to the test.
const load = ($: any) => $.session.start({ surface: 'terminal', isInteractive: true, cwd: '/work' })
const optionLines = (w: World) => w.logs.filter(l => l.startsWith('context-guard: option '))
const graceLine = (kind: string) => `context-guard: option zone_gate_grace_calls is ${kind}; it reads as the default, 20`
const dataLine = (items: string) =>
  `context-guard: option zone_line_data has an item that is not zone, percent, tokens or window (${items}); it reads as the default, zone`

for (const [grace, kind] of [
  [-1, 'a negative number'],
  [1_000_000_000, 'above 999999999'],
  [1.5, 'not a whole number'],
] as const) {
  test(`options: a grace value of ${grace} loads, gates with the default 20 and logs one line`, BLOCKING(grace), async ($, on) => {
    const { w } = world(on, { percent: 80 })
    await load($)
    await prompt($, 'composer')
    const out = await writes($, 21)
    expect(out.slice(0, 20)).toEqual(Array(20).fill(undefined))
    expect(out[20]).toBe(denial('Write', 20))
    expect(optionLines(w)).toEqual([graceLine(kind)])
  })
}

test('options: zone_line_data with an unknown item loads, carries the verdict alone and logs one line', { options: { zone_line_data: 'zone, percent, bogus' } }, async ($, on) => {
  const { w } = world(on)
  await load($)
  expect((await walk($, w, [30, 60])).flat()).toEqual([crossing('smart', 'acceptable')])
  expect(optionLines(w)).toEqual([dataLine('"bogus"')])
})

test('options: a long unknown zone_line_data item is cut to 40 characters in the log line', { options: { zone_line_data: `zone, ${'x'.repeat(60)}` } }, async ($, on) => {
  const { w } = world(on)
  await load($)
  await walk($, w, [30])
  expect(optionLines(w)).toEqual([dataLine(`"${'x'.repeat(40)}..."`)])
})

test('options: an empty zone_line_data is the default, not a bad value', { options: { zone_line_data: '' } }, async ($, on) => {
  const { w } = world(on)
  await load($)
  await walk($, w, [30, 60])
  expect(optionLines(w)).toEqual([])
})

// A choice outside its list reaches the module as the default, and the engine logs that itself.
test('options: zone_hook_mode outside its list loads as advisory', { options: { zone_hook_mode: 'block', zone_gate_grace_calls: 0 } }, async ($, on) => {
  const { w } = world(on, { percent: 80 })
  await load($)
  await prompt($, 'composer')
  expect(await writes($, 2)).toEqual([undefined, undefined])
  expect(optionLines(w)).toEqual([])
})

test('options: zone_report_mode outside its list loads as automatic', { options: { zone_report_mode: 'quiet' } }, async ($, on) => {
  const { w } = world(on)
  await load($)
  await prompt($, 'composer')
  expect((await walk($, w, [30, 60])).flat()).toEqual([crossing('smart', 'acceptable')])
  expect(w.suggested).toEqual([])
  expect(optionLines(w)).toEqual([])
})

test('options: zone_block_unattended outside its list loads as post-compaction', BLOCKING(0, { zone_block_unattended: 'always' }), async ($, on) => {
  const { w } = world(on, { percent: 80 })
  await load($)
  await prompt($, 'sdk')
  expect(await writes($, 2)).toEqual([undefined, undefined])
  expect(optionLines(w)).toEqual([])
})

test('options: two bad options give two log lines, and later events add none', BLOCKING(-5, { zone_line_data: 'zone, pct' }), async ($, on) => {
  const { w } = world(on, { percent: 30 })
  await load($)
  await prompt($, 'composer')
  await walk($, w, [60, 80])
  await writes($, 3)
  await prompt($, 'composer')
  await compact($, 'manual')
  await load($)
  await walk($, w, [85])
  // In plugin.json's declaration order.
  expect(optionLines(w)).toEqual([dataLine('"pct"'), graceLine('a negative number')])
})

test('gate: an unattended turn gets no pre-compaction denial, and the post-compaction one', BLOCKING(1), async ($, on) => {
  const { w } = world(on, { percent: 80 })
  for (const kind of ['sdk', 'scheduled-trigger', 'task-notification']) {
    await prompt($, kind)
    expect(await writes($, 3)).toEqual([undefined, undefined, undefined])
  }
  await compact($, 'auto')
  w.percent = 10
  await prompt($, 'sdk')
  expect(await writes($, 2)).toEqual([undefined, denial('Write', 1)])
})

test('gate: a turn with no prompt seen yet counts as unattended', BLOCKING(0), async ($, on) => {
  world(on, { percent: 80 })
  expect(await writes($, 2)).toEqual([undefined, undefined])
})

test('gate: zone_block_unattended same-as-typed denies in unattended turns too', BLOCKING(1, { zone_block_unattended: 'same-as-typed' }), async ($, on) => {
  world(on, { percent: 80 })
  await prompt($, 'sdk')
  expect(await writes($, 2)).toEqual([undefined, denial('Write', 1)])
})

test('gate: a compaction resets the budget, a precompute one does not', BLOCKING(1), async ($, on) => {
  world(on, { percent: 80 })
  await prompt($, 'composer')
  expect(await writes($, 2)).toEqual([undefined, denial('Write', 1)])
  await compact($, 'precompute')
  expect(await writes($, 1)).toEqual([denial('Write', 1)])
  await compact($, 'manual')
  expect(await writes($, 2)).toEqual([undefined, denial('Write', 1)])
})

test('gate: after a compaction the zone counts as dumb whatever the reading', BLOCKING(0), async ($, on) => {
  const { w } = world(on, { percent: 10 })
  await prompt($, 'composer')
  expect(await writes($, 1)).toEqual([undefined])
  w.files[`${CTX}/sess-1.compacted`] = { text: '{}', mtimeMs: 1 }
  expect(await writes($, 1)).toEqual([denial('Write', 0)])
})

test('gate: a subagent write is judged by the session zone and counts', BLOCKING(1), async ($, on) => {
  world(on, { percent: 80 })
  await prompt($, 'composer')
  expect((await write($, '/work/a.ts', 'agent-1')).deny).toBeUndefined()
  expect((await write($, '/work/a.ts', 'agent-1')).deny).toBe(denial('Write', 1))
})

test('gate: context_guard_hooks_enabled false turns the gate off', BLOCKING(0, { context_guard_hooks_enabled: false }), async ($, on) => {
  world(on, { percent: 80 })
  await prompt($, 'composer')
  expect(await writes($, 2)).toEqual([undefined, undefined])
})

test('gate: a block action in zones.json arms it without zone_hook_mode, and an action there overrides the option', async ($, on) => {
  const { w } = world(on, { percent: 80 })
  zonesFile(w, { actions: { dumb: { action: 'block' } } })
  await prompt($, 'composer')
  expect((await write($)).deny).toBeUndefined()
  expect((await writes($, 19)).every(d => d === undefined)).toBe(true)
  expect((await write($)).deny).toContain('the grace budget of 20 matched calls is spent')
})

test('gate: an action other than block at the dumb zone in zones.json leaves blocking mode inert', BLOCKING(0), async ($, on) => {
  const { w } = world(on, { percent: 80 })
  zonesFile(w, { actions: { dumb: { action: 'handoff' } } })
  await prompt($, 'composer')
  expect(await writes($, 2)).toEqual([undefined, undefined])
})

test('gate: a block action at the acceptable zone gates there', async ($, on) => {
  const { w } = world(on, { percent: 60 })
  zonesFile(w, { actions: { acceptable: { action: 'block' } } })
  await prompt($, 'composer')
  expect(await writes($, 21)).toEqual([...Array(20).fill(undefined), expect.stringContaining('this session is in the acceptable context zone')])
})

test('gate: blocking mode adds its sentence to the dumb-zone line, before the save-state note', BLOCKING(20), async ($, on) => {
  const { w } = world(on)
  expect((await walk($, w, [30, 80])).flat()).toEqual([
    `${crossing('smart', 'dumb')} context-guard (operator setting for the dumb zone): new Write, Edit, NotebookEdit, Agent and Workflow calls are denied past the grace budget; handoff-path writes, reads, Bash and Skill calls stay allowed. ${SAVE}`,
  ])
})

test('gate: fails open when the reading throws', BLOCKING(0), async ($, on) => {
  const { w } = world(on, {}, { HOME }, ['session.usage'])
  on('session.usage', () => {
    throw new Error('usage unavailable')
  })
  await prompt($, 'composer')
  expect(await writes($, 2)).toEqual([undefined, undefined])
  expect(w.ran).toEqual(['Write', 'Write'])
})

// ---- Operator mode, the operator's menu, the band, the command and the pull tool ------------

const OPERATOR = { options: { zone_report_mode: 'operator' } }
const MENU = (from: string, to: string) =>
  `context-guard: context zone ${from} → ${to}. Response quality can degrade as context fills (bands tunable: zones.json). Continuation options, yours to choose: continue; /compact; /clear; /session-flow:handoff (if installed) or a hand-written resume note, then /clear. To pick one, route the next step with /session-flow:workflow (if installed); without it, see https://code.claude.com/docs/en/context-window#when-your-context-fills-up.`
const notice = async ($: any) => {
  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  const found = await ui.find({ type: 'Text', text: /notice/ })
  await ui.unmount()
  return found?.text
}

test('operator mode: a typed turn holds the line and offers it at turn end with an empty box, with a band notice', OPERATOR, async ($, on) => {
  const { w } = world(on)
  await prompt($, 'composer')
  w.percent = 60
  expect(own((await bash($)).context)).toEqual([])
  await $.turn.complete({ text: 'done', reason: 'answer' } as any)
  const offered = `FYI, ${crossing('smart', 'acceptable')}`
  expect(w.suggested).toEqual([offered])
  expect(await notice($)).toBe(`context-guard notice: ${offered}`)
  expect(own((await prompt($, 'composer')).context)).toEqual([])
  expect(await notice($)).toBeUndefined()
})

test('operator mode: with text in the box only the notice shows, and the offer comes back once the box empties', OPERATOR, async ($, on) => {
  const { w, clock } = world(on, { box: 'half typed' })
  await prompt($, 'composer')
  w.percent = 60
  await bash($)
  await $.turn.complete({ text: 'done', reason: 'answer' } as any)
  expect(w.suggested).toEqual([])
  expect(await notice($)).toBe(`context-guard notice: FYI, ${crossing('smart', 'acceptable')}`)
  w.box = ''
  await clock.advance(5_000)
  expect(w.suggested).toHaveLength(1)
  await clock.advance(20_000)
  expect(w.suggested).toHaveLength(1)
})

test('operator mode: a Remote Control bridge turn counts as a person', OPERATOR, async ($, on) => {
  const { w } = world(on)
  await prompt($, 'bridge')
  w.percent = 60
  expect(own((await bash($)).context)).toEqual([])
  await $.turn.complete({ text: 'done', reason: 'answer' } as any)
  expect(w.suggested).toHaveLength(1)
})

test('operator mode: SDK, loop and notification turns get the automatic line', OPERATOR, async ($, on) => {
  const { w } = world(on)
  for (const [kind, p] of [['sdk', 47], ['scheduled-trigger', 60], ['task-notification', 80]] as const) {
    await prompt($, kind)
    w.percent = p
    expect(own((await bash($)).context)).toHaveLength(1)
  }
})

test('operator mode: a notification delivered into a typed turn keeps the line held', OPERATOR, async ($, on) => {
  const { w } = world(on)
  await prompt($, 'composer')
  await prompt($, 'task-notification', { turnId: 'turn-1' })
  w.percent = 60
  expect(own((await bash($)).context)).toEqual([])
})

test('operator mode: a typed turn with no drawing surface gets the automatic line', OPERATOR, async ($, on) => {
  const { w } = world(on, { surfaces: [] })
  await prompt($, 'composer')
  w.percent = 60
  expect(own((await bash($)).context)).toEqual([crossing('smart', 'acceptable')])
})

// A shown suggestion nobody took (a --bg launch turn reads as typed) is handed to Claude at the next
// turn no person started, as the ordinary automatic line.
const shownThenUntaken = async ($: any, w: World, p = 60) => {
  await prompt($, 'composer')
  w.percent = p
  await bash($)
  await $.turn.complete({ text: 'done', reason: 'answer' } as any)
  expect(w.suggested).toHaveLength(1)
}

for (const kind of ['scheduled-trigger', 'task-notification', 'sdk']) {
  test(`hand-off: a shown suggestion not taken reaches Claude at the next ${kind} turn, once, and clears the notice`, OPERATOR, async ($, on) => {
    const { w } = world(on)
    await shownThenUntaken($, w)
    expect((await prompt($, kind, { context: ['theirs'] })).context).toEqual(['theirs', crossing('smart', 'acceptable')])
    expect(await notice($)).toBeUndefined()
    expect(own((await prompt($, kind)).context)).toEqual([])
    expect(own((await bash($)).context)).toEqual([])
  })
}

test('hand-off: a new typed turn clears it unsent, and a later unattended turn gets nothing', OPERATOR, async ($, on) => {
  const { w } = world(on)
  await shownThenUntaken($, w)
  expect(own((await prompt($, 'composer')).context)).toEqual([])
  expect(await notice($)).toBeUndefined()
  expect(own((await prompt($, 'scheduled-trigger')).context)).toEqual([])
})

test('hand-off: a prompt delivered into a running turn changes nothing', OPERATOR, async ($, on) => {
  const { w } = world(on)
  await shownThenUntaken($, w)
  expect(own((await prompt($, 'task-notification', { turnId: 'turn-1' })).context)).toEqual([])
  expect(await notice($)).toBeDefined()
  expect(own((await prompt($, 'scheduled-trigger')).context)).toEqual([crossing('smart', 'acceptable')])
})

test('hand-off: a restatement due at the same prompt merges with the held line into one', OPERATOR, async ($, on) => {
  const { w } = world(on)
  await shownThenUntaken($, w)
  await compact($, 'auto')
  expect(own((await prompt($, 'scheduled-trigger')).context)).toEqual([restated(DEGRADED, ` ${SAVE}`)])
})

test('operator mode: a suggestion that cannot show goes to Claude at the next prompt', OPERATOR, async ($, on) => {
  const { w } = world(on, { shown: false })
  await prompt($, 'composer')
  w.percent = 60
  await bash($)
  await $.turn.complete({ text: 'done', reason: 'answer' } as any)
  expect(own((await prompt($, 'composer')).context)).toEqual([crossing('smart', 'acceptable')])
})

test('menu: a crossing in automatic mode shows the operator the continuation menu, never Claude', async ($, on) => {
  const { w } = world(on)
  const lines = (await walk($, w, [30, 47, 60])).flat()
  expect(w.logs).toEqual([MENU('smart', 'acceptable')])
  expect(await notice($)).toBe(`context-guard notice: ${MENU('smart', 'acceptable')}`)
  expect(lines.join(' ')).not.toContain('/compact')
  await prompt($, 'composer')
  expect(await notice($)).toBeUndefined()
})

test('menu: shown with zone lines off, not with the hooks switch off', { options: { zone_lines_enabled: false } }, async ($, on) => {
  const { w } = world(on)
  await walk($, w, [30, 80])
  expect(w.logs).toEqual([MENU('smart', 'dumb')])
})

test('menu: the hooks switch off shows nothing', { options: { context_guard_hooks_enabled: false } }, async ($, on) => {
  const { w } = world(on)
  await walk($, w, [30, 80])
  expect(w.logs).toEqual([])
  expect(await notice($)).toBeUndefined()
})

const bandRow = async ($: any, surface: 'terminal' | 'desktop' = 'terminal') => {
  const ui = await $.ui.mount({ ...BAND, surface })
  const found = await ui.find({ type: 'Text', text: / ctx / })
  const beneath = await ui.find({ type: 'Text', text: 'drawn beneath' })
  await ui.unmount()
  return { row: found?.text, beneath: beneath !== undefined }
}

test('band: a dash before a reading, the figure and zone after, kept above what is drawn beneath', async ($, on) => {
  const { w } = world(on, { percent: undefined })
  for (const surface of ['terminal', 'desktop'] as const) expect(await bandRow($, surface)).toEqual({ row: '[Opus 5.5] ctx -', beneath: true })
  w.percent = 23
  await bash($)
  for (const surface of ['terminal', 'desktop'] as const) expect(await bandRow($, surface)).toEqual({ row: '[Opus 5.5] ctx 23% (smart)', beneath: true })
  w.files[`${CTX}/sess-1.compacted`] = { text: '{}', mtimeMs: 1 }
  await bash($)
  expect((await bandRow($)).row).toBe('[Opus 5.5] ctx 23% (dumb, compacted)')
})

test('band: the option hides it and the band command shows and hides it', { options: { context_guard_band: false } }, async ($, on) => {
  world(on)
  await bash($)
  expect((await bandRow($)).row).toBeUndefined()
  expect((await $.command.run({ command: 'band', args: 'show' } as any)).text).toBe('context-guard: band row shown for this session')
  expect((await bandRow($)).row).toBe('[Opus 5.5] ctx 30% (smart)')
  expect((await $.command.run({ command: 'band', args: '' } as any)).text).toBe('context-guard: band row hidden for this session')
  expect((await bandRow($)).row).toBeUndefined()
})

test('status tool: a refused registration is logged once, and lines, gate, band and writes carry on', BLOCKING(0), async ($, on) => {
  const debug: string[] = []
  const { w } = world(on, {}, { HOME }, ['tool.register', 'ui.log', 'tool.list'])
  on('tool.register', () => {
    throw new Error('refused: policy allows only listed MCP servers')
  })
  on('tool.list', () => ({ value: [] }))
  on('ui.log', ($: unknown, e: { text: string; to?: string }) => {
    ;(e.to === 'debug' ? debug : w.logs).push(e.text)
    return { value: undefined }
  })
  await $.session.start({ surface: 'terminal', isInteractive: true, cwd: '/work' })
  await $.session.end({ reason: 'clear', sessionId: 'sess-1', resume: { id: 'sess-1' } } as any)
  await prompt($, 'composer')
  expect(debug.filter(l => l.includes('status tool'))).toHaveLength(1)
  expect(debug.filter(l => l.includes('status tool'))[0]).toMatch(/^context-guard: the status tool could not register: /)
  expect((await walk($, w, [30, 80])).flat()).toEqual([`${crossing('smart', 'dumb')} context-guard (operator setting for the dumb zone): new Write, Edit, NotebookEdit, Agent and Workflow calls are denied past the grace budget; handoff-path writes, reads, Bash and Skill calls stay allowed. ${SAVE}`])
  expect((await write($)).deny).toBe(denial('Write', 0))
  expect(w.runs.length).toBeGreaterThan(0)
  expect((await bandRow($)).row).toBe('[Opus 5.5] ctx 80% (dumb)')
})

test('session.start registers the status tool and the band command', async ($, on) => {
  const registered: string[] = []
  world(on, {}, { HOME }, ['tool.register', 'command.register'])
  on('tool.register', ($: unknown, e: { name: string }) => (registered.push(e.name), { value: { tool: e.name } }))
  on('command.register', ($: unknown, e: { name: string }) => (registered.push(`/${e.name}`), { value: { command: e.name } }))
  await $.session.start({ surface: 'terminal', isInteractive: true, cwd: '/work' })
  expect(registered.sort()).toEqual(['/band', 'status'])
})

test('/clear: the first prompt after it registers the status tool again when it is gone', async ($, on) => {
  const registered: string[] = []
  let listed: string[] = ['mcp__context-guard__status']
  world(on, {}, { HOME }, ['tool.register', 'command.register', 'tool.list'])
  on('tool.list', () => ({ value: listed.map(name => ({ name, description: "", mcp: undefined }) as any) }))
  on('tool.register', ($: unknown, e: { name: string }) => (registered.push(e.name), { value: { tool: e.name } }))
  on('command.register', ($: unknown, e: { name: string }) => (registered.push(`/${e.name}`), { value: { command: e.name } }))
  await prompt($, 'composer')
  await $.session.end({ reason: 'clear', sessionId: 'sess-1', resume: { id: 'sess-1' } } as any)
  await prompt($, 'composer')
  expect(registered).toEqual([])
  await $.session.end({ reason: 'clear', sessionId: 'sess-1', resume: { id: 'sess-1' } } as any)
  listed = []
  await prompt($, 'composer')
  expect(registered.sort()).toEqual(['/band', 'status'])
})

test('pull tool: the latest figures and zone, with no line attached, whatever the switches', { options: { context_guard_hooks_enabled: false } }, async ($, on) => {
  world(on, { percent: 60, output: 900 })
  const answer = await $.tool.call({ tool: 'mcp__context-guard__status' } as any)
  expect(answer.context).toBeUndefined()
  expect(JSON.parse(String(answer.result))).toEqual({
    source: 'the last API response',
    zone: 'acceptable',
    evidence_degraded: false,
    used_percentage: 60,
    total_input_tokens: 120_000,
    total_output_tokens: 900,
    context_window_size: 200_000,
    bands: { smart_max_used_percentage: 50, acceptable_max_used_percentage: 75 },
    approach_margin: 5,
    gate: { mode: 'advisory', grace_calls: 20, calls_counted: 0 },
  })
})

test('pull tool: unknown before the first response, and the degraded dumb zone after a compaction', async ($, on) => {
  const { w } = world(on, { percent: undefined })
  expect(JSON.parse(String((await $.tool.call({ tool: 'mcp__context-guard__status' } as any)).result)).zone).toBe('unknown')
  await compact($, 'manual')
  const after = JSON.parse(String((await $.tool.call({ tool: 'mcp__context-guard__status' } as any)).result))
  expect([after.zone, after.evidence_degraded]).toEqual(['dumb', true])
  void w
})

// ---- Hook telemetry (docs/conventions/hook-telemetry) -----------------------------------------

const SINK = '/opt/sink.sh'
// The sink receives one envelope per dispatch on stdin; these are the dispatches the world recorded.
const envelopes = (w: World, sink = SINK) => w.runs.filter(r => r.argv[0] === sink && r.argv.length === 1).map(r => JSON.parse(String(r.stdin)))
// The envelope schema's required fields and types (envelope.schema.json), checked by hand.
const checkEnvelope = (e: Record<string, unknown>) => {
  expect(e.schema_version).toBe('1.1')
  expect(String(e.timestamp)).toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/)
  expect(typeof e.hook).toBe('string')
  expect(typeof e.hook_event).toBe('string')
  expect(typeof e.status).toBe('string')
  expect(Number.isInteger(e.duration_ms) && (e.duration_ms as number) >= 0).toBe(true)
  expect(typeof e.data === 'object' && e.data !== null && !Array.isArray(e.data)).toBe(true)
  for (const key of ['session_id', 'prompt_id', 'tool_use_id', 'agent_id']) {
    if (key in e) expect(String(e[key])).toMatch(/^[A-Za-z0-9._-]+$/)
  }
}

test('telemetry: one zone-crossing-inject envelope per fire that sends lines, none on other calls', async ($, on) => {
  const { w } = world(on, {}, { HOME, HOOK_TELEMETRY_SINK: SINK })
  await walk($, w, [30, 31, 60, 62, 55])
  await $.tool.call({ tool: 'Bash', command: 'true', tool_use_id: 'toolu_1' } as any)
  w.percent = 80
  await $.tool.call({ tool: 'Bash', command: 'true', tool_use_id: 'toolu_2' } as any)
  const sent = envelopes(w)
  for (const e of sent) checkEnvelope(e)
  expect(sent.map(e => [e.hook, e.hook_event, e.status, e.session_id, e.data])).toEqual([
    ['zone-crossing-inject', 'tool.call', 'ok', 'sess-1', { zone: 'acceptable', previous: 'smart', armed: 'smart', injected: true }],
    ['zone-crossing-inject', 'tool.call', 'ok', 'sess-1', { zone: 'dumb', previous: 'acceptable', armed: 'acceptable', injected: true }],
  ])
  expect(sent[1].tool_use_id).toBe('toolu_2')
})

test('telemetry: a line sent at a prompt is recorded with that event', async ($, on) => {
  const { w } = world(on, {}, { HOME, HOOK_TELEMETRY_SINK: SINK })
  await prompt($)
  w.percent = 60
  await prompt($)
  expect(envelopes(w).map(e => [e.hook_event, e.data.zone])).toEqual([['prompt.submit', 'acceptable']])
})

test('telemetry: a relative sink path resolves against the session project root', async ($, on) => {
  const { w } = world(on, {}, { HOME, HOOK_TELEMETRY_SINK: '.claude/hooks/sink.sh' })
  await walk($, w, [30, 60])
  expect(envelopes(w, '/repo/.claude/hooks/sink.sh')).toHaveLength(1)
})

test('telemetry: one zone-gate envelope per deny, blocked, with the budget', BLOCKING(1), async ($, on) => {
  const { w } = world(on, { percent: 80 }, { HOME, HOOK_TELEMETRY_SINK: SINK })
  await prompt($, 'composer')
  w.runs = []
  await writes($, 3)
  const gate = envelopes(w).filter(e => e.hook === 'zone-gate')
  for (const e of gate) checkEnvelope(e)
  expect(gate.map(e => [e.hook_event, e.status, e.data])).toEqual([
    ['tool.call', 'blocked', { zone: 'dumb', grace: 1, calls_seen: 2 }],
    ['tool.call', 'blocked', { zone: 'dumb', grace: 1, calls_seen: 3 }],
  ])
})

test('telemetry: an operator-mode suggestion offered is recorded once', OPERATOR, async ($, on) => {
  const { w } = world(on, {}, { HOME, HOOK_TELEMETRY_SINK: SINK })
  await prompt($, 'composer')
  w.percent = 60
  await bash($)
  expect(envelopes(w)).toEqual([])
  await $.turn.complete({ text: 'done', reason: 'answer' } as any)
  const sent = envelopes(w)
  for (const e of sent) checkEnvelope(e)
  expect(sent.map(e => [e.hook_event, e.data])).toEqual([['turn.complete', { zone: 'acceptable', previous: 'smart', armed: 'smart', injected: false, suggested: true }]])
})

test('telemetry: no sink set, nothing dispatched', BLOCKING(0), async ($, on) => {
  const { w } = world(on, { percent: 80 })
  await prompt($, 'composer')
  await writes($, 2)
  expect(w.runs.every(r => r.argv[0] === 'node')).toBe(true)
})

// ---- The snapshot writer ----------------------------------------------------------------------

const TARGET = `${CTX}/sess-1.json`
const bodies = (w: World) => w.runs.map(r => JSON.parse(String(r.stdin)))

test('snapshot: the tee contract body on stdin, the per-session target and --prune in argv', async ($, on) => {
  const { w } = world(on)
  await bash($)
  expect(w.runs.map(r => r.argv)).toEqual([['node', expect.stringMatching(/\/lib\/write-snapshot\.mjs$/), TARGET, '--prune']])
  expect(w.runs[0]?.stdin).toBe(
    JSON.stringify({
      captured_at: '2026-10-03T18:00:00Z',
      session_id: 'sess-1',
      cli_version: '2.1.288',
      context_window: {
        total_input_tokens: 60_000,
        total_output_tokens: 0,
        context_window_size: 200_000,
        used_percentage: 30,
        remaining_percentage: 70,
        current_usage: { input_tokens: 5, output_tokens: 0, cache_creation_input_tokens: 0, cache_read_input_tokens: 0 },
      },
    }),
  )
})

test('snapshot: before the first response the body carries the nulls the status line does', async ($, on) => {
  const { w } = world(on, { percent: undefined })
  await bash($)
  expect(bodies(w)[0].context_window).toEqual({ context_window_size: 200_000, used_percentage: null, remaining_percentage: null, current_usage: null })
})

test('floor: an unchanged body is not rewritten within 60 s, then is, floor-bound; a changed one writes at once', async ($, on) => {
  const { w, clock } = world(on)
  await bash($)
  await clock.advance(59_000)
  await bash($)
  expect(w.runs).toHaveLength(1)
  await clock.advance(1_000)
  await bash($)
  expect(w.runs[1]?.argv.slice(-3)).toEqual(['--prune', '--floor', '60'])
  w.percent = 31
  await bash($)
  expect(w.runs).toHaveLength(3)
  expect(w.runs[2]?.argv).not.toContain('--floor')
})

test('budget: no process on calls that write nothing, one per write, none for the gate', BLOCKING(5), async ($, on) => {
  const { w } = world(on, { percent: 80 })
  await prompt($, 'composer')
  expect(w.runs).toHaveLength(0)
  await bash($)
  expect(w.runs).toHaveLength(1)
  for (let i = 0; i < 20; i += 1) await bash($)
  await writes($, 7)
  expect(w.runs).toHaveLength(1)
})

test('snapshot: a subagent tool call and session.measure write too', async ($, on) => {
  const { w } = world(on)
  await bash($, 'agent-1')
  expect(w.runs).toHaveLength(1)
  w.percent = 40
  await $.session.measure({ context: { window: 200_000, percent: 40, tokens: 80_000 }, rateLimits: [], changed: ['context'] } as any)
  expect(bodies(w).map(b => b.context_window.used_percentage)).toEqual([30, 40])
})

test('snapshot: session.end writes what the floor held back', async ($, on) => {
  const { w, clock } = world(on)
  await bash($)
  await clock.advance(61_000)
  await $.session.end({ reason: 'other', sessionId: 'sess-1', resume: { id: 'sess-1' } } as any)
  expect(w.runs).toHaveLength(2)
})

const end = ($: any, reason: string, sessionId = 'sess-1') => $.session.end({ reason, sessionId, resume: { id: sessionId } } as any)

test('snapshot: session.end with no usage left writes the last populated body, not a blank one', async ($, on) => {
  const { w, clock } = world(on)
  await bash($)
  await clock.advance(61_000)
  w.percent = undefined
  await end($, 'other')
  expect(w.runs).toHaveLength(2)
  expect(bodies(w).map(b => b.context_window.used_percentage)).toEqual([30, 30])
})

test('snapshot: a reading that comes back empty never replaces a populated body', async ($, on) => {
  const { w, clock } = world(on)
  await bash($)
  w.percent = undefined
  await bash($)
  await clock.advance(61_000)
  await bash($)
  expect(bodies(w).map(b => b.context_window.used_percentage)).toEqual([30, 30])
})

test('snapshot: a session that never read its usage writes nothing at session.end', async ($, on) => {
  const { w } = world(on)
  await end($, 'other')
  expect(w.runs).toEqual([])
})

test('snapshot: after /clear the new session writes its own populated body at its first carrier', async ($, on) => {
  const { w } = world(on)
  await bash($)
  await end($, 'clear')
  w.sid = 'sess-2'
  w.percent = 5
  await bash($)
  // The end flush is the same body inside the 60 s floor, so it starts no process.
  expect(w.runs.map(r => r.argv[2])).toEqual([TARGET, `${CTX}/sess-2.json`])
  expect(bodies(w).map(b => [b.session_id, b.context_window.used_percentage])).toEqual([
    ['sess-1', 30],
    ['sess-2', 5],
  ])
})

test('timer: rewrites every 60 s inside a turn, never outside one', async ($, on) => {
  const { w, clock } = world(on)
  await bash($)
  await clock.advance(600_000)
  expect(w.runs).toHaveLength(1)
  await $.turn.start({ text: 'go', turnId: 'turn-1' })
  await clock.advance(60_000)
  expect(w.runs).toHaveLength(2)
  await clock.advance(60_000)
  expect(w.runs).toHaveLength(3)
  await $.turn.complete({ text: 'done', reason: 'answer' } as any)
  await clock.advance(600_000)
  expect(w.runs).toHaveLength(3)
})

test('switch: writes continue with the zone lines and the hooks switch off', { options: { zone_lines_enabled: false, context_guard_hooks_enabled: false } }, async ($, on) => {
  const { w } = world(on)
  await bash($)
  w.percent = 60
  await bash($)
  expect(w.runs).toHaveLength(2)
})

for (const sid of ['a.b', '../x', 'a b', '']) {
  test(`snapshot: a session id outside [A-Za-z0-9_-] (${JSON.stringify(sid)}) is never written`, async ($, on) => {
    const { w } = world(on, { sid })
    await bash($)
    expect(w.runs).toEqual([])
  })
}

test('snapshot: falls back to USERPROFILE when HOME is unset, and writes nothing with neither', async ($, on) => {
  const { w } = world(on, {}, { USERPROFILE: 'C:/Users/u' })
  await bash($)
  expect(w.runs[0]?.argv[2]).toBe('C:/Users/u/.claude/context-guard/context/sess-1.json')
})

test('snapshot: no home directory, no write, and the lines still arrive', async ($, on) => {
  const { w } = world(on, {}, {})
  expect((await walk($, w, [30, 60])).flat()).toEqual([crossing('smart', 'acceptable')])
  expect(w.runs).toEqual([])
})

test('fallback: where $.process.run is unavailable, nothing is written, it is logged once, and the line and result stand', async ($, on) => {
  const debug: string[] = []
  const { w } = world(on, {}, { HOME }, ['process.run', 'ui.log'])
  on('process.run', () => {
    throw new Error('process.run is CLI only')
  })
  on('ui.log', ($: unknown, e: { text: string; to?: string }) => {
    ;(e.to === 'debug' ? debug : w.logs).push(e.text)
    return { value: undefined }
  })
  await bash($)
  w.percent = 60
  const called = await bash($)
  expect(called.text).toBe('ok')
  expect(own(called.context)).toEqual([crossing('smart', 'acceptable')])
  // A stub that throws is skipped, so the engine answers that nothing implements process.run.
  expect(debug).toHaveLength(1)
  expect(debug[0]).toMatch(/^context-guard: snapshot write did not run: /)
})

test('snapshot: a failed write is logged once; a skip by rule is not', async ($, on) => {
  const debug: string[] = []
  let exit = 3
  const { w } = world(on, {}, { HOME }, ['process.run', 'ui.log'])
  on('process.run', () => ({ value: { exitCode: exit, stdout: exit === 3 ? 'skip floor' : '', stderr: exit === 1 ? 'write-snapshot: rename failed' : '', isStdoutTruncated: false, isStderrTruncated: false } }))
  on('ui.log', ($: unknown, e: { text: string; to?: string }) => {
    if (e.to === 'debug') debug.push(e.text)
    return { value: undefined }
  })
  await bash($)
  exit = 1
  for (const p of [31, 32]) {
    w.percent = p
    await bash($)
  }
  expect(debug).toEqual(['context-guard: snapshot write failed (exit 1): write-snapshot: rename failed'])
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

test('fail open: a prompt passes through with its context when the hook throws', async ($, on) => {
  world(on, {}, { HOME }, ['session.usage'])
  on('session.usage', () => {
    throw new Error('usage unavailable')
  })
  expect((await prompt($, 'sdk', { context: ['theirs'] })).context).toEqual(['theirs'])
})
