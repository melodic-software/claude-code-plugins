import type { EngineInterface, Register } from 'claude-code'

import {
  buildPrompt,
  CLEAR_AFTER_PROMPTS,
  disputeLine,
  type Finding,
  isKnown,
  isStepCheck,
  ledgerHeader,
  ledgerSection,
  noteFor,
  parseReply,
  remember,
  checksToSkipAfterIgnored,
  type Trigger,
} from './observer-live.ts'

const PERSON_ORIGINS = ['composer', 'bridge']

type Card = { finding: Finding; ledger: string; promptsSurvived: number }
type Usage = { input_tokens: number; output_tokens: number; cache_read_input_tokens: number; cache_creation_input_tokens: number }

const fresh = () => ({
  on: false,
  sid: '',
  liveFile: '',
  ledgerDir: '',
  gen: 0,
  tools: 0,
  inFlight: false,
  ended: false,
  card: null as Card | null,
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
const appendTo = async ($: EngineInterface, path: string, text: string) => $.fs.write(path, (await readOr($, path)) + text)
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

const record = async ($: EngineInterface, row: object) => appendTo($, st.liveFile, `${JSON.stringify(row)}\n`)

const runCheck = async ($: EngineInterface, trigger: Trigger, turnId: string, step: number) => {
  if (st.inFlight) return
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
    const r = await $.model.fork({ prompt: buildPrompt(seen, disputed) })
    if (!r.isAnswered) {
      outcome = r.reason === 'nothing-to-fork' || r.reason === 'empty-reply' ? 'none' : String(r.reason).replace('-', '_')
      return
    }
    usage = r.usage
    const parsed = parseReply(r.text)
    if (st.ended || st.gen !== gen) outcome = 'stale'
    else if (parsed.kind !== 'finding') outcome = parsed.kind === 'none' ? 'none' : 'parse_failed'
    else if (isKnown(parsed.value.finding, seen, disputed)) outcome = 'deduped'
    else {
      const redact = (t: string) => $.session.redact(t)
      const f = { ...parsed.value, finding: await redact(parsed.value.finding), rule: await redact(parsed.value.rule), evidence: await redact(parsed.value.evidence) }
      const ledger = await writeFinding($, await iso($), trigger, turnId, step, f)
      await $.store.set('seen', remember(seen, f.finding))
      if (ledger === undefined) outcome = 'unsafe_memory_root'
      else {
        st.card = { finding: f, ledger, promptsSurvived: 0 }
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

const answered = async ($: EngineInterface) => {
  st.card = null
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
    st.sid = await $.session.id()
    st.liveFile = `${env.CLAUDE_PLUGIN_DATA}/session-flow-observer/live-${st.sid}.jsonl`
    st.ledgerDir = `${env.CLAUDE_PROJECT_DIR || e.cwd}/.work/running-retros`
    st.ended = false
    st.on = true
    return result
  }).catch(($, e, next) => next(e))

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
    if (card === null || e.props.hasSurvey) return theirs
    const { Box, Button, Text } = $.ui.resolve(e)
    const f = card.finding
    return (
      <Box flexDirection="column">
        <Box>
          <Text color="warning">◆ </Text>
          <Text wrap="wrap">
            observer · {f.category} · {f.finding}
          </Text>
        </Box>
        <Box>
          <Button
            key="send"
            hotkey="1"
            label="Send to Claude"
            onPress={async () => {
              await $.prompt.fill({ text: noteFor(f), mode: 'append' })
              await answered($)
            }}
          />
          <Button key="noted" hotkey="2" label="Noted" onPress={() => answered($)} />
          <Button
            key="dispute"
            hotkey="3"
            label="Dispute"
            onPress={async () => {
              await $.store.set('disputed', remember(await list($, 'disputed'), f.finding))
              await appendTo($, card.ledger, disputeLine(await iso($), f))
              await answered($)
            }}
          />
          <Button key="dismiss" hotkey="0" label="Dismiss" dimColor onPress={() => answered($)} />
        </Box>
        {theirs}
      </Box>
    )
  }).catch(($, e, next) => next(e))
}
