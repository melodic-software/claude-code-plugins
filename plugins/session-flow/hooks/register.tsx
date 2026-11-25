import type { EngineInterface, Register } from 'claude-code'

import { askedRow, band } from './observer-band.tsx'
import { type CheckRequest, type Effect, type Event, type Options, type Rate, initial, readOptions, step } from './observer-machine.ts'
import { buildPrompt, type Finding, ledgerHeader, ledgerLine, ledgerSection, remember, summarize, type Trigger } from './observer-live.ts'

const DAY_MS = 86_400_000
const USAGE = `Usage: /observer [on|off]. Bare /observer shows this session's and the last day's checks.`

const PERSON_ORIGINS = ['composer', 'bridge']
const PLUGIN = 'session-flow'

type Usage = { input_tokens: number; output_tokens: number; cache_read_input_tokens: number; cache_creation_input_tokens: number }

const fresh = () => ({ sid: '', dataDir: '', liveFile: '', ledgerDir: '', icon: '◆', rows: [] as object[] })
let st = fresh()
let m = initial()
let opts: Options

const list = async ($: EngineInterface, key: string) => {
  const v = await $.store.get(key)
  return Array.isArray(v) ? (v as string[]) : []
}
const count = async ($: EngineInterface, key: string) => {
  const v = await $.store.get(key)
  return typeof v === 'number' ? v : 0
}
const readOr = async ($: EngineInterface, path: string) => ((await $.fs.exists(path)) ? await $.fs.read(path) : '')
const APPEND = "const fs=require('fs'),p=process.argv[1];fs.mkdirSync(require('path').dirname(p),{recursive:true});fs.appendFileSync(p,fs.readFileSync(0))"
const appendTo = async ($: EngineInterface, path: string, text: string) => {
  const r = await $.process.run(['node', '-e', APPEND, path], { stdin: text, timeoutMs: 10_000 }).catch(() => undefined)
  if (r?.exitCode === 0) return
  const mark = async () => ((await $.fs.exists(path)) ? JSON.stringify(await $.fs.stat(path)) : '')
  for (let tries = 0; tries < 3; tries++) {
    const before = await mark()
    const old = await readOr($, path)
    if ((await mark()) !== before) continue
    await $.fs.write(path, old + text)
    return
  }
  throw new Error(`append failed: ${path} kept changing`)
}
const mainCheckout = async ($: EngineInterface, dir: string) => {
  const r = await $.process.run(['git', 'rev-parse', '--path-format=absolute', '--git-common-dir'], { cwd: dir, timeoutMs: 10_000 }).catch(() => undefined)
  const common = r?.exitCode === 0 ? r.stdout.trim() : ''
  return /[\\/]\.git$/.test(common) ? common.replace(/[\\/]\.git$/, '') : dir
}

const KEEP_DAYS = 30
const PRUNE =
  "const fs=require('fs'),path=require('path'),[d,cut]=process.argv.slice(1);for(const n of fs.readdirSync(d)){const p=path.join(d,n);if(/^(live-.*\\.jsonl|observations-.*\\.ndjson|status-.*\\.json|observer-.*\\.(log|lock))$/.test(n)&&fs.statSync(p).mtimeMs<Number(cut))fs.rmSync(p,{force:true})}"
const prune = async ($: EngineInterface, now: number) => {
  if (await $.fs.exists(st.dataDir)) await $.process.run(['node', '-e', PRUNE, st.dataDir, String(now - KEEP_DAYS * DAY_MS)], { timeoutMs: 10_000 }).catch(() => undefined)
}

const iso = async ($: EngineInterface) => new Date(await $.clock.now()).toISOString()

const ensureMemoryRootIgnored = async ($: EngineInterface) => {
  const root = st.ledgerDir.replace(/[\\/]running-retros$/, '')
  if (await $.fs.exists(`${root}/.git`)) return false
  const gi = `${root}/.gitignore`
  const text = await readOr($, gi)
  if (!text.split(/\r?\n/).some(l => l.trim() === '*' || l.trim() === '**')) await $.fs.write(gi, `${text}${text === '' || text.endsWith('\n') ? '' : '\n'}*\n`)
  return true
}

const sessionLedger = async ($: EngineInterface) => {
  if (!(await $.fs.exists(st.ledgerDir))) return undefined
  const re = new RegExp(`^session_id:\\s*${st.sid.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\s*$`, 'm')
  for (const e of [...(await $.fs.list(st.ledgerDir))].sort((a, b) => a.name.localeCompare(b.name))) {
    if (e.kind !== 'file' || !/-running-retro-.*\.md$/.test(e.name)) continue
    const path = `${st.ledgerDir}/${e.name}`
    if (re.test((await $.fs.read(path, { length: 400 })) as string)) return path
  }
  return undefined
}

