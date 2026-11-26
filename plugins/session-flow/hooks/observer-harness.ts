import type { Finding, Fix } from './observer-live.ts'

export type HarnessOptions = {
  harnessCheck: boolean
  hookLogDir: string
  hookP95Ms: number
  hookMinRuns: number
  cacheMissTokens: number
  toolSlowMs: number
  toolRepeat: number
  contextPercents: readonly number[]
  rateLimitPercent: number
}

export type Platform = 'macos' | 'windows' | 'wsl' | 'linux' | 'unknown'
export type Where = { repo: string; platform: Platform }

export type HarnessCheck = 'hook-latency' | 'cache-miss' | 'slow-tool' | 'context' | 'rate-limit'

type Usage = { cache_read_input_tokens?: number; cache_creation_input_tokens?: number; ephemeral_1h_input_tokens?: number; model?: string }
export type RateLimit = { kind: string; percentUsed: number; resetsAt?: string }

export type HarnessState = {
  hooks: readonly string[]
  slow: Readonly<Record<string, number>>
  tools: readonly string[]
  zone: number
  rates: Readonly<Record<string, string>>
  context?: number
  turnStartedAt?: number
  lastTurnEndedAt?: number
  ttlMinutes: number
  model?: string
  compacted: boolean
  pending?: { usage: Usage; idleMinutes?: number }
  turns: number
  misses: readonly string[]
}

export const harnessInitial = (): HarnessState => ({ hooks: [], slow: {}, tools: [], zone: 0, rates: {}, ttlMinutes: 5, compacted: false, turns: 0, misses: [] })

export type HarnessEvent =
  | { kind: 'hook-runs'; runs: readonly { hook: string; ms: number }[] }
  | { kind: 'turn-started'; at: number }
  | { kind: 'turn-completed'; at: number; usage?: Usage }
  | { kind: 'compacted' }
  | { kind: 'tool-ran'; key: string; ms: number }
  | { kind: 'measured'; tokens?: number; percent?: number; rateLimits: readonly RateLimit[] }

export type HarnessFinding = { check: HarnessCheck; finding: Finding }
export type HarnessResult = { state: HarnessState; findings: HarnessFinding[]; rows: object[] }

export const p95 = (values: readonly number[]) => {
  const sorted = [...values].sort((a, b) => a - b)
  return sorted[Math.max(0, Math.ceil(sorted.length * 0.95) - 1)] ?? 0
}

const safe = (text: string) => text.replace(/["'`$\\]/g, '')
const slug = (text: string) => text.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '').slice(0, 40)

export const sessionCommand = (where: Where, name: string, prompt: string) => {
  const repo = where.repo.replace(/'/g, where.platform === 'windows' ? "''" : `'\\''`)
  const run = `claude -n ${slug(name)} "${safe(prompt)}"`
  return where.platform === 'windows' ? `Set-Location '${repo}'; ${run}` : `cd '${repo}' && ${run}`
}

const here = (how: string): Fix => ({ route: 'here', how })
const session = (where: Where, name: string, how: string, prompt: string): Fix => ({ route: 'session', how, command: sessionCommand(where, name, prompt) })
const finding = (check: HarnessCheck, text: string, rule: string, evidence: string, fix: Fix): HarnessFinding => ({ check, finding: { finding: text, category: 'harness', rule, evidence, fix } })

export const commandKey = (tool: string, command?: string) => {
  if (tool !== 'Bash' || command === undefined) return tool
  const words = command.trim().split(/\s+/).filter(w => !/^\w+=/.test(w))
  return `Bash: ${words.slice(0, 2).join(' ')}`.trim()
}

const hookRuns = (s: HarnessState, e: Extract<HarnessEvent, { kind: 'hook-runs' }>, o: HarnessOptions, where: Where): HarnessResult => {
  const byHook = new Map<string, number[]>()
  for (const r of e.runs) byHook.set(r.hook, [...(byHook.get(r.hook) ?? []), r.ms])
  const findings: HarnessFinding[] = []
  const hooks = [...s.hooks]
  for (const [hook, ms] of byHook) {
    if (hooks.includes(hook) || ms.length < o.hookMinRuns) continue
    const p = p95(ms)
    if (p <= o.hookP95Ms) continue
    hooks.push(hook)
    findings.push(
      finding(
        'hook-latency',
        `Hook ${hook} is slow: its p95 latency is over the ${o.hookP95Ms} ms budget.`,
        `observer_hook_p95_ms: a hook's p95 latency stays at or under ${o.hookP95Ms} ms`,
        `${hook}: p95 ${p} ms, max ${Math.max(...ms)} ms, ${ms.length} runs`,
        session(where, `hook-${hook}`, 'profile and speed up the hook in a dedicated session', `Hook ${hook} ran with p95 ${p} ms over ${ms.length} runs. Find where it is defined, profile it, and bring its p95 under ${o.hookP95Ms} ms without weakening what it checks.`),
      ),
    )
  }
  return { state: { ...s, hooks }, findings, rows: findings.map(f => ({ harness: f.check, subject: f.finding.evidence })) }
}

