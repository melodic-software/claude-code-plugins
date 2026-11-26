import { expect, test } from 'claude-code/testing'

import { AUTO_NOTE, type Finding } from './observer-live.ts'
import { initial, readOptions, step, type Card, type CheckRequest, type Event, type State } from './observer-machine.ts'

const F: Finding = { finding: 'Merged without the verdict.', category: 'verification', rule: 'R6', evidence: 'gh pr merge ran first' }
const FINDING_REPLY = 'finding: Merged without the verdict.\ncategory: verification\nrule: R6\nevidence: gh pr merge ran first'

const opts = (raw: Record<string, unknown> = {}) => readOptions(raw).options
const card = (extra: Partial<Card> = {}): Card => ({ id: 1, finding: F, ledger: '/l.md', source: 'step 6', promptsSurvived: 0, isOpen: false, ...extra })
const req = (extra: Partial<CheckRequest> = {}): CheckRequest => ({ trigger: 'step', turnId: 't1', step: 6, gen: 1, open: null, ...extra })
const on = (extra: Partial<State> = {}): State => ({ ...initial(), on: true, ...extra })
const answered = (text: string) => ({ isAnswered: true as const, text })


test('check-requested does nothing while a check is in flight', () => {
  const r = step(on({ inFlight: true }), { kind: 'check-requested', trigger: 'step', turnId: 't1', step: 6, paused: false, skip: 0 }, opts())
  expect(r.effects).toEqual([])
  expect(r.state.inFlight).toBe(true)
})

test('check-requested does nothing while paused', () => {
  const r = step(on(), { kind: 'check-requested', trigger: 'step', turnId: 't1', step: 6, paused: true, skip: 0 }, opts())
  expect(r.effects).toEqual([])
  expect(r.state.inFlight).toBe(false)
})

test('check-requested with skip above zero stores skip minus one and forks nothing', () => {
  const r = step(on(), { kind: 'check-requested', trigger: 'step', turnId: 't1', step: 6, paused: false, skip: 3 }, opts())
  expect(r.effects).toEqual([{ kind: 'store', key: 'skip', value: 2 }])
  expect(r.state.inFlight).toBe(false)
})

test('check-requested forks with the current gen and open card and marks the check in flight', () => {
  const c = card()
  const r = step(on({ gen: 4, card: c }), { kind: 'check-requested', trigger: 'change', turnId: 't9', step: 2, paused: false, skip: 0 }, opts())
  expect(r.state.inFlight).toBe(true)
  expect(r.effects).toEqual([{ kind: 'fork', req: { trigger: 'change', turnId: 't9', step: 2, gen: 4, open: c } }])
})

test('check-finished clears inFlight', () => {
  expect(step(on({ inFlight: true }), { kind: 'check-finished' }, opts())).toEqual({ state: on({ inFlight: false }), effects: [] })
})


const replied = (s: State, reply: Extract<Event, { kind: 'check-replied' }>['reply'], extra: { paused?: boolean; seen?: string[]; disputed?: string[]; req?: CheckRequest } = {}) =>
  step(s, { kind: 'check-replied', req: extra.req ?? req(), reply, paused: extra.paused ?? false, seen: extra.seen ?? [], disputed: extra.disputed ?? [] }, opts())

test('check-replied maps nothing-to-fork and empty-reply to outcome none', () => {
  for (const reason of ['nothing-to-fork', 'empty-reply']) {
    expect(replied(on({ gen: 1 }), { isAnswered: false, reason }).effects).toEqual([{ kind: 'finish', req: req(), outcome: 'none' }])
  }
})

test('check-replied underscores any other unanswered reason', () => {
  expect(replied(on({ gen: 1 }), { isAnswered: false, reason: 'rate-limit' }).effects).toEqual([{ kind: 'finish', req: req(), outcome: 'rate_limit' }])
})

test('check-replied while paused finishes as paused and accepts nothing', () => {
  const r = replied(on({ gen: 1 }), answered(FINDING_REPLY), { paused: true })
  expect(r.effects).toEqual([{ kind: 'finish', req: req(), outcome: 'paused' }])
})

test('check-replied from an older generation finishes as stale', () => {
  const r = replied(on({ gen: 2 }), answered(FINDING_REPLY))
  expect(r.effects).toEqual([{ kind: 'finish', req: req(), outcome: 'stale' }])
})