const writeFinding = async ($: EngineInterface, at: string, trigger: Trigger, turnId: string, step: number, f: Finding) => {
  if (!(await ensureMemoryRootIgnored($))) return undefined
  const section = ledgerSection(at, trigger, turnId, step, f)
  const found = await sessionLedger($)
  if (found !== undefined) {
    await appendTo($, found, section)
    return found
  }
  const path = `${st.ledgerDir}/${at.replace(/[-:]/g, '').replace(/\.\d+Z$/, 'Z')}-running-retro-session.md`
  await $.fs.write(path, ledgerHeader(st.sid) + section)
  return path
}

const record = async ($: EngineInterface, row: object) => {
  st.rows.push(row)
  await appendTo($, st.liveFile, `${JSON.stringify(row)}\n`)
}

const parseRows = (text: string) =>
  text.split('\n').flatMap(l => {
    try {
      return l.trim() === '' ? [] : [JSON.parse(l) as object]
    } catch {
      return []
    }
  })

const lastDayRows = async ($: EngineInterface) => {
  if (!(await $.fs.exists(st.dataDir))) return []
  const since = (await $.clock.now()) - DAY_MS
  const files = (await $.fs.list(st.dataDir)).filter(e => e.kind === 'file' && /^live-.*\.jsonl$/.test(e.name) && e.mtimeMs >= since)
  const rows = (await Promise.all(files.map(async e => parseRows((await $.fs.read(`${st.dataDir}/${e.name}`)) as string)))).flat()
  return rows.filter(r => Date.parse(String((r as { at?: string }).at)) >= since)
}

const accept = async ($: EngineInterface, req: CheckRequest, finding: Finding) => {
  const redact = (t: string) => $.session.redact(t)
  const f = { ...finding, finding: await redact(finding.finding), rule: await redact(finding.rule), evidence: await redact(finding.evidence) }
  const ledger = await writeFinding($, await iso($), req.trigger, req.turnId, req.step, f)
  await $.store.set('seen', remember(await list($, 'seen'), f.finding))
  return run($, { kind: 'finding-accepted', req, finding: f, ledger })
}

const perform = async ($: EngineInterface, fx: Effect): Promise<string | undefined> => {
  switch (fx.kind) {
    case 'check':
      void runCheck($, fx.trigger, fx.turnId, fx.step)
      return undefined
    case 'fork':
      return undefined
    case 'accept':
      return accept($, fx.req, fx.finding)
    case 'finish':
      return fx.outcome
    case 'store':
      await $.store.set(fx.key, fx.value)
      return undefined
    case 'record':
      await record($, { at: await iso($), ...fx.row }).catch(() => undefined)
      return undefined
    case 'ledger':
      await appendTo($, fx.path, ledgerLine(fx.line, await iso($), fx.finding, fx.detail)).catch(() => undefined)
      return undefined
    case 'deliver':
      await deliver($, fx)
      return undefined
    case 'drop':
      return undefined
    case 'gate-fork':
    case 'deny':
      return undefined
    case 'abort':
      await $.turn.abort({ turnId: fx.turnId }).catch(() => undefined)
      return undefined
    case 'toast':
      $.ui.toast(fx.text)
      return undefined
    case 'fill':
      await $.prompt.fill({ text: fx.text, mode: 'append' })
      return undefined
    case 'after':
      $.clock.after(fx.ms, () => void run($, fx.event))
      return undefined
    case 'invalidate':
      $.ui.invalidate('ui.render')
      return undefined
  }
}

const dispatch = async ($: EngineInterface, e: Event) => {
  const r = step(m, e, opts)
  m = r.state
  let outcome: string | undefined
  for (const fx of r.effects) outcome = (await perform($, fx)) ?? outcome
  return { outcome, effects: r.effects }
}
const run = async ($: EngineInterface, e: Event) => (await dispatch($, e)).outcome

const deliver = async ($: EngineInterface, fx: Extract<Effect, { kind: 'deliver' }>) => {
  const done = (error?: string) => run($, { kind: 'delivered', cardId: fx.cardId, delivery: fx.delivery, chars: fx.text.length, stepsLate: fx.stepsLate, error })
  if (fx.delivery === 'submit') {
    void $.prompt.submit({ text: fx.text }).then(
      r => done('drop' in r && r.drop !== undefined ? `dropped: ${r.drop}` : undefined),
      err => done(String(err)),
    )
    return
  }
  const r = await $.session.append({ message: { type: 'user', content: [{ type: 'text', text: fx.text }] } }).catch((err: unknown) => ({ deny: String(err) }))
  await done(r.deny === undefined ? undefined : String(r.deny))
}

