import {
  AUTO_NOTE,
  CHECK_EVERY,
  CLEAR_AFTER_PROMPTS,
  GUIDANCE_MAX,
  SKIP_MAX,
  TYPED_PAST_FREE,
  type Finding,
  type Trigger,
  checksToSkipAfterIgnored,
  isKnown,
  isResolved,
  isStepCheck,
  noteFor,
  parseReply,
  remember,
} from './observer-live.ts'

export const ASKED_MS = 20_000

export type Options = {
  stepCheck: boolean
  turnEndCheck: boolean
  stepEvery: number
  clearAfterPrompts: number
  ignoredFree: number
  skipMax: number
  autoSend: boolean
  autoNote: string
  guidance: string
  guidanceMax: number
  checkPrompt: string
  changeCheck: boolean
  changeTools: readonly string[]
  gateCheck: boolean
  gatePattern: RegExp
  gateTimeoutMs: number
  gateRefusals: number
}

export const GATE_PATTERN = String.raw`\b(git\s+push|gh\s+pr\s+(create|merge|comment|review)|gh\s+issue\s+(create|comment)|gh\s+api\b.*\s(-X|--method)\s*(POST|PATCH|PUT|DELETE))\b`

export const readOptions = (raw: Readonly<Record<string, unknown>>): { options: Options; invalid: string[] } => {
  const invalid: string[] = []
  const pick = <T>(key: string, fallback: T, valid: (v: unknown) => boolean, map: (v: never) => T = v => v as T): T => {
    const v = raw[key]
    if (v === undefined || v === '') return fallback
    if (valid(v)) return map(v as never)
    invalid.push(key)
    return fallback
  }
  const bool = (key: string, fallback: boolean) => pick(key, fallback, v => typeof v === 'boolean')
  const int = (key: string, fallback: number, min: number) => pick(key, fallback, v => Number.isInteger(v) && (v as number) >= min)
  const text = (key: string, fallback: string) => pick(key, fallback, v => typeof v === 'string')
  const regex = (v: unknown) => {
    try {
      return typeof v === 'string' && new RegExp(v) instanceof RegExp
    } catch {
      return false
    }
  }
  const options: Options = {
    stepCheck: bool('observer_step_check', true),
    turnEndCheck: bool('observer_turn_end_check', false),
    stepEvery: int('observer_step_every', CHECK_EVERY, 1),
    clearAfterPrompts: int('observer_clear_after_prompts', CLEAR_AFTER_PROMPTS, 1),
    ignoredFree: int('observer_ignored_free', TYPED_PAST_FREE, 0),
    skipMax: int('observer_skip_max', SKIP_MAX, 0),
    autoSend: bool('observer_auto_send', false),
    autoNote: text('observer_auto_note', AUTO_NOTE),
    guidance: text('observer_guidance', ''),
    guidanceMax: int('observer_guidance_max', GUIDANCE_MAX, 0),
    checkPrompt: text('observer_check_prompt', ''),
    changeCheck: bool('observer_change_check', false),
    changeTools: pick('observer_change_tools', ['Edit', 'Write', 'NotebookEdit'], v => typeof v === 'string', (v: string) => v.split(',').map(t => t.trim()).filter(Boolean)),
    gateCheck: bool('observer_gate_check', false),
    gatePattern: new RegExp(pick('observer_gate_pattern', GATE_PATTERN, regex)),
    gateTimeoutMs: int('observer_gate_timeout_seconds', 30, 1) * 1000,
    gateRefusals: int('observer_gate_refusals', 1, 0),
  }
  return { options, invalid }
}

export type Delivery = 'append' | 'submit'

export type Card = { id: number; finding: Finding; ledger: string; source: string; promptsSurvived: number; isOpen: boolean; sent?: Delivery }

