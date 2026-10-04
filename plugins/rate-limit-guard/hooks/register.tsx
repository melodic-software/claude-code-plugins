import type { EngineInterface, PromptOrigin, Register, SessionRateLimit, Timer } from 'claude-code'

// The contract directory under the home directory. make-probe-copy.sh rewrites this one line.
const CONTRACT_DIR = 'rate-limit-guard'
const SNAPSHOT_FILE = 'rate-limits.json'
const HELPER = 'lib/write-snapshot.mjs'
const PAUSE_EDGE = 95
const FLOOR_MS = 300_000
const WRITE_TIMER_MS = 60_000
const REOFFER_MS = 5_000
const WINDOWS = [
  { kind: 'five_hour', name: '5-hour', short: '5h' },
  { kind: 'seven_day', name: '7-day', short: '7d' },
] as const
// The verdict is always in a line; these add to it.
const DATA_ITEMS = ['verdict', 'percent', 'window', 'reset']
const DEFAULT_DATA = ['verdict', 'window', 'reset']
const RANK = { quiet: 0, approach: 1, edge: 2 } as const
const PERSON_ORIGINS = ['composer', 'bridge']
const COMMAND = 'rate-limit-guard'
// Command replies carry no plugin prefix: Claude Code shows each under the plugin's name.
const USAGE = `Usage: /${COMMAND} [band [on|off]]`
const README = 'https://github.com/melodic-software/claude-code-plugins/blob/main/plugins/rate-limit-guard/README.md'

type Level = 'quiet' | 'approach' | 'edge'
type Event = Level | 'reset'
type Reading = Map<string, SessionRateLimit>
type Config = {
  bad: string[]
  writes: boolean
  lines: boolean
  operator: boolean
  threshold: number
  approach: number
  data: Set<string>
  band: boolean
  toast: boolean
}
// An operator notice offers held lines and shows on every surface; a crossing notice stands in for
// the toast where toasts may not draw, so it shows only off the terminal.
type Notice = { text: string; kind: 'crossing' | 'operator' }
type Body = {
  captured_at: string
  session_id: string
  rate_limits?: Record<string, { used_percentage: number; resets_at?: number }>
  account?: { email: string }
}
type State = {
  reading: Reading | undefined
  spend: SessionRateLimit | undefined
  levels: Map<string, { level: Level; resetsMs: number }>
  limits: readonly SessionRateLimit[]
  pending: Map<string, Event>
  // Rises from a known level and resets not yet shown to the person.
  toastQueue: [string, Event][]
  // Operator mode: the changes the operator notice offers, and whether its row has been drawn.
  // The row and a shown suggestion are the person's channel, so a change either reached is never toasted.
  heldToasts: [string, Event][]
  rowSeen: boolean
  // Operator mode: events a shown suggestion offered, handed to Claude if no person takes them.
  handoff: Map<string, Event>
  restate: boolean
  restateIfLoud: boolean
  // An in-process /resume or /branch ended the last session; cleared by the first decided write.
  branched: boolean
  forceAutomatic: boolean
  origin: PromptOrigin | undefined
  notice: Notice | undefined
  bandShown: boolean
  lastResponseAtMs: number | undefined
  responseEmail: string | undefined
  identityCache: { key: string; email: string | undefined } | undefined
  lastAttempt: { sig: string; at: number } | undefined
  loggedOnce: Set<string>
  writing: Promise<void>
  writeTimer: Timer | undefined
  reofferTimer: Timer | undefined
}

