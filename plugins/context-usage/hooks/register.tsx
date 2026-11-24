import type { EngineInterface, PromptOrigin, Register, Timer } from 'claude-code'
import { desktopNotice, type DesktopCrossing } from './desktop-notice.tsx'
import { alias, followWindow, ofWindow, RANK, readBands, resolveZone, tokenShape, type Bands, type TokenShape, type Zone } from './zone.ts'

const CONTRACT_DIR = 'context-usage'
const EARLIER_DIR = 'context-guard'
const PREFIX = 'context-usage: '
const NEXT_ZONE: Partial<Record<Zone, Zone>> = { light: 'moderate', moderate: 'heavy' }
const SESSION_ID = /^[A-Za-z0-9_-]+$/
const PERSON_ORIGINS = ['composer', 'bridge']
const REOFFER_MS = 5_000
const FLOOR_MS = 60_000
const WRITE_TIMER_MS = 15_000
const HELPER = 'lib/write-snapshot.mjs'
const DATA_ITEMS = ['zone', 'percent', 'tokens', 'window']
const ACTIONS = ['none', 'save-state', 'handoff'] as const
const ACTION_TEXT: Record<Action, string> = {
  none: '',
  'save-state': 'save-state',
  handoff: 'handoff',
}

type Action = (typeof ACTIONS)[number]
type Rule = { action: Action; text?: string }
type Threshold = Rule & { at: number; at_percent: number }
type Settings = { bands: Bands; notices: string[]; margin: number; actions: Partial<Record<Zone, Rule>>; thresholds: Threshold[] }
type Config = {
  enabled: boolean
  lines: boolean
  operator: boolean
  data: Set<string>
  band: boolean
  toast: boolean
}
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
  zone?: Zone | 'unknown'
  evidence_degraded?: boolean
  bands?: {
    light_max_used_percentage: number
    moderate_max_used_percentage: number
    light_max_tokens: number | null
    moderate_max_tokens: number | null
    auto_compact_window?: number
  }
}
type Reading = { zone: Zone | undefined; degraded: boolean; percent?: number; tokens?: number; window: number; token?: TokenShape }
type Crossing = { kind: 'crossing'; from: string; zone: Zone; degraded: boolean; handedOff?: boolean; shown?: boolean; armedBefore: number }
type Event =
  | Crossing
  | { kind: 'restate'; zone: Zone; degraded: boolean; unavailable?: undefined }
  | { kind: 'restate'; zone: undefined; degraded: true; unavailable: true }
  | { kind: 'approach'; zone: Zone; toward: string }
  | { kind: 'threshold'; zone: Zone; degraded: boolean; rule: Threshold; actionOnly?: boolean }
type Session = {
  armed: number
  last: Zone | undefined
  fired: Set<number>
  approached: Set<string>
  compacted: boolean
  pending: Event[]
  restate: boolean
  awaiting: boolean
  reading: Reading | undefined
  written: { sig: string; at: number } | undefined
  body: Snapshot | undefined
  offered: Event[]
}
type Notice = { text: string; kind: 'crossing' | 'operator'; crossing?: DesktopCrossing }
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
  zonesPath: string | undefined
  zonesToast: boolean
  zonesToasted: Set<string>
}

// plugin.json declares no number bounds, because the engine refuses the whole module for a value
// outside them; the module checks them here, uses the default and names each bad option once.
const badOption = (name: string, kind: string, fallback: string) => `context-usage: option ${name} ${kind}; it reads as the default, ${fallback}`
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
  return {
    enabled: options.context_usage_hooks_enabled !== false,
    lines: options.model_notices === true,
    operator: options.zone_report_mode === 'operator',
    data: new Set(['zone', ...items]),
    band: options.context_usage_band === true,
    toast: options.context_usage_toast !== false,
    bad,
  }
}

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
  if (v.action === 'block') return { action: 'none' }
  if (!ACTIONS.includes(v.action as Action)) return undefined
  const text = typeof v.text === 'string' ? oneLine(v.text) : ''
  return { action: v.action as Action, ...(text !== '' ? { text } : {}) }
}

