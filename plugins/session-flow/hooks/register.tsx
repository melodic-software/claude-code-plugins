import type { EngineInterface, Register } from 'claude-code'

import { askedRow, band } from './observer-band.tsx'
import {
  buildPrompt,
  CLEAR_AFTER_PROMPTS,
  disputeLine,
  notedLine,
  resolvedLine,
  type Finding,
  isKnown,
  isResolved,
  isStepCheck,
  ledgerHeader,
  ledgerSection,
  noteFor,
  parseReply,
  remember,
  checksToSkipAfterIgnored,
  summarize,
  type Trigger,
} from './observer-live.ts'

const DAY_MS = 86_400_000
const USAGE = `Usage: /observer [on|off]. Bare /observer shows this session's and the last day's checks.`

const PERSON_ORIGINS = ['composer', 'bridge']

type Card = { finding: Finding; ledger: string; source: string; promptsSurvived: number; isOpen: boolean }
type Usage = { input_tokens: number; output_tokens: number; cache_read_input_tokens: number; cache_creation_input_tokens: number }

const fresh = () => ({
  on: false,
  sid: '',
  dataDir: '',
  liveFile: '',
  ledgerDir: '',
  gen: 0,
  tools: 0,
  inFlight: false,
  ended: false,
  card: null as Card | null,
  asked: false,
  icon: '◆',
  rows: [] as object[],
})
let st = fresh()

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
  await $.fs.write(path, (await readOr($, path)) + text)
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

const syncSession = async ($: EngineInterface) => {
  const sid = await $.session.id()
  if (sid === st.sid) return
  st.sid = sid
  st.liveFile = `${st.dataDir}/live-${sid}.jsonl`
  st.card = null
  st.rows = parseRows(await readOr($, st.liveFile))
}

const runCheck = async ($: EngineInterface, trigger: Trigger, turnId: string, step: number) => {
  if (st.inFlight || (await $.store.get('paused')) === true) return
  await syncSession($)
  const skip = await count($, 'skip')
  if (skip > 0) {
    await $.store.set('skip', skip - 1)
    return
  }
  st.inFlight = true
  const gen = st.gen
  const started = await $.clock.now()
  let outcome = 'error'
  let usage: Usage | undefined
  try {
    const [seen, disputed] = [await list($, 'seen'), await list($, 'disputed')]
    const open = st.card
    const r = await $.model.fork({ prompt: buildPrompt(seen, disputed, open?.finding.finding) })
    if (!r.isAnswered) {
      outcome = r.reason === 'nothing-to-fork' || r.reason === 'empty-reply' ? 'none' : String(r.reason).replace('-', '_')
      return
    }
    usage = r.usage
    const parsed = parseReply(r.text)
    if ((await $.store.get('paused')) === true) {
      outcome = 'paused'
      return
    }
    const isCurrent = !st.ended && st.gen === gen
    if (isCurrent && open !== null && st.card === open && isResolved(r.text)) {
      await appendTo($, open.ledger, resolvedLine(await iso($), open.finding))
      await record($, { at: await iso($), answer: 'resolved' })
      st.card = null
      $.ui.invalidate('ui.render')
    }
    if (!isCurrent) outcome = 'stale'
    else if (parsed.kind !== 'finding') outcome = parsed.kind === 'none' ? 'none' : 'parse_failed'
    else if (isKnown(parsed.value.finding, seen, disputed)) outcome = 'deduped'
    else {
      const redact = (t: string) => $.session.redact(t)
      const f = { ...parsed.value, finding: await redact(parsed.value.finding), rule: await redact(parsed.value.rule), evidence: await redact(parsed.value.evidence) }
      const ledger = await writeFinding($, await iso($), trigger, turnId, step, f)
      await $.store.set('seen', remember(seen, f.finding))
      if (ledger === undefined) outcome = 'unsafe_memory_root'
      else {
        st.card = { finding: f, ledger, source: trigger === 'step' ? `step ${step}` : 'turn end', promptsSurvived: 0, isOpen: false }
        outcome = 'shown'
        $.ui.invalidate('ui.render')
      }
    }
  } catch {
    outcome = 'error'
  } finally {
    st.inFlight = false
    const latencyMs = (await $.clock.now()) - started
    await record($, { at: await iso($), trigger, turnId, step, outcome, latencyMs, usage }).catch(() => undefined)
  }
}

const ASKED_MS = 20_000

const answered = async ($: EngineInterface, answer: string, toast?: string) => {
  st.card = null
  st.asked = false
  if (toast) $.ui.toast(toast)
  await record($, { at: await iso($), answer }).catch(() => undefined)
  await $.store.set('typedPast', 0)
  await $.store.set('skip', 0)
  $.ui.invalidate('ui.render')
}