// A bad value reads as the option's default and adds one line to `bad`: the engine refuses the whole
// module for a value outside a declared range, so the ranges are checked here instead.
export const parseConfig = (options: Record<string, unknown>): Config => {
  const bad: string[] = []
  const reject = (key: string, kind: string, fallback: string) =>
    bad.push(`option ${key} is ${kind}; using the default, ${fallback}`)
  const number = (key: string, fallback: number) => {
    const value = options[key]
    if (value === undefined) return fallback
    if (typeof value === 'number' && value >= 1 && value <= 100) return value
    reject(key, typeof value === 'number' ? `${value}, outside 1 to 100` : `a ${typeof value}, not a number`, String(fallback))
    return fallback
  }
  const raw = options.rate_limit_line_data
  const items = String(raw ?? '')
    .split(',')
    .map(s => s.trim().toLowerCase())
    .filter(s => s !== '')
  const known = items.length > 0 && items.every(s => DATA_ITEMS.includes(s))
  // An empty value reads as the default silently, as an unset one does.
  if (raw !== undefined && String(raw).trim() !== '' && !known) {
    const shown = typeof raw === 'string' ? JSON.stringify(raw.slice(0, 40)) : `a ${typeof raw}`
    reject('rate_limit_line_data', `${shown}, not a list of ${DATA_ITEMS.join(', ')}`, DEFAULT_DATA.join(','))
  }
  const data = new Set(known ? items : DEFAULT_DATA)
  return {
    bad,
    writes: options.rate_limit_guard_enabled !== false,
    lines: options.rate_limit_lines_enabled !== false,
    operator: options.rate_limit_report_mode === 'operator',
    threshold: number('rate_limit_line_threshold', PAUSE_EDGE),
    approach: number('rate_limit_approach_pct', 90),
    data,
    band: options.rate_limit_guard_band === true,
    toast: options.rate_limit_guard_toast !== false,
  }
}

// The status line drops a window once its reset time has passed; so does this reading.
export const liveWindows = (limits: readonly SessionRateLimit[], nowMs: number): Reading => {
  const reading: Reading = new Map()
  for (const { kind } of WINDOWS) {
    const limit = limits.find(l => l.kind === kind)
    if (limit === undefined) continue
    const resetsMs = limit.resetsAt === undefined ? NaN : Date.parse(limit.resetsAt)
    if (Number.isFinite(resetsMs) && resetsMs <= nowMs) continue
    reading.set(kind, limit)
  }
  return reading
}

const levelOf = (percent: number, cfg: Config): Level =>
  percent >= cfg.threshold ? 'edge' : percent >= cfg.approach ? 'approach' : 'quiet'

const edgeName = (cfg: Config) =>
  cfg.threshold === PAUSE_EDGE ? `${PAUSE_EDGE}% pause edge` : `${cfg.threshold}% line threshold`

const resetLabel = (iso: string) => {
  const at = new Date(iso)
  return Number.isNaN(at.getTime()) ? iso : `${at.toISOString().slice(0, 16).replace('T', ' ')} UTC`
}

// The person's wording; Claude's names the threshold alone, since Claude Code waits out a usage limit itself.
const verdictText = (event: Event, cfg: Config) =>
  ({ edge: 'at', approach: 'nearing', quiet: 'below', reset: 'reset and below' })[event] + ` the ${edgeName(cfg)}`

const modelVerdict = (event: Event, cfg: Config) =>
  ({ edge: 'at', approach: 'nearing', quiet: 'below', reset: 'reset, now below' })[event] + ` ${cfg.threshold}%`

const windowOf = (kind: string) => WINDOWS.find(w => w.kind === kind)

const clause = (kind: string, event: Event, limit: SessionRateLimit | undefined, cfg: Config) => {
  const subject = cfg.data.has('window') ? `${windowOf(kind)?.name ?? kind} window` : 'a rate-limit window'
  const percent = limit !== undefined && cfg.data.has('percent') ? `${limit.percentUsed}% used` : undefined
  let text = `${subject} ${modelVerdict(event, cfg)}${percent ? ` (${percent})` : ''}`
  if (event !== 'reset' && cfg.data.has('reset') && limit?.resetsAt !== undefined) {
    text += `, resets at ${resetLabel(limit.resetsAt)}`
  }
  return text
}

// The person's short form: the 5-hour window resets within the day, so its time alone is enough.
const toastBody = (kind: string, event: Event, limit: SessionRateLimit | undefined, cfg: Config) => {
  if (event === 'reset') return `${windowOf(kind)?.short ?? kind} reset, below the ${edgeName(cfg)}`
  const text = `${windowOf(kind)?.short ?? kind} ${verdictText(event, cfg)}`
  if (limit?.resetsAt === undefined) return text
  const label = resetLabel(limit.resetsAt)
  return `${text} · resets ${kind === 'five_hour' ? label.replace(/^\d{4}-\d{2}-\d{2} /, '') : label}`
}

