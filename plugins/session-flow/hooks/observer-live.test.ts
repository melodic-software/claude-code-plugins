import { expect, mock, test as kitTest } from 'claude-code/testing'

import { buildPrompt, parseReply, checksToSkipAfterIgnored } from './observer-live.ts'

const ON = { options: { observer_enabled: true } }
const test = (name: string, ...rest: [any] | [any, any]) =>
  rest.length === 1 ? kitTest(name, ON, rest[0]) : kitTest(name, { ...rest[0], options: { ...ON.options, ...rest[0].options } }, rest[1])

const SID = 'sess-1'
const DATA = '/data'
const PROJECT = '/proj'
const LIVE = `${DATA}/session-flow-observer/live-${SID}.jsonl`
const LEDGERS = `${PROJECT}/.work/running-retros`
const FINDING = 'finding: Merged without reading the pr-verify verdict.\ncategory: verification\nrule: R6 merge only after the verdict (handoff Current rules)\nevidence: gh pr merge ran before monitor-poll --verdict'
const USAGE = { input_tokens: 10, output_tokens: 5, cache_read_input_tokens: 900, cache_creation_input_tokens: 0 }
const BAND = {
  plugin: 'session-flow',
  component: 'AbovePrompt',
  viewport: { columns: 120, rows: 40 },
  props: { hasSurvey: false, isWorking: false, maxRows: 10, bodyColumns: 120, scroll: { offset: 0, bodyRows: 9 }, view: {} },
} as const

type World = {
  sid: string
  files: Record<string, string>
  store: Record<string, unknown>
  forks: string[]
  replies: (() => Promise<object>)[]
  fills: string[]
}

const world = (on: any, env: Record<string, string> = {}) => {
  const w: World = { sid: SID, files: {}, store: {}, forks: [], replies: [], fills: [] }
  mock.clock(on, { now: 1_791_050_400_000 })
  mock.env(on, env)
  on('session.id', () => ({ value: w.sid }))
  on('process.hookEnv', () => ({ value: { CLAUDE_PLUGIN_DATA: DATA, CLAUDE_PROJECT_DIR: PROJECT } }))
  on('fs.exists', ($: unknown, e: { path: string }) => ({ value: e.path in w.files || Object.keys(w.files).some(f => f.startsWith(`${e.path}/`)) }))
  on('fs.read', ($: unknown, e: { path: string }) => {
    if (!(e.path in w.files)) throw new Error(`ENOENT: ${e.path}`)
    return { value: w.files[e.path] }
  })
  on('fs.write', ($: unknown, e: { path: string; text: string }) => ((w.files[e.path] = e.text), { value: undefined }))
  on('fs.list', ($: unknown, e: { path: string }) => ({
    value: Object.keys(w.files)
      .filter(f => f.startsWith(`${e.path}/`) && !f.slice(e.path.length + 1).includes('/'))
      .map(f => ({ name: f.slice(e.path.length + 1), kind: 'file', size: 0, mtimeMs: 0, isLink: false })),
  }))
  on('store.get', ($: unknown, e: { key: string }) => ({ value: w.store[e.key] }))
  on('store.set', ($: unknown, e: { key: string; value: unknown }) => ((w.store[e.key] = e.value), { value: undefined }))
  on('model.fork', async ($: unknown, e: { prompt: string }) => {
    w.forks.push(e.prompt)
    const reply = w.replies.shift()
    return { value: reply ? await reply() : { isAnswered: true, text: 'finding: none', usage: USAGE } }
  })
  on('prompt.fill', ($: unknown, e: { text: string }) => (w.fills.push(e.text), { isFilled: true, text: e.text, cursor: e.text.length }))
  on('session.redact', ($: unknown, e: { text: string }) => ({ value: e.text.replace(/sk-[a-z0-9]+/g, '<REDACTED: API key>') }))
  on('ui.invalidate', () => ({ value: undefined }))
  on('session.start', () => ({ cwd: PROJECT }))
  on('session.end', ($: unknown, e: object) => e)
  on('turn.start', ($: unknown, e: { turnId: string }) => ({ turnId: e.turnId }))
  on('turn.complete', () => ({ text: 'done' }))
  on('tool.call', () => ({ result: { stdout: 'ok' }, text: 'ok' }))
  on('prompt.submit', ($: unknown, e: { text: string }) => ({ text: e.text }))
  on('turn.step', async function* ($: unknown, e: { turnId: string; index: number }) {
    return { turnId: e.turnId, index: e.index, answer: 'ok', toolUses: [], stopReason: 'end_turn', usage: null }
  })
  on('ui.render', () => ({ type: 'Text', props: {}, children: ['beneath'] }))
  return w
}