const missCause = (s: HarnessState, usage: Usage, idleMinutes: number | undefined) => {
  if (s.compacted) return 'compaction'
  if (idleMinutes !== undefined && idleMinutes > s.ttlMinutes) return 'idle'
  if (s.model !== undefined && usage.model !== undefined && usage.model !== s.model) return 'model-switch'
  return 'prefix-change'
}

const settle = (s: HarnessState, tokens: number | undefined, o: HarnessOptions, where: Where): HarnessResult => {
  const p = s.pending
  const next: HarnessState = { ...s, pending: undefined, compacted: false, context: tokens ?? s.context, turns: s.turns + (p ? 1 : 0) }
  if (p === undefined) return { state: next, findings: [], rows: [] }
  const usage = p.usage
  next.model = usage.model ?? s.model
  next.ttlMinutes = (usage.ephemeral_1h_input_tokens ?? 0) > 0 ? 60 : s.ttlMinutes
  const written = usage.cache_creation_input_tokens ?? 0
  const growth = tokens !== undefined && s.context !== undefined ? Math.max(0, tokens - s.context) : written
  const rewritten = written - growth
  if (s.turns === 0 || rewritten < o.cacheMissTokens) return { state: next, findings: [], rows: [] }
  const cause = missCause(s, usage, p.idleMinutes)
  const row = { harness: 'cache-miss', cause, rewritten, written }
  if (cause === 'compaction' || cause === 'idle' || s.misses.includes(cause)) return { state: next, findings: [], rows: [row] }
  next.misses = [...s.misses, cause]
  const rule = `observer_cache_miss_tokens: a turn rewrites under ${o.cacheMissTokens} tokens of cached prompt it could have read`
  const evidence = `${rewritten} tokens rewritten (${written} written, context grew ${growth})`
  const f =
    cause === 'model-switch'
      ? finding('cache-miss', `The prompt cache was rewritten because the model changed from ${s.model} to ${usage.model}.`, rule, evidence, here('stay on one model for the rest of the session; each switch rewrites the whole cache'))
      : finding(
          'cache-miss',
          'The prompt cache was rewritten mid-session without a break, compaction or model switch.',
          rule,
          evidence,
          session(where, 'cache-miss', 'find what changed the prompt prefix in a dedicated session', `A Claude Code session in this repository rewrote ${rewritten} tokens of cached prompt mid-session with no idle gap, compaction or model switch. Find what changed the prompt prefix (an instruction file, a plugin, MCP server or tool set, a hook that edits context) and stop it changing mid-session. /session-flow:audit-sessions and /harness-ops:audit-performance can help.`),
        )
  return { state: next, findings: [f], rows: [{ ...row, finding: true }] }
}

