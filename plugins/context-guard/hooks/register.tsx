import type { EngineInterface, PromptOrigin, Register, Timer, ToolCallInput } from 'claude-code'
import { RANK, readBands, resolveZone, type Bands, type Zone } from './zone.ts'

const CONTRACT_DIR = 'context-guard'
const SOURCE_NOTE = '(a measurement from the last API response)'
const STEER =
  "A zone is a measurement, not an instruction: degradation shows in the work itself (drift, repetition, dropped constraints), never in a zone word, and continuation is the operator's call."
const DEGRADED_LABEL = 'dumb (evidence-degraded: this session was compacted)'
const SESSION_ID = /^[A-Za-z0-9_-]+$/
const GATED_TOOLS = ['Write', 'Edit', 'NotebookEdit', 'Agent', 'Workflow']
const PERSON_ORIGINS = ['composer', 'bridge']
const REOFFER_MS = 5_000
const FLOOR_MS = 60_000
// A tick lands a write once the floor has passed, so a write is never later than the floor plus one tick.
const WRITE_TIMER_MS = 15_000
const HELPER = 'lib/write-snapshot.mjs'
const DATA_ITEMS = ['zone', 'percent', 'tokens', 'window']
const ACTIONS = ['none', 'save-state', 'handoff', 'block'] as const
const ACTION_TEXT: Record<Action, string> = {
  none: '',
  'save-state': 'compaction distance is short, so each expensive conclusion goes to a durable note as it stabilizes',
  handoff: 'hand off at the next clean stopping point',
  block: 'new Write, Edit, NotebookEdit, Agent and Workflow calls are denied past the grace budget; handoff-path writes, reads, Bash and Skill calls stay allowed',
}

type Action = (typeof ACTIONS)[number]
type Rule = { action: Action; text?: string }
type Threshold = Rule & { at: number }
type Settings = { bands: Bands; margin: number; actions: Partial<Record<Zone, Rule>>; thresholds: Threshold[] }
type Config = {
  enabled: boolean
  lines: boolean
  operator: boolean
  data: Set<string>
  blocking: boolean
  grace: number
  blockUnattended: boolean
  band: boolean
}
// The tee's snapshot body: reference/reader-contract.md "Snapshot file shape".
type Snapshot = {
  captured_at: string
  session_id: string
  cli_version?: string
  context_window: {
    total_input_tokens?: number
    total_output_tokens?: number
    context_window_size: number
    used_percentage: number | null
    remaining_percentage: number | null
    current_usage: { input_tokens: number; output_tokens: number; cache_creation_input_tokens: number; cache_read_input_tokens: number } | null
  }
}
type Reading = { zone: Zone | undefined; degraded: boolean; percent?: number; tokens?: number; window: number }
type Event =
  | { kind: 'crossing'; from: string; zone: Zone; degraded: boolean; handedOff?: boolean; armedBefore: number }
  | { kind: 'restate'; zone: Zone; degraded: boolean }
  | { kind: 'approach'; zone: Zone; toward: string }
  | { kind: 'threshold'; zone: Zone; degraded: boolean; rule: Threshold }
type Session = {
  armed: number
  last: Zone | undefined
  fired: Set<number>
  approached: Set<string>
  compacted: boolean
  pending: Event[]
  restate: 'all' | 'loud' | undefined
  reading: Reading | undefined
  grace: number
  written: { sig: string; at: number } | undefined
  body: Snapshot | undefined
  offered: Event[]
}
type State = {
  origin: PromptOrigin | undefined
  forceAutomatic: boolean
  notice: string | undefined
  bandShown: boolean
  band: string | undefined
  reading: Reading | undefined
  recheckTool: boolean
  reofferTimer: Timer | undefined
  writeTimer: Timer | undefined
  writing: Promise<void>
  loggedOnce: Set<string>
  sessions: Map<string, Session>
  carry: 'all' | undefined
  settings: Settings
  zonesText: string | null
  zonesKey: string | undefined
}

// plugin.json declares no number bounds, because the engine refuses the whole module for a value
// outside them; the module checks them here, uses the default and names each bad option once.
const badOption = (name: string, kind: string, fallback: string) => `context-guard: option ${name} ${kind}; it reads as the default, ${fallback}`
const quote = (s: string) => JSON.stringify(s.length > 40 ? `${s.slice(0, 40)}...` : s)