const order = (kind: string) => WINDOWS.findIndex(w => w.kind === kind)

// Records crossings since the last check as pending events, one per window, the newest kept.
// Use only rises within a window, so a dip is reporting noise: a window's level falls, and its
// lines re-arm, only when the window resets (its reset time passes) or leaves the reading.
// Returns the events the person is told of: a rise from a known level, or a reset from the edge.
// A window's first reading is never one, so a fresh load or the reading after a reset stays quiet.
export const recordCrossings = (st: State, reading: Reading, cfg: Config, nowMs: number) => {
  const changes: [string, Event][] = []
  for (const { kind } of WINDOWS) {
    const limit = reading.get(kind)
    let prev = st.levels.get(kind)
    if (prev !== undefined && (limit === undefined || prev.resetsMs <= nowMs)) {
      if (prev.level === 'edge') {
        st.pending.set(kind, 'reset')
        changes.push([kind, 'reset'])
      } else st.pending.delete(kind)
      st.levels.delete(kind)
      prev = undefined
    }
    if (limit === undefined) continue
    const level = levelOf(limit.percentUsed, cfg)
    const resetsMs = limit.resetsAt === undefined ? NaN : Date.parse(limit.resetsAt)
    if (prev !== undefined && RANK[level] <= RANK[prev.level]) continue
    st.levels.set(kind, { level, resetsMs: Number.isFinite(resetsMs) ? resetsMs : Infinity })
    if (level === 'quiet') continue
    st.pending.set(kind, level)
    if (prev !== undefined) changes.push([kind, level])
  }
  return changes
}

// The events due now, one per window, without consuming them.
const dueEvents = (st: State): [string, Event][] => {
  // After /clear or a fresh load mid-session, only a window at the edge is restated.
  const atEdge = st.restateIfLoud ? [...st.levels].filter(([, w]) => w.level === 'edge').map(([kind]) => kind) : []
  return st.restate
    ? [...(st.reading ?? new Map()).keys()].map(kind => [kind, st.levels.get(kind)?.level ?? 'quiet'])
    : [...new Map<string, Event>([...st.pending.entries(), ...atEdge.map(kind => [kind, 'edge'] as const)])]
}

const dueLines = (st: State, cfg: Config): string[] => {
  const reading = st.reading ?? new Map()
  const events = dueEvents(st).sort(([a], [b]) => order(a) - order(b))
  const lastEdge = events.map(([, event]) => event).lastIndexOf('edge')
  return events.map(
    ([kind, event], i) => `rate-limit-guard: ${clause(kind, event, reading.get(kind), cfg)}.${i === lastEdge ? ' Keep working.' : ''}`,
  )
}

const consume = (st: State) => {
  st.pending.clear()
  st.restate = false
  st.restateIfLoud = false
  st.forceAutomatic = false
}

const isPersonTurn = (st: State) => st.origin !== undefined && PERSON_ORIGINS.includes(st.origin.kind)

async function operatorHolds($: EngineInterface, st: State, cfg: Config) {
  if (!cfg.operator || st.forceAutomatic || !isPersonTurn(st)) return false
  return (await $.session.surfaces()).length > 0
}

async function refresh($: EngineInterface, st: State, cfg: Config, limits?: readonly SessionRateLimit[]) {
  const [now, rateLimits] = await Promise.all([$.clock.now(), limits ?? $.session.usage().then(u => u.rateLimits)])
  const reading = liveWindows(rateLimits, now)
  const changed = bandText(reading) !== bandText(st.reading)
  st.reading = reading
  st.limits = rateLimits
  st.spend = rateLimits.find(l => l.kind === 'spend_limit')
  if (changed) $.ui.invalidate('ui.render')
  // No window reported is no reading, never a reset: the levels wait for the next reading.
  if (rateLimits.some(l => WINDOWS.some(w => w.kind === l.kind))) st.toastQueue.push(...recordCrossings(st, reading, cfg, now))
  return { now, reading }
}