const measured = (s: HarnessState, e: Extract<HarnessEvent, { kind: 'measured' }>, o: HarnessOptions, where: Where): HarnessResult => {
  const r = settle(s, e.tokens, o, where)
  let state = r.state
  const findings = [...r.findings]
  if (e.percent !== undefined) {
    const zone = o.contextPercents.filter(t => e.percent! >= t).length
    if (zone > s.zone) {
      const at = o.contextPercents[zone - 1]
      findings.push(
        finding(
          'context',
          `Context use crossed ${at}%: it is at ${e.percent}% of the window.`,
          `observer_context_percents: report each crossing of ${o.contextPercents.join(', ')}%`,
          `${e.tokens ?? 'unknown'} tokens, ${e.percent}% of the window`,
          here('record every decision and pending question in a durable file, then compact, clear or hand off (/session-flow:workflow decides)'),
        ),
      )
    }
    state = { ...state, zone }
  }
  const rates = { ...state.rates }
  for (const w of e.rateLimits) {
    const mark = w.resetsAt ?? 'unknown'
    if (w.percentUsed < o.rateLimitPercent || rates[w.kind] === mark) continue
    rates[w.kind] = mark
    findings.push(
      finding(
        'rate-limit',
        `The ${w.kind} rate-limit window is ${w.percentUsed}% used.`,
        `observer_rate_limit_percent: report a window at or past ${o.rateLimitPercent}%`,
        `${w.kind}: ${w.percentUsed}% used${w.resetsAt ? `, resets ${w.resetsAt}` : ''}`,
        here('plan the remaining work around the reset: finish or save state before the limit stops the session'),
      ),
    )
  }
  state = { ...state, rates }
  return { state, findings, rows: [...r.rows, ...findings.filter(f => f.check !== 'cache-miss').map(f => ({ harness: f.check, subject: f.finding.evidence }))] }
}

export const harness = (s: HarnessState, e: HarnessEvent, o: HarnessOptions, where: Where): HarnessResult => {
  const none = (state: HarnessState = s): HarnessResult => ({ state, findings: [], rows: [] })
  if (!o.harnessCheck) return none()
  switch (e.kind) {
    case 'hook-runs':
      return hookRuns(s, e, o, where)
    case 'turn-started':
      return none({ ...s, turnStartedAt: e.at })
    case 'turn-completed': {
      const idleMinutes = s.lastTurnEndedAt !== undefined && s.turnStartedAt !== undefined ? (s.turnStartedAt - s.lastTurnEndedAt) / 60_000 : undefined
      return none({ ...s, lastTurnEndedAt: e.at, pending: e.usage ? { usage: e.usage, idleMinutes } : s.pending })
    }
    case 'compacted':
      return none({ ...s, compacted: true })
    case 'tool-ran': {
      if (e.ms < o.toolSlowMs || s.tools.includes(e.key)) return none()
      const n = (s.slow[e.key] ?? 0) + 1
      const state = { ...s, slow: { ...s.slow, [e.key]: n } }
      if (n < o.toolRepeat) return none(state)
      const f = finding(
        'slow-tool',
        `${e.key} has run slowly ${n} times this session.`,
        `observer_tool_slow_seconds and observer_tool_repeat: a tool call over ${o.toolSlowMs / 1000} s repeated ${o.toolRepeat} times`,
        `${n} calls over ${o.toolSlowMs / 1000} s, the last ${Math.round(e.ms / 1000)} s`,
        here('narrow what it runs (one test file, one package), reuse its last output, or run it in the background'),
      )
      return { state: { ...state, tools: [...s.tools, e.key] }, findings: [f], rows: [{ harness: 'slow-tool', subject: e.key }] }
    }
    case 'measured':
      return measured(s, e, o, where)
  }
}

export const hookRunsFrom = (text: string) =>
  text.split('\n').flatMap(line => {
    try {
      const r = JSON.parse(line) as { source?: unknown; hook?: unknown; duration_ms?: unknown }
      return r.source === 'envelope' && typeof r.hook === 'string' && typeof r.duration_ms === 'number' ? [{ hook: r.hook, ms: r.duration_ms }] : []
    } catch {
      return []
    }
  })