export const parseConfig = (options: Record<string, unknown>): Config & { bad: string[] } => {
  const bad: string[] = []
  let items = String(options.zone_line_data ?? '')
    .split(',')
    .map(s => s.trim().toLowerCase())
    .filter(s => s !== '')
  const unknown = items.filter(s => !DATA_ITEMS.includes(s))
  if (unknown.length > 0) {
    bad.push(badOption('zone_line_data', `has an item that is not zone, percent, tokens or window (${quote(unknown.join(', '))})`, 'zone'))
    items = []
  }
  let grace = Number(options.zone_gate_grace_calls ?? 20)
  const graceKind = !Number.isInteger(grace) ? 'not a whole number' : grace < 0 ? 'a negative number' : grace > 999_999_999 ? 'above 999999999' : undefined
  if (graceKind !== undefined) {
    bad.push(badOption('zone_gate_grace_calls', `is ${graceKind}`, '20'))
    grace = 20
  }
  return {
    enabled: options.context_guard_hooks_enabled !== false,
    lines: options.zone_lines_enabled !== false,
    operator: options.zone_report_mode === 'operator',
    data: new Set(['zone', ...items]),
    blocking: options.zone_hook_mode === 'blocking',
    grace,
    blockUnattended: options.zone_block_unattended === 'same-as-typed',
    band: options.context_guard_band !== false,
    bad,
  }
}

const asRule = (value: unknown): Rule | undefined => {
  if (typeof value !== 'object' || value === null) return undefined
  const v = value as Record<string, unknown>
  if (!ACTIONS.includes(v.action as Action)) return undefined
  return { action: v.action as Action, ...(typeof v.text === 'string' && v.text.trim() !== '' ? { text: v.text.trim() } : {}) }
}

// zones.json: the bands as the resolver reads them, plus the mod's keys; an absent or invalid key
// means its default, so a file written for the resolver alone keeps working.
export const parseSettings = (zones: string | null): Settings => {
  const { bands } = readBands(zones)
  let z: Record<string, unknown> = {}
  try {
    const parsed: unknown = zones === null ? {} : JSON.parse(zones)
    if (typeof parsed === 'object' && parsed !== null && !Array.isArray(parsed)) z = parsed as Record<string, unknown>
  } catch {
    // malformed: every mod key takes its default
  }
  const margin = typeof z.approach_margin === 'number' ? z.approach_margin : NaN
  const actionsIn = (typeof z.actions === 'object' && z.actions !== null ? z.actions : {}) as Record<string, unknown>
  const actions: Partial<Record<Zone, Rule>> = {}
  for (const zone of ['smart', 'acceptable', 'dumb'] as const) {
    const rule = asRule(actionsIn[zone])
    if (rule) actions[zone] = rule
  }
  const thresholds = (Array.isArray(z.thresholds) ? z.thresholds : [])
    .map(t => {
      const rule = asRule(t)
      const at = (t as Record<string, unknown>)?.at_percent
      return rule && typeof at === 'number' && at > 0 && at <= 100 ? { ...rule, at } : undefined
    })
    .filter((t): t is Threshold => t !== undefined)
    .sort((a, b) => a.at - b.at)
  return { bands, margin: Number.isFinite(margin) && margin >= 0 && margin < 100 ? margin : 5, actions, thresholds }
}

const newSession = (restate: Session['restate']): Session => ({
  armed: 0,
  last: undefined,
  fired: new Set(),
  approached: new Set(),
  compacted: false,
  pending: [],
  restate,
  reading: undefined,
  grace: 0,
  written: undefined,
  body: undefined,
  offered: [],
})