function clearNotice($: EngineInterface, st: State, kind?: Notice['kind']) {
  if (st.notice === undefined || (kind !== undefined && st.notice.kind !== kind)) return
  st.notice = undefined
  st.reofferTimer = stopTimer(st.reofferTimer)
  $.ui.invalidate('ui.render')
}

// The lines a carrier attaches now, consumed; none when none is due or operator mode holds them.
// Lines sent to Claude supersede any notice still offering them to the person.
async function takeLines($: EngineInterface, st: State, cfg: Config): Promise<string[]> {
  if (!cfg.lines) {
    consume(st)
    return []
  }
  if (await operatorHolds($, st, cfg)) return []
  const lines = dueLines(st, cfg)
  // A restatement with no reading to restate waits for the first carrier that has one.
  if (st.restate && lines.length === 0) return []
  consume(st)
  if (lines.length > 0 && st.notice?.kind === 'operator') {
    releaseHeld(st, st.rowSeen)
    clearNotice($, st)
  }
  return lines
}

// Ends the operator notice's hold on its changes: dropped when the person saw them, otherwise
// queued for the next flush.
function releaseHeld(st: State, seen: boolean) {
  if (!seen) st.toastQueue.unshift(...st.heldToasts)
  st.heldToasts = []
}

// Tells the person of each queued window change: a transcript line always, a toast when the option
// allows. Run after a carrier's lines are built and never throws, so a failing toast drops no line.
// While operator mode holds the lines the queue waits: a shown suggestion or the person's next
// prompt drops it, and a suggestion that cannot show leaves it for the carrier that sends the line.
// `held` is the carrier's answer from before its lines were taken, which may end a forced turn.
async function flushToasts($: EngineInterface, st: State, cfg: Config, held?: boolean) {
  try {
    if (st.toastQueue.length === 0) return
    if (held ?? (cfg.lines && (await operatorHolds($, st, cfg)))) return
    const changes = st.toastQueue.splice(0).sort(([a], [b]) => order(a) - order(b))
    const bodies: string[] = []
    for (const [kind, event] of changes) {
      const body = toastBody(kind, event, st.reading?.get(kind), cfg)
      bodies.push(body)
      $.ui.log(`rate-limit-guard: ${body} · more: /${COMMAND}`, { to: 'transcript' })
      if (cfg.toast) $.ui.toast(body)
    }
    if (st.notice?.kind !== 'operator') {
      st.notice = { text: `rate-limit-guard: ${bodies.join('; ')} · more: /${COMMAND}`, kind: 'crossing' }
      $.ui.invalidate('ui.render')
    }
  } catch (error) {
    logOnce($, st, 'flush-failed', `window change not shown: ${error instanceof Error ? error.message : String(error)}`)
  }
}

const noticeShows = (st: State, surface: string) =>
  st.notice !== undefined && (st.notice.kind === 'operator' || surface !== 'terminal')

// The module's band row: 5h <x>% | 7d <y>%.
export const bandText = (reading: Reading | undefined) =>
  WINDOWS.map(({ kind, short }) => {
    const limit = reading?.get(kind)
    return `${short} ${limit === undefined ? '-' : `${limit.percentUsed}%`}`
  }).join(' | ')

// What /rate-limit-guard with no argument prints.
async function statusText($: EngineInterface, st: State, cfg: Config) {
  await refresh($, st, cfg)
  const windows = WINDOWS.map(({ kind, name }) => {
    const limit = st.reading?.get(kind)
    if (limit === undefined) return `${name} window: no reading`
    const reset = limit.resetsAt === undefined ? '' : `, resets at ${resetLabel(limit.resetsAt)}`
    return `${name} window: ${limit.percentUsed}% used, ${modelVerdict(levelOf(limit.percentUsed, cfg), cfg)}${reset}`
  })
  const home = await homeDir($)
  const snapshot = !cfg.writes
    ? 'off (rate_limit_guard_enabled is false)'
    : home
      ? `${home}/.claude/${CONTRACT_DIR}/${SNAPSHOT_FILE}`
      : 'no home directory to write under'
  return [
    'From the last API response:',
    ...windows,
    ...(st.spend ? [`Spend limit: ${st.spend.percentUsed}% used`] : []),
    `Line threshold ${cfg.threshold}%, approach mark ${cfg.approach}%.`,
    `Band row ${st.bandShown ? 'on' : 'off'}, window-change toast ${cfg.toast ? 'on' : 'off'}. Set the row with /${COMMAND} band [on|off].`,
    `Snapshot: ${snapshot}`,
    `README: ${README}`,
  ].join('\n')
}