const gate = async ($: EngineInterface, command: string) => {
  const { effects } = await dispatch($, { kind: 'gate-requested', command, paused: (await $.store.get('paused')) === true })
  if (!effects.some(fx => fx.kind === 'gate-fork')) return undefined
  await syncSession($)
  const started = await $.clock.now()
  const [seen, disputed, notRelevant] = [await list($, 'seen'), await list($, 'disputed'), await list($, 'notRelevant')]
  const prompt = buildPrompt(seen, disputed, undefined, notRelevant, (await count($, 'unclear')) > 0, {
    autoSend: true,
    guidance: opts.guidance,
    guidanceMax: opts.guidanceMax,
    override: opts.checkPrompt,
    heldCommand: command,
  })
  const timeout = new Promise<'timeout'>(resolve => $.clock.after(opts.gateTimeoutMs, () => resolve('timeout')))
  const r = await Promise.race([$.model.fork({ prompt }), timeout]).catch(() => 'error' as const)
  const reply = r === 'timeout' || r === 'error' ? { isAnswered: false as const, reason: r } : r.isAnswered ? { isAnswered: true as const, text: r.text } : { isAnswered: false as const, reason: 'error' as const }
  const usage = typeof r === 'object' && r.isAnswered ? r.usage : undefined
  const done = await dispatch($, { kind: 'gate-replied', command, reply, latencyMs: (await $.clock.now()) - started, usage })
  const deny = done.effects.find(fx => fx.kind === 'deny')
  return deny?.kind === 'deny' ? deny.text : undefined
}

const syncSession = async ($: EngineInterface) => {
  const sid = await $.session.id()
  if (sid === st.sid) return
  st.sid = sid
  st.liveFile = `${st.dataDir}/live-${sid}.jsonl`
  await run($, { kind: 'session-changed' })
  st.rows = parseRows(await readOr($, st.liveFile))
}

const runCheck = async ($: EngineInterface, trigger: Trigger, turnId: string, stepIndex: number) => {
  await syncSession($)
  const requested = step(m, { kind: 'check-requested', trigger, turnId, step: stepIndex, paused: (await $.store.get('paused')) === true, skip: await count($, 'skip') }, opts)
  m = requested.state
  const fork = requested.effects.find(fx => fx.kind === 'fork')
  for (const fx of requested.effects) await perform($, fx)
  if (fork?.kind !== 'fork') return
  const { req } = fork
  const started = await $.clock.now()
  let outcome = 'error'
  let usage: Usage | undefined
  try {
    const [seen, disputed, notRelevant] = [await list($, 'seen'), await list($, 'disputed'), await list($, 'notRelevant')]
    const extra = { autoSend: opts.autoSend, guidance: opts.guidance, guidanceMax: opts.guidanceMax, override: opts.checkPrompt }
    const r = await $.model.fork({ prompt: buildPrompt(seen, disputed, req.open?.finding.finding, notRelevant, (await count($, 'unclear')) > 0, extra) })
    if (r.isAnswered) usage = r.usage
    const reply = r.isAnswered ? { isAnswered: true as const, text: r.text } : { isAnswered: false as const, reason: String(r.reason) }
    outcome = (await run($, { kind: 'check-replied', req, reply, paused: (await $.store.get('paused')) === true, seen, disputed })) ?? 'error'
  } catch {
    outcome = 'error'
  } finally {
    m = step(m, { kind: 'check-finished' }, opts).state
    const latencyMs = (await $.clock.now()) - started
    await record($, { at: await iso($), trigger, turnId, step: stepIndex, outcome, latencyMs, usage }).catch(() => undefined)
  }
}