// Records what the reading crossed since the last one as pending events. Each zone is reported once
// per cycle: a zone's line fires when the session first reaches it, a dip below a boundary changes
// nothing, and only a return to smart opens a new cycle.
export const recordReading = (s: Session, reading: Reading, settings: Settings) => {
  s.reading = reading
  const { zone, percent } = reading
  if (zone === undefined) return
  if (s.restate !== undefined) {
    if (s.restate === 'all' || zone !== 'smart') s.pending.push({ kind: 'restate', zone, degraded: reading.degraded })
    s.restate = undefined
    s.armed = Math.max(s.armed, RANK[zone])
    s.last = zone
    for (const t of settings.thresholds) if (percent !== undefined && percent >= t.at) s.fired.add(t.at)
    return
  }
  if (RANK[zone] > s.armed) {
    s.pending.push({ kind: 'crossing', from: s.last ?? 'unobserved', zone, degraded: reading.degraded, armedBefore: s.armed })
    s.armed = RANK[zone]
  } else if (zone === 'smart' && s.armed > 0) {
    s.armed = 0
    s.fired.clear()
    s.approached.clear()
  }
  s.last = zone
  if (percent === undefined) return
  for (const t of settings.thresholds) {
    if (!s.fired.has(t.at) && percent >= t.at) {
      s.fired.add(t.at)
      s.pending.push({ kind: 'threshold', zone, degraded: reading.degraded, rule: t })
    }
  }
  // One approach line per boundary per cycle, on the percentage shape (points are percentage points).
  if (settings.margin <= 0) return
  const { smart, acceptable } = settings.bands
  const boundaries = [
    { key: 'acceptable', toward: 'the acceptable zone', near: s.armed < 1 && percent >= smart - settings.margin && percent <= smart },
    { key: 'dumb', toward: 'the dumb zone', near: s.armed < 2 && percent >= acceptable - settings.margin && percent <= acceptable },
    ...settings.thresholds.map(t => ({ key: `t${t.at}`, toward: 'an operator threshold', near: !s.fired.has(t.at) && percent >= t.at - settings.margin })),
  ]
  for (const b of boundaries) {
    if (b.near && !s.approached.has(b.key)) {
      s.approached.add(b.key)
      s.pending.push({ kind: 'approach', zone, toward: b.toward })
    }
  }
}

const label = (zone: Zone, degraded: boolean) => (degraded && zone === 'dumb' ? DEGRADED_LABEL : zone)

const dataText = (r: Reading | undefined, cfg: Config) => {
  const items: string[] = []
  if (cfg.data.has('percent') && r?.percent !== undefined) items.push(`${r.percent}% of the window used`)
  if (cfg.data.has('tokens') && r?.tokens !== undefined) items.push(`${r.tokens} tokens in context`)
  if (cfg.data.has('window') && r !== undefined) items.push(`a ${r.window}-token window`)
  return items.length === 0 ? '' : `, ${items.join(', ')}`
}

const sentence = (source: string, rule: Rule) => {
  const text = (rule.text ?? ACTION_TEXT[rule.action]).replace(/\.+$/, '')
  return text === '' || rule.action === 'none' && rule.text === undefined ? '' : ` context-guard (${source}): ${text}.`
}

// The rules a zone carries: its zones.json action, else blocking mode's block at the dumb zone,
// then the dumb zone's default save-state note.
const zoneRules = (zone: Zone, settings: Settings, cfg: Config): { source: string; rule: Rule; via: 'zones' | 'option' | 'default' }[] => {
  const set = settings.actions[zone]
  if (set) return [{ source: `operator setting for the ${zone} zone`, rule: set, via: 'zones' }]
  if (zone !== 'dumb') return []
  return [
    ...(cfg.blocking ? [{ source: 'operator setting for the dumb zone', rule: { action: 'block' as const }, via: 'option' as const }] : []),
    { source: 'default for the dumb zone', rule: { action: 'save-state' as const }, via: 'default' as const },
  ]
}

// The block in force for this session now, if any: its zone's, or a passed threshold's.
const blockFor = (s: Session, settings: Settings, cfg: Config) => {
  const zone = s.reading?.zone
  if (zone === undefined) return undefined
  const rule = zoneRules(zone, settings, cfg).find(r => r.rule.action === 'block')
  if (rule) return { zone, source: rule.source, via: rule.via }
  const t = settings.thresholds.find(th => th.action === 'block' && s.fired.has(th.at))
  return t ? { zone, source: 'operator setting for a threshold', via: 'zones' as const } : undefined
}

export const renderEvent = (e: Event, r: Reading | undefined, cfg: Config, settings: Settings) => {
  const data = dataText(r, cfg)
  const action = (zone: Zone) =>
    zoneRules(zone, settings, cfg)
      .map(z => sentence(z.source, z.rule))
      .join('')
  switch (e.kind) {
    case 'crossing':
      return `context-guard: this session crossed from the ${e.from} into the ${label(e.zone, e.degraded)} context zone${data} ${SOURCE_NOTE}. ${STEER}${action(e.zone)}`
    case 'restate':
      return `context-guard: this session is in the ${label(e.zone, e.degraded)} context zone${data} ${SOURCE_NOTE}. ${STEER}${action(e.zone)}`
    case 'approach':
      return `context-guard: this session is in the ${e.zone} context zone${data}, approaching ${e.toward} ${SOURCE_NOTE}.`
    case 'threshold':
      return `context-guard: this session passed an operator threshold in the ${label(e.zone, e.degraded)} context zone${data} ${SOURCE_NOTE}. ${STEER}${sentence('operator setting for a threshold', e.rule)}`
  }
}