const isoSeconds = (ms: number) => new Date(ms).toISOString().replace(/\.\d{3}Z$/, 'Z')

export const isEmailShaped = (value: unknown): value is string => {
  if (typeof value !== 'string') return false
  const points = [...value].map(c => c.codePointAt(0) ?? 0)
  return points.length >= 3 && points.length <= 254 && value.includes('@') && !points.some(p => p < 32 || p === 34 || p === 92 || p === 127)
}

const homeDir = async ($: EngineInterface) => (await $.env.get('HOME')) || (await $.env.get('USERPROFILE'))

// The account in the state file, undefined when unreadable or malformed. The file is large and
// rewritten often, so a parse is kept until the file's mtime or size changes.
async function readIdentity($: EngineInterface, st: State, home: string) {
  const path = `${(await $.env.get('CLAUDE_CONFIG_DIR')) || home}/.claude.json`
  const stat = await $.fs.stat(path).catch(() => undefined)
  if (stat === undefined || stat.kind !== 'file') return undefined
  const key = `${path}|${stat.mtimeMs}|${stat.size}`
  if (st.identityCache?.key === key) return st.identityCache.email
  const text = await $.fs.read(path).catch(() => undefined)
  if (typeof text !== 'string') return undefined
  let email: string | undefined
  try {
    const value: unknown = JSON.parse(text)?.oauthAccount?.emailAddress
    email = isEmailShaped(value) ? value : undefined
  } catch {}
  st.identityCache = { key, email }
  return email
}

// An API response: its time, and the account it was for.
async function recordResponse($: EngineInterface, st: State, cfg: Config) {
  st.lastResponseAtMs = await $.clock.now()
  st.responseEmail = undefined
  const home = await homeDir($)
  if (cfg.writes && home) st.responseEmail = await readIdentity($, st, home)
}

// Omit rather than guess: attribute only when the account now is the one read at the last response.
async function accountEmail($: EngineInterface, st: State, home: string) {
  if (st.responseEmail === undefined) return undefined
  const email = await readIdentity($, st, home)
  return email !== undefined && email === st.responseEmail ? email : undefined
}

export const snapshotBody = (capturedAt: string, sessionId: string, reading: Reading, email?: string): Body => {
  const windows = [...reading.entries()].map(([kind, l]) => {
    const resetsMs = l.resetsAt === undefined ? NaN : Date.parse(l.resetsAt)
    const resets = Number.isFinite(resetsMs) ? { resets_at: Math.floor(resetsMs / 1000) } : {}
    return [kind, { used_percentage: l.percentUsed, ...resets }] as const
  })
  return {
    captured_at: capturedAt,
    session_id: sessionId,
    ...(windows.length > 0 ? { rate_limits: Object.fromEntries(windows) } : {}),
    ...(email ? { account: { email } } : {}),
  }
}

const wholePoints = (body: Partial<Body> | undefined) =>
  JSON.stringify(
    Object.entries(body?.rate_limits ?? {})
      .sort(([a], [b]) => a.localeCompare(b))
      .map(([kind, w]) => [kind, Math.floor(Number(w?.used_percentage)), w?.resets_at ?? null]),
  )

const logOnce = ($: EngineInterface, st: State, key: string, text: string, to: 'debug' | 'transcript' = 'debug') => {
  if (st.loggedOnce.has(key)) return
  st.loggedOnce.add(key)
  $.ui.log(`rate-limit-guard: ${text}`, { to })
}

// A bad option is the person's to fix, so its line goes to the transcript, once per load.
const reportOptions = ($: EngineInterface, st: State, cfg: Config) => {
  for (const line of cfg.bad) logOnce($, st, line, line, 'transcript')
}

