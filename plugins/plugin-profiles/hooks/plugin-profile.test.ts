import { expect, test } from 'claude-code/testing'

// The /plugin-profile command and its end-of-turn reload. The command-line tool is stubbed by its
// argument vector; scripts/profiles.test.mjs tests the tool itself.

const PROFILES = ['build', 'discovery', 'harness-upkeep', 'interface-design', 'planning', 'review']
const MORE = 'More profiles'

type Out = { exitCode: number; stdout?: string; stderr?: string }
type Preview = { upToDate?: boolean; pending?: string[]; mcpOrLspOn?: string[]; prerequisitesMissing?: string[]; othersInFolder?: { name: string }[]; lines?: string[] }

const preview = (p: Preview = {}): Out => ({
  exitCode: 0,
  stdout: JSON.stringify({
    upToDate: false,
    pending: ['songwriting@melodic-software'],
    mcpOrLspOn: [],
    prerequisitesMissing: [],
    lines: ['Profile review for folder: /p/.claude/settings.local.json'],
    ...p,
  }),
})

// The world beneath the plugin: `cli` answers each run of profiles.mjs by its verb and flags, and
// `answers` are the labels the person picks, in order.
const clearPreview = (p: { recorded?: boolean; sessionProfile?: string | null; lines?: string[] } = {}): Out => ({
  exitCode: 0,
  stdout: JSON.stringify({
    recorded: true,
    sessionProfile: null,
    lines: ['Clears profile review from /p/.claude/settings.local.json.', 'Puts back 3 plugin entries and 0 skill entries to their values before the first apply.'],
    ...p,
  }),
})
const NEXT_STEP = 'Send any message, or run /reload-plugins now, to load the change into this session; a new session starts with it.'

const world = (on: any, answers: string[], cli: { dry?: Out; apply?: Out; list?: Out; clearDry?: Out; clear?: Out; reloadHangs?: boolean; noPane?: boolean } = {}) => {
  const w = { runs: [] as string[][], envs: [] as (Record<string, string> | undefined)[], asks: [] as { question: string; options: string[] }[], logs: [] as string[], commands: [] as string[], registered: [] as string[], panes: [] as string[], closed: [] as string[] }
  on('ui.open', ($: unknown, e: { id: string }) => {
    w.panes.push(e.id)
    return { value: cli.noPane ? { isPlaced: false, reason: 'no surface' } : { isPlaced: true } }
  })
  on('ui.close', ($: unknown, e: { id: string }) => {
    w.closed.push(e.id)
    return { value: undefined }
  })
  on('process.run', ($: unknown, e: { argv: readonly string[]; init?: { env?: Record<string, string> } }) => {
    const args = e.argv.slice(2)
    w.runs.push([...args])
    w.envs.push(e.init?.env)
    const out =
      args[0] === 'clear'
        ? args.includes('--dry-run')
          ? (cli.clearDry ?? clearPreview())
          : (cli.clear ?? { exitCode: 0, stdout: 'Cleared profile review from /p/.claude/settings.local.json.\n' })
        : args[0] === 'list'
        ? (cli.list ?? { exitCode: 0, stdout: JSON.stringify(PROFILES.map(name => ({ name, description: `${name} work` }))) })
        : args.includes('--dry-run')
          ? (cli.dry ?? preview())
          : (cli.apply ?? { exitCode: 0, stdout: 'Applied.' })
    return { value: { stdout: '', stderr: '', isStdoutTruncated: false, isStderrTruncated: false, ...out } }
  })
  on('tool.call', { tool: 'AskUserQuestion' }, ($: unknown, e: any) => {
    const q = e.questions[0]
    w.asks.push({ question: q.question, options: q.options.map((o: { label: string }) => o.label) })
    const answer = answers.shift()
    if (answer === undefined) return { deny: 'dismissed' }
    return { result: { questions: e.questions, answers: { [q.question]: answer } } }
  })
  on('ui.log', ($: unknown, e: { text: string }) => {
    w.logs.push(e.text)
    return { value: undefined }
  })
  on('command.register', ($: unknown, e: { name: string }) => {
    w.registered.push(e.name)
    return { value: { command: e.name } }
  })
  on('command.run', ($: unknown, e: { command: string }) => {
    w.commands.push(e.command)
    // A reload that unloads this module never answers the call that queued it.
    if (cli.reloadHangs) return new Promise(() => undefined)
    return { text: `ran ${e.command}` }
  })
  on('session.start', () => ({ cwd: '/p' }))
  on('session.id', () => ({ value: 'own-session' }))
  on('turn.complete', () => ({ text: '' }))
  return w
}