test('check-replied after the session ended finishes as stale', () => {
  const r = replied(on({ gen: 1, ended: true }), answered(FINDING_REPLY))
  expect(r.effects).toEqual([{ kind: 'finish', req: req(), outcome: 'stale' }])
})

test('check-replied with "finding: none" finishes as none', () => {
  expect(replied(on({ gen: 1 }), answered('finding: none')).effects).toEqual([{ kind: 'finish', req: req(), outcome: 'none' }])
})

test('check-replied with an unparsable reply finishes as parse_failed', () => {
  expect(replied(on({ gen: 1 }), answered('I could not tell.')).effects).toEqual([{ kind: 'finish', req: req(), outcome: 'parse_failed' }])
  expect(replied(on({ gen: 1 }), answered('finding: x\ncategory: taste\nrule: r')).effects).toEqual([{ kind: 'finish', req: req(), outcome: 'parse_failed' }])
})

test('check-replied with a finding already seen or disputed finishes as deduped', () => {
  const seen = replied(on({ gen: 1 }), answered(FINDING_REPLY), { seen: ['Merged without the verdict.'] })
  expect(seen.effects).toEqual([{ kind: 'finish', req: req(), outcome: 'deduped' }])
  const disputed = replied(on({ gen: 1 }), answered(FINDING_REPLY), { disputed: ['merged without the verdict'] })
  expect(disputed.effects).toEqual([{ kind: 'finish', req: req(), outcome: 'deduped' }])
})

test('check-replied with a new finding emits accept with the parsed finding', () => {
  const r = replied(on({ gen: 1 }), answered(FINDING_REPLY), { seen: ['something else.'] })
  expect(r.effects).toEqual([{ kind: 'accept', req: req(), finding: F }])
  expect(r.state).toEqual(on({ gen: 1 }))
})

test('check-replied "resolved: yes" for the open card records it, clears the card and finishes', () => {
  const c = card()
  const r = replied(on({ gen: 1, card: c }), answered('finding: none\nresolved: yes'), { req: req({ open: c }) })
  expect(r.state.card).toBeNull()
  expect(r.effects).toEqual([
    { kind: 'ledger', path: '/l.md', line: 'resolved', finding: F },
    { kind: 'record', row: { answer: 'resolved' } },
    { kind: 'invalidate' },
    { kind: 'finish', req: req({ open: c }), outcome: 'none' },
  ])
})

test('check-replied "resolved: yes" keeps a card that is no longer the open one', () => {
  const r = replied(on({ gen: 1, card: card({ id: 2 }) }), answered('finding: none\nresolved: yes'), { req: req({ open: card({ id: 1 }) }) })
  expect(r.state.card?.id).toBe(2)
  expect(r.effects.some(fx => fx.kind === 'ledger')).toBe(false)
})


const accepted = (s: State, o: Record<string, unknown>, extra: { req?: CheckRequest; ledger?: string | undefined } = {}) =>
  step(s, { kind: 'finding-accepted', req: extra.req ?? req(), finding: F, ledger: 'ledger' in extra ? extra.ledger : '/l.md' }, opts(o))

test('finding-accepted without a ledger path finishes as unsafe_memory_root and sets no card', () => {
  const r = accepted(on({ gen: 1 }), {}, { ledger: undefined })
  expect(r.state.card).toBeNull()
  expect(r.effects).toEqual([{ kind: 'finish', req: req(), outcome: 'unsafe_memory_root' }])
})

test('finding-accepted with auto-send off shows the card and delivers nothing', () => {
  const r = accepted(on({ gen: 1, nextCard: 5 }), {})
  expect(r.state.card).toEqual({ id: 5, finding: F, ledger: '/l.md', source: 'step 6', promptsSurvived: 0, isOpen: false })
  expect(r.state.nextCard).toBe(6)
  expect(r.effects).toEqual([{ kind: 'invalidate' }, { kind: 'finish', req: req(), outcome: 'shown' }])
})

test('finding-accepted names the source of a turn-end check "turn end"', () => {
  const r = accepted(on({ gen: 1 }), {}, { req: req({ trigger: 'turn-end', step: -1 }) })
  expect(r.state.card?.source).toBe('turn end')
})