// Decides in memory whether to write, so an event that writes nothing starts no process.
async function writeSnapshot($: EngineInterface, st: State, cfg: Config, trigger: 'event' | 'timer') {
  if (!cfg.writes || st.origin?.kind === 'task-notification' || st.reading === undefined) return
  const home = await homeDir($)
  if (!home) return
  const target = `${home}/.claude/${CONTRACT_DIR}/${SNAPSHOT_FILE}`
  const [now, sessionId] = await Promise.all([$.clock.now(), $.session.id()])
  const email = await accountEmail($, st, home)
  const body = snapshotBody(isoSeconds(now), sessionId, st.reading, email)
  const onDisk = await $.fs
    .read(target)
    .then(text => JSON.parse(String(text)) as Partial<Body>)
    .catch(() => undefined)
  const diskAt = onDisk?.captured_at === undefined ? NaN : Date.parse(onDisk.captured_at)
  if (trigger === 'timer' && onDisk !== undefined && onDisk.session_id !== sessionId && !(diskAt < (st.lastResponseAtMs ?? 0))) {
    return
  }
  // After a branch the file takes the new session id at once: the id is part of what a reader trusts.
  const moved =
    onDisk === undefined || wholePoints(onDisk) !== wholePoints(body) || (st.branched && onDisk.session_id !== sessionId)
  if (!moved && Number.isFinite(diskAt) && now - diskAt < FLOOR_MS) return
  const sig = JSON.stringify({ ...body, captured_at: undefined })
  if (st.lastAttempt !== undefined && st.lastAttempt.sig === sig && now - st.lastAttempt.at < FLOOR_MS) return
  const argv = ['node', `${$.plugin.root}/${HELPER}`, target, '--preserve-key', 'rate_limits', ...(moved ? [] : ['--floor', '300'])]
  // Only a write the helper decided (written, or skipped by rule) dedupes; a failed one is tried at the next carrier.
  try {
    const run = await $.process.run(argv, { stdin: JSON.stringify(body), timeoutMs: 10_000 })
    if (run.exitCode === 0 || run.exitCode === 3) {
      st.lastAttempt = { sig, at: now }
      st.branched = false
    }
    else logOnce($, st, 'write-failed', `snapshot write failed (exit ${run.exitCode}): ${run.stderr.trim()}`)
  } catch (error) {
    logOnce($, st, 'write-threw', `snapshot write did not run: ${error instanceof Error ? error.message : String(error)}`)
  }
}

function queueWrite($: EngineInterface, st: State, cfg: Config, trigger: 'event' | 'timer') {
  st.writing = st.writing.then(() => writeSnapshot($, st, cfg, trigger)).catch(() => undefined)
  return st.writing
}

async function statusJson($: EngineInterface, st: State, cfg: Config) {
  await refresh($, st, cfg)
  // Every window the response reported except a gateway's spend limit, which has its own entry.
  const now = await $.clock.now()
  const live = st.limits.filter(l => l.kind !== 'spend_limit' && !(Date.parse(l.resetsAt ?? '') <= now))
  const windows = Object.fromEntries(
    live.map(l => [l.kind, { used_percentage: l.percentUsed, resets_at: l.resetsAt ?? null, verdict: levelOf(l.percentUsed, cfg) }]),
  )
  const levels = live.map(l => levelOf(l.percentUsed, cfg))
  return JSON.stringify({
    source: 'the last API response',
    windows,
    verdict: levels.length === 0 ? 'unknown' : levels.includes('edge') ? 'edge' : levels.includes('approach') ? 'approach' : 'quiet',
    line_threshold: cfg.threshold,
    approach_pct: cfg.approach,
    ...(st.spend ? { spend_limit: { used_percentage: st.spend.percentUsed, resets_at: st.spend.resetsAt ?? null } } : {}),
  })
}