export type State = {
  on: boolean
  ended: boolean
  gen: number
  tools: number
  inFlight: boolean
  nextCard: number
  card: Card | null
  asked: boolean
  dismissed: Finding | null
  lastStep: number
  turnRunning: boolean
  submitWaiting: boolean
  nextTurnIsObserver: boolean
  pendingSubmit: string | null
  observerTurnId: string | null
  lastTurnWasObserver: boolean
  changed: boolean
  refused: Readonly<Record<string, number>>
}

export const initial = (): State => ({
  on: false,
  ended: false,
  gen: 0,
  tools: 0,
  inFlight: false,
  nextCard: 1,
  card: null,
  asked: false,
  dismissed: null,
  lastStep: 0,
  turnRunning: false,
  submitWaiting: false,
  nextTurnIsObserver: false,
  pendingSubmit: null,
  observerTurnId: null,
  lastTurnWasObserver: false,
  changed: false,
  refused: {},
})

export type CheckRequest = { trigger: Trigger; turnId: string; step: number; gen: number; open: Card | null }
export type Reply = { isAnswered: true; text: string } | { isAnswered: false; reason: string }
export type LedgerKind = 'confirmed' | 'disputed' | 'resolved' | 'auto-sent'
export type Rate = 'helpful' | 'not_relevant' | 'unclear' | 'turned_off' | 'closed'

export type Event =
  | { kind: 'session-started' }
  | { kind: 'session-changed' }
  | { kind: 'session-ended' }
  | { kind: 'turn-started'; main: boolean; turnId: string; text: string; paused: boolean }
  | { kind: 'tool-called'; main: boolean; name: string }
  | { kind: 'gate-requested'; command: string; paused: boolean }
  | { kind: 'gate-replied'; command: string; reply: Reply | { isAnswered: false; reason: 'timeout' | 'error' }; latencyMs: number; usage?: object }
  | { kind: 'step'; main: boolean; turnId: string; index: number }
  | { kind: 'turn-completed'; main: boolean; turnId: string; isAborted: boolean; durationMs?: number; usage?: object }
  | { kind: 'check-requested'; trigger: Trigger; turnId: string; step: number; paused: boolean; skip: number }
  | { kind: 'check-replied'; req: CheckRequest; reply: Reply; paused: boolean; seen: readonly string[]; disputed: readonly string[] }
  | { kind: 'finding-accepted'; req: CheckRequest; finding: Finding; ledger: string | undefined }
  | { kind: 'check-finished' }
  | { kind: 'prompt-submitted'; byPerson: boolean; ours: boolean; paused: boolean; typedPast: number }
  | { kind: 'delivered'; cardId: number; delivery: Delivery; chars: number; stepsLate?: number; error?: string }
  | { kind: 'command'; arg: 'on' | 'off' }
  | { kind: 'noted'; ok: boolean }
  | { kind: 'send' }
  | { kind: 'dispute'; disputed: readonly string[] }
  | { kind: 'why' }
  | { kind: 'dismiss' }
  | { kind: 'asked-expired' }
  | { kind: 'rate'; answer: Rate; notRelevant: readonly string[]; unclear: number }

export type Effect =
  | { kind: 'check'; trigger: Trigger; turnId: string; step: number }
  | { kind: 'fork'; req: CheckRequest }
  | { kind: 'accept'; req: CheckRequest; finding: Finding }
  | { kind: 'finish'; req: CheckRequest; outcome: string }
  | { kind: 'store'; key: string; value: unknown }
  | { kind: 'record'; row: object }
  | { kind: 'ledger'; path: string; line: LedgerKind; finding: Finding; detail?: string }
  | { kind: 'deliver'; cardId: number; delivery: Delivery; text: string; stepsLate?: number }
  | { kind: 'drop'; reason: string }
  | { kind: 'abort'; turnId: string }
  | { kind: 'gate-fork'; command: string }
  | { kind: 'deny'; text: string }
  | { kind: 'toast'; text: string }
  | { kind: 'fill'; text: string }
  | { kind: 'after'; ms: number; event: Event }
  | { kind: 'invalidate' }

export type Result = { state: State; effects: Effect[] }