test('finding-accepted with auto-send on while idle submits and waits for the observer turn', () => {
  const r = accepted(on({ gen: 1 }), { observer_auto_send: true, observer_auto_note: 'Lead:' })
  const text = r.state.pendingSubmit
  expect(text?.startsWith('Lead:\n> verification: Merged without the verdict.\n> Rule: R6\n> Evidence: gh pr merge ran first')).toBe(true)
  expect(r.state.submitWaiting).toBe(true)
  expect(r.effects).toEqual([
    { kind: 'invalidate' },
    { kind: 'deliver', cardId: 1, delivery: 'submit', text, stepsLate: undefined },
    { kind: 'finish', req: req(), outcome: 'shown' },
  ])
})

test('finding-accepted appends during a running turn and reports how many steps late it is', () => {
  const r = accepted(on({ gen: 1, turnRunning: true, lastStep: 8 }), { observer_auto_send: true })
  const deliver = r.effects.find(fx => fx.kind === 'deliver')
  expect(deliver).toMatchObject({ kind: 'deliver', cardId: 1, delivery: 'append', stepsLate: 3 })
  expect(r.state.submitWaiting).toBe(false)
  expect(r.state.pendingSubmit).toBeNull()
})

test('finding-accepted appends while a submit is still waiting', () => {
  const r = accepted(on({ gen: 1, submitWaiting: true }), { observer_auto_send: true })
  expect(r.effects.find(fx => fx.kind === 'deliver')).toMatchObject({ delivery: 'append' })
  expect(r.state.pendingSubmit).toBeNull()
})

test('finding-accepted appends right after an observer turn', () => {
  const r = accepted(on({ gen: 1, lastTurnWasObserver: true }), { observer_auto_send: true })
  expect(r.effects.find(fx => fx.kind === 'deliver')).toMatchObject({ delivery: 'append' })
})

test('finding-accepted from a turn-end check during a running turn reports no stepsLate', () => {
  const r = accepted(on({ gen: 1, turnRunning: true, lastStep: 8 }), { observer_auto_send: true }, { req: req({ trigger: 'turn-end', step: -1 }) })
  const deliver = r.effects.find(fx => fx.kind === 'deliver')
  expect(deliver).toMatchObject({ delivery: 'append' })
  expect(deliver).toHaveProperty('stepsLate', undefined)
})

test('finding-accepted with the observer off delivers nothing even with auto-send on', () => {
  const r = accepted(on({ gen: 1, on: false }), { observer_auto_send: true })
  expect(r.state.card).not.toBeNull()
  expect(r.effects.some(fx => fx.kind === 'deliver')).toBe(false)
})


test('delivered success for the current card records auto_sent, writes the ledger and marks the card sent', () => {
  const c = card()
  const r = step(on({ card: c }), { kind: 'delivered', cardId: 1, delivery: 'append', chars: 120, stepsLate: 2 }, opts())
  expect(r.state.card).toEqual({ ...c, sent: 'append' })
  expect(r.effects).toEqual([
    { kind: 'record', row: { answer: 'auto_sent', delivery: 'append', chars: 120, stepsLate: 2 } },
    { kind: 'ledger', path: '/l.md', line: 'auto-sent', finding: F, detail: 'append' },
    { kind: 'invalidate' },
  ])
})

test('delivered success omits stepsLate from the row when it is unknown', () => {
  const r = step(on({ card: card() }), { kind: 'delivered', cardId: 1, delivery: 'submit', chars: 50 }, opts())
  expect(r.effects[0]).toEqual({ kind: 'record', row: { answer: 'auto_sent', delivery: 'submit', chars: 50 } })
  expect(r.state.card?.sent).toBe('submit')
})

test('delivered success with no matching card only records the row', () => {
  const s = on({ card: card({ id: 2 }) })
  const r = step(s, { kind: 'delivered', cardId: 1, delivery: 'append', chars: 10 }, opts())
  expect(r.state).toEqual(s)
  expect(r.effects).toEqual([{ kind: 'record', row: { answer: 'auto_sent', delivery: 'append', chars: 10 } }])
})

test('delivered error for a submit records the failure and clears the submit wait', () => {
  const s = on({ submitWaiting: true, pendingSubmit: 'note', nextTurnIsObserver: true })
  const r = step(s, { kind: 'delivered', cardId: 1, delivery: 'submit', chars: 10, error: 'boom' }, opts())
  expect(r.state).toMatchObject({ submitWaiting: false, pendingSubmit: null, nextTurnIsObserver: false })
  expect(r.effects).toEqual([{ kind: 'record', row: { answer: 'auto_send_failed', delivery: 'submit', error: 'boom' } }])
})