const run = ($: any, args = '') => $.command.run({ command: 'plugin-profile', args })
const turnEnd = ($: any, agentId?: string) =>
  $.turn.complete({ answer: 'done', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer', ...(agentId ? { agentId } : {}) })
const settle = async () => {
  for (let i = 0; i < 500; i++) await Promise.resolve()
}
const writes = (w: { runs: string[][] }) => w.runs.filter(r => r[0] === 'apply' && !r.includes('--dry-run'))

const PICKER = {
  plugin: 'plugin-profiles',
  component: 'Pane',
  requestId: 'plugin-profile-picker',
  props: { title: 'Which profile should this folder use?', isFocused: true, bodyColumns: 80, placement: 'dock', scroll: { offset: 0, bodyRows: 20 }, view: {} },
} as const

/** Starts /plugin-profile, picks `value` in the pane drawn on `surface`, and resolves the command's answer. */
const runPicking = async ($: any, value: string, surface: 'terminal' | 'desktop' | 'vscode' | 'mobile' = 'terminal') => {
  const answer = run($)
  await settle()
  const ui = await $.ui.mount({ ...PICKER, surface })
  if (surface === 'mobile') await ui.press({ key: `profile:${value}` })
  else await ui.select({ key: 'profile', value })
  await ui.unmount()
  return answer
}

test('session.start registers /plugin-profile', async ($, on) => {
  const w = world(on, [])
  await $.session.start({ cwd: '/p' } as any)
  expect(w.registered).toEqual(['plugin-profile'])
})

test('#16747: the picker is one pane listing every profile and No profile; a pick previews, asks, then writes the on entries', async ($, on) => {
  const w = world(on, ['Apply'])
  const answer = run($)
  await settle()
  const ui = await $.ui.mount({ ...PICKER, surface: 'terminal' })
  const select = await ui.find({ key: 'profile' })
  expect((select?.props.options as { value: string }[]).map(o => o.value)).toEqual([...PROFILES, 'No profile'])
  await ui.select({ key: 'profile', value: 'review' })
  await ui.unmount()
  const { text } = await answer
  expect(w.panes).toEqual(['plugin-profile-picker'])
  expect(w.closed).toEqual(['plugin-profile-picker'])
  expect(w.asks).toEqual([{ question: 'Apply profile review to this folder?', options: ['Apply', 'Cancel'] }])
  expect(writes(w)).toEqual([['apply', 'review', '--for', 'folder', '--defer-off', '--yes']])
  expect(text).toContain('Switched this folder to profile review.')
})

test('#16747: on mobile, which may not draw a Select, the pane holds one Button per profile', async ($, on) => {
  const w = world(on, ['Apply'])
  await runPicking($, 'planning', 'mobile')
  expect(w.runs[1]).toEqual(['apply', 'planning', '--for', 'folder', '--defer-off', '--dry-run', '--json'])
})

test('#16747: Cancel in the picker pane closes it: nothing chosen, nothing written', async ($, on) => {
  const w = world(on, [])
  const answer = run($)
  await settle()
  const ui = await $.ui.mount({ ...PICKER, surface: 'mobile' })
  await ui.press({ key: 'cancel' })
  await ui.unmount()
  expect((await answer).text).toBe('No profile chosen; nothing changed.')
  expect(w.closed).toEqual(['plugin-profile-picker'])
  expect(w.runs).toEqual([['list', '--json']])
})

test('AC6: where the pane cannot be placed, the picker pages through every profile, previews the pick, asks, then writes the on entries', async ($, on) => {
  const w = world(on, [MORE, 'review', 'Apply'], { noPane: true })
  const { text } = await run($)
  expect(w.asks[0].options).toEqual(['build', 'discovery', 'harness-upkeep', MORE])
  expect(w.asks[1].options).toEqual(['interface-design', 'planning', 'review', MORE])
  expect(w.asks[2]).toEqual({ question: 'Apply profile review to this folder?', options: ['Apply', 'Cancel'] })
  expect(w.logs).toContain('Profile review for folder: /p/.claude/settings.local.json')
  expect(w.runs).toEqual([
    ['list', '--json'],
    ['apply', 'review', '--for', 'folder', '--defer-off', '--dry-run', '--json'],
    ['apply', 'review', '--for', 'folder', '--defer-off', '--yes'],
  ])
  expect(text).toContain('Switched this folder to profile review.')
  expect(text).toBe(
    `Switched this folder to profile review. ${NEXT_STEP} The plugins it switches off (songwriting@melodic-software) stay loaded in this session until a later /reload-plugins or the next session start.`,
  )
  expect(w.commands).toEqual([])
})

test('AC6: a profile named on the command line skips the picker', async ($, on) => {
  const w = world(on, ['Apply'])
  await run($, 'review')
  expect(w.runs[0]).toEqual(['apply', 'review', '--for', 'folder', '--defer-off', '--dry-run', '--json'])
  expect(w.asks.length).toBe(1)
})

test('AC6: Cancel at the confirm writes nothing', async ($, on) => {
  const w = world(on, ['Cancel'])
  const { text } = await run($, 'review')
  expect(text).toBe('Not applied; nothing changed.')
  expect(writes(w)).toEqual([])
})

test('AC6: a dismissed paged picker writes nothing', async ($, on) => {
  const w = world(on, [], { noPane: true })
  const { text } = await run($)
  expect(text).toBe('No profile chosen; nothing changed.')
  expect(w.runs).toEqual([['list', '--json']])
})

test('AC10: a switch that enables an MCP or language server names it and the re-read, and applies only on Apply without --force', async ($, on) => {
  const w = world(on, ['Cancel'], { dry: preview({ mcpOrLspOn: ['playwright@melodic-software'] }) })
  await run($, 'review')
  expect(w.asks[0].question).toBe(
    'playwright@melodic-software ship an MCP or language server, so your next message after the switch re-reads the whole conversation. Apply profile review to this folder?',
  )
  expect(writes(w)).toEqual([])
})

test('D22: the confirm names the other sessions in the folder, and Apply still writes', async ($, on) => {
  const w = world(on, ['Apply'], { dry: preview({ othersInFolder: [{ name: 'builder' }, { name: 'reviewer' }] }) })
  await run($, 'review')
  expect(w.asks[0].question).toBe(
    'Other sessions in this folder (builder, reviewer) also get this profile at their next reload or start; to give one its own profile, start it with the launch command instead. Apply profile review to this folder?',
  )
  expect(writes(w)).toEqual([['apply', 'review', '--for', 'folder', '--defer-off', '--yes']])
})

test('AC10: Apply at the MCP prompt writes the on entries, never with --force', async ($, on) => {
  const w = world(on, ['Apply'], { dry: preview({ mcpOrLspOn: ['playwright@melodic-software'] }) })
  await run($, 'review')
  expect(writes(w)).toEqual([['apply', 'review', '--for', 'folder', '--defer-off', '--yes']])
  expect(w.runs.flat()).not.toContain('--force')
})

test('AC11, AC13: a switch the tool refuses (remembering off, a one-session profile) shows its reason and asks nothing', async ($, on) => {
  const reason = 'not applied: folder remembering is off (remember_folder_profile), so every session starts from the initial profile; start one session in review with apply review --for session'
  const w = world(on, [], { dry: { exitCode: 1, stderr: `${reason}\n` } })
  const { text } = await run($, 'review')
  expect(text).toBe(reason)
  expect(w.asks).toEqual([])
  expect(writes(w)).toEqual([])
})

test('a plugin missing a required prerequisite is left to a terminal: no confirm, no write', async ($, on) => {
  const w = world(on, [], { dry: preview({ prerequisitesMissing: ['implementation@melodic-software'] }) })
  const { text } = await run($, 'build')
  expect(text).toContain('Not applied: implementation@melodic-software miss a required prerequisite')
  expect(w.asks).toEqual([])
  expect(writes(w)).toEqual([])
})

test('a profile already in force says so and writes nothing', async ($, on) => {
  const w = world(on, [], { dry: preview({ upToDate: true }) })
  expect((await run($, 'review')).text).toBe('This folder already uses profile review; nothing to change.')
  expect(writes(w)).toEqual([])
})

test('AC9, AC11: the turn end after a switch runs /reload-plugins once, then writes the off entries; never /reload-skills', async ($, on) => {
  const w = world(on, ['Apply'])
  await run($, 'review')
  await turnEnd($)
  await settle()
  expect(w.commands).toEqual(['reload-plugins'])
  expect(writes(w)).toEqual([
    ['apply', 'review', '--for', 'folder', '--defer-off', '--yes'],
    ['apply', 'review', '--for', 'folder', '--yes'],
  ])
  expect(w.logs).toContain('Profile review is in force. The plugins it switches off (songwriting@melodic-software) stay loaded in this session until a later /reload-plugins or the next session start.')
  await turnEnd($)
  await settle()
  expect(w.commands).toEqual(['reload-plugins'])
  expect(writes(w).length).toBe(2)
})

test('AC9: a turn end with no switch, or a subagent turn end, reloads nothing', async ($, on) => {
  const w = world(on, ['Apply'])
  await turnEnd($)
  await run($, 'review')
  await turnEnd($, 'agent-1')
  await settle()
  expect(w.commands).toEqual([])
  expect(writes(w).length).toBe(1)
})

test('the person running /reload-plugins first finishes the switch, and the turn end reloads nothing more', async ($, on) => {
  const w = world(on, ['Apply'])
  await run($, 'review')
  await $.command.run({ command: 'reload-plugins', args: '' } as any)
  expect(writes(w)[1]).toEqual(['apply', 'review', '--for', 'folder', '--yes'])
  await turnEnd($)
  await settle()
  expect(w.commands).toEqual(['reload-plugins'])
})

test('a second /plugin-profile while a switch waits for its reload changes nothing', async ($, on) => {
  const w = world(on, ['Apply'])
  await run($, 'review')
  const { text } = await run($, 'build')
  expect(text).toBe(`A change to this folder's profile is still waiting for its reload: ${NEXT_STEP} Then run /plugin-profile again.`)
  expect(w.runs.length).toBe(2)
})

test('an off write that fails leaves the switch named as unfinished', async ($, on) => {
  const cli: { apply?: Out } = {}
  const w = world(on, ['Apply'], cli)
  await run($, 'review')
  cli.apply = { exitCode: 1, stderr: 'not applied: busy\n' }
  await turnEnd($)
  await settle()
  expect(w.logs).toContain('The switch to review is unfinished (not applied: busy); /plugin-profile review finishes it.')
})

test('AC11: the module loaded again by the reload finishes the switch at its session.start', async ($, on) => {
  const w = world(on, ['Apply'], { reloadHangs: true })
  await run($, 'review')
  await turnEnd($)
  await settle()
  expect(w.commands).toEqual(['reload-plugins'])
  expect(writes(w).length).toBe(1)
  await $.session.start({ cwd: '/p' } as any)
  await settle()
  expect(writes(w)[1]).toEqual(['apply', 'review', '--for', 'folder', '--yes'])
})

test('#16747: the profile list and the preview log one line per call, never a newline-joined block', async ($, on) => {
  const w = world(on, ['review', 'Cancel'], { noPane: true, dry: preview({ lines: ['Profile review for folder: /p/.claude/settings.local.json', 'Switches on (1): review@melodic-software'] }) })
  await run($)
  expect(w.logs.some(line => line.includes('\n'))).toBe(false)
  expect(w.logs).toContain('build: build work')
  expect(w.logs).toContain('Switches on (1): review@melodic-software')
})

test('#16747: the tool is told this session id, so the confirm leaves the running session out of "Other sessions"', async ($, on) => {
  const w = world(on, ['Cancel'])
  await run($, 'review')
  expect(w.envs[0]).toEqual({ CLAUDE_CODE_SESSION_ID: 'own-session' })
})

test('#16747: a switch that turns nothing off says only that the profile is in force, with no plugin-profiles: prefix', async ($, on) => {
  const w = world(on, ['Apply'], { dry: preview({ pending: [] }) })
  const { text } = await run($, 'review')
  expect(text).toBe(`Switched this folder to profile review. ${NEXT_STEP}`)
  await turnEnd($)
  await settle()
  expect(w.logs).toContain('Profile review is in force.')
  expect(w.logs.some(line => line.startsWith('plugin-profiles:'))).toBe(false)
})

test('#16747: the picker offers No profile, which previews the clear, asks, clears, and reloads at the turn end', async ($, on) => {
  const w = world(on, ['Apply'])
  const { text } = await runPicking($, 'No profile')
  expect(w.logs).toContain('Puts back 3 plugin entries and 0 skill entries to their values before the first apply.')
  expect(w.asks).toEqual([{ question: 'Clear the profile from this folder?', options: ['Apply', 'Cancel'] }])
  expect(w.runs.slice(1)).toEqual([
    ['clear', '--for', 'folder', '--dry-run', '--json'],
    ['clear', '--for', 'folder', '--yes'],
  ])
  expect(text).toBe(`Cleared this folder's profile. ${NEXT_STEP}`)
  await turnEnd($)
  await settle()
  expect(w.commands).toEqual(['reload-plugins'])
  expect(writes(w)).toEqual([])
  expect(w.logs).toContain('This folder has no profile now; this session loaded the plugins your user and project settings name.')
})

test('#16747: Cancel at the clear confirm clears nothing', async ($, on) => {
  const w = world(on, ['Cancel'])
  expect((await runPicking($, 'No profile')).text).toBe('Not cleared; nothing changed.')
  expect(w.runs.filter(r => r[0] === 'clear' && r.includes('--yes'))).toEqual([])
})

test('#16747: a folder with no profile says what loads and how to drop an earlier profile still loaded', async ($, on) => {
  const w = world(on, [], { clearDry: clearPreview({ recorded: false, lines: ['A folder with no recorded profile, in words the tool owns.'] }) })
  const { text } = await runPicking($, 'No profile')
  expect(w.logs).toContain('A folder with no recorded profile, in words the tool owns.')
  expect(text).toBe(
    "Nothing to clear; this folder's plugins come from your user and project settings. If this session still has an earlier profile's plugins loaded, run /reload-plugins to load what the settings say now.",
  )
  expect(w.asks).toEqual([])
  expect(w.runs.filter(r => r.includes('--yes'))).toEqual([])
})

test('#16747: in a session started in a one-session profile, a clear says the session keeps that profile', async ($, on) => {
  const sessionLine = 'This session runs in profile review from a one-session settings file and keeps it after the clear.'
  const w = world(on, ['Apply'], { clearDry: clearPreview({ sessionProfile: 'review', lines: ['Clears profile build from /p/.claude/settings.local.json.', sessionLine] }) })
  await runPicking($, 'No profile')
  expect(w.logs).toContain(sessionLine)
  await turnEnd($)
  await settle()
  expect(w.logs).toContain('This folder has no profile now; this session keeps its one-session profile review.')
  expect(w.logs).not.toContain('This folder has no profile now; this session loaded the plugins your user and project settings name.')
})