const settle = () => new Promise(r => setTimeout(r, 0))
const start = ($: any, isInteractive = true) => $.session.start({ cwd: PROJECT, surface: isInteractive ? 'terminal' : null, isInteractive })
const turn = ($: any, turnId: string) => $.turn.start({ turnId, prompt: 'go' })
const step = async ($: any, turnId: string, index: number, agentId?: string) => {
  for await (const c of $.turn.step({ turnId, index, model: 'm', messageCount: 1, ...(agentId ? { agentId } : {}) })) void c
  await settle()
}
const steps = async ($: any, turnId: string, upTo: number) => {
  for (let i = 0; i <= upTo; i++) await step($, turnId, i)
}
const complete = async ($: any, turnId: string, extra: object = {}) => {
  await $.turn.complete({ turnId, answer: 'done', durationMs: 1, isAborted: false, reason: 'answer', ...extra })
  await settle()
}
const bash = ($: any) => $.tool.call({ tool: 'Bash', command: 'true' })
const person = ($: any) => $.prompt.submit({ text: 'next', wait: false, origin: { kind: 'composer' } })
const live = (w: World) => (w.files[LIVE] ?? '').trim().split('\n').filter(Boolean).map(l => JSON.parse(l))
const ledgerFiles = (w: World) => Object.keys(w.files).filter(f => f.startsWith(`${LEDGERS}/`))
const answer = (text: string) => async () => ({ isAnswered: true, text, usage: USAGE })

test('step trigger: checks on steps 6 and 12 of the main thread only', async ($, on) => {
  const w = world(on)
  await start($)
  await turn($, 't1')
  await steps($, 't1', 13)
  await step($, 't1', 6, 'sub-1')
  expect(w.forks.length).toBe(2)
  expect(live(w).map(r => r.step)).toEqual([6, 12])
})

test('never two checks at once: a step while one is in flight starts none', async ($, on) => {
  const w = world(on)
  let release = (_: object) => {}
  w.replies.push(() => new Promise(r => (release = r)))
  await start($)
  await turn($, 't1')
  await steps($, 't1', 12)
  expect(w.forks.length).toBe(1)
  release({ isAnswered: true, text: 'finding: none', usage: USAGE })
  await settle()
  await step($, 't1', 18)
  expect(w.forks.length).toBe(2)
})

test('a reply that arrives after the next turn started is dropped as stale', async ($, on) => {
  const w = world(on)
  let release = (_: object) => {}
  w.replies.push(() => new Promise(r => (release = r)))
  await start($)
  await turn($, 't1')
  await steps($, 't1', 6)
  await turn($, 't2')
  release({ isAnswered: true, text: FINDING, usage: USAGE })
  await settle()
  expect(live(w).map(r => r.outcome)).toEqual(['stale'])
  expect(ledgerFiles(w)).toEqual([])
})

test('turn-end trigger is off by default', async ($, on) => {
  const w = world(on)
  await start($)
  await turn($, 't1')
  await bash($)
  await complete($, 't1')
  expect(w.forks.length).toBe(0)
})

