import type { EngineInterface, PromptOrigin, Register, Timer, ToolCallInput } from 'claude-code'
import { RANK, readBands, resolveZone, tokenShape, type Bands, type TokenShape, type Zone } from './zone.ts'

const CONTRACT_DIR = 'context-guard'
const PREFIX = 'context-guard: '
const NEXT_ZONE: Partial<Record<Zone, Zone>> = { smart: 'acceptable', acceptable: 'dumb' }
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
  'save-state': 'save-state',
  handoff: 'handoff',
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
  toast: boolean
}
// The snapshot body: reference/reader-contract.md "Snapshot file shape".
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
type Reading = { zone: Zone | undefined; degraded: boolean; percent?: number; tokens?: number; window: number; token?: TokenShape }
// shown: the person's channel has handled it: the batch's last crossing got the transcript line
// (and the toast, when on), or it came from 'unobserved' and was deliberately skipped.
type Crossing = { kind: 'crossing'; from: string; zone: Zone; degraded: boolean; handedOff?: boolean; shown?: boolean; armedBefore: number }
type Event =
  | Crossing
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
  restate: boolean
  reading: Reading | undefined
  grace: number
  written: { sig: string; at: number } | undefined
  body: Snapshot | undefined
  offered: Event[]
}
// A crossing's notice is drawn only where a toast may not show (any surface but the terminal);
// operator mode's held line is drawn on every surface.
type Notice = { text: string; kind: 'crossing' | 'operator' }
type State = {
  origin: PromptOrigin | undefined
  forceAutomatic: boolean
  notice: Notice | undefined
  bandShown: boolean
  band: string | undefined
  reading: Reading | undefined
  recheckTool: boolean
  reofferTimer: Timer | undefined
  writeTimer: Timer | undefined
  writing: Promise<void>
  loggedOnce: Set<string>
  sessions: Map<string, Session>
  carry: boolean
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
    band: options.context_guard_band === true,
    toast: options.context_guard_toast !== false,
    bad,
  }
}

// C0 and C1 controls, DEL and the Unicode line and paragraph separators each break a line
const breaksLine = (c: number): boolean => c < 0x20 || (c >= 0x7f && c <= 0x9f) || c === 0x2028 || c === 0x2029
const oneLine = (s: string): string => {
  let out = ''
  let inRun = false
  for (const ch of s) {
    const brk = breaksLine(ch.charCodeAt(0))
    if (!brk) out += ch
    else if (!inRun) out += ' '
    inRun = brk
  }
  return out.trim()
}

