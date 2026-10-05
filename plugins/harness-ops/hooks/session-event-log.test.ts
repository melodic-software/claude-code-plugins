import { expect, test } from 'claude-code/testing'

// The session event log module. Process runs, the debug log and the answer each event resolves
// with are what these tests read; the scripts the runs start are tested by session-event-log.test.sh.

const ROOT = '/srv/project'
// The 28 events hook-events.registry.json marks observe, written out by hand from the registry.
const OBSERVED = [
  'ConfigChange', 'CwdChanged', 'DirectoryAdded', 'Elicitation', 'ElicitationResult', 'InstructionsLoaded',
  'Notification', 'PermissionDenied', 'PermissionRequest', 'PostCompact', 'PostModelSwitch', 'PostToolBatch',
  'PostToolUseFailure', 'PreCompact', 'PreModelSwitch', 'SessionEnd', 'SessionStart', 'Setup', 'Stop',
  'StopFailure', 'SubagentStart', 'SubagentStop', 'TaskCompleted', 'TaskCreated', 'TeammateIdle',
  'UserPromptExpansion', 'UserPromptSubmit', 'WorktreeRemove',
] as const
const ON = { options: { session_event_log_enabled: true } }

type Run = { argv: readonly string[]; cwd?: string; env?: Record<string, string>; stdin?: string }