export const parseSettings = (zones: string | null): Settings => {
  const { bands, notices } = readBands(zones)
  let z: Record<string, unknown> = {}
  try {
    const parsed: unknown = zones === null ? {} : JSON.parse(zones)
    if (typeof parsed === 'object' && parsed !== null && !Array.isArray(parsed)) z = parsed as Record<string, unknown>
  } catch {
  }
  const margin = typeof z.approach_margin === 'number' ? z.approach_margin : NaN
  const actionsRaw = typeof z.actions === 'object' && z.actions !== null && !Array.isArray(z.actions) ? (z.actions as Record<string, unknown>) : {}
  const actionsIn = alias(alias(alias(actionsRaw, 'light', 'smart'), 'moderate', 'acceptable'), 'heavy', 'dumb')
  const actions: Partial<Record<Zone, Rule>> = {}
  for (const zone of ['light', 'moderate', 'heavy'] as const) {
    const rule = asRule(actionsIn[zone])
    if (rule) actions[zone] = rule
  }
  const thresholds = (Array.isArray(z.thresholds) ? z.thresholds : [])
    .map(t => {
      const rule = asRule(t)
      const at = (t as Record<string, unknown>)?.at_percent
      return rule && typeof at === 'number' && at > 0 && at <= 100 ? { ...rule, at, at_percent: at } : undefined
    })
    .filter((t): t is Threshold => t !== undefined)
    .sort((a, b) => a.at - b.at)
  return { bands, notices, margin: Number.isFinite(margin) && margin >= 0 && margin < 100 ? margin : 5, actions, thresholds }
}

export const followSettings = (s: Settings, window: number, compactWindow: number | undefined): Settings => ({
  ...s,
  bands: followWindow(s.bands, window, compactWindow),
  margin: ofWindow(s.margin, window, compactWindow),
  thresholds: s.thresholds.map(t => ({ ...t, at: ofWindow(t.at, window, compactWindow) })),
})

const newSession = (restate: Session['restate']): Session => ({
  armed: 0,
  last: undefined,
  fired: new Set(),
  approached: new Set(),
  compacted: false,
  pending: [],
  restate,
  awaiting: false,
  reading: undefined,
  written: undefined,
  body: undefined,
  offered: [],
})

export const recordReading = (s: Session, reading: Reading, settings: Settings) => {
  s.reading = reading
  const { zone, percent } = reading
  if (s.restate && reading.degraded && percent === undefined && reading.tokens === undefined) {
    if (!s.awaiting) s.pending.push({ kind: 'restate', zone: undefined, degraded: true, unavailable: true })
    s.awaiting = true
    return
  }
  if (zone === undefined) return
  if (s.restate) {
    s.awaiting = false
    if (zone !== 'light' || reading.degraded) s.pending.push({ kind: 'restate', zone, degraded: reading.degraded })
    s.restate = false
    if (reading.degraded) {
      s.armed = RANK[zone]
      s.fired.clear()
      s.approached.clear()
    } else s.armed = Math.max(s.armed, RANK[zone])
    s.last = zone
    for (const t of settings.thresholds) if (percent !== undefined && percent >= t.at) s.fired.add(t.at_percent)
    return
  }
  if (RANK[zone] > s.armed) {
    s.pending.push({ kind: 'crossing', from: s.last ?? 'unobserved', zone, degraded: reading.degraded, armedBefore: s.armed })
    s.armed = RANK[zone]
  } else if (zone === 'light' && s.armed > 0) {
    s.armed = 0
    s.fired.clear()
    s.approached.clear()
  }
  s.last = zone
  if (percent !== undefined) {
    for (const t of settings.thresholds) {
      if (!s.fired.has(t.at_percent) && percent >= t.at) {
        s.fired.add(t.at_percent)
        s.pending.push({ kind: 'threshold', zone, degraded: reading.degraded, rule: t })
      }
    }
  }
  if (settings.margin <= 0) return
  const { light, moderate } = settings.bands
  const tok = reading.token
  const near = (edgePercent: number, edgeTokens: number | undefined) => {
    if (tok !== undefined && edgeTokens !== undefined && (percent === undefined || edgeTokens < (edgePercent * tok.size) / 100)) {
      return tok.used >= edgeTokens - (settings.margin * tok.size) / 100 && tok.used <= edgeTokens
    }
    return percent !== undefined && percent >= edgePercent - settings.margin && percent <= edgePercent
  }
  const boundaries = [
    { key: 'moderate', toward: 'moderate', near: s.armed < 1 && near(light, tok?.light) },
    { key: 'heavy', toward: 'heavy', near: s.armed < 2 && near(moderate, tok?.moderate) },
    ...settings.thresholds.map(t => ({
      key: `t${t.at_percent}`,
      toward: 'an operator threshold',
      near: percent !== undefined && !s.fired.has(t.at_percent) && percent >= t.at - settings.margin,
    })),
  ]
  for (const b of boundaries) {
    if (b.near && !s.approached.has(b.key)) {
      s.approached.add(b.key)
      s.pending.push({ kind: 'approach', zone, toward: b.toward })
    }
  }
}