const answered = (s: State, answer: string, toast?: string): Result => ({
  state: { ...s, card: null, asked: false },
  effects: [
    ...(toast ? [{ kind: 'toast', text: toast } as const] : []),
    { kind: 'record', row: { answer } },
    { kind: 'store', key: 'typedPast', value: 0 },
    { kind: 'store', key: 'skip', value: 0 },
    { kind: 'invalidate' },
  ],
})

const replied = (s: State, e: Extract<Event, { kind: 'check-replied' }>): Result => {
  const finish = (state: State, outcome: string, before: Effect[] = []): Result => ({ state, effects: [...before, { kind: 'finish', req: e.req, outcome }] })
  if (!e.reply.isAnswered) {
    const reason = e.reply.reason
    return finish(s, reason === 'nothing-to-fork' || reason === 'empty-reply' ? 'none' : reason.replace('-', '_'))
  }
  if (e.paused) return finish(s, 'paused')
  const { text } = e.reply
  const parsed = parseReply(text)
  const isCurrent = !s.ended && s.gen === e.req.gen
  const open = e.req.open
  let state = s
  const effects: Effect[] = []
  if (isCurrent && open !== null && s.card?.id === open.id && isResolved(text)) {
    effects.push({ kind: 'ledger', path: open.ledger, line: 'resolved', finding: open.finding }, { kind: 'record', row: { answer: 'resolved' } }, { kind: 'invalidate' })
    state = { ...state, card: null }
  }
  if (!isCurrent) return finish(state, 'stale', effects)
  if (parsed.kind !== 'finding') return finish(state, parsed.kind === 'none' ? 'none' : 'parse_failed', effects)
  if (isKnown(parsed.value.finding, e.seen, e.disputed)) return finish(state, 'deduped', effects)
  return { state, effects: [...effects, { kind: 'accept', req: e.req, finding: parsed.value }] }
}