// The world beneath the plugin: each observed event answers `answer` (nothing to change by default),
// and process runs exit with `exit.code` or fail to start.
const world = (stub: any, exit: { code: number; throws?: boolean } = { code: 0 }, answer: object = {}) => {
  const w = { runs: [] as Run[], logs: [] as { text: string; to: string }[] }
  for (const event of OBSERVED) stub(`classic.${event}`, () => answer)
  stub('session.root', () => ({ value: ROOT }))
  stub('process.run', ($: unknown, e: { argv: readonly string[]; init?: Omit<Run, 'argv'> }) => {
    w.runs.push({ argv: e.argv, ...e.init })
    if (exit.throws) throw new Error('spawn node ENOENT')
    return { value: { exitCode: exit.code, stdout: '', stderr: exit.code ? 'boom\n' : '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  stub('ui.log', ($: unknown, e: { text: string; to: string }) => {
    w.logs.push({ text: e.text, to: e.to })
    return { value: undefined }
  })
  return w
}

const raise = ($: any, event: string, fields: Record<string, unknown> = {}) => $.classic[event]({ session_id: 'sess-1', ...fields })
const script = (run: Run) => run.argv[2].replace(/^.*\/hooks\//, '')

test('budget: with the log off (the default) no observed event starts a process', async ($, on) => {
  const w = world(on)
  for (const event of OBSERVED) await raise($, event)
  expect(w.runs.length).toBe(0)
})

test('budget: with the log on each observed event starts one process, SessionEnd two', ON, async ($, on) => {
  const w = world(on)
  for (const event of OBSERVED) await raise($, event)
  expect(w.runs.length).toBe(29)
  expect(w.runs.filter(run => script(run) === 'session-event-log.sh').length).toBe(28)
  expect(w.runs.filter(run => script(run) === 'session-retention.sh').length).toBe(1)
})

test('on: each event hands its own payload to session-event-log.sh through the bash launcher', ON, async ($, on) => {
  const w = world(on)
  for (const event of OBSERVED) await raise($, event)
  const logged = w.runs.filter(run => script(run) === 'session-event-log.sh')
  expect(logged.map(run => JSON.parse(run.stdin ?? '{}').hook_event_name)).toEqual([...OBSERVED])
  for (const run of logged) {
    expect(run.argv[0]).toBe('node')
    expect(run.argv[1]).toMatch(/\/hooks\/exec-bash\.mjs$/)
    expect(run.argv.length).toBe(3)
    expect(run.cwd).toBe(ROOT)
  }
})

test('on: the payload reaches the script as the event carried it', ON, async ($, on) => {
  const w = world(on)
  await raise($, 'Stop', {
    transcript_path: '/srv/t/sess-1.jsonl',
    cwd: '/srv/project/sub',
    permission_mode: 'default',
    stop_hook_active: false,
    last_assistant_message: 'done "quoted"\nnext line',
    effort: { level: 'high' },
  })
  expect(JSON.parse(w.runs[0].stdin ?? '')).toEqual({
    session_id: 'sess-1',
    transcript_path: '/srv/t/sess-1.jsonl',
    cwd: '/srv/project/sub',
    hook_event_name: 'Stop',
    permission_mode: 'default',
    stop_hook_active: false,
    last_assistant_message: 'done "quoted"\nnext line',
    effort: { level: 'high' },
  })
})

test('on: the script gets the options a settings hook got, the project root, and no inherited effort or trace', {
  options: {
    session_event_log_enabled: true,
    session_event_log_dir: 'logs/claude',
    session_event_log_categories: 'turn,tool',
    session_event_log_content: true,
    stdin_read_timeout: 3,
  },
}, async ($, on) => {
  const w = world(on)
  await raise($, 'PostToolBatch')
  expect(w.runs[0].env).toEqual(expect.objectContaining({
    CLAUDE_PLUGIN_OPTION_SESSION_EVENT_LOG_ENABLED: 'true',
    CLAUDE_PLUGIN_OPTION_SESSION_EVENT_LOG_DIR: 'logs/claude',
    CLAUDE_PLUGIN_OPTION_SESSION_EVENT_LOG_CATEGORIES: 'turn,tool',
    CLAUDE_PLUGIN_OPTION_SESSION_EVENT_LOG_CONTENT: 'true',
    CLAUDE_PLUGIN_OPTION_STDIN_READ_TIMEOUT: '3',
    CLAUDE_PROJECT_DIR: ROOT,
    CLAUDE_EFFORT: '',
    TRACEPARENT: '',
  }))
})

test('on: SessionEnd also runs retention with the retention options and no stdin', {
  options: { session_event_log_enabled: true, session_log_keep_sessions: 5, session_log_keep_days: 7 },
}, async ($, on) => {
  const w = world(on)
  await raise($, 'SessionEnd', { reason: 'clear' })
  const retention = w.runs.find(run => script(run) === 'session-retention.sh')
  expect(retention?.stdin).toBe(undefined)
  expect(retention?.cwd).toBe(ROOT)
  expect(retention?.env).toEqual(expect.objectContaining({
    CLAUDE_PLUGIN_OPTION_SESSION_EVENT_LOG_ENABLED: 'true',
    CLAUDE_PLUGIN_OPTION_SESSION_LOG_KEEP_SESSIONS: '5',
    CLAUDE_PLUGIN_OPTION_SESSION_LOG_KEEP_DAYS: '7',
    CLAUDE_PROJECT_DIR: ROOT,
  }))
})

test('on: the event resolves with the answer beneath it', ON, async ($, on) => {
  world(on, { code: 0 }, { block: 'keep going' })
  expect(await raise($, 'Stop')).toEqual(expect.objectContaining({ block: 'keep going' }))
})

test('on: a failing script passes the event through and is logged once to the debug log', ON, async ($, on) => {
  const w = world(on, { code: 1 }, { block: 'keep going' })
  expect(await raise($, 'Stop')).toEqual(expect.objectContaining({ block: 'keep going' }))
  await raise($, 'Stop')
  expect(w.logs).toEqual([{ text: 'harness-ops: session-event-log.sh exited 1: boom', to: 'debug' }])
})

test('on: a process that cannot start passes the event through and is logged once', ON, async ($, on) => {
  const w = world(on, { code: 0, throws: true })
  await raise($, 'UserPromptSubmit', { prompt: 'hi' })
  await raise($, 'UserPromptSubmit', { prompt: 'again' })
  expect(w.runs.length).toBe(2)
  expect(w.logs.length).toBe(1)
  expect(w.logs[0].text).toContain('session-event-log.sh did not run')
})