// Operator mode: offer the line as the prompt box's suggestion; with text in the box, show the
// notice row and offer again once the box is empty; where it cannot show, the line goes to Claude.
// A first offer that cannot show leaves the changes to be toasted with the automatic line; a
// re-offer comes after the row was up, so the person has seen them unless a survey hid the row.
async function offer($: EngineInterface, st: State, first = false) {
  if (st.notice?.kind !== 'operator') return true
  const { text } = st.notice
  const box = await $.prompt.read()
  if (box.text.trim() !== '') return false
  const { isShown } = await $.prompt.suggest({ text })
  if (isShown) {
    st.handoff = new Map([...st.handoff, ...dueEvents(st)])
    consume(st)
    releaseHeld(st, true)
  } else {
    releaseHeld(st, !first && st.rowSeen)
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

export const register: Register = (on, options) => {
  const cfg = parseConfig(options)
  const st: State = {
    reading: undefined,
    spend: undefined,
    levels: new Map(),
    limits: [],
    pending: new Map(),
    toastQueue: [],
    heldToasts: [],
    rowSeen: false,
    handoff: new Map(),
    restate: false,
    restateIfLoud: false,
    branched: false,
    forceAutomatic: false,
    origin: undefined,
    notice: undefined,
    bandShown: cfg.band,
    lastResponseAtMs: undefined,
    responseEmail: undefined,
    identityCache: undefined,
    lastAttempt: undefined,
    loggedOnce: new Set(),
    writing: Promise.resolve(),
    writeTimer: undefined,
    reofferTimer: undefined,
  }

  on('session.start', async ($, e, next) => {
    reportOptions($, st, cfg)
    const [tool] = await Promise.allSettled([
      $.tool.register({
        name: 'status',
        description:
          "Read-only. Returns this session's rate-limit windows as the last API response reported them " +
          '(five_hour, seven_day, and a gateway spend_limit when present) with rate-limit-guard\'s verdict ' +
          'for each, as JSON. Takes no input.',
        inputSchema: { type: 'object', properties: {}, additionalProperties: false },
      }),
      $.command.register({
        name: 'rate-limit-guard',
        description: 'Rate-limit windows and verdicts; band on or off sets the band row for this session',
        argumentHint: '[band [on|off]]',
      }),
    ])
    if (tool.status === 'rejected') {
      const reason = tool.reason instanceof Error ? tool.reason.message : String(tool.reason)
      logOnce($, st, 'tool-register', `the status pull tool could not register: ${reason}`)
    }
    await refresh($, st, cfg)
    // A fresh load mid-session (a reload, a worker respawn, an enable, a --resume launch): the
    // earlier lines already reached Claude, so only a window at the edge is restated.
    if ((await $.session.turns()) > 0) {
      st.pending.clear()
      st.restateIfLoud = true
    }
    return next(e)
  }).catch(($, e, next) => next(e))

  on('session.end', async ($, e, next) => {
    st.writeTimer = stopTimer(st.writeTimer)
    st.reofferTimer = stopTimer(st.reofferTimer)
    await queueWrite($, st, cfg, 'event')
    if (e.reason === 'resume') st.restate = st.branched = true
    if (e.reason === 'clear') st.restateIfLoud = true
    st.origin = undefined
    return next(e)
  }).catch(($, e, next) => next(e))

  on('session.compact', async ($, e, next) => {
    const result = await next(e)
    if (e.agentId === undefined && e.trigger !== 'precompute' && !('skip' in result && result.skip)) st.restate = true
    return result
  }).catch(($, e, next) => next(e))

  on('session.measure', async ($, e, next) => {
    reportOptions($, st, cfg)
    await recordResponse($, st, cfg).catch(() => undefined)
    await refresh($, st, cfg, e.rateLimits)
    await queueWrite($, st, cfg, 'event')
    await flushToasts($, st, cfg)
    return next(e)
  }).catch(($, e, next) => next(e))

  on('turn.step', async function* ($, e, next) {
    const result = yield* next(e)
    await recordResponse($, st, cfg).catch(() => undefined)
    return result
  }).catch(async function* ($, e, next) {
    return yield* next(e)
  })

  on('prompt.submit', async ($, e, next) => {
    reportOptions($, st, cfg)
    if (e.turnId === undefined) {
      st.origin = e.origin
      // An untaken suggestion goes to Claude at the next turn no person started; a person's turn drops it.
      const handingOff = !isPersonTurn(st) && st.handoff.size > 0
      if (handingOff) {
        for (const [kind, event] of st.handoff) {
          if (!st.pending.has(kind) && (event === 'reset' || st.levels.has(kind))) st.pending.set(kind, event)
        }
      }
      st.handoff.clear()
      if (isPersonTurn(st) && st.notice?.kind === 'operator') releaseHeld(st, st.rowSeen)
      if (isPersonTurn(st) || handingOff) clearNotice($, st)
    }
    await refresh($, st, cfg)
    const held = cfg.lines && (await operatorHolds($, st, cfg))
    const lines = await takeLines($, st, cfg)
    await flushToasts($, st, cfg, held)
    return next(lines.length === 0 ? e : { ...e, context: [...(e.context ?? []), ...lines] })
  }).catch(($, e, next) => next(e))

  on('turn.start', async ($, e, next) => {
    st.reofferTimer = stopTimer(st.reofferTimer)
    st.writeTimer ??= $.clock.every(WRITE_TIMER_MS, () => {
      void queueWrite($, st, cfg, 'timer')
    })
    return next(e)
  }).catch(($, e, next) => next(e))

  on('turn.complete', async ($, e, next) => {
    if (e.agentId !== undefined) return next(e)
    st.writeTimer = stopTimer(st.writeTimer)
    if (cfg.lines && (await operatorHolds($, st, cfg))) {
      await refresh($, st, cfg)
      await flushToasts($, st, cfg)
      const lines = dueLines(st, cfg)
      if (lines.length > 0) {
        // One row, one prefix, however many windows it offers.
        st.notice = { text: `FYI, rate-limit-guard: ${lines.map(l => l.replace(/^rate-limit-guard: /, '')).join(' ')}`, kind: 'operator' }
        st.heldToasts.push(...st.toastQueue.splice(0))
        st.rowSeen = false
        $.ui.invalidate('ui.render')
        if (!(await offer($, st, true))) {
          st.reofferTimer ??= $.clock.every(REOFFER_MS, () => {
            void offer($, st)
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

  on('tool.call', async ($, e, next) => {
    if (e.tool === `mcp__${$.plugin.name}__status`) {
      const json = await statusJson($, st, cfg)
      await flushToasts($, st, cfg)
      return { result: json }
    }
    reportOptions($, st, cfg)
    const result = await next(e)
    if (e.agentId !== undefined) return result
    await refresh($, st, cfg)
    await queueWrite($, st, cfg, 'event')
    if (result.deny !== undefined || result.isError) return result
    const held = cfg.lines && (await operatorHolds($, st, cfg))
    const lines = await takeLines($, st, cfg)
    await flushToasts($, st, cfg, held)
    return lines.length === 0 ? result : { ...result, context: [...(result.context ?? []), ...lines] }
  }).catch(($, e, next) => next(e))

  on('command.run', { command: 'rate-limit-guard' }, async ($, e, next) => {
    const words = (e.args ?? '').trim().toLowerCase().split(/\s+/).filter(w => w !== '')
    if (words.length === 0) {
      const text = await statusText($, st, cfg)
      await flushToasts($, st, cfg)
      return { text }
    }
    const [word, arg, ...rest] = words
    if (word !== 'band' || rest.length > 0 || (arg !== undefined && arg !== 'on' && arg !== 'off')) return { text: USAGE }
    st.bandShown = arg === undefined ? !st.bandShown : arg === 'on'
    $.ui.invalidate('ui.render')
    return { text: `Band row ${st.bandShown ? 'on' : 'off'} for this session` }
  }).catch(($, e, next) => next(e))

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const theirs = await next(e)
    const notice = noticeShows(st, e.surface) ? st.notice : undefined
    if (e.props.hasSurvey || (!st.bandShown && notice === undefined)) return theirs
    if (notice?.kind === 'operator') st.rowSeen = true
    const { Box, Text } = $.ui.resolve(e)
    return (
      <Box flexDirection="column">
        {st.bandShown ? (
          <Text dimColor wrap="truncate">
            {bandText(st.reading)}
          </Text>
        ) : null}
        {notice !== undefined ? <Text wrap="wrap">{notice.text}</Text> : null}
        {theirs}
      </Box>
    )
  }).catch(($, e, next) => next(e))
}