const homeDir = async ($: EngineInterface) => (await $.env.get('HOME')) || (await $.env.get('USERPROFILE')) || undefined

// zones.json, re-read only when it appears, disappears or its mtime moves.
async function loadSettings($: EngineInterface, st: State, home: string | undefined) {
  if (home === undefined) return st.settings
  const path = `${home}/.claude/${CONTRACT_DIR}/zones.json`
  const stat = await $.fs.stat(path).catch(() => undefined)
  const key = stat === undefined ? 'absent' : `${stat.mtimeMs}:${stat.size}`
  if (key !== st.zonesKey) {
    const text = stat === undefined ? null : await $.fs.read(path).then(String).catch(() => null)
    st.settings = parseSettings(text)
    st.zonesText = text
    st.zonesKey = key
  }
  return st.settings
}

const isoSeconds = (ms: number) => new Date(ms).toISOString().replace(/\.\d{3}Z$/, 'Z')

// The session's state, created on first use: after /clear or a resume no session.start fires, so
// every hook starts the new conversation's state lazily.
const sessionFor = (st: State, sid: string) => {
  let s = st.sessions.get(sid)
  if (s === undefined) {
    s = newSession(st.carry)
    st.carry = undefined
    st.sessions.set(sid, s)
  }
  return s
}

async function current($: EngineInterface, st: State) {
  return sessionFor(st, await $.session.id())
}

async function refresh($: EngineInterface, st: State) {
  const sid = await $.session.id()
  const s = sessionFor(st, sid)
  const home = await homeDir($)
  const [usage, version, now, settings] = await Promise.all([
    $.session.usage({ breakdown: 'summary' }),
    $.session.version().catch(() => undefined),
    $.clock.now(),
    loadSettings($, st, home),
  ])
  const c = usage.context
  const api = c.breakdown?.apiUsage ?? null
  const body: Snapshot = {
    captured_at: isoSeconds(now),
    session_id: sid,
    ...(version?.version ? { cli_version: version.version } : {}),
    context_window: {
      ...(c.tokens === undefined ? {} : { total_input_tokens: c.tokens }),
      ...(api ? { total_output_tokens: api.output_tokens } : {}),
      context_window_size: c.window,
      used_percentage: c.percent ?? null,
      remaining_percentage: c.percent === undefined ? null : 100 - c.percent,
      current_usage: api
        ? {
            input_tokens: api.input_tokens,
            output_tokens: api.output_tokens,
            cache_creation_input_tokens: api.cache_creation_input_tokens,
            cache_read_input_tokens: api.cache_read_input_tokens,
          }
        : null,
    },
  }
  const { word } = resolveZone({ sid, snapshot: JSON.stringify(body), zones: st.zonesText, nowSec: Math.floor(now / 1000) })
  if (!s.compacted && home !== undefined && SESSION_ID.test(sid)) {
    s.compacted = await $.fs.exists(`${home}/.claude/${CONTRACT_DIR}/context/${sid}.compacted`).catch(() => false)
  }
  const zone = s.compacted ? 'dumb' : word === 'unknown' ? undefined : word
  const reading: Reading = { zone, degraded: s.compacted, percent: c.percent, tokens: c.tokens, window: c.window }
  recordReading(s, reading, settings)
  // A reading with no figures (usage gone at exit, or between responses) never replaces one that had them.
  if (body.context_window.used_percentage !== null || s.body === undefined || s.body.context_window.used_percentage === null) s.body = body
  st.reading = reading
  const band = bandText(reading, undefined)
  if (band !== st.band) {
    st.band = band
    $.ui.invalidate('ui.render')
  }
  return { sid, s, body, settings }
}

const isPersonTurn = (st: State) => st.origin !== undefined && PERSON_ORIGINS.includes(st.origin.kind)

// Operator mode holds the lines in a turn a person typed, where a suggestion can show.
async function operatorHolds($: EngineInterface, st: State, cfg: Config) {
  if (!cfg.operator || st.forceAutomatic || !isPersonTurn(st)) return false
  return (await $.session.surfaces()).length > 0
}

// The continuation menu is the operator's: a transcript line Claude does not read, and a band
// notice until the person's next prompt. It never goes into Claude's context.
const menuText = (from: string, to: string) =>
  `context-guard: context zone ${from} → ${to}. Response quality can degrade as context fills (bands tunable: zones.json). ` +
  'Continuation options, yours to choose: continue; /compact; /clear; /session-flow:handoff (if installed) or a hand-written ' +
  'resume note, then /clear. To pick one, route the next step with /session-flow:workflow (if installed); without it, see ' +
  'https://code.claude.com/docs/en/context-window#when-your-context-fills-up.'