test('turn-end trigger, when on, checks a tool-using turn and skips one with no tools or an abort', { options: { observer_turn_end_check: true } }, async ($, on) => {
  const w = world(on)
  await start($)
  await turn($, 't1')
  await complete($, 't1')
  await turn($, 't2')
  await bash($)
  await complete($, 't2', { isAborted: true, reason: 'aborted' })
  await turn($, 't3')
  await bash($)
  await complete($, 't3')
  expect(live(w).map(r => [r.trigger, r.turnId])).toEqual([['turn-end', 't3']])
})

test('the step trigger can be switched off', { options: { observer_step_check: false } }, async ($, on) => {
  const w = world(on)
  await start($)
  await turn($, 't1')
  await steps($, 't1', 12)
  expect(w.forks.length).toBe(0)
})

test('a finding lands in a new self-ignored ledger and the band, and Send fills the prompt', async ($, on) => {
  const w = world(on)
  w.replies.push(answer(FINDING))
  await start($)
  await turn($, 't1')
  await steps($, 't1', 6)
  const [ledger] = ledgerFiles(w).filter(f => f.endsWith('.md'))
  expect(ledger).toMatch(/-running-retro-session\.md$/)
  expect(w.files[ledger]).toContain(`session_id: ${SID}`)
  expect(w.files[ledger]).toContain('- **verification**: Merged without reading the pr-verify verdict.')
  expect(w.files[ledger]).toContain('Rule: R6 merge only after the verdict')
  expect(w.files[`${PROJECT}/.work/.gitignore`]).toBe('*\n')
  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /observer · verification · Merged without reading/ })).toBeDefined()
  await ui.press({ key: 'send' })
  expect(w.fills.length).toBe(1)
  expect(w.fills[0]).toContain('> verification: Merged without reading the pr-verify verdict.')
  await ui.unmount()
  const after = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await after.find({ key: 'send' })).toBeUndefined()
  await after.unmount()
})

test('nothing reaches the prompt unless Send is pressed', async ($, on) => {
  const w = world(on)
  w.replies.push(answer(FINDING))
  await start($)
  await turn($, 't1')
  await steps($, 't1', 6)
  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  await ui.press({ key: 'noted' })
  expect(w.fills).toEqual([])
  await ui.unmount()
})

test('a finding seen in an earlier session is not reported again', async ($, on) => {
  const w = world(on)
  w.store.seen = ['merged without reading the pr-verify verdict']
  w.replies.push(answer(FINDING))
  await start($)
  await turn($, 't1')
  await steps($, 't1', 6)
  expect(live(w).map(r => r.outcome)).toEqual(['deduped'])
  expect(ledgerFiles(w).filter(f => f.endsWith('.md'))).toEqual([])
  expect(w.forks[0]).toContain('- merged without reading the pr-verify verdict')
})

test('Dispute marks the ledger and suppresses the finding for good', async ($, on) => {
  const w = world(on)
  w.replies.push(answer(FINDING))
  await start($)
  await turn($, 't1')
  await steps($, 't1', 6)
  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  await ui.press({ key: 'dispute' })
  await ui.unmount()
  const [ledger] = ledgerFiles(w).filter(f => f.endsWith('.md'))
  expect(w.files[ledger]).toContain('- Disputed ')
  expect(w.store.disputed).toEqual(['Merged without reading the pr-verify verdict.'])
})

test('ignored findings back off: the third ignored one skips the next eligible check', async ($, on) => {
  const w = world(on)
  w.store.typedPast = 2
  w.replies.push(answer(FINDING))
  await start($)
  await turn($, 't1')
  await steps($, 't1', 6)
  await person($)
  await person($)
  expect(w.store.typedPast).toBe(3)
  expect(w.store.skip).toBe(1)
  await turn($, 't2')
  await steps($, 't2', 12)
  expect(w.forks.length).toBe(2)
  expect(live(w).map(r => [r.turnId, r.step])).toEqual([['t1', 6], ['t2', 12]])
})