test('delivered error for an append records the failure and leaves the state alone', () => {
  const s = on({ submitWaiting: true, pendingSubmit: 'note', nextTurnIsObserver: true })
  const r = step(s, { kind: 'delivered', cardId: 1, delivery: 'append', chars: 10, error: 'boom' }, opts())
  expect(r.state).toEqual(s)
  expect(r.effects).toEqual([{ kind: 'record', row: { answer: 'auto_send_failed', delivery: 'append', error: 'boom' } }])
})


const typed = (s: State, o: Record<string, unknown>, typedPast = 0) =>
  step(s, { kind: 'prompt-submitted', byPerson: true, ours: false, paused: false, typedPast }, opts(o))

test('a typed prompt with no card changes nothing', () => {
  const s = on()
  expect(typed(s, {})).toEqual({ state: s, effects: [] })
})

test('a typed prompt that is not from the person changes nothing', () => {
  const s = on({ card: card() })
  expect(step(s, { kind: 'prompt-submitted', byPerson: false, ours: false, paused: false, typedPast: 0 }, opts())).toEqual({ state: s, effects: [] })
})

test('a card survives typed prompts until clearAfterPrompts, counting each', () => {
  const r = typed(on({ card: card() }), { observer_clear_after_prompts: 3 })
  expect(r.effects).toEqual([])
  expect(r.state.card?.promptsSurvived).toBe(1)
  const r2 = typed(r.state, { observer_clear_after_prompts: 3 })
  expect(r2.effects).toEqual([])
  expect(r2.state.card?.promptsSurvived).toBe(2)
})

test('a sent card is cleared by the last prompt without an ignored row', () => {
  const r = typed(on({ card: card({ sent: 'append' }) }), { observer_clear_after_prompts: 1 })
  expect(r.state.card).toBeNull()
  expect(r.effects).toEqual([{ kind: 'invalidate' }])
})

test('an unsent card cleared by a prompt records ignored and stores no skip within the free allowance', () => {
  const r = typed(on({ card: card() }), { observer_clear_after_prompts: 1, observer_ignored_free: 1, observer_skip_max: 3 }, 0)
  expect(r.state.card).toBeNull()
  expect(r.effects).toEqual([
    { kind: 'record', row: { answer: 'ignored' } },
    { kind: 'store', key: 'typedPast', value: 1 },
    { kind: 'store', key: 'skip', value: 0 },
    { kind: 'invalidate' },
  ])
})

test('an unsent card ignored past the free allowance of 0 stores a skip of 1, 2 then the cap of 3', () => {
  const o = { observer_clear_after_prompts: 1, observer_ignored_free: 0, observer_skip_max: 3 }
  const cases: [number, number, number][] = [[0, 1, 1], [1, 2, 2], [2, 3, 3], [5, 6, 3]]
  for (const [before, typedPast, skip] of cases) {
    const r = typed(on({ card: card() }), o, before)
    expect(r.effects).toContainEqual({ kind: 'store', key: 'typedPast', value: typedPast })
    expect(r.effects).toContainEqual({ kind: 'store', key: 'skip', value: skip })
    expect(r.effects).toContainEqual({ kind: 'record', row: { answer: 'ignored' } })
  }
})


test('command on turns the observer on and stores paused false', () => {
  const r = step(initial(), { kind: 'command', arg: 'on' }, opts())
  expect(r.state.on).toBe(true)
  expect(r.effects).toEqual([{ kind: 'store', key: 'paused', value: false }])
})

test('command on is refused for an ended session', () => {
  const r = step({ ...initial(), ended: true }, { kind: 'command', arg: 'on' }, opts())
  expect(r.state.on).toBe(false)
})

test('command off stores paused true and leaves the observer flag alone', () => {
  const r = step(on(), { kind: 'command', arg: 'off' }, opts())
  expect(r.state.on).toBe(true)
  expect(r.effects).toEqual([{ kind: 'store', key: 'paused', value: true }])
})

test('command off dismisses an open card with a dismissed row', () => {
  const r = step(on({ card: card() }), { kind: 'command', arg: 'off' }, opts())
  expect(r.state.card).toBeNull()
  expect(r.effects).toEqual([
    { kind: 'store', key: 'paused', value: true },
    { kind: 'record', row: { answer: 'dismissed' } },
    { kind: 'store', key: 'typedPast', value: 0 },
    { kind: 'store', key: 'skip', value: 0 },
    { kind: 'invalidate' },
  ])
})