// The lines a carrier attaches now, consumed; none when none is due or operator mode holds them.
// One fire of a hook, for its telemetry envelope: the event, when it started, and the optional
// correlation keys (docs/conventions/hook-telemetry, "Correlation keys").
type Fire = { event: string; startMs: number; toolUseId?: unknown; agentId?: unknown }
const PLAIN_ID = /^[A-Za-z0-9._-]+$/
const RANK_WORD = ['smart', 'acceptable', 'dumb'] as const

// Sends one envelope to HOOK_TELEMETRY_SINK, fire-and-forget; no sink set, nothing is sent. A
// relative sink path is joined onto the session's project root, else skipped.
async function emitTelemetry($: EngineInterface, hook: string, status: string, data: Record<string, unknown>, fire: Fire) {
  const sink = await $.env.get('HOOK_TELEMETRY_SINK')
  if (!sink) return
  let path = sink
  if (!/^(\/|[A-Za-z]:[\\/])/.test(sink)) {
    const root = (await $.session.root().catch(() => undefined)) || (await $.env.get('CLAUDE_PROJECT_DIR'))
    if (!root) return
    path = `${root.replace(/[\\/]+$/, '')}/${sink}`
  }
  const [now, sid] = await Promise.all([$.clock.now(), $.session.id()])
  const corr = Object.fromEntries(
    [
      ['session_id', sid],
      ['tool_use_id', fire.toolUseId],
      ['agent_id', fire.agentId],
    ].filter(([, v]) => typeof v === 'string' && PLAIN_ID.test(v)),
  )
  const envelope = {
    schema_version: '1.1',
    timestamp: isoSeconds(now),
    hook,
    hook_event: fire.event,
    status,
    duration_ms: Math.max(0, Math.round(now - fire.startMs)),
    ...corr,
    data,
  }
  void $.process.run([path], { stdin: `${JSON.stringify(envelope)}\n`, timeoutMs: 10_000 }).catch(() => undefined)
}

// zone-crossing-inject's data for a fire that sent lines (data/zone-crossing-inject.schema.json).
const crossingData = (s: Session, events: Event[], extra: Record<string, unknown>) => {
  const crossed = events.filter(e => e.kind === 'crossing').at(-1)
  const zone = s.reading?.zone ?? 'unknown'
  return crossed?.kind === 'crossing'
    ? { zone, previous: crossed.from === 'unobserved' ? '' : crossed.from, armed: RANK_WORD[crossed.armedBefore], ...extra }
    : { zone, previous: s.last ?? '', armed: RANK_WORD[s.armed], ...extra }
}

async function takeLines($: EngineInterface, st: State, cfg: Config, fire: Fire): Promise<string[]> {
  const s = st.sessions.get(await $.session.id())
  if (s === undefined) return []
  if (!cfg.enabled) {
    s.pending = []
    return []
  }
  if (cfg.lines && (await operatorHolds($, st, cfg))) return []
  const taken = s.pending.splice(0)
  // A restatement says the current verdict, so a crossing or an earlier restatement due at the same
  // carrier merges into it rather than reaching Claude twice.
  const lastRestate = taken.findLastIndex(e => e.kind === 'restate')
  const events = lastRestate < 0 ? taken : taken.filter((e, i) => i === lastRestate || (e.kind !== 'crossing' && e.kind !== 'restate'))
  st.forceAutomatic = false
  const crossed = events.filter(e => e.kind === 'crossing' && !e.handedOff).at(-1)
  if (crossed?.kind === 'crossing') {
    st.notice = menuText(crossed.from, label(crossed.zone, crossed.degraded))
    $.ui.log(st.notice)
    $.ui.invalidate('ui.render')
  }
  if (!cfg.lines || events.length === 0) return []
  await emitTelemetry($, 'zone-crossing-inject', 'ok', crossingData(s, events, { injected: true }), fire)
  return events.map(e => renderEvent(e, s.reading, cfg, st.settings))
}

// Offers the held lines as the prompt box's suggestion. With text in the box it waits (false);
// where a suggestion cannot show, the lines go to Claude at the next carrier.
async function offer($: EngineInterface, st: State, s: Session, fire: Fire) {
  if (st.notice === undefined) return true
  const box = await $.prompt.read()
  if (box.text.trim() !== '') return false
  const { isShown } = await $.prompt.suggest({ text: st.notice })
  if (isShown) {
    await emitTelemetry($, 'zone-crossing-inject', 'ok', crossingData(s, s.pending, { injected: false, suggested: true }), fire)
    // Shown is not taken: kept until the next turn says whether a person saw it.
    s.offered.push(...s.pending.splice(0))
  } else {
    st.notice = undefined
    st.forceAutomatic = true
  }
  $.ui.invalidate('ui.render')
  return true
}