export const step = (s: State, e: Event, o: Options): Result => {
  const none = (state: State = s): Result => ({ state, effects: [] })
  switch (e.kind) {
    case 'session-started':
      return none({ ...s, ended: false, on: true })
    case 'session-changed':
      return none({ ...s, card: null })
    case 'session-ended':
      return none({ ...s, ended: true, on: false })
    case 'turn-started': {
      if (!e.main) return none()
      const p = s.pendingSubmit
      const observer = s.nextTurnIsObserver || (p !== null && e.text.trim() !== '' && (e.text.includes(p) || p.includes(e.text.trim())))
      const state = {
        ...s,
        gen: s.gen + 1,
        tools: 0,
        lastStep: 0,
        turnRunning: true,
        nextTurnIsObserver: false,
        pendingSubmit: observer ? null : p,
        submitWaiting: observer ? false : s.submitWaiting,
        observerTurnId: observer ? e.turnId : null,
      }
      return observer && (!s.on || e.paused) ? { state, effects: [{ kind: 'abort', turnId: e.turnId }] } : none(state)
    }
    case 'tool-called':
      return none(e.main ? { ...s, tools: s.tools + 1, changed: s.changed || (o.changeCheck && o.changeTools.includes(e.name)) } : s)
    case 'gate-requested':
      return s.on && o.gateCheck && !e.paused && o.gatePattern.test(e.command) ? { state: s, effects: [{ kind: 'gate-fork', command: e.command }] } : none()
    case 'gate-replied': {
      const times = s.refused[e.command] ?? 0
      const row = { trigger: 'gate', latencyMs: e.latencyMs, usage: e.usage, ...(times > 0 ? { repeat: true } : {}) }
      const parsed = e.reply.isAnswered ? parseReply(e.reply.text) : undefined
      if (parsed?.kind === 'finding' && times < o.gateRefusals)
        return {
          state: { ...s, refused: { ...s.refused, [e.command]: times + 1 } },
          effects: [{ kind: 'record', row: { ...row, outcome: 'refused', finding: parsed.value.finding } }, { kind: 'deny', text: noteFor(parsed.value, 'plugin', o.autoNote) }],
        }
      const outcome = !e.reply.isAnswered ? e.reply.reason : parsed?.kind === 'finding' ? 'allowed_after_refusals' : parsed?.kind === 'none' ? 'none' : 'parse_failed'
      return { state: s, effects: [{ kind: 'record', row: { ...row, outcome } }] }
    }
    case 'step':
      if (e.main) s = { ...s, lastStep: e.index }
      if (e.main && s.changed) {
        s = { ...s, changed: false }
        if (s.on) return { state: s, effects: [{ kind: 'check', trigger: 'change', turnId: e.turnId, step: e.index }] }
      }
      return s.on && o.stepCheck && e.main && isStepCheck(e.index, undefined, o.stepEvery)
        ? { state: s, effects: [{ kind: 'check', trigger: 'step', turnId: e.turnId, step: e.index }] }
        : none()
    case 'turn-completed': {
      if (!e.main) return none()
      const wasObserver = s.observerTurnId !== null && s.observerTurnId === e.turnId
      const state = { ...s, turnRunning: false, lastTurnWasObserver: wasObserver, observerTurnId: null }
      const effects: Effect[] = wasObserver ? [{ kind: 'record', row: { observerTurn: e.turnId, durationMs: e.durationMs, usage: e.usage } }] : []
      if (s.on && o.turnEndCheck && !e.isAborted && s.tools > 0) effects.push({ kind: 'check', trigger: 'turn-end', turnId: e.turnId, step: -1 })
      return { state, effects }
    }
    case 'check-requested':
      if (s.inFlight || e.paused) return none()
      if (e.skip > 0) return { state: s, effects: [{ kind: 'store', key: 'skip', value: e.skip - 1 }] }
      return { state: { ...s, inFlight: true }, effects: [{ kind: 'fork', req: { trigger: e.trigger, turnId: e.turnId, step: e.step, gen: s.gen, open: s.card } }] }
    case 'check-replied':
      return replied(s, e)
    case 'finding-accepted': {
      if (e.ledger === undefined) return { state: s, effects: [{ kind: 'finish', req: e.req, outcome: 'unsafe_memory_root' }] }
      const card: Card = { id: s.nextCard, finding: e.finding, ledger: e.ledger, source: e.req.trigger === 'turn-end' ? 'turn end' : `${e.req.trigger} ${e.req.step}`, promptsSurvived: 0, isOpen: false }
      const state = { ...s, card, nextCard: s.nextCard + 1 }
      const effects: Effect[] = [{ kind: 'invalidate' }]
      if (o.autoSend && s.on) {
        const delivery: Delivery = !s.turnRunning && !s.submitWaiting && !s.lastTurnWasObserver ? 'submit' : 'append'
        const text = noteFor(card.finding, 'plugin', o.autoNote)
        if (delivery === 'submit') Object.assign(state, { submitWaiting: true, pendingSubmit: text })
        const stepsLate = e.req.step >= 0 && s.turnRunning ? s.lastStep + 1 - e.req.step : undefined
        effects.push({ kind: 'deliver', cardId: card.id, delivery, text, stepsLate })
      }
      return { state, effects: [...effects, { kind: 'finish', req: e.req, outcome: 'shown' }] }
    }
    case 'delivered': {
      const card = s.card?.id === e.cardId ? s.card : null
      if (e.error !== undefined)
        return {
          state: e.delivery === 'submit' ? { ...s, submitWaiting: false, pendingSubmit: null } : s,
          effects: [{ kind: 'record', row: { answer: 'auto_send_failed', delivery: e.delivery, error: e.error } }],
        }
      const effects: Effect[] = [{ kind: 'record', row: { answer: 'auto_sent', delivery: e.delivery, chars: e.chars, ...(e.stepsLate === undefined ? {} : { stepsLate: e.stepsLate }) } }]
      if (card === null) return { state: s, effects }
      effects.push({ kind: 'ledger', path: card.ledger, line: 'auto-sent', finding: card.finding, detail: e.delivery }, { kind: 'invalidate' })
      return { state: { ...s, card: { ...card, sent: e.delivery } }, effects }
    }
    case 'check-finished':
      return none({ ...s, inFlight: false })
    case 'prompt-submitted': {
      if (e.ours) return !s.on || e.paused ? { state: { ...s, submitWaiting: false }, effects: [{ kind: 'drop', reason: 'observer off' }] } : none({ ...s, nextTurnIsObserver: true, pendingSubmit: null })
      const card = s.card
      if (card === null || !e.byPerson) return none()
      const survived = { ...card, promptsSurvived: card.promptsSurvived + 1 }
      if (survived.promptsSurvived < o.clearAfterPrompts) return none({ ...s, card: survived })
      if (card.sent !== undefined) return { state: { ...s, card: null }, effects: [{ kind: 'invalidate' }] }
      const typedPast = e.typedPast + 1
      return {
        state: { ...s, card: null },
        effects: [
          { kind: 'record', row: { answer: 'ignored' } },
          { kind: 'store', key: 'typedPast', value: typedPast },
          { kind: 'store', key: 'skip', value: checksToSkipAfterIgnored(typedPast, { free: o.ignoredFree, max: o.skipMax }) },
          { kind: 'invalidate' },
        ],
      }
    }
    case 'command': {
      const state = e.arg === 'on' ? { ...s, on: !s.ended } : s
      const pause: Effect = { kind: 'store', key: 'paused', value: e.arg === 'off' }
      if (e.arg === 'off' && s.card !== null) {
        const r = answered(state, 'dismissed')
        return { state: r.state, effects: [pause, ...r.effects] }
      }
      return { state, effects: [pause] }
    }
    case 'noted':
      return s.card === null ? none() : answered(s, 'noted', e.ok ? 'observer: noted in the running-retro ledger' : `observer: could not write ${s.card.ledger}`)
    case 'send': {
      if (s.card === null) return none()
      const r = answered(s, 'sent')
      return { state: r.state, effects: [{ kind: 'fill', text: noteFor(s.card.finding) }, ...r.effects] }
    }
    case 'dispute': {
      if (s.card === null) return none()
      const { finding, ledger } = s.card
      const r = answered(s, 'disputed', 'observer: disputed; it will not be reported again')
      return { state: r.state, effects: [{ kind: 'store', key: 'disputed', value: remember(e.disputed, finding.finding) }, { kind: 'ledger', path: ledger, line: 'disputed', finding }, ...r.effects] }
    }
    case 'why':
      return s.card === null ? none() : { state: { ...s, card: { ...s.card, isOpen: !s.card.isOpen } }, effects: [{ kind: 'invalidate' }] }
    case 'dismiss': {
      if (s.card === null) return none()
      const r = answered({ ...s, dismissed: s.card.finding }, 'dismissed')
      return { state: { ...r.state, asked: true }, effects: [...r.effects, { kind: 'after', ms: ASKED_MS, event: { kind: 'asked-expired' } }, { kind: 'invalidate' }] }
    }
    case 'asked-expired':
      return { state: { ...s, asked: false }, effects: [{ kind: 'invalidate' }] }
    case 'rate': {
      const effects: Effect[] = []
      let state: State = { ...s, asked: false }
      if (e.answer === 'turned_off') {
        state = { ...state, on: false }
        effects.push({ kind: 'toast', text: 'observer: live checks off for this session (/observer on resumes; /observer off pauses every session)' })
      }
      if (e.answer === 'not_relevant' && s.dismissed !== null) effects.push({ kind: 'store', key: 'notRelevant', value: remember(e.notRelevant, s.dismissed.finding) })
      if (e.answer === 'unclear') effects.push({ kind: 'store', key: 'unclear', value: e.unclear + 1 })
      effects.push({ kind: 'record', row: { answer: e.answer } }, { kind: 'invalidate' })
      return { state, effects }
    }
  }
}