test('a finding is redacted before the ledger write', async ($, on) => {
  const w = world(on)
  w.replies.push(answer(FINDING.replace('gh pr merge ran', 'curl -H sk-abc123 ran')))
  await start($)
  await turn($, 't1')
  await steps($, 't1', 6)
  const [ledger] = ledgerFiles(w).filter(f => f.endsWith('.md'))
  expect(w.files[ledger]).toContain('curl -H <REDACTED: API key> ran')
  expect(w.files[ledger]).not.toContain('sk-abc123')
})

test('after /clear the checks write under the new session id', async ($, on) => {
  const w = world(on)
  await start($)
  w.sid = 'sess-2'
  w.replies.push(answer(FINDING))
  await turn($, 't1')
  await steps($, 't1', 6)
  expect(w.files[`${DATA}/session-flow-observer/live-sess-2.jsonl`]).toBeDefined()
  expect(w.files[LIVE]).toBeUndefined()
  const [ledger] = ledgerFiles(w).filter(f => f.endsWith('.md'))
  expect(w.files[ledger]).toContain('session_id: sess-2')
})

test('each check records its usage', async ($, on) => {
  const w = world(on)
  await start($)
  await turn($, 't1')
  await steps($, 't1', 6)
  expect(live(w)[0]).toMatchObject({ trigger: 'step', turnId: 't1', step: 6, outcome: 'none', usage: USAGE })
})

kitTest('off unless observer_enabled', async ($, on) => {
  const w = world(on)
  await start($)
  await turn($, 't1')
  await steps($, 't1', 6)
  expect(w.forks.length).toBe(0)
})

test('no live checks in a headless run or in the catch-up analysis run', async ($, on) => {
  const w = world(on, { SESSION_FLOW_OBSERVER_ANALYSIS: '1' })
  await start($)
  await turn($, 't1')
  await steps($, 't1', 6)
  await start($, false)
  await steps($, 't1', 12)
  expect(w.forks.length).toBe(0)
})

kitTest('parseReply reads none, a finding, and rejects malformed or overlong replies', async () => {
  expect(parseReply('finding: none')).toEqual({ kind: 'none' })
  expect(parseReply('**finding:** None.')).toEqual({ kind: 'none' })
  const p = parseReply(`\u001b[1m${FINDING}\u001b[0m`)
  expect(p).toMatchObject({ kind: 'finding', value: { category: 'verification', finding: 'Merged without reading the pr-verify verdict.' } })
  expect(parseReply('finding: x\ncategory: taste\nrule: r')).toEqual({ kind: 'unparsable' })
  expect(parseReply('finding: x\ncategory: process')).toEqual({ kind: 'unparsable' })
  expect(parseReply(`finding: ${'x'.repeat(241)}\ncategory: process\nrule: r`)).toEqual({ kind: 'unparsable' })
  expect(parseReply('no labels here')).toEqual({ kind: 'unparsable' })
})

kitTest('parseReply stays linear on a long run of asterisks', async () => {
  const started = Date.now()
  expect(parseReply(`${'*'.repeat(5000)}x\n${'*'.repeat(5000)}`)).toEqual({ kind: 'unparsable' })
  expect(Date.now() - started).toBeLessThan(1000)
})

kitTest('checksToSkipAfterIgnored: free for two ignores, then doubles to a cap of 16', async () => {
  expect([0, 1, 2, 3, 4, 5, 6, 7, 8].map(checksToSkipAfterIgnored)).toEqual([0, 0, 0, 1, 2, 4, 8, 16, 16])
})

kitTest('buildPrompt lists what was seen and disputed', async () => {
  const p = buildPrompt(['a seen one'], ['a disputed one'])
  expect(p).toContain('- a seen one')
  expect(p).toContain('- a disputed one')
  expect(buildPrompt([], [])).not.toContain('Already reported')
})
