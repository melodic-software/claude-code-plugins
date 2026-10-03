import type { EngineInterface, PromptOrigin, Register, SessionRateLimit, Timer } from 'claude-code'

// The contract directory under the home directory. make-probe-copy.sh rewrites this one line.
const CONTRACT_DIR = 'rate-limit-guard'
const SNAPSHOT_FILE = 'rate-limits.json'
const HELPER = 'lib/write-snapshot.mjs'
const PAUSE_EDGE = 90
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
const SOURCE_NOTE = '(a measurement from the last API response)'
const PERSON_ORIGINS = ['composer', 'bridge']

type Level = 'quiet' | 'approach' | 'edge'
type Event = Level | 'reset'
type Reading = Map<string, SessionRateLimit>
type Config = {
  writes: boolean
  lines: boolean
  operator: boolean
  threshold: number
  approach: number
  data: Set<string>
  band: boolean
}
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
  model: string | undefined
  pending: Map<string, Event>
  // Operator mode: events a shown suggestion offered, handed to Claude if no person takes them.
  handoff: Map<string, Event>
  restate: boolean
  restateIfLoud: boolean
  forceAutomatic: boolean
  origin: PromptOrigin | undefined
  notice: string | undefined
  bandShown: boolean
  lastResponseAtMs: number | undefined
  lastAttempt: { sig: string; at: number } | undefined
  loggedOnce: Set<string>
  writing: Promise<void>
  writeTimer: Timer | undefined
  reofferTimer: Timer | undefined
}