test('noted with a written ledger toasts success and answers noted', () => {
  const r = step(on({ card: card() }), { kind: 'noted', ok: true }, opts())
  expect(r.state.card).toBeNull()
  expect(r.effects).toEqual([
    { kind: 'toast', text: 'observer: noted in the running-retro ledger' },
    { kind: 'record', row: { answer: 'noted' } },
    { kind: 'store', key: 'typedPast', value: 0 },
    { kind: 'store', key: 'skip', value: 0 },
    { kind: 'invalidate' },
  ])
})

test('noted with a failed write toasts the ledger path', () => {
  const r = step(on({ card: card() }), { kind: 'noted', ok: false }, opts())
  expect(r.effects[0]).toEqual({ kind: 'toast', text: 'observer: could not write /l.md' })
  expect(r.effects).toContainEqual({ kind: 'record', row: { answer: 'noted' } })
})

test('noted, send, dispute, why and dismiss do nothing without a card', () => {
  for (const kind of ['noted', 'send', 'dispute', 'why', 'dismiss'] as const) {
    const e: Event = kind === 'noted' ? { kind, ok: true } : kind === 'dispute' ? { kind, disputed: [] } : { kind }
    expect(step(on(), e, opts())).toEqual({ state: on(), effects: [] })
  }
})

test('send fills the input with a note about the finding and answers sent', () => {
  const r = step(on({ card: card() }), { kind: 'send' }, opts())
  const fill = r.effects.find(fx => fx.kind === 'fill')
  expect(fill).toBeDefined()
  expect(fill?.kind === 'fill' && fill.text).toContain('> verification: Merged without the verdict.')
  expect(r.effects).toContainEqual({ kind: 'record', row: { answer: 'sent' } })
  expect(r.state.card).toBeNull()
})

test('dispute stores the finding in the disputed list, writes the ledger and toasts', () => {
  const r = step(on({ card: card() }), { kind: 'dispute', disputed: ['older one.'] }, opts())
  expect(r.state.card).toBeNull()
  expect(r.effects).toEqual([
    { kind: 'store', key: 'disputed', value: ['older one.', 'Merged without the verdict.'] },
    { kind: 'ledger', path: '/l.md', line: 'disputed', finding: F },
    { kind: 'toast', text: 'observer: disputed; it will not be reported again' },
    { kind: 'record', row: { answer: 'disputed' } },
    { kind: 'store', key: 'typedPast', value: 0 },
    { kind: 'store', key: 'skip', value: 0 },
    { kind: 'invalidate' },
  ])
})

test('why toggles the card open and closed', () => {
  const open = step(on({ card: card() }), { kind: 'why' }, opts())
  expect(open.state.card?.isOpen).toBe(true)
  expect(open.effects).toEqual([{ kind: 'invalidate' }])
  expect(step(open.state, { kind: 'why' }, opts()).state.card?.isOpen).toBe(false)
})

test('dismiss asks why, keeps the dismissed finding and schedules asked-expired', () => {
  const r = step(on({ card: card() }), { kind: 'dismiss' }, opts())
  expect(r.state).toMatchObject({ card: null, asked: true, dismissed: F })
  const after = r.effects.find(fx => fx.kind === 'after')
  expect(after).toMatchObject({ kind: 'after', event: { kind: 'asked-expired' } })
  expect(after?.kind === 'after' && after.ms).toBeGreaterThan(0)
  expect(r.effects).toContainEqual({ kind: 'record', row: { answer: 'dismissed' } })
})

test('asked-expired clears asked', () => {
  const r = step(on({ asked: true }), { kind: 'asked-expired' }, opts())
  expect(r.state.asked).toBe(false)
  expect(r.effects).toEqual([{ kind: 'invalidate' }])
})

test('rate turned_off turns the observer off with a toast', () => {
  const r = step(on({ asked: true }), { kind: 'rate', answer: 'turned_off', notRelevant: [], unclear: 0 }, opts())
  expect(r.state).toMatchObject({ on: false, asked: false })
  expect(r.effects).toEqual([
    { kind: 'toast', text: 'observer: live checks off for this session (/observer on resumes; /observer off pauses every session)' },
    { kind: 'record', row: { answer: 'turned_off' } },
    { kind: 'invalidate' },
  ])
})