export const register: Register = (on, options) => {
  st = fresh()
  if (options.observer_enabled !== true) return
  const stepCheck = options.observer_step_check !== false
  const turnEndCheck = options.observer_turn_end_check === true

  on('session.start', async ($, e, next) => {
    const result = await next(e)
    if (!e.isInteractive || (await $.env.get('SESSION_FLOW_OBSERVER_ANALYSIS'))) return result
    const env = await $.process.hookEnv()
    st.dataDir = `${env.CLAUDE_PLUGIN_DATA}/session-flow-observer`
    st.sid = ''
    await syncSession($)
    st.ledgerDir = `${env.CLAUDE_PROJECT_DIR || e.cwd}/.work/running-retros`
    st.icon = (await $.env.get('TERM')) === 'dumb' ? '*' : '◆'
    st.ended = false
    st.on = true
    await $.command.register({ name: 'observer', description: 'Session observer: show its checks and token use, or turn its live checks on or off on this machine' })
    return result
  }).catch(($, e, next) => next(e))

  on('command.run', { command: 'observer' }, async ($, e) => {
    const arg = e.args.trim().toLowerCase()
    if (arg === 'off' || arg === 'on') {
      await $.store.set('paused', arg === 'off')
      if (arg === 'off' && st.card !== null) await answered($, 'dismissed')
      return { text: arg === 'off' ? 'Live checks paused on this machine until /observer on. The catch-up for ended sessions still runs.' : 'Live checks on.' }
    }
    if (arg !== '') return { text: USAGE }
    const paused = (await $.store.get('paused')) === true
    return {
      text: [
        `live checks: ${paused ? 'paused (/observer on)' : 'on'}; step ${stepCheck ? 'on' : 'off'}, turn end ${turnEndCheck ? 'on' : 'off'}`,
        '',
        'This session:',
        summarize(st.rows),
        '',
        'Last 24 hours, all sessions:',
        summarize(await lastDayRows($)),
      ].join('\n'),
    }
  })

  on('session.end', ($, e, next) => {
    st.ended = true
    st.on = false
    return next(e)
  })

  on('turn.start', ($, e, next) => {
    if (e.agentId === undefined) {
      st.gen += 1
      st.tools = 0
    }
    return next(e)
  })

  on('tool.call', ($, e, next) => {
    if (e.agentId === undefined) st.tools += 1
    return next(e)
  }).catch(($, e, next) => next(e))

  on('turn.step', async function* ($, e, next) {
    if (st.on && stepCheck && isStepCheck(e.index, e.agentId)) void runCheck($, 'step', e.turnId, e.index)
    return yield* next(e)
  })

  on('turn.complete', ($, e, next) => {
    if (st.on && turnEndCheck && e.agentId === undefined && !e.isAborted && st.tools > 0) void runCheck($, 'turn-end', e.turnId, -1)
    return next(e)
  })

  on('prompt.submit', async ($, e, next) => {
    const card = st.card
    if (card !== null && PERSON_ORIGINS.includes(e.origin.kind)) {
      card.promptsSurvived += 1
      if (card.promptsSurvived >= CLEAR_AFTER_PROMPTS) {
        st.card = null
        await record($, { at: await iso($), answer: 'ignored' }).catch(() => undefined)
        const typedPast = (await count($, 'typedPast')) + 1
        await $.store.set('typedPast', typedPast)
        await $.store.set('skip', checksToSkipAfterIgnored(typedPast))
        $.ui.invalidate('ui.render')
      }
    }
    return next(e)
  }).catch(($, e, next) => next(e))

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const theirs = await next(e)
    const card = st.card
    if (e.props.hasSurvey || (card === null && !st.asked)) return theirs
    const ui = $.ui.resolve(e)
    const { Box } = ui
    if (card === null) {
      const rate = (answer: string) => async () => {
        st.asked = false
        await record($, { at: await iso($), answer }).catch(() => undefined)
        $.ui.invalidate('ui.render')
      }
      return (
        <Box flexDirection="column">
          {askedRow(ui, st.icon, { useful: rate('useful'), notUseful: rate('not_useful'), close: rate('closed') })}
          {theirs}
        </Box>
      )
    }
    const f = card.finding
    return (
      <Box flexDirection="column">
        {band(ui, st.icon, f, card.source, card.isOpen, `this session: ${summarize(st.rows).split('\n')[1] ?? ''} (/observer for more)`, {
          noted: async () => {
            const ok = await appendTo($, card.ledger, notedLine(await iso($), f)).then(() => true, () => false)
            await answered($, 'noted', ok ? 'observer: noted in the running-retro ledger' : `observer: could not write ${card.ledger}`)
          },
          send: async () => {
            await $.prompt.fill({ text: noteFor(f), mode: 'append' })
            await answered($, 'sent')
          },
          dispute: async () => {
            await $.store.set('disputed', remember(await list($, 'disputed'), f.finding))
            await appendTo($, card.ledger, disputeLine(await iso($), f)).catch(() => undefined)
            await answered($, 'disputed', 'observer: disputed; it will not be reported again')
          },
          why: () => {
            card.isOpen = !card.isOpen
            $.ui.invalidate('ui.render')
          },
          dismiss: async () => {
            await answered($, 'dismissed')
            st.asked = true
            $.clock.after(ASKED_MS, () => {
              st.asked = false
              $.ui.invalidate('ui.render')
            })
            $.ui.invalidate('ui.render')
          },
        })}
        {theirs}
      </Box>
    )
  }).catch(($, e, next) => next(e))
}