function stopTimer(timer: Timer | undefined) {
  timer?.cancel()
  return undefined
}

// The tee's standalone status line, as a band row: [<model>] ctx <n>% (<zone>).
export const bandText = (r: Reading | undefined, model: string | undefined) => {
  const zone = r?.zone === undefined ? '' : ` (${r.degraded && r.zone === 'dumb' ? 'dumb, compacted' : r.zone})`
  return `[${model || 'Claude'}] ctx ${r?.percent === undefined ? '-' : `${r.percent}%${zone}`}`
}

async function statusJson($: EngineInterface, st: State, cfg: Config) {
  const { s, body, settings } = await refresh($, st)
  const w = body.context_window
  return JSON.stringify({
    source: 'the last API response',
    zone: s.reading?.zone ?? 'unknown',
    evidence_degraded: s.compacted,
    used_percentage: w.used_percentage,
    total_input_tokens: w.total_input_tokens ?? null,
    total_output_tokens: w.total_output_tokens ?? null,
    context_window_size: w.context_window_size,
    bands: { smart_max_used_percentage: settings.bands.smart, acceptable_max_used_percentage: settings.bands.acceptable },
    approach_margin: settings.margin,
    gate: { mode: cfg.blocking ? 'blocking' : 'advisory', grace_calls: cfg.grace, calls_counted: s.grace },
  })
}

const logOnce = ($: EngineInterface, st: State, key: string, text: string) => {
  if (st.loggedOnce.has(key)) return
  st.loggedOnce.add(key)
  $.ui.log(`context-guard: ${text}`, { to: 'debug' })
}

// Writes the session's snapshot through the shared helper. Decided in memory: a body unchanged
// since the last write is rewritten at most once per 60 s (floor-bound in the helper too), so a
// call that writes nothing starts no process. Where $.process.run is unavailable nothing is
// written; readers then read unknown, as they do with no file.
async function writeSnapshot($: EngineInterface, st: State, read: boolean) {
  const sid = await $.session.id()
  if (read) await refresh($, st)
  const s = st.sessions.get(sid)
  const body = s?.body
  if (s === undefined || body === undefined) return
  const home = await homeDir($)
  if (home === undefined || !SESSION_ID.test(sid)) return
  const now = await $.clock.now()
  const sig = JSON.stringify({ ...body, captured_at: undefined })
  const same = s.written?.sig === sig
  if (same && s.written !== undefined && now - s.written.at < FLOOR_MS) return
  s.written = { sig, at: now }
  const target = `${home}/.claude/${CONTRACT_DIR}/context/${sid}.json`
  const argv = ['node', `${$.plugin.root}/${HELPER}`, target, '--prune', ...(same ? ['--floor', String(FLOOR_MS / 1000)] : [])]
  try {
    const run = await $.process.run(argv, { stdin: JSON.stringify(body), timeoutMs: 10_000 })
    if (run.exitCode !== 0 && run.exitCode !== 3) {
      logOnce($, st, 'write-failed', `snapshot write failed (exit ${run.exitCode}): ${run.stderr.trim()}`)
    }
  } catch (error) {
    logOnce($, st, 'write-threw', `snapshot write did not run: ${error instanceof Error ? error.message : String(error)}`)
  }
}

function queueWrite($: EngineInterface, st: State, read = false) {
  st.writing = st.writing.then(() => writeSnapshot($, st, read)).catch(() => undefined)
  return st.writing
}

// A refused tool registration (a policy can refuse a user mod's tools) is logged once; everything
// else the module does carries on without the tool.
async function registerSurfaces($: EngineInterface, st: State) {
  const [tool] = await Promise.allSettled([
    $.tool.register({
      name: 'status',
      description:
        "Read-only. Returns this session's context-window figures as the last API response reported them, with " +
        "context-guard's zone (smart, acceptable, dumb or unknown), whether a compaction degraded the evidence, the " +
        'bands in force and the gate state, as JSON. Takes no input.',
      inputSchema: { type: 'object', properties: {}, additionalProperties: false },
    }),
    $.command.register({
      name: 'band',
      description: 'Show or hide the context-guard band row for this session: show, hide, or nothing to toggle',
      argumentHint: '[show|hide]',
    }),
  ])
  if (tool.status === 'rejected') {
    const reason = tool.reason instanceof Error ? tool.reason.message : String(tool.reason)
    logOnce($, st, 'tool-register', `the status tool could not register: ${reason}`)
  }
}