const verdictText = (zone: Zone, degraded: boolean) => `${zone} zone (${RANK[zone] + 1} of 3${degraded ? ', compacted' : ''})`

const dataText = (r: Reading | undefined, cfg: Config) => {
  const items: string[] = []
  if (cfg.data.has('percent') && r?.percent !== undefined) items.push(`${r.percent}% of the window used`)
  if (cfg.data.has('tokens') && r?.tokens !== undefined) items.push(`${r.tokens} tokens in context`)
  if (cfg.data.has('window') && r !== undefined) items.push(`a ${r.window}-token window`)
  return items.length === 0 ? '' : `, ${items.join(', ')}`
}

const sentence = (source: string, rule: Rule) => {
  const text = (rule.text ?? ACTION_TEXT[rule.action]).replace(/\.+$/, '')
  return text === '' || rule.action === 'none' && rule.text === undefined ? '' : ` context-usage (${source}): ${text}.`
}

export const renderEvent = (e: Event, s: Session, cfg: Config, settings: Settings) => {
  const data = dataText(s.reading, cfg)
  const action = (zone: Zone) => {
    const rule = settings.actions[zone]
    return rule ? sentence(`operator setting for the ${zone} zone`, rule) : ''
  }
  const line = (zone: Zone, degraded: boolean, hint: string) => `context-usage: ${verdictText(zone, degraded)}${data}${hint}.`
  const near = (zone: Zone) => {
    const toward = NEXT_ZONE[zone]
    return toward !== undefined && s.approached.has(toward) ? `, nearing ${toward}` : ''
  }
  switch (e.kind) {
    case 'restate':
    case 'crossing':
      if (e.kind === 'restate' && e.unavailable) return 'context-usage: the context reading is unavailable after the compaction, until the next API response.'
      return `${line(e.zone, e.degraded, near(e.zone))}${action(e.zone)}`
    case 'approach':
      return line(e.zone, false, `, nearing ${e.toward}`)
    case 'threshold':
      if (e.actionOnly) return sentence('operator setting for a threshold', e.rule).trimStart()
      return `${line(e.zone, e.degraded, ', past an operator threshold')}${sentence('operator setting for a threshold', e.rule)}`
  }
}

const OPTIONS =
  'context-usage: options: record decisions and pending items in a durable file, then continue, /compact, or hand off with /session-flow:handoff, as you and the user choose; /context shows what fills the window. A zone never calls for terser output, fewer agents, or lower quality.'

const renderAll = (events: Event[], s: Session, cfg: Config, settings: Settings) => {
  const lines = [...new Set(events.map(e => renderEvent(e, s, cfg, settings)))]
  const verdicts = lines.filter(l => !lines.some(o => o !== l && o.startsWith(l)))
  return events.some(e => e.zone !== 'light' && !(e.kind === 'restate' && e.unavailable)) ? [...verdicts, OPTIONS] : verdicts
}