test('rate not_relevant stores the dismissed finding in the not-relevant list', () => {
  const r = step(on({ asked: true, dismissed: F }), { kind: 'rate', answer: 'not_relevant', notRelevant: ['old.'], unclear: 0 }, opts())
  expect(r.effects).toEqual([
    { kind: 'store', key: 'notRelevant', value: ['old.', 'Merged without the verdict.'] },
    { kind: 'record', row: { answer: 'not_relevant' } },
    { kind: 'invalidate' },
  ])
})

test('rate not_relevant with no dismissed finding stores nothing', () => {
  const r = step(on(), { kind: 'rate', answer: 'not_relevant', notRelevant: [], unclear: 0 }, opts())
  expect(r.effects).toEqual([{ kind: 'record', row: { answer: 'not_relevant' } }, { kind: 'invalidate' }])
})

test('rate unclear stores the unclear count plus one', () => {
  const r = step(on(), { kind: 'rate', answer: 'unclear', notRelevant: [], unclear: 4 }, opts())
  expect(r.effects).toEqual([
    { kind: 'store', key: 'unclear', value: 5 },
    { kind: 'record', row: { answer: 'unclear' } },
    { kind: 'invalidate' },
  ])
})


test('gate-requested forks a gate check for a command matching the pattern', () => {
  const r = step(on(), { kind: 'gate-requested', command: 'git push origin main', paused: false }, opts({ observer_gate_check: true }))
  expect(r.effects).toEqual([{ kind: 'gate-fork', command: 'git push origin main' }])
})

test('gate-requested does nothing when paused, gate check off, observer off or the command does not match', () => {
  const push = { kind: 'gate-requested', command: 'git push origin main', paused: false } as const
  const gate = { observer_gate_check: true }
  expect(step(on(), { ...push, paused: true }, opts(gate)).effects).toEqual([])
  expect(step(on(), push, opts()).effects).toEqual([])
  expect(step(on({ on: false }), push, opts(gate)).effects).toEqual([])
  expect(step(on(), { ...push, command: 'git status' }, opts(gate)).effects).toEqual([])
})

const gateReplied = (s: State, reply: Extract<Event, { kind: 'gate-replied' }>['reply'], o: Record<string, unknown> = {}) =>
  step(s, { kind: 'gate-replied', command: 'git push', reply, latencyMs: 700 }, opts(o))

test('gate-replied with a finding below the refusal cap refuses the command and counts it', () => {
  const r = gateReplied(on(), answered(FINDING_REPLY))
  expect(r.state.refused).toEqual({ 'git push': 1 })
  expect(r.effects).toHaveLength(2)
  expect(r.effects[0]).toEqual({ kind: 'record', row: { trigger: 'gate', latencyMs: 700, usage: undefined, outcome: 'refused', finding: 'Merged without the verdict.' } })
  const deny = r.effects[1]
  expect(deny?.kind).toBe('deny')
  expect(deny?.kind === 'deny' && deny.text.startsWith(AUTO_NOTE)).toBe(true)
  expect(deny?.kind === 'deny' && deny.text).toContain('> verification: Merged without the verdict.')
})

test('gate-replied with a repeat finding after the cap lets the command run and marks the row repeat', () => {
  const r = gateReplied(on({ refused: { 'git push': 1 } }), answered(FINDING_REPLY))
  expect(r.state.refused).toEqual({ 'git push': 1 })
  expect(r.effects).toEqual([{ kind: 'record', row: { trigger: 'gate', latencyMs: 700, usage: undefined, repeat: true, outcome: 'allowed_after_refusals' } }])
})

test('gate-replied with a refusal cap of 0 never denies', () => {
  const r = gateReplied(on(), answered(FINDING_REPLY), { observer_gate_refusals: 0 })
  expect(r.effects).toEqual([{ kind: 'record', row: { trigger: 'gate', latencyMs: 700, usage: undefined, outcome: 'allowed_after_refusals' } }])
})

test('gate-replied with "finding: none" records none', () => {
  expect(gateReplied(on(), answered('finding: none')).effects).toEqual([{ kind: 'record', row: { trigger: 'gate', latencyMs: 700, usage: undefined, outcome: 'none' } }])
})

test('gate-replied with an unparsable reply records parse_failed', () => {
  expect(gateReplied(on(), answered('hmm')).effects).toEqual([{ kind: 'record', row: { trigger: 'gate', latencyMs: 700, usage: undefined, outcome: 'parse_failed' } }])
})