// Blocking: the reason a gated call is denied, or undefined to let it run. A typed turn gets the
// configured block; an unattended turn only the post-compaction one, unless configured otherwise.
// The budget counts in memory, synchronously after the reading, so calls dispatched together never
// overspend it.
async function gate($: EngineInterface, st: State, cfg: Config, e: ToolCallInput, fire: Fire) {
  if (!cfg.enabled || !GATED_TOOLS.includes(e.tool)) return undefined
  const { s, settings } = await refresh($, st)
  const block = blockFor(s, settings, cfg)
  if (block === undefined) {
    s.grace = 0
    return undefined
  }
  if (!isPersonTurn(st) && !cfg.blockUnattended && !s.compacted) return undefined
  const input = e as unknown as { file_path?: unknown; notebook_path?: unknown }
  const target = String(input.file_path ?? input.notebook_path ?? '')
  if (/handoff/i.test(target)) return undefined
  s.grace += 1
  if (s.grace <= cfg.grace) return undefined
  await emitTelemetry($, 'zone-gate', 'blocked', { zone: block.zone, grace: cfg.grace, calls_seen: s.grace }, fire)
  const off = block.via === 'option' ? 'zone_hook_mode advisory turns the gate off.' : 'The actions entry in zones.json sets this gate.'
  return (
    `context-guard blocking mode (${block.source}): this session is in the ${block.zone} context zone and the grace budget of ` +
    `${cfg.grace} matched calls is spent, so new ${e.tool} work is denied. Handoff-path writes, read-only tools, Bash and Skill ` +
    `calls stay allowed; /session-flow:handoff (if installed) writes a save-point this gate exempts. ${off}`
  )
}