export const parseConfig = (options: Record<string, unknown>): Config => {
  const number = (value: unknown, fallback: number) => {
    const n = Number(value)
    return Number.isFinite(n) && n > 0 && n <= 100 ? n : fallback
  }
  const items = String(options.rate_limit_line_data ?? '')
    .split(',')
    .map(s => s.trim().toLowerCase())
    .filter(s => DATA_ITEMS.includes(s))
  const data = new Set(items.length > 0 ? items : DEFAULT_DATA)
  return {
    writes: options.rate_limit_guard_enabled !== false,
    lines: options.rate_limit_lines_enabled !== false,
    operator: options.rate_limit_report_mode === 'operator',
    threshold: number(options.rate_limit_line_threshold, PAUSE_EDGE),
    approach: number(options.rate_limit_approach_pct, 85),
    data,
    band: options.rate_limit_guard_band !== false,
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

const clause = (kind: string, event: Event, limit: SessionRateLimit | undefined, cfg: Config) => {
  const name = WINDOWS.find(w => w.kind === kind)?.name ?? kind
  const subject = cfg.data.has('window') ? `the ${name} window` : 'a rate-limit window'
  const percent = limit !== undefined && cfg.data.has('percent') ? `${limit.percentUsed}% used` : undefined
  const verdict = {
    edge: `is at the ${edgeName(cfg)}`,
    approach: `is approaching the ${edgeName(cfg)}`,
    quiet: `is below the ${edgeName(cfg)}`,
    reset: `reset and is below the ${edgeName(cfg)}`,
  }[event]
  let text = `${subject} ${verdict}${percent ? ` (${percent})` : ''}`
  if (event !== 'reset' && cfg.data.has('reset') && limit?.resetsAt !== undefined) {
    text += `, resets at ${resetLabel(limit.resetsAt)}`
  }
  return text
}

const order = (kind: string) => WINDOWS.findIndex(w => w.kind === kind)

// Records crossings since the last check as pending events, one per window, the newest kept.
// Use only rises within a window, so a dip is reporting noise: a window's level falls, and its
// lines re-arm, only when the window resets (its reset time passes) or leaves the reading.
export const recordCrossings = (st: State, reading: Reading, cfg: Config, nowMs: number) => {
  for (const { kind } of WINDOWS) {
    const limit = reading.get(kind)
    let prev = st.levels.get(kind)
    if (prev !== undefined && (limit === undefined || prev.resetsMs <= nowMs)) {
      if (prev.level === 'edge') st.pending.set(kind, 'reset')
      else st.pending.delete(kind)
      st.levels.delete(kind)
      prev = undefined
    }
    if (limit === undefined) continue
    const level = levelOf(limit.percentUsed, cfg)
    const resetsMs = limit.resetsAt === undefined ? NaN : Date.parse(limit.resetsAt)
    if (prev !== undefined && RANK[level] <= RANK[prev.level]) continue
    st.levels.set(kind, { level, resetsMs: Number.isFinite(resetsMs) ? resetsMs : Infinity })
    if (level !== 'quiet') st.pending.set(kind, level)
  }
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
  return dueEvents(st)
    .sort(([a], [b]) => order(a) - order(b))
    .map(([kind, event]) => `rate-limit-guard: ${clause(kind, event, reading.get(kind), cfg)} ${SOURCE_NOTE}`)
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
  const [now, rateLimits, model] = await Promise.all([
    $.clock.now(),
    limits ?? $.session.usage().then(u => u.rateLimits),
    $.session.model().catch(() => undefined),
  ])
  const reading = liveWindows(rateLimits, now)
  const changed = bandText(reading, model) !== bandText(st.reading, st.model)
  st.reading = reading
  st.model = model
  st.limits = rateLimits
  st.spend = rateLimits.find(l => l.kind === 'spend_limit')
  if (changed) $.ui.invalidate('ui.render')
  recordCrossings(st, reading, cfg, now)
  return { now, reading }
}

function clearNotice($: EngineInterface, st: State) {
  if (st.notice === undefined) return
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
  consume(st)
  if (lines.length > 0) clearNotice($, st)
  return lines
}

// The tee's standalone status line, less the context figure: [<model>] 5h <x>% | 7d <y>%.
export const bandText = (reading: Reading | undefined, model: string | undefined) =>
  `[${model || 'Claude'}] ${WINDOWS.map(({ kind, short }) => {
    const limit = reading?.get(kind)
    return `${short} ${limit === undefined ? '-' : `${limit.percentUsed}%`}`
  }).join(' | ')}`

const isoSeconds = (ms: number) => new Date(ms).toISOString().replace(/\.\d{3}Z$/, 'Z')

export const isEmailShaped = (value: unknown): value is string => {
  if (typeof value !== 'string') return false
  const points = [...value].map(c => c.codePointAt(0) ?? 0)
  return points.length >= 3 && points.length <= 254 && value.includes('@') && !points.some(p => p < 32 || p === 34 || p === 92 || p === 127)
}

// Omit rather than guess: attribute only when the state file is strictly older than the response
// the windows came from.
async function accountEmail($: EngineInterface, home: string, lastResponseAtMs: number | undefined) {
  if (lastResponseAtMs === undefined) return undefined
  const dir = (await $.env.get('CLAUDE_CONFIG_DIR')) || home
  const path = `${dir}/.claude.json`
  const stat = await $.fs.stat(path).catch(() => undefined)
  if (stat === undefined || stat.kind !== 'file' || !(stat.mtimeMs < lastResponseAtMs)) return undefined
  const text = await $.fs.read(path).catch(() => undefined)
  if (typeof text !== 'string') return undefined
  try {
    const email: unknown = JSON.parse(text)?.oauthAccount?.emailAddress
    return isEmailShaped(email) ? email : undefined
  } catch {
    return undefined
  }
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

const logOnce = ($: EngineInterface, st: State, key: string, text: string) => {
  if (st.loggedOnce.has(key)) return
  st.loggedOnce.add(key)
  $.ui.log(`rate-limit-guard: ${text}`, { to: 'debug' })
}

// Decides in memory whether to write, so an event that writes nothing starts no process.
async function writeSnapshot($: EngineInterface, st: State, cfg: Config, trigger: 'event' | 'timer') {
  if (!cfg.writes || st.origin?.kind === 'task-notification' || st.reading === undefined) return
  const home = (await $.env.get('HOME')) || (await $.env.get('USERPROFILE'))
  if (!home) return
  const target = `${home}/.claude/${CONTRACT_DIR}/${SNAPSHOT_FILE}`
  const [now, sessionId] = await Promise.all([$.clock.now(), $.session.id()])
  const email = await accountEmail($, home, st.lastResponseAtMs)
  const body = snapshotBody(isoSeconds(now), sessionId, st.reading, email)
  const onDisk = await $.fs
    .read(target)
    .then(text => JSON.parse(String(text)) as Partial<Body>)
    .catch(() => undefined)
  const diskAt = onDisk?.captured_at === undefined ? NaN : Date.parse(onDisk.captured_at)
  if (trigger === 'timer' && onDisk !== undefined && onDisk.session_id !== sessionId && !(diskAt < (st.lastResponseAtMs ?? 0))) {
    return
  }
  const moved = onDisk === undefined || wholePoints(onDisk) !== wholePoints(body)
  if (!moved && Number.isFinite(diskAt) && now - diskAt < FLOOR_MS) return
  const sig = JSON.stringify({ ...body, captured_at: undefined })
  if (st.lastAttempt !== undefined && st.lastAttempt.sig === sig && now - st.lastAttempt.at < FLOOR_MS) return
  const argv = ['node', `${$.plugin.root}/${HELPER}`, target, '--preserve-key', 'rate_limits', ...(moved ? [] : ['--floor', '300'])]
  // Only a write the helper decided (written, or skipped by rule) dedupes; a failed one is tried at the next carrier.
  try {
    const run = await $.process.run(argv, { stdin: JSON.stringify(body), timeoutMs: 10_000 })
    if (run.exitCode === 0 || run.exitCode === 3) st.lastAttempt = { sig, at: now }
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
    lanes_pause_edge: PAUSE_EDGE,
    ...(st.spend ? { spend_limit: { used_percentage: st.spend.percentUsed, resets_at: st.spend.resetsAt ?? null } } : {}),
  })
}

// Operator mode: offer the line as the prompt box's suggestion; with text in the box, show the band
// notice and offer again once the box is empty; where it cannot show, the line goes to Claude.
async function offer($: EngineInterface, st: State) {
  const text = st.notice
  if (text === undefined) return true
  const box = await $.prompt.read()
  if (box.text.trim() !== '') return false
  const { isShown } = await $.prompt.suggest({ text })
  if (isShown) {
    st.handoff = new Map([...st.handoff, ...dueEvents(st)])
    consume(st)
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

export const register: Register = (on, options) => {
  const cfg = parseConfig(options)
  const st: State = {
    reading: undefined,
    spend: undefined,
    levels: new Map(),
    limits: [],
    model: undefined,
    pending: new Map(),
    handoff: new Map(),
    restate: false,
    restateIfLoud: false,
    forceAutomatic: false,
    origin: undefined,
    notice: undefined,
    bandShown: cfg.band,
    lastResponseAtMs: undefined,
    lastAttempt: undefined,
    loggedOnce: new Set(),
    writing: Promise.resolve(),
    writeTimer: undefined,
    reofferTimer: undefined,
  }

  on('session.start', async ($, e, next) => {
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
        name: 'band',
        description: 'Show or hide the rate-limit-guard band row for this session: show, hide, or nothing to toggle',
        argumentHint: '[show|hide]',
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
    if (e.reason === 'resume') st.restate = true
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
    await refresh($, st, cfg, e.rateLimits)
    await queueWrite($, st, cfg, 'event')
    return next(e)
  }).catch(($, e, next) => next(e))

  on('turn.step', async function* ($, e, next) {
    const result = yield* next(e)
    st.lastResponseAtMs = await $.clock.now()
    return result
  }).catch(async function* ($, e, next) {
    return yield* next(e)
  })

  on('prompt.submit', async ($, e, next) => {
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
      if (isPersonTurn(st) || handingOff) clearNotice($, st)
    }
    await refresh($, st, cfg)
    const lines = await takeLines($, st, cfg)
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
      const lines = dueLines(st, cfg)
      if (lines.length > 0) {
        st.notice = `FYI, ${lines.join(' ')}`
        $.ui.invalidate('ui.render')
        if (!(await offer($, st))) {
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
    if (e.tool === `mcp__${$.plugin.name}__status`) return { result: await statusJson($, st, cfg) }
    const result = await next(e)
    if (e.agentId !== undefined) return result
    await refresh($, st, cfg)
    await queueWrite($, st, cfg, 'event')
    if (result.deny !== undefined || result.isError) return result
    const lines = await takeLines($, st, cfg)
    return lines.length === 0 ? result : { ...result, context: [...(result.context ?? []), ...lines] }
  }).catch(($, e, next) => next(e))

  on('command.run', async ($, e, next) => {
    if (e.command !== 'band' && e.command !== `${$.plugin.name}:band`) return next(e)
    const arg = e.args.trim().toLowerCase()
    st.bandShown = arg === 'show' ? true : arg === 'hide' ? false : !st.bandShown
    $.ui.invalidate('ui.render')
    return { text: `rate-limit-guard: band row ${st.bandShown ? 'shown' : 'hidden'} for this session` }
  }).catch(($, e, next) => next(e))

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const theirs = await next(e)
    if (e.props.hasSurvey || (!st.bandShown && st.notice === undefined)) return theirs
    const { Box, Text } = $.ui.resolve(e)
    return (
      <Box flexDirection="column">
        {st.bandShown ? (
          <Text dimColor wrap="truncate">
            {bandText(st.reading, st.model ?? (await $.session.model().catch(() => undefined)))}
          </Text>
        ) : null}
        {st.notice !== undefined ? <Text wrap="truncate">{`rate-limit-guard notice: ${st.notice}`}</Text> : null}
        {theirs}
      </Box>
    )
  }).catch(($, e, next) => next(e))
}