test('gate-replied after a timeout records timeout', () => {
  expect(gateReplied(on(), { isAnswered: false, reason: 'timeout' }).effects).toEqual([{ kind: 'record', row: { trigger: 'gate', latencyMs: 700, usage: undefined, outcome: 'timeout' } }])
})


const stepAt = (s: State, index: number, o: Record<string, unknown>, main = true) => step(s, { kind: 'step', main, turnId: 't1', index }, opts(o))

test('step emits a step check only on multiples of observer_step_every', () => {
  const o = { observer_step_every: 3 }
  for (const index of [1, 2, 4, 5]) expect(stepAt(on(), index, o).effects).toEqual([])
  for (const index of [3, 6, 9]) expect(stepAt(on(), index, o).effects).toEqual([{ kind: 'check', trigger: 'step', turnId: 't1', step: index }])
})

test('step records the index of a main step as lastStep', () => {
  expect(stepAt(on(), 4, { observer_step_every: 3 }).state.lastStep).toBe(4)
  expect(stepAt(on({ lastStep: 2 }), 4, { observer_step_every: 3 }, false).state.lastStep).toBe(2)
})

test('step emits no check with step checks off, the observer off or a non-main step', () => {
  expect(stepAt(on(), 3, { observer_step_every: 3, observer_step_check: false }).effects).toEqual([])
  expect(stepAt(on({ on: false }), 3, { observer_step_every: 3 }).effects).toEqual([])
  expect(stepAt(on(), 3, { observer_step_every: 3 }, false).effects).toEqual([])
})

test('tool-called with a change tool sets changed only with change check on and a main call', () => {
  const tool = (s: State, name: string, main: boolean, o: Record<string, unknown>) => step(s, { kind: 'tool-called', main, name }, opts(o)).state
  expect(tool(on(), 'Edit', true, { observer_change_check: true })).toMatchObject({ changed: true, tools: 1 })
  expect(tool(on(), 'Bash', true, { observer_change_check: true })).toMatchObject({ changed: false, tools: 1 })
  expect(tool(on(), 'Edit', true, {})).toMatchObject({ changed: false, tools: 1 })
  expect(tool(on(), 'Edit', false, { observer_change_check: true })).toMatchObject({ changed: false, tools: 0 })
  expect(tool(on(), 'Custom', true, { observer_change_check: true, observer_change_tools: 'Custom, Other' }).changed).toBe(true)
})

test('after a change tool the next main step emits a change check and clears changed', () => {
  const r = stepAt(on({ changed: true }), 1, { observer_change_check: true })
  expect(r.state.changed).toBe(false)
  expect(r.effects).toEqual([{ kind: 'check', trigger: 'change', turnId: 't1', step: 1 }])
})

test('a non-main step leaves changed set and emits nothing', () => {
  const r = stepAt(on({ changed: true }), 1, { observer_change_check: true }, false)
  expect(r.state.changed).toBe(true)
  expect(r.effects).toEqual([])
})

test('with the observer off a main step clears changed without a check', () => {
  const r = stepAt(on({ on: false, changed: true }), 1, { observer_change_check: true })
  expect(r.state.changed).toBe(false)
  expect(r.effects).toEqual([])
})


const completed = (s: State, o: Record<string, unknown>, extra: { isAborted?: boolean; main?: boolean } = {}) =>
  step(s, { kind: 'turn-completed', main: extra.main ?? true, turnId: 't1', isAborted: extra.isAborted ?? false }, opts(o))

test('turn-completed emits a turn-end check with turnEndCheck on, tools used, not aborted, observer on', () => {
  const r = completed(on({ tools: 2, turnRunning: true }), { observer_turn_end_check: true })
  expect(r.state.turnRunning).toBe(false)
  expect(r.effects).toEqual([{ kind: 'check', trigger: 'turn-end', turnId: 't1', step: -1 }])
})

test('turn-completed emits no turn-end check when any condition is missing', () => {
  const o = { observer_turn_end_check: true }
  expect(completed(on({ tools: 2 }), {}).effects).toEqual([])
  expect(completed(on({ tools: 0 }), o).effects).toEqual([])
  expect(completed(on({ tools: 2 }), o, { isAborted: true }).effects).toEqual([])
  expect(completed(on({ tools: 2, on: false }), o).effects).toEqual([])
  expect(completed(on({ tools: 2, turnRunning: true }), o, { main: false })).toEqual({ state: on({ tools: 2, turnRunning: true }), effects: [] })
})
