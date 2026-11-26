import { expect, test } from 'claude-code/testing'

import { commandKey, harness, harnessInitial, type HarnessEvent, type HarnessState, hookRunsFrom, p95, sessionCommand, type Where } from './observer-harness.ts'
import { fixText, ledgerSection, noteFor, summarize } from './observer-live.ts'
import { initial, readOptions, step } from './observer-machine.ts'
import HOOK_LOG from './observer-harness.hook-log.ts'

const opts = (raw: Record<string, unknown> = {}) => readOptions({ observer_harness_check: true, ...raw }).options
const WSL: Where = { repo: '/srv/repo', platform: 'wsl' }
const run = (events: HarnessEvent[], raw: Record<string, unknown> = {}, s: HarnessState = harnessInitial(), where = WSL) => {
  const all = { state: s, findings: [] as ReturnType<typeof harness>['findings'], rows: [] as object[] }
  for (const e of events) {
    const r = harness(all.state, e, opts(raw), where)
    all.state = r.state
    all.findings.push(...r.findings)
    all.rows.push(...r.rows)
  }
  return all
}
const hooks = (hook: string, ms: number[]): HarnessEvent => ({ kind: 'hook-runs', runs: ms.map(n => ({ hook, ms: n })) })
const turn = (start: number, end: number, written: number, extra: Record<string, unknown> = {}): HarnessEvent[] => [
  { kind: 'turn-started', at: start },
  { kind: 'turn-completed', at: end, usage: { cache_read_input_tokens: 1000, cache_creation_input_tokens: written, model: 'm1', ...extra } },
]
const measured = (tokens: number, percent = 10, rateLimits: { kind: string; percentUsed: number; resetsAt?: string }[] = []): HarnessEvent => ({ kind: 'measured', tokens, percent, rateLimits })

test('every check stays silent with observer_harness_check off', () => {
  const r = run([hooks('slow', [5000, 5000, 5000, 5000, 5000]), measured(1, 99, [{ kind: 'five_hour', percentUsed: 99 }])], { observer_harness_check: false })
  expect(r.findings).toEqual([])
  expect(r.rows).toEqual([])
})

test('p95 takes the nearest-rank 95th percentile', () => {
  expect(p95([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 100])).toBe(19)
  expect(p95([5])).toBe(5)
})