export const register: Register = (on, options) => {
  const cfg = parseConfig(options)
  const st: State = {
    origin: undefined,
    forceAutomatic: false,
    notice: undefined,
    bandShown: cfg.band,
    band: undefined,
    reading: undefined,
    recheckTool: false,
    reofferTimer: undefined,
    writeTimer: undefined,
    writing: Promise.resolve(),
    loggedOnce: new Set(),
    sessions: new Map(),
    carry: undefined,
    settings: parseSettings(null),
    zonesText: null,
    zonesKey: undefined,
  }

  on('session.start', async ($, e, next) => {
    for (const line of cfg.bad) {
      if (!st.loggedOnce.has(line)) $.ui.log(line)
      st.loggedOnce.add(line)
    }
    await registerSurfaces($, st)
    // A fresh load mid-session (a reload, a worker respawn, an enable, a --resume launch): the
    // earlier lines already reached Claude, so only a verdict past smart is restated.
    if ((await $.session.turns()) > 0) {
      const s = await current($, st)
      s.pending = []
      s.restate = 'loud'
    }
    return next(e)
  }).catch(($, e, next) => next(e))

  on('session.end', async ($, e, next) => {
    st.reofferTimer = stopTimer(st.reofferTimer)
    st.writeTimer = stopTimer(st.writeTimer)
    // A -p exit does not drop the last reading the floor held back. The last refreshed body, not
    // a fresh read: usage at exit can come back empty, and a session never refreshed writes nothing.
    await queueWrite($, st)
    st.sessions.delete(e.sessionId)
    st.carry = e.reason === 'resume' ? 'all' : undefined
    st.origin = undefined
    st.recheckTool = true
    return next(e)
  }).catch(($, e, next) => next(e))

  on('session.compact', async ($, e, next) => {
    const result = await next(e)
    if (e.agentId === undefined && e.trigger !== 'precompute' && !('skip' in result && result.skip)) {
      const s = await current($, st)
      s.compacted = true
      s.restate = 'all'
      s.grace = 0
    }
    return result
  }).catch(($, e, next) => next(e))

  on('prompt.submit', async ($, e, next) => {
    const startMs = await $.clock.now()
    // Only a prompt that starts a turn sets its origin; one delivered into a running turn does not.
    if (e.turnId === undefined) {
      st.origin = e.origin
      // A shown suggestion: a person's turn means they saw it and chose, so it goes unsent; a turn
      // no person started (a --bg launch turn reads as typed, so its suggestion went unseen) gets
      // it as the ordinary line.
      const s = await current($, st)
      const handOff = s.offered.splice(0)
      if (!isPersonTurn(st)) s.pending.unshift(...handOff.map(ev => (ev.kind === 'crossing' ? { ...ev, handedOff: true } : ev)))
      if (st.notice !== undefined && (isPersonTurn(st) || handOff.length > 0)) {
        st.notice = undefined
        st.reofferTimer = stopTimer(st.reofferTimer)
        $.ui.invalidate('ui.render')
      }
    }
    // session.start does not fire after /clear or a resume: register the tool again if it is gone.
    if (st.recheckTool) {
      st.recheckTool = false
      const tools = await $.tool.list().catch(() => undefined)
      if (tools !== undefined && !tools.some(t => t.name === `mcp__${$.plugin.name}__status`)) await registerSurfaces($, st)
    }
    await refresh($, st)
    const lines = await takeLines($, st, cfg, { event: 'prompt.submit', startMs })
    return next(lines.length === 0 ? e : { ...e, context: [...(e.context ?? []), ...lines] })
  }).catch(($, e, next) => next(e))

  on('session.measure', async ($, e, next) => {
    await refresh($, st)
    await queueWrite($, st)
    return next(e)
  }).catch(($, e, next) => next(e))

  on('turn.start', async ($, e, next) => {
    st.reofferTimer = stopTimer(st.reofferTimer)
    // Keeps the snapshot fresh through one long tool call or subagent run, as the tee's renders did.
    st.writeTimer ??= $.clock.every(WRITE_TIMER_MS, () => {
      void queueWrite($, st, true)
    })
    return next(e)
  }).catch(($, e, next) => next(e))

  on('turn.complete', async ($, e, next) => {
    if (e.agentId !== undefined) return next(e)
    const startMs = await $.clock.now()
    st.writeTimer = stopTimer(st.writeTimer)
    if (cfg.enabled && cfg.lines && (await operatorHolds($, st, cfg))) {
      const s = await current($, st)
      const lines = s.pending.map(ev => renderEvent(ev, s.reading, cfg, st.settings))
      if (lines.length > 0) {
        st.notice = `FYI, ${lines.join(' ')}`
        $.ui.invalidate('ui.render')
        const fire: Fire = { event: 'turn.complete', startMs }
        if (!(await offer($, st, s, fire))) {
          st.reofferTimer ??= $.clock.every(REOFFER_MS, () => {
            void offer($, st, s, fire)
              .then(done => {
                if (done) st.reofferTimer = stopTimer(st.reofferTimer)
              })
              .catch(() => undefined)
          })
        }
      }
    }
    return next(e)
  }).catch(($, e, next) => next(e))

  on('command.run', async ($, e, next) => {
    if (e.command !== 'band' && e.command !== `${$.plugin.name}:band`) return next(e)
    const arg = e.args.trim().toLowerCase()
    st.bandShown = arg === 'show' ? true : arg === 'hide' ? false : !st.bandShown
    $.ui.invalidate('ui.render')
    return { text: `context-guard: band row ${st.bandShown ? 'shown' : 'hidden'} for this session` }
  }).catch(($, e, next) => next(e))

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const theirs = await next(e)
    if (e.props.hasSurvey || (!st.bandShown && st.notice === undefined)) return theirs
    const { Box, Text } = $.ui.resolve(e)
    return (
      <Box flexDirection="column">
        {st.bandShown ? (
          <Text dimColor wrap="truncate">
            {bandText(st.reading, await $.session.model().catch(() => undefined))}
          </Text>
        ) : null}
        {st.notice !== undefined ? <Text wrap="truncate">{`context-guard notice: ${st.notice}`}</Text> : null}
        {theirs}
      </Box>
    )
  }).catch(($, e, next) => next(e))

  on('tool.call', async ($, e, next) => {
    if (e.tool === `mcp__${$.plugin.name}__status`) return { result: await statusJson($, st, cfg) }
    const fire: Fire = { event: 'tool.call', startMs: await $.clock.now(), toolUseId: (e as { tool_use_id?: unknown }).tool_use_id, agentId: e.agentId }
    const deny = await gate($, st, cfg, e, fire)
    if (deny !== undefined) return { deny }
    const result = await next(e)
    await refresh($, st)
    await queueWrite($, st)
    if (e.agentId !== undefined) return result
    if (result.deny !== undefined || result.isError) return result
    const lines = await takeLines($, st, cfg, fire)
    return lines.length === 0 ? result :{ ...result, context: [...(result.context ?? []), ...lines] }
  }).catch(($, e, next) => next(e))
}