const withLines = <T extends { context?: readonly string[] }>($: EngineInterface, e: T, lines: readonly string[]): T => {
  for (const line of lines) $.ui.log(line, { to: 'debug' })
  return lines.length === 0 ? e : { ...e, context: [...(e.context ?? []), ...lines] }
}

const homeDir = async ($: EngineInterface) => (await $.env.get('HOME')) || (await $.env.get('USERPROFILE')) || undefined

const zonesToastText = (path: string, notices: string[]) =>
  `${path}: shipped defaults replace malformed ${notices.join(' and ')} · /context-usage:setup check`

async function loadSettings($: EngineInterface, st: State, home: string | undefined) {
  if (home === undefined) return st.settings
  let path = `${home}/.claude/${CONTRACT_DIR}/zones.json`
  let stat = await $.fs.stat(path).catch(() => undefined)
  if (stat === undefined) {
    const earlier = `${home}/.claude/${EARLIER_DIR}/zones.json`
    const found = await $.fs.stat(earlier).catch(() => undefined)
    if (found !== undefined) [path, stat] = [earlier, found]
  }
  st.zonesPath = path
  const key = stat === undefined ? 'absent' : `${path}:${stat.mtimeMs}:${stat.size}`
  if (key !== st.zonesKey) {
    const text = stat === undefined ? null : await $.fs.read(path).then(String).catch(() => null)
    st.settings = parseSettings(text)
    st.zonesText = text
    st.zonesKey = key
    const { notices } = st.settings
    if (st.zonesToast && text !== null && notices.length > 0 && !st.zonesToasted.has(text)) {
      st.zonesToasted.add(text)
      $.ui.toast(zonesToastText(path, notices))
    }
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
  const [usage, version, now, loaded] = await Promise.all([
    $.session.usage({ breakdown: 'summary' }),
    $.session.version().catch(() => undefined),
    $.clock.now(),
    loadSettings($, st, home),
  ])
  const c = usage.context
  const api = c.breakdown?.apiUsage ?? null
  const compactWindow = c.breakdown?.rawMaxTokens
  const follows = ofWindow(100, c.window, compactWindow) < 100
  const settings = followSettings(loaded, c.window, compactWindow)
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
  const { word } = resolveZone({
    sid,
    snapshot: JSON.stringify(body),
    zones: st.zonesText,
    nowSec: Math.floor(now / 1000),
    follow: bands => followWindow(bands, c.window, compactWindow),
  })
  if (!s.compacted && home !== undefined && SESSION_ID.test(sid)) {
    s.compacted = await $.fs.exists(`${home}/.claude/${CONTRACT_DIR}/context/${sid}.compacted`).catch(() => false)
      || await $.fs.exists(`${home}/.claude/${EARLIER_DIR}/context/${sid}.compacted`).catch(() => false)
    if (s.compacted) s.restate = true
  }
  const zone = word === 'unknown' ? undefined : word
  const token = tokenShape(body.context_window, body.cli_version, settings.bands)
  body.zone = zone ?? 'unknown'
  body.evidence_degraded = s.compacted
  body.bands = {
    light_max_used_percentage: settings.bands.light,
    moderate_max_used_percentage: settings.bands.moderate,
    light_max_tokens: token?.light ?? null,
    moderate_max_tokens: token?.moderate ?? null,
    ...(follows ? { auto_compact_window: compactWindow } : {}),
  }
  const reading: Reading = { zone, degraded: s.compacted, percent: c.percent, tokens: c.tokens, window: c.window, token }
  recordReading(s, reading, settings)
  if (body.context_window.used_percentage !== null || s.body === undefined || s.body.context_window.used_percentage === null) s.body = body
  else if (s.compacted) s.body = { ...s.body, evidence_degraded: true }
  st.reading = reading
  const band = bandText(reading)
  if (band !== st.band) {
    st.band = band
    $.ui.invalidate('ui.render')
  }
  return { sid, s, body, settings }
}

const isPersonTurn = (st: State) => st.origin !== undefined && PERSON_ORIGINS.includes(st.origin.kind)

async function operatorHolds($: EngineInterface, st: State, cfg: Config) {
  if (!cfg.operator || st.forceAutomatic || !isPersonTurn(st)) return false
  return (await $.session.surfaces()).length > 0
}

const toastText = (from: string, to: string) => `${from} → ${to} · continue, /compact, /clear or handoff`
const menuLine = (from: string, to: string) =>
  `context-usage: ${from} → ${to} · options: continue, /compact, /clear, or /session-flow:handoff then /clear · more: /context-usage`
const menuZone = (zone: Zone, degraded: boolean) => (degraded ? `${zone} (compacted)` : zone)
const noticeShows = (st: State, surface: string) => st.notice !== undefined && (st.notice.kind === 'operator' || surface !== 'terminal')

type Fire = { event: string; startMs: number; toolUseId?: unknown; agentId?: unknown }
const PLAIN_ID = /^[A-Za-z0-9._-]+$/
const RANK_WORD = ['light', 'moderate', 'heavy'] as const

// CLAUDE_CONFIG_DIR, default ~/.claude, holds the plugins (https://code.claude.com/docs/en/env-vars).
async function sessionTelemetrySink($: EngineInterface) {
  const home = await homeDir($)
  const config = (await $.env.get('CLAUDE_CONFIG_DIR')) || (home && `${home}/.claude`)
  if (!config) return undefined
  const base = `${config.replace(/[\\/]+$/, '')}/plugins/data`
  const entries = await $.fs.list(base).catch(() => [])
  const names = entries.filter(e => e.kind === 'dir' && e.name.startsWith('session-telemetry-')).map(e => e.name)
  let best: { path: string; mtimeMs: number } | undefined
  for (const name of names.sort()) {
    const path = `${base}/${name}/hook-telemetry-sink.sh`
    const stat = await $.fs.stat(path).catch(() => undefined)
    if (stat?.kind === 'file' && (best === undefined || stat.mtimeMs > best.mtimeMs)) best = { path, mtimeMs: stat.mtimeMs }
  }
  return best?.path
}

async function emitTelemetry($: EngineInterface, hook: string, status: string, data: Record<string, unknown>, fire: Fire) {
  const sink = await $.env.get('HOOK_TELEMETRY_SINK')
  if (!sink) return
  let path = sink
  if (sink.startsWith('@')) {
    const launcher = sink === '@session-telemetry' || sink === '@harness-ops' ? await sessionTelemetrySink($) : undefined
    if (!launcher) return
    path = launcher
  } else if (!/^(\/|[A-Za-z]:[\\/])/.test(sink)) {
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

const crossingData = (s: Session, events: Event[], extra: Record<string, unknown>) => {
  const crossed = events.filter(e => e.kind === 'crossing').at(-1)
  const zone = s.reading?.zone ?? 'unknown'
  return crossed?.kind === 'crossing'
    ? { zone, previous: crossed.from === 'unobserved' ? '' : crossed.from, armed: RANK_WORD[crossed.armedBefore], ...extra }
    : { zone, previous: s.last ?? '', armed: RANK_WORD[s.armed], ...extra }
}

const mergeRestated = (pending: Event[]): Event[] => {
  const lastRestate = pending.findLastIndex(e => e.kind === 'restate')
  if (lastRestate < 0) return pending
  const keep = pending.findLastIndex(e => e.kind === 'crossing') > lastRestate ? -1 : lastRestate
  return pending.flatMap((e, i): Event[] => {
    if (i > lastRestate || i === keep) return [e]
    if (e.kind !== 'threshold' || sentence('operator setting for a threshold', e.rule) === '') return []
    return [{ ...e, actionOnly: true }]
  })
}

async function takeLines($: EngineInterface, st: State, cfg: Config, fire: Fire): Promise<string[]> {
  const s = st.sessions.get(await $.session.id())
  if (s === undefined) return []
  if (!cfg.enabled) {
    s.pending = []
    return []
  }
  const holds = cfg.lines && (await operatorHolds($, st, cfg))
  const merged = mergeRestated(s.pending)
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
  showCrossing($, st, cfg, events)
  return lines
}

function showCrossing($: EngineInterface, st: State, cfg: Config, events: Event[]) {
  const due = events.filter((e): e is Crossing => e.kind === 'crossing' && !e.handedOff && !e.shown)
  const crossed = due.at(-1)
  const showable = crossed !== undefined && crossed.from !== 'unobserved'
  const to = showable ? menuZone(crossed.zone, crossed.degraded) : ''
  if (showable) {
    st.notice = { text: menuLine(crossed.from, to), kind: 'crossing', crossing: { from: crossed.from, to, zone: crossed.zone } }
    $.ui.log(st.notice.text)
  }
  for (const e of due) e.shown = true
  if (!showable) return
  // The engine drops a failing toast itself; it never throws into the module.
  if (cfg.toast) $.ui.toast(toastText(crossed.from, to))
  $.ui.invalidate('ui.render')
}

async function showPending($: EngineInterface, st: State, cfg: Config) {
  const s = st.sessions.get(await $.session.id())
  if (s === undefined || !cfg.enabled) return
  if (cfg.lines && (await operatorHolds($, st, cfg))) return
  showCrossing($, st, cfg, s.pending)
}

async function offer($: EngineInterface, st: State, s: Session, fire: Fire) {
  if (st.notice?.kind !== 'operator') return true
  const box = await $.prompt.read()
  if (box.text.trim() !== '') return false
  const { isShown } = await $.prompt.suggest({ text: st.notice.text })
  if (isShown) {
    await emitTelemetry($, 'zone-crossing-inject', 'ok', crossingData(s, s.pending, { injected: false, suggested: true }), fire)
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

export const bandText = (r: Reading | undefined) => {
  if (r?.percent === undefined) return `${PREFIX}-`
  const zone = r.zone === undefined ? '' : `${r.zone}${r.degraded ? ', compacted' : ''} `
  return `${PREFIX}${zone}${r.percent}%`
}

const USAGE = 'usage: /context-usage [band [on|off]]'
const README = 'https://github.com/melodic-software/claude-code-plugins/blob/main/plugins/context-usage/README.md'
const DOCS = 'https://code.claude.com/docs/en/context-window#when-your-context-fills-up'

const POINTER = `context-usage: next step: route it with /session-flow:workflow (if installed), or see ${DOCS} · more: ${README}`
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
  const zonesAt = st.zonesPath ?? `${home}/.claude/${CONTRACT_DIR}/zones.json`
  const zones = home === undefined ? 'zones.json: no home directory' : `${zonesAt} (${st.zonesText === null ? 'absent' : 'present'})`
  const { light, moderate } = settings.bands
  const t = tokenShape(w, body.cli_version, settings.bands)
  const bands = t
    ? `Bands (the worse decides): light up to ${light}% and ${t.light} tokens, moderate up to ${moderate}% and ${t.moderate} tokens`
    : `Bands: light up to ${light}%, moderate up to ${moderate}%`
  const acw = body.bands?.auto_compact_window
  const follows = acw === undefined ? '' : ` (percentages of the window, following a ${acw}-token auto-compact window)`
  return [
    `${verdict}, ${figures}`,
    `${bands}; approach margin ${settings.margin} points${follows}`,
    `This session: band row ${st.bandShown ? 'on' : 'off'}, zone-change toast ${cfg.toast ? 'on' : 'off'}`,
    `Settings: ${zones}`,
  ].join('\n')
}

async function statusJson($: EngineInterface, st: State, cfg: Config) {
  const { s, body, settings } = await refresh($, st)
  await showPending($, st, cfg)
  const w = body.context_window
  return JSON.stringify({
    source: 'the last API response',
    zone: s.reading?.zone ?? 'unknown',
    evidence_degraded: s.compacted,
    used_percentage: w.used_percentage,
    total_input_tokens: w.total_input_tokens ?? null,
    total_output_tokens: w.total_output_tokens ?? null,
    context_window_size: w.context_window_size,
    bands: body.bands,
    approach_margin: settings.margin,
  })
}

const logOnce = ($: EngineInterface, st: State, key: string, text: string) => {
  if (st.loggedOnce.has(key)) return
  st.loggedOnce.add(key)
  $.ui.log(`context-usage: ${text}`, { to: 'debug' })
}

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
  if (body.context_window.used_percentage === null && (await diskHasFigures($, target))) return
  const argv = ['node', `${$.plugin.root}/${HELPER}`, target, '--prune', ...(same ? ['--floor', String(FLOOR_MS / 1000)] : [])]
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

async function registerSurfaces($: EngineInterface, st: State) {
  const [tool] = await Promise.allSettled([
    $.tool.register({
      name: 'status',
      description:
        "Returns this session's context-window reading as JSON: `zone` (light, moderate, heavy or unknown; the worse of the percent and token bands decides it), `used_percentage`, input and output token totals, `context_window_size`, the band edges and approach margin in force, `evidence_degraded` (true after a compaction; the zone still reports room only). Figures come from the last API response: before the first response and right after a compaction, `used_percentage` and the token totals are null and the zone is unknown, and they never include text added since that response, so they change only when a response arrives. With the model_notices option on (off by default), context-usage also adds lines to the next prompt or tool result when the zone worsens, nears a boundary or passes a zones.json threshold, and restates the zone after a resume, reload or compaction. Read-only.",
      inputSchema: { type: 'object', properties: {}, additionalProperties: false },
    }),
    $.command.register({
      name: 'context-usage',
      description: 'Context zone status and details; band on or off sets the band row for this session, bare band toggles it',
      argumentHint: '[band [on|off]]',
    }),
  ])
  if (tool.status === 'rejected') {
    const reason = tool.reason instanceof Error ? tool.reason.message : String(tool.reason)
    logOnce($, st, 'tool-register', `the status tool could not register: ${reason}`)
  }
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
    zonesPath: undefined,
    zonesToast: cfg.enabled && cfg.toast,
    zonesToasted: new Set(),
  }

  on('session.start', async ($, e, next) => {
    for (const line of cfg.bad) {
      if (!st.loggedOnce.has(line)) $.ui.log(line)
      st.loggedOnce.add(line)
    }
    await registerSurfaces($, st)
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
      s.awaiting = false
    }
    return result
  }).catch(($, e, next) => next(e))

  on('prompt.submit', async ($, e, next) => {
    const startMs = await $.clock.now()
    if (e.turnId === undefined) {
      st.origin = e.origin
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
    try {
      await showPending($, st, cfg)
    } finally {
      await queueWrite($, st)
    }
    return next(e)
  }).catch(($, e, next) => next(e))

  on('turn.start', async ($, e, next) => {
    st.reofferTimer = stopTimer(st.reofferTimer)
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
      s.pending = mergeRestated(s.pending)
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

  on('command.run', { command: 'context-usage' }, async ($, e, next) => {
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
    const ui = $.ui.resolve(e)
    const { Box, Text } = ui
    const crossing = e.surface === 'desktop' ? st.notice?.crossing : undefined
    const dismiss = () => {
      st.notice = undefined
      $.ui.invalidate('ui.render')
    }
    return (
      <Box flexDirection="column">
        {st.bandShown ? (
          <Text dimColor wrap="truncate">
            {bandText(st.reading)}
          </Text>
        ) : null}
        {crossing !== undefined ? desktopNotice($, ui, crossing, dismiss) : notice !== undefined ? <Text wrap="wrap">{notice}</Text> : null}
        {theirs}
      </Box>
    )
  }).catch(($, e, next) => next(e))

  on('tool.call', async ($, e, next) => {
    if (e.tool === `mcp__${$.plugin.name}__status`) return { result: await statusJson($, st, cfg) }
    const result = await next(e)
    const fire: Fire = { event: 'tool.call', startMs: await $.clock.now(), toolUseId: (e as { tool_use_id?: unknown }).tool_use_id, agentId: e.agentId }
    await refresh($, st)
    await queueWrite($, st)
    if (e.agentId !== undefined) return result
    if (result.deny !== undefined || result.isError) return result
    return withLines($, result, await takeLines($, st, cfg, fire))
  }).catch(($, e, next) => next(e))
}