test('a hook over its p95 budget is reported once with a dedicated-session command', () => {
  const r = run([hooks('merge-guard', [100, 200, 300, 9000, 9400]), hooks('merge-guard', [100, 200, 300, 9000, 9400, 9500])])
  expect(r.findings).toHaveLength(1)
  const f = r.findings[0]!.finding
  expect(f.category).toBe('harness')
  expect(f.finding).toContain('merge-guard')
  expect(f.fix?.route).toBe('session')
  expect(f.fix?.route === 'session' && f.fix.command).toMatch(/^cd '\/srv\/repo' && claude -n hook-merge-guard "Hook merge-guard ran with p95 9400 ms/)
})

test('a hook at its budget, or with too few runs, is not reported', () => {
  expect(run([hooks('ok', [1000, 1000, 1000, 1000, 1000])]).findings).toEqual([])
  expect(run([hooks('few', [9000, 9000, 9000, 9000])]).findings).toEqual([])
  expect(run([hooks('few', [9000, 9000])], { observer_hook_min_runs: 2 }).findings).toHaveLength(1)
})

test('hookRunsFrom reads the rows session-telemetry\'s hook-telemetry-sink.sh writes', () => {
  expect(hookRunsFrom(HOOK_LOG)).toEqual([
    { hook: 'block-dangerous-git', ms: 3 },
    { hook: 'merge-guard', ms: 9400 },
    { hook: 'block-no-verify', ms: 7 },
  ])
})

test('hookRunsFrom skips rows that are not envelope rows with a hook and a numeric duration', () => {
  const text = [
    '{"source":"event-log","hook_event_name":"Stop","duration_ms":3}',
    '{"source":"envelope","hook":"b","duration_ms":null}',
    'not json',
    '',
  ].join('\n')
  expect(hookRunsFrom(text)).toEqual([])
})

test('a mid-session cache rewrite with no break, compaction or model switch is reported with a session route', () => {
  const r = run([...turn(0, 1000, 20_000), measured(100_000), ...turn(60_000, 61_000, 160_000), measured(110_000)])
  expect(r.findings).toHaveLength(1)
  expect(r.findings[0]!.check).toBe('cache-miss')
  expect(r.findings[0]!.finding.evidence).toBe('150000 tokens rewritten (160000 written, context grew 10000)')
  expect(r.findings[0]!.finding.fix?.route).toBe('session')
  expect(r.rows).toContainEqual({ harness: 'cache-miss', cause: 'prefix-change', rewritten: 150_000, written: 160_000, finding: true })
})

test('a cache write that only covers the context the turn added is no miss', () => {
  const r = run([...turn(0, 1000, 20_000), measured(100_000), ...turn(60_000, 61_000, 90_000), measured(190_000)])
  expect(r.findings).toEqual([])
  expect(r.rows).toEqual([])
})

test('a measurement mid-turn does not move the turn\'s growth baseline', () => {
  const r = run([...turn(0, 1000, 20_000), measured(100_000), { kind: 'turn-started', at: 60_000 }, measured(150_000), { kind: 'turn-completed', at: 61_000, usage: { cache_read_input_tokens: 90_000, cache_creation_input_tokens: 60_000, model: 'm1' } }, measured(160_000)])
  expect(r.findings).toEqual([])
  expect(r.rows).toEqual([])
})

test('a measurement between compaction and the turn\'s end keeps the compaction explanation', () => {
  const r = run([...turn(0, 1000, 20_000), measured(100_000), { kind: 'compacted' }, { kind: 'turn-started', at: 60_000 }, measured(30_000), { kind: 'turn-completed', at: 61_000, usage: { cache_read_input_tokens: 1000, cache_creation_input_tokens: 160_000, model: 'm1' } }, measured(40_000)])
  expect(r.findings).toEqual([])
  expect(r.rows).toEqual([expect.objectContaining({ harness: 'cache-miss', cause: 'compaction' })])
})

test('a measurement with no token count leaves the pending turn for the next one that has it', () => {
  const r = run([...turn(0, 1000, 20_000), measured(100_000), ...turn(60_000, 61_000, 160_000), { kind: 'measured', rateLimits: [] }, measured(110_000)])
  expect(r.findings.map(f => f.finding.evidence)).toEqual(['150000 tokens rewritten (160000 written, context grew 10000)'])
})

test('the first turn of a session is never a miss', () => {
  expect(run([...turn(0, 1000, 500_000), measured(100_000)]).findings).toEqual([])
})

test('a rewrite after a break past the 5-minute cache lifetime is recorded, not reported', () => {
  const r = run([...turn(0, 1000, 20_000), measured(100_000), ...turn(1000 + 6 * 60_000, 1000 + 6 * 60_000 + 500, 160_000), measured(110_000)])
  expect(r.findings).toEqual([])
  expect(r.rows).toEqual([{ harness: 'cache-miss', cause: 'idle', rewritten: 150_000, written: 160_000 }])
})

test('one-hour cache writes stretch the lifetime, so a 6-minute break is a real miss', () => {
  const r = run([...turn(0, 1000, 20_000, { ephemeral_1h_input_tokens: 20_000 }), measured(100_000), ...turn(1000 + 6 * 60_000, 1000 + 6 * 60_000 + 500, 160_000), measured(110_000)])
  expect(r.findings).toHaveLength(1)
})

test('a rewrite after compaction is recorded, not reported', () => {
  const r = run([...turn(0, 1000, 20_000), measured(100_000), { kind: 'compacted' }, ...turn(60_000, 61_000, 160_000), measured(110_000)])
  expect(r.findings).toEqual([])
  expect(r.rows).toEqual([{ harness: 'cache-miss', cause: 'compaction', rewritten: 150_000, written: 160_000 }])
})

test('a model switch names both models and routes the fix here, once per cause', () => {
  const r = run([...turn(0, 1000, 20_000), measured(100_000), ...turn(60_000, 61_000, 160_000, { model: 'm2' }), measured(110_000), ...turn(70_000, 71_000, 160_000, { model: 'm1' }), measured(120_000)])
  expect(r.findings).toHaveLength(1)
  expect(r.findings[0]!.finding.finding).toContain('from m1 to m2')
  expect(r.findings[0]!.finding.fix?.route).toBe('here')
})

test('a Bash command is reported after observer_tool_repeat slow runs, keyed by its first two words', () => {
  const slow = (ms: number): HarnessEvent => ({ kind: 'tool-ran', key: commandKey('Bash', 'FOO=1 npm test -- a.test.ts'), ms })
  const r = run([slow(61_000), slow(59_000), slow(70_000), slow(65_000), slow(90_000)])
  expect(r.findings).toHaveLength(1)
  expect(r.findings[0]!.finding.finding).toBe('Bash: npm test has run slowly 3 times this session.')
  expect(r.findings[0]!.finding.fix?.route).toBe('here')
})

test('commandKey keeps a non-Bash tool by name', () => {
  expect(commandKey('Read')).toBe('Read')
  expect(commandKey('Bash', '  git   status --short')).toBe('Bash: git status')
})

test('context crossings report each upward threshold and fire again after compaction drops below it', () => {
  const r = run([measured(1, 40), measured(1, 55), measured(1, 60), measured(1, 80), measured(1, 30), measured(1, 52)])
  expect(r.findings.map(f => f.finding.finding)).toEqual([
    'Context use crossed 50%: it is at 55% of the window.',
    'Context use crossed 75%: it is at 80% of the window.',
    'Context use crossed 50%: it is at 52% of the window.',
  ])
})

test('a jump past two thresholds reports the higher one', () => {
  expect(run([measured(1, 90)]).findings.map(f => f.finding.finding)).toEqual(['Context use crossed 75%: it is at 90% of the window.'])
})

test('a rate-limit window at its percent is reported once per reset', () => {
  const w = (percentUsed: number, resetsAt: string) => measured(1, 10, [{ kind: 'five_hour', percentUsed, resetsAt }])
  const r = run([w(79.9, 'r1'), w(80, 'r1'), w(95, 'r1'), w(85, 'r2')])
  expect(r.findings.map(f => f.finding.evidence)).toEqual(['five_hour: 80% used, resets r1', 'five_hour: 85% used, resets r2'])
})

test('readOptions reads the harness thresholds and rejects a malformed percent list', () => {
  const o = opts({ observer_tool_slow_seconds: 30, observer_context_percents: '75, 50,75' })
  expect(o.toolSlowMs).toBe(30_000)
  expect(o.contextPercents).toEqual([50, 75])
  const bad = readOptions({ observer_context_percents: '50%' })
  expect(bad.invalid).toEqual(['observer_context_percents'])
  expect(bad.options.contextPercents).toEqual([50, 75])
  expect(readOptions({}).options.harnessCheck).toBe(false)
})

test('sessionCommand quotes the repository for PowerShell on Windows and strips quotes from the prompt', () => {
  expect(sessionCommand({ repo: "D:\\work\\o'k\\repo", platform: 'windows' }, 'Hook X!', 'say "hi" $HOME')).toBe(`Set-Location 'D:\\work\\o''k\\repo'; claude -n hook-x "say hi HOME"`)
  expect(sessionCommand({ repo: "/r/o'k", platform: 'linux' }, 'n', 'p')).toBe(`cd '/r/o'\\''k' && claude -n n "p"`)
})

test('a session-route harness finding is shown but never auto-sent; a here-route one is', () => {
  const o = readOptions({ observer_auto_send: true }).options
  const req = { trigger: 'harness' as const, turnId: '', step: -1, gen: 0, open: null, source: 'cache-miss' }
  const s = { ...initial(), on: true }
  const base = { category: 'harness' as const, rule: 'r', evidence: 'e' }
  const away = step(s, { kind: 'finding-accepted', req, finding: { ...base, finding: 'A.', fix: { route: 'session', how: 'h', command: 'c' } }, ledger: '/l.md' }, o)
  expect(away.effects.some(fx => fx.kind === 'deliver')).toBe(false)
  expect(away.state.card?.source).toBe('cache-miss')
  const near = step(s, { kind: 'finding-accepted', req, finding: { ...base, finding: 'B.', fix: { route: 'here', how: 'h' } }, ledger: '/l.md' }, o)
  expect(near.effects.some(fx => fx.kind === 'deliver')).toBe(true)
})

test('the fix route reaches the ledger and the agent note', () => {
  const f = { finding: 'F.', category: 'harness' as const, rule: 'r', evidence: 'e', fix: { route: 'session' as const, how: 'do it elsewhere', command: 'cd x && claude' } }
  expect(fixText(f.fix)).toBe('do it elsewhere: cd x && claude')
  expect(ledgerSection('T', 'harness', '', -1, f)).toContain('(harness)\n')
  expect(ledgerSection('T', 'harness', '', -1, f)).toContain('  - Fix: do it elsewhere: cd x && claude\n')
  expect(noteFor(f, 'plugin')).toContain('> Fix: do it elsewhere: cd x && claude')
})

test('summarize shows harness findings beside the live checks', () => {
  const rows = [
    { trigger: 'step', outcome: 'none', latencyMs: 1000 },
    { harness: 'hook-latency', subject: 'x' },
    { harness: 'cache-miss', cause: 'idle' },
    { harness: 'cache-miss', cause: 'prefix-change', finding: true },
  ]
  expect(summarize(rows).split('\n').at(-1)).toBe('harness: hook-latency 1, cache-miss 1 reported; 2 cache miss(es) seen')
  expect(summarize([{ harness: 'cache-miss', cause: 'idle' }])).toBe('no checks yet\nharness: none reported; 1 cache miss(es) seen')
  expect(summarize([])).toBe('no checks yet')
})