const asRule = (value: unknown): Rule | undefined => {
  if (typeof value !== 'object' || value === null) return undefined
  const v = value as Record<string, unknown>
  if (!ACTIONS.includes(v.action as Action)) return undefined
  // one line: a newline in the operator's text must not start a line that reads as the guard's own
  const text = typeof v.text === 'string' ? oneLine(v.text) : ''
  return { action: v.action as Action, ...(text !== '' ? { text } : {}) }
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
  if (s.restate) {
    if (zone !== 'smart') s.pending.push({ kind: 'restate', zone, degraded: reading.degraded })
    s.restate = false
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
  if (percent !== undefined) {
    for (const t of settings.thresholds) {
      if (!s.fired.has(t.at) && percent >= t.at) {
        s.fired.add(t.at)
        s.pending.push({ kind: 'threshold', zone, degraded: reading.degraded, rule: t })
      }
    }
  }
  // One approach line per boundary per cycle, in the shape that decides the boundary: the token
  // shape when its edge sits below the percentage edge, else the percentage shape. The margin is in
  // percentage points, of the window in the token shape.
  if (settings.margin <= 0) return
  const { smart, acceptable } = settings.bands
  const tok = reading.token
  const near = (edgePercent: number, edgeTokens: number | undefined) => {
    if (tok !== undefined && edgeTokens !== undefined && (percent === undefined || edgeTokens < (edgePercent * tok.size) / 100)) {
      return tok.used >= edgeTokens - (settings.margin * tok.size) / 100 && tok.used <= edgeTokens
    }
    return percent !== undefined && percent >= edgePercent - settings.margin && percent <= edgePercent
  }
  const boundaries = [
    { key: 'acceptable', toward: 'acceptable', near: s.armed < 1 && near(smart, tok?.smart) },
    { key: 'dumb', toward: 'dumb', near: s.armed < 2 && near(acceptable, tok?.acceptable) },
    ...settings.thresholds.map(t => ({
      key: `t${t.at}`,
      toward: 'an operator threshold',
      near: percent !== undefined && !s.fired.has(t.at) && percent >= t.at - settings.margin,
    })),
  ]
  for (const b of boundaries) {
    if (b.near && !s.approached.has(b.key)) {
      s.approached.add(b.key)
      s.pending.push({ kind: 'approach', zone, toward: b.toward })
    }
  }
}

// The verdict as Claude and the person read it: acceptable zone (2 of 3), dumb zone (3 of 3, compacted).
const verdictText = (zone: Zone, degraded: boolean) => `${zone} zone (${RANK[zone] + 1} of 3${degraded && zone === 'dumb' ? ', compacted' : ''})`

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

// The rules a zone carries: its zones.json action, else blocking mode's block at the dumb zone.
const zoneRules = (zone: Zone, settings: Settings, cfg: Config): { source: string; rule: Rule }[] => {
  const set = settings.actions[zone]
  if (set) return [{ source: `operator setting for the ${zone} zone`, rule: set }]
  return zone === 'dumb' && cfg.blocking ? [{ source: 'operator setting for the dumb zone', rule: { action: 'block' } }] : []
}

// The zone whose block is in force for this session now, if any: its zone's, or a passed threshold's.
const blockFor = (s: Session, settings: Settings, cfg: Config) => {
  const zone = s.reading?.zone
  if (zone === undefined) return undefined
  if (zoneRules(zone, settings, cfg).some(r => r.rule.action === 'block')) return zone
  return settings.thresholds.some(th => th.action === 'block' && s.fired.has(th.at)) ? zone : undefined
}

export const renderEvent = (e: Event, s: Session, cfg: Config, settings: Settings) => {
  const data = dataText(s.reading, cfg)
  const action = (zone: Zone) =>
    zoneRules(zone, settings, cfg)
      .map(z => sentence(z.source, z.rule))
      .join('')
  // A line states facts only: what to do about them is left to the model and the user.
  const line = (zone: Zone, degraded: boolean, hint: string) => `context-guard: ${verdictText(zone, degraded)}${data}${hint}.`
  // Within the approach margin of the next zone's boundary, the verdict says which zone is near.
  const near = (zone: Zone) => {
    const toward = NEXT_ZONE[zone]
    return toward !== undefined && s.approached.has(toward) ? `, nearing ${toward}` : ''
  }
  switch (e.kind) {
    case 'crossing':
    case 'restate':
      return `${line(e.zone, e.degraded, near(e.zone))}${action(e.zone)}`
    case 'approach':
      return line(e.zone, false, `, nearing ${e.toward}`)
    case 'threshold':
      return `${line(e.zone, e.degraded, ', past an operator threshold')}${sentence('operator setting for a threshold', e.rule)}`
  }
}

// The verdict lines due at one carrier: a line that another one already starts with (an approach
// line its crossing repeats, with or without an action after it) is sent once.
const renderAll = (events: Event[], s: Session, cfg: Config, settings: Settings) => {
  const lines = [...new Set(events.map(e => renderEvent(e, s, cfg, settings)))]
  return lines.filter(l => !lines.some(o => o !== l && o.startsWith(l)))
}

// Appends lines to what Claude reads and writes each to the debug log, so the log holds what Claude was told.
const withLines = <T extends { context?: readonly string[] }>($: EngineInterface, e: T, lines: readonly string[]): T => {
  for (const line of lines) $.ui.log(line, { to: 'debug' })
  return lines.length === 0 ? e : { ...e, context: [...(e.context ?? []), ...lines] }
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
    st.carry = false
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
  const token = tokenShape(body.context_window, body.cli_version, settings.bands)
  const reading: Reading = { zone, degraded: s.compacted, percent: c.percent, tokens: c.tokens, window: c.window, token }
  recordReading(s, reading, settings)
  // A reading with no figures (usage gone at exit, or between responses) never replaces one that had them.
  if (body.context_window.used_percentage !== null || s.body === undefined || s.body.context_window.used_percentage === null) s.body = body
  st.reading = reading
  const band = bandText(reading)
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

// The continuation menu is the person's: a toast, and a transcript line Claude does not read. It
// never goes into Claude's context. The engine titles the toast with the plugin's name.
const toastText = (from: string, to: string) => `${from} → ${to} · continue, /compact, /clear or handoff`
const menuLine = (from: string, to: string) =>
  `context-guard: ${from} → ${to} · options: continue, /compact, /clear, or /session-flow:handoff then /clear · more: /context-guard`
const menuZone = (zone: Zone, degraded: boolean) => (degraded && zone === 'dumb' ? 'dumb (compacted)' : zone)
const noticeShows = (st: State, surface: string) => st.notice !== undefined && (st.notice.kind === 'operator' || surface !== 'terminal')

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
  const holds = cfg.lines && (await operatorHolds($, st, cfg))
  // A restatement says the verdict as of when it was recorded, so a crossing or an earlier
  // restatement before it merges into it rather than reaching Claude twice. A crossing recorded
  // after it is the newer verdict and replaces it. No await from here until s.pending is replaced.
  const pending = s.pending
  const lastRestate = pending.findLastIndex(e => e.kind === 'restate')
  const keep = pending.findLastIndex(e => e.kind === 'crossing') > lastRestate ? -1 : lastRestate
  const merged =
    lastRestate < 0 ? pending : pending.filter((e, i) => i > lastRestate || i === keep || (e.kind !== 'crossing' && e.kind !== 'restate'))
  // A hold keeps lines for the suggestion, except a crossing the person was already shown (read in an
  // unattended turn): offering it again would repeat it, so it goes to Claude as in automatic mode.
  const seen = (e: Event) => e.kind === 'crossing' && e.shown === true
  const events = holds ? merged.filter(seen) : merged
  s.pending = holds ? merged.filter(e => !seen(e)) : []
  if (holds && events.length === 0) return []
  st.forceAutomatic = false
  let lines: string[] = []
  if (cfg.lines && events.length > 0) {
    await emitTelemetry($, 'zone-crossing-inject', 'ok', crossingData(s, events, { injected: true }), fire)
    lines = renderAll(events, s, cfg, st.settings)
  }
  // The person's channel runs after Claude's lines are built, so a failing toast never drops one.
  showCrossing($, st, cfg, events)
  return lines
}

// Shows the person the last crossing among events not yet shown: a toast, a transcript line and the
// crossing notice. Each crossing is shown once. A handed-off suggestion already reached the person,
// and a crossing from 'unobserved' (a first reading already past smart) is never shown.
function showCrossing($: EngineInterface, st: State, cfg: Config, events: Event[]) {
  const due = events.filter((e): e is Crossing => e.kind === 'crossing' && !e.handedOff && !e.shown)
  const crossed = due.at(-1)
  const showable = crossed !== undefined && crossed.from !== 'unobserved'
  const to = showable ? menuZone(crossed.zone, crossed.degraded) : ''
  if (showable) {
    st.notice = { text: menuLine(crossed.from, to), kind: 'crossing' }
    $.ui.log(st.notice.text)
  }
  for (const e of due) e.shown = true
  if (!showable) return
  // The engine drops a failing toast itself; it never throws into the module.
  if (cfg.toast) $.ui.toast(toastText(crossed.from, to))
  $.ui.invalidate('ui.render')
}

// A crossing read with a turn's final answer has no carrier until the next prompt, so the person
// sees it at the measurement; Claude's line still waits for that carrier. A turn operator mode
// holds keeps it for the suggestion.
async function showPending($: EngineInterface, st: State, cfg: Config) {
  const s = st.sessions.get(await $.session.id())
  if (s === undefined || !cfg.enabled) return
  if (cfg.lines && (await operatorHolds($, st, cfg))) return
  showCrossing($, st, cfg, s.pending)
}

// Offers the held lines as the prompt box's suggestion. With text in the box it waits (false);
// where a suggestion cannot show, the lines go to Claude at the next carrier.
async function offer($: EngineInterface, st: State, s: Session, fire: Fire) {
  if (st.notice?.kind !== 'operator') return true
  const box = await $.prompt.read()
  if (box.text.trim() !== '') return false
  const { isShown } = await $.prompt.suggest({ text: st.notice.text })
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

// The band row: ctx <n>% (<zone>).
export const bandText = (r: Reading | undefined) => {
  const zone = r?.zone === undefined ? '' : ` (${r.degraded && r.zone === 'dumb' ? 'dumb, compacted' : r.zone})`
  return `ctx ${r?.percent === undefined ? '-' : `${r.percent}%${zone}`}`
}

const USAGE = 'usage: /context-guard [band [on|off]]'
const README = 'https://github.com/melodic-software/claude-code-plugins/blob/main/plugins/context-guard/README.md'
const DOCS = 'https://code.claude.com/docs/en/context-window#when-your-context-fills-up'

// /context-guard with no argument: the verdict with its figures and the settings in force. The reply
// is stored as a transcript row Claude reads, so it carries no menu, router pointer or link; those
// go to a transcript line Claude does not read.
const POINTER = `context-guard: next step: route it with /session-flow:workflow (if installed), or see ${DOCS} · more: ${README}`
async function statusText($: EngineInterface, st: State, cfg: Config) {
  const { s, body, settings } = await refresh($, st)
  await showPending($, st, cfg)
  const r = s.reading
  const w = body.context_window
  const verdict = r?.zone === undefined ? 'zone unknown' : verdictText(r.zone, r.degraded)
  const figures =
    w.used_percentage === null
      ? `no reading yet (a ${w.context_window_size}-token window)`
      : `${w.used_percentage}% of a ${w.context_window_size}-token window used (${w.total_input_tokens ?? '?'} tokens)`
  const home = await homeDir($)
  const zones = home === undefined ? 'zones.json: no home directory' : `${home}/.claude/${CONTRACT_DIR}/zones.json (${st.zonesText === null ? 'absent' : 'present'})`
  const { smart, acceptable } = settings.bands
  const t = tokenShape(w, body.cli_version, settings.bands)
  const bands = t
    ? `Bands (the worse decides): smart up to ${smart}% and ${t.smart} tokens, acceptable up to ${acceptable}% and ${t.acceptable} tokens`
    : `Bands: smart up to ${smart}%, acceptable up to ${acceptable}%`
  return [
    `${verdict}, ${figures}`,
    `${bands}; approach margin ${settings.margin} points; gate ${cfg.blocking ? `blocking, ${cfg.grace} grace calls` : 'advisory'}`,
    `This session: band row ${st.bandShown ? 'on' : 'off'}, zone-change toast ${cfg.toast ? 'on' : 'off'}`,
    `Settings: ${zones}`,
  ].join('\n')
}

async function statusJson($: EngineInterface, st: State, cfg: Config) {
  const { s, body, settings } = await refresh($, st)
  await showPending($, st, cfg)
  const w = body.context_window
  const t = tokenShape(w, body.cli_version, settings.bands)
  return JSON.stringify({
    source: 'the last API response',
    zone: s.reading?.zone ?? 'unknown',
    evidence_degraded: s.compacted,
    used_percentage: w.used_percentage,
    total_input_tokens: w.total_input_tokens ?? null,
    total_output_tokens: w.total_output_tokens ?? null,
    context_window_size: w.context_window_size,
    bands: {
      smart_max_used_percentage: settings.bands.smart,
      acceptable_max_used_percentage: settings.bands.acceptable,
      smart_max_tokens: t?.smart ?? null,
      acceptable_max_tokens: t?.acceptable ?? null,
    },
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
  const target = `${home}/.claude/${CONTRACT_DIR}/context/${sid}.json`
  // A body with no figures (before a session's first response, or after session.end or a fresh
  // load dropped the in-memory one) never goes over a file on disk that has them.
  if (body.context_window.used_percentage === null && (await diskHasFigures($, target))) return
  const argv = ['node', `${$.plugin.root}/${HELPER}`, target, '--prune', ...(same ? ['--floor', String(FLOOR_MS / 1000)] : [])]
  // Only a write the helper decided (written, or skipped by rule) dedupes; a failed one is tried at the next carrier.
  try {
    const run = await $.process.run(argv, { stdin: JSON.stringify(body), timeoutMs: 10_000 })
    if (run.exitCode === 0 || run.exitCode === 3) s.written = { sig, at: now }
    else logOnce($, st, 'write-failed', `snapshot write failed (exit ${run.exitCode}): ${run.stderr.trim()}`)
  } catch (error) {
    logOnce($, st, 'write-threw', `snapshot write did not run: ${error instanceof Error ? error.message : String(error)}`)
  }
}

async function diskHasFigures($: EngineInterface, target: string) {
  const text = await $.fs.read(target).then(String).catch(() => null)
  if (text === null) return false
  try {
    return typeof JSON.parse(text)?.context_window?.used_percentage === 'number'
  } catch {
    return false
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
        "Returns this session's context-window reading as JSON: `zone` (smart, acceptable, dumb or unknown; the worse of the percent and token bands decides it), `used_percentage`, input and output token totals, `context_window_size`, the band edges and approach margin in force, `evidence_degraded` (true after a compaction, which forces the zone to dumb), and the gate's mode (advisory or blocking) with its grace calls and calls counted. Figures come from the last API response: before the first response and right after a compaction, `used_percentage` and the token totals are null and the zone is unknown (dumb after a compaction), and they never include text added since that response, so they change only when a response arrives. By default context-guard also adds a line to the next prompt or tool result when the zone worsens or nears a boundary. Read-only.",
      inputSchema: { type: 'object', properties: {}, additionalProperties: false },
    }),
    $.command.register({
      name: 'context-guard',
      description: 'Context zone status and details; band on or off sets the band row for this session, bare band toggles it',
      argumentHint: '[band [on|off]]',
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
  await emitTelemetry($, 'zone-gate', 'blocked', { zone: block, grace: cfg.grace, calls_seen: s.grace }, fire)
  return (
    `${PREFIX}${e.tool} denied: ${block} zone, grace budget of ${cfg.grace} calls spent. ` +
    'Reads, Bash, Skill and handoff-path writes still run.'
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
    carry: false,
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
      s.restate = true
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
    st.carry = e.reason === 'resume'
    st.origin = undefined
    st.recheckTool = true
    return next(e)
  }).catch(($, e, next) => next(e))

  on('session.compact', async ($, e, next) => {
    const result = await next(e)
    if (e.agentId === undefined && e.trigger !== 'precompute' && !('skip' in result && result.skip)) {
      const s = await current($, st)
      s.compacted = true
      s.restate = true
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
    return next(withLines($, e, await takeLines($, st, cfg, { event: 'prompt.submit', startMs })))
  }).catch(($, e, next) => next(e))

  on('session.measure', async ($, e, next) => {
    await refresh($, st)
    await queueWrite($, st)
    await showPending($, st, cfg)
    return next(e)
  }).catch(($, e, next) => next(e))

  on('turn.start', async ($, e, next) => {
    st.reofferTimer = stopTimer(st.reofferTimer)
    // Keeps the snapshot fresh through one long tool call or subagent run.
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
      const lines = renderAll(s.pending, s, cfg, st.settings)
      if (lines.length > 0) {
        st.notice = { text: `FYI, ${PREFIX}${lines.map(l => l.replace(PREFIX, '')).join(' ')}`, kind: 'operator' }
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

  on('command.run', { command: 'context-guard' }, async ($, e, next) => {
    const [sub, arg, ...rest] = e.args.trim().toLowerCase().split(/\s+/).filter(Boolean)
    if (sub === undefined) {
      const text = await statusText($, st, cfg)
      $.ui.log(POINTER, { to: 'transcript' })
      return { text }
    }
    if (sub !== 'band' || rest.length > 0 || (arg !== undefined && arg !== 'on' && arg !== 'off')) return { text: USAGE }
    st.bandShown = arg === undefined ? !st.bandShown : arg === 'on'
    $.ui.invalidate('ui.render')
    // Claude Code puts the plugin's name before a command's reply, so no reply carries it again.
    return { text: `band row ${st.bandShown ? 'on' : 'off'} for this session` }
  }).catch(($, e, next) => next(e))

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const theirs = await next(e)
    const notice = noticeShows(st, e.surface) ? st.notice?.text : undefined
    if (e.props.hasSurvey || (!st.bandShown && notice === undefined)) return theirs
    const { Box, Text } = $.ui.resolve(e)
    return (
      <Box flexDirection="column">
        {st.bandShown ? (
          <Text dimColor wrap="truncate">
            {bandText(st.reading)}
          </Text>
        ) : null}
        {notice !== undefined ? <Text wrap="wrap">{notice}</Text> : null}
        {theirs}
      </Box>
    )
  }).catch(($, e, next) => next(e))

  on('tool.call', async ($, e, next) => {
    if (e.tool === `mcp__${$.plugin.name}__status`) return { result: await statusJson($, st, cfg) }
    const fire: Fire = { event: 'tool.call', startMs: await $.clock.now(), toolUseId: (e as { tool_use_id?: unknown }).tool_use_id, agentId: e.agentId }
    const deny = await gate($, st, cfg, e, fire)
    if (deny !== undefined) {
      $.ui.log(deny, { to: 'debug' })
      return { deny }
    }
    const result = await next(e)
    // The gate's envelope timed the call before the tool ran; the line work after it starts its own clock.
    const after: Fire = { ...fire, startMs: await $.clock.now() }
    await refresh($, st)
    await queueWrite($, st)
    if (e.agentId !== undefined) return result
    if (result.deny !== undefined || result.isError) return result
    return withLines($, result, await takeLines($, st, cfg, after))
  }).catch(($, e, next) => next(e))
}