export const register: Register = (on, options) => {
  st = fresh()
  m = initial()
  if (options.observer_enabled !== true) return
  const read = readOptions(options)
  opts = read.options

  on('session.start', async ($, e, next) => {
    const result = await next(e)
    if (!e.isInteractive || (await $.env.get('SESSION_FLOW_OBSERVER_ANALYSIS'))) return result
    const env = await $.process.hookEnv()
    st.dataDir = `${env.CLAUDE_PLUGIN_DATA}/session-flow-observer`
    st.sid = ''
    await syncSession($)
    st.ledgerDir = `${await mainCheckout($, env.CLAUDE_PROJECT_DIR || e.cwd)}/.work/running-retros`
    void prune($, await $.clock.now())
    st.icon = (await $.env.get('TERM')) === 'dumb' ? '*' : '◆'
    await run($, { kind: 'session-started' })
    for (const key of read.invalid) await record($, { at: await iso($), answer: 'option_invalid', key }).catch(() => undefined)
    await $.command.register({ name: 'observer', description: 'Session observer: show its checks and token use, or turn its live checks on or off on this machine' })
    return result
  }).catch(($, e, next) => next(e))

  on('command.run', { command: 'observer' }, async ($, e) => {
    const arg = e.args.trim().toLowerCase()
    if (arg === 'off' || arg === 'on') {
      await run($, { kind: 'command', arg })
      return { text: arg === 'off' ? 'Live checks paused on this machine until /observer on. The catch-up for ended sessions still runs.' : 'Live checks on.' }
    }
    if (arg !== '') return { text: USAGE }
    const paused = (await $.store.get('paused')) === true
    return {
      text: [
        `live checks: ${paused ? 'paused (/observer on)' : 'on'}; step ${opts.stepCheck ? 'on' : 'off'}, turn end ${opts.turnEndCheck ? 'on' : 'off'}`,
        '',
        'This session:',
        summarize(st.rows),
        '',
        'Last 24 hours, all sessions:',
        summarize(await lastDayRows($)),
      ].join('\n'),
    }
  })

  on('session.end', async ($, e, next) => {
    await run($, { kind: 'session-ended' })
    return next(e)
  })

  on('turn.start', async ($, e, next) => {
    await run($, { kind: 'turn-started', main: e.agentId === undefined, turnId: e.turnId, text: e.text ?? '', paused: (await $.store.get('paused')) === true })
    return next(e)
  })

  on('tool.call', async ($, e, next) => {
    const main = e.agentId === undefined
    await run($, { kind: 'tool-called', main, name: e.tool })
    const command = (e as { command?: unknown }).command
    if (main && e.tool === 'Bash' && typeof command === 'string') {
      const deny = await gate($, command.trim())
      if (deny !== undefined) return { deny }
    }
    return next(e)
  }).catch(($, e, next) => next(e))

  on('turn.step', async function* ($, e, next) {
    await run($, { kind: 'step', main: e.agentId === undefined, turnId: e.turnId, index: e.index })
    return yield* next(e)
  })

  on('turn.complete', async ($, e, next) => {
    await run($, { kind: 'turn-completed', main: e.agentId === undefined, turnId: e.turnId, isAborted: e.isAborted, durationMs: e.durationMs, usage: e.usage })
    return next(e)
  })

  on('prompt.submit', async ($, e, next) => {
    const ours = e.origin.kind === 'plugin' && e.origin.name === PLUGIN
    const { effects } = await dispatch($, {
      kind: 'prompt-submitted',
      byPerson: PERSON_ORIGINS.includes(e.origin.kind),
      ours,
      paused: ours && (await $.store.get('paused')) === true,
      typedPast: await count($, 'typedPast'),
    })
    const drop = effects.find(fx => fx.kind === 'drop')
    return drop?.kind === 'drop' ? { drop: drop.reason } : next(e)
  }).catch(($, e, next) => next(e))

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const theirs = await next(e)
    const card = m.card
    if (e.props.hasSurvey || (card === null && !m.asked)) return theirs
    const ui = $.ui.resolve(e)
    const { Box } = ui
    if (card === null) {
      const rate = (answer: Rate) => async () => {
        await run($, { kind: 'rate', answer, notRelevant: await list($, 'notRelevant'), unclear: await count($, 'unclear') })
      }
      return (
        <Box flexDirection="column" marginTop={1}>
          {askedRow(ui, st.icon, { helpful: rate('helpful'), notRelevant: rate('not_relevant'), unclear: rate('unclear'), turnOff: rate('turned_off'), close: rate('closed') })}
          {theirs}
        </Box>
      )
    }
    const f = card.finding
    return (
      <Box flexDirection="column" marginTop={1}>
        {band(ui, st.icon, f, card.source, card.isOpen, `this session: ${summarize(st.rows).split('\n')[1] ?? ''} (/observer for more)`, {
          noted: async () => {
            const ok = await appendTo($, card.ledger, ledgerLine('confirmed', await iso($), f)).then(() => true, () => false)
            await run($, { kind: 'noted', ok })
          },
          send: () => run($, { kind: 'send' }),
          dispute: async () => run($, { kind: 'dispute', disputed: await list($, 'disputed') }),
          why: () => void run($, { kind: 'why' }),
          dismiss: () => run($, { kind: 'dismiss' }),
        }, card.sent)}
        {theirs}
      </Box>
    )
  }).catch(($, e, next) => next(e))
}
