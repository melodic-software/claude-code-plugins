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

type Answer = { label: string; flag: string }
type ResetRow = { file: string; action: string; ask?: { file: string; question: string; yes: Answer; no: Answer } }
const UNRECORDED = { yes: { label: 'Remove', flag: '--remove-unrecorded' }, no: { label: 'Keep', flag: '--keep-unrecorded' } }
const QUESTION = 'Reset the files above that have a record? (the question the tool words)'
const resetPreview = (folders: ResetRow[] = [{ file: '/p/.claude/settings.local.json', action: 'restore' }], sessionProfile: string | null = null): Out => ({
  exitCode: 0,
  stdout: JSON.stringify({
    sessionProfile,
    previewId: 'preview-1',
    question: QUESTION,
    folders: folders.map(f => ({ recorded: f.action !== 'remove-entries', adopted: false, unfinished: false, overwrites: [], lines: [`${f.file}: a line the tool owns.`], ...f })),
    lines: ['Reset looked for profile records in the places the tool owns.', ...folders.map(f => `${f.file}: a line the tool owns.`)],
  }),
})

const world = (on: any, answers: string[], cli: { dry?: Out; apply?: Out; list?: Out; clearDry?: Out; clear?: Out; resetDry?: Out; reset?: Out; reloadHangs?: boolean; noPane?: boolean } = {}) => {
  const w = { runs: [] as string[][], envs: [] as (Record<string, string> | undefined)[], asks: [] as { question: string; options: string[] }[], headers: [] as string[], logs: [] as string[], commands: [] as string[], registered: [] as string[], panes: [] as string[], closed: [] as string[] }
  const up = new Set<string>()
  on('ui.open', ($: unknown, e: { id: string }) => {
    w.panes.push(e.id)
    up.add(e.id)
    return { value: cli.noPane ? { isPlaced: false, reason: 'no surface' } : { isPlaced: true } }
  })
  on('ui.close', ($: unknown, e: { id: string }) => {
    w.closed.push(e.id)
    up.delete(e.id)
    return { value: undefined }
  })
  on('ui.panes', () => ({ value: [...up].map(id => ({ id, title: id, isShown: true, isFocused: true, isPlaced: !cli.noPane })) }))
  on('process.run', ($: unknown, e: { argv: readonly string[]; init?: { env?: Record<string, string> } }) => {
    const args = e.argv.slice(2)
    w.runs.push([...args])
    w.envs.push(e.init?.env)
    const out =
      args[0] === 'reset'
        ? args.includes('--dry-run')
          ? (cli.resetDry ?? resetPreview())
          : (cli.reset ?? { exitCode: 0, stdout: JSON.stringify({ lines: ['Restored /p/.claude/settings.local.json (profile review).'] }) })
        : args[0] === 'clear'
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
    w.headers.push(q.header)
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
  on('ui.focus', { plugin: '*' }, () => ({ value: {} }))
  on('session.start', () => ({ cwd: '/p' }))
  on('session.id', () => ({ value: 'own-session' }))
  on('turn.complete', () => ({ text: '' }))
  return w
}

const run = ($: any, args = '') => $.command.run({ command: 'plugin-profile', args })
const turnEnd = ($: any, agentId?: string) =>
  $.turn.complete({ answer: 'done', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer', ...(agentId ? { agentId } : {}) })
const settle = async () => {
  for (let i = 0; i < 2000; i++) await Promise.resolve()
}
const writes = (w: { runs: string[][] }) => w.runs.filter(r => r[0] === 'apply' && !r.includes('--dry-run'))

const PICKER = {
  plugin: 'plugin-profiles',
  component: 'Pane',
  requestId: 'plugin-profile-picker',
  props: { title: 'Which profile should this folder use?', isFocused: true, bodyColumns: 80, placement: 'dock', scroll: { offset: 0, bodyRows: 20 }, view: {} },
} as const

const SURFACES = ['terminal', 'desktop', 'vscode', 'mobile'] as const
const PICK_IN_PANE = 'Pick a profile in the pane; the next step shows what it changes and asks before writing.'

const runPicking = async ($: any, w: { logs: string[] }, value: string, surface: (typeof SURFACES)[number] = 'terminal') => {
  expect((await run($)).text).toBe(PICK_IN_PANE)
  const ui = await $.ui.mount({ ...PICKER, surface })
  await ui.press({ key: `profile:${value}` })
  await settle()
  await ui.unmount()
  return w.logs[w.logs.length - 1]
}

const focusOn = (element: string) => ({ component: 'Pane', requestId: 'plugin-profile-picker', plugin: 'plugin-profiles', element, origin: { kind: 'person' } }) as any

test('session.start registers /plugin-profile', async ($, on) => {
  const w = world(on, [])
  await $.session.start({ cwd: '/p' } as any)
  expect(w.registered).toEqual(['plugin-profile'])
})

test('#16818: /plugin-profile answers before any pick, so no wait on the person counts against its hook budget', async ($, on) => {
  const w = world(on, ['Apply'])
  const answer = run($)
  const ui = await $.ui.mount({ ...PICKER, surface: 'terminal' })
  await settle()
  const answered = await Promise.race([answer, Promise.resolve('still waiting')])
  await ui.unmount()
  expect(answered).toEqual({ text: PICK_IN_PANE })
  expect(w.panes).toEqual(['plugin-profile-picker'])
  expect(w.runs).toEqual([['list', '--json']])
})

test('#16818: a pick in the pane previews, asks, writes the on entries, and logs the outcome the command used to return', async ($, on) => {
  const w = world(on, ['Apply'])
  const last = await runPicking($, w, 'review')
  expect(w.closed).toEqual(['plugin-profile-picker'])
  expect(w.asks).toEqual([{ question: 'Apply profile review to this folder?', options: ['Cancel', 'Apply'] }])
  expect(writes(w)).toEqual([['apply', 'review', '--for', 'folder', '--defer-off', '--yes']])
  expect(last).toBe(`Switched this folder to profile review. ${NEXT_STEP} The plugin it switches off stays loaded in this session until a later /reload-plugins or the next session start.`)
})

for (const surface of SURFACES)
  test(`#16818: on ${surface} every profile and No profile is a row drawn at once, with no drop-down, and a press picks it`, async ($, on) => {
    const w = world(on, ['Apply'])
    await run($)
    const ui = await $.ui.mount({ ...PICKER, surface })
    expect(await ui.find({ type: 'Select' })).toBeUndefined()
    const rows = (await ui.findAll({ type: 'Button' })).map(b => b.key)
    expect(rows).toEqual([...[...PROFILES, 'No profile', 'Reset'].map(name => `profile:${name}`), 'cancel'])
    await ui.press({ key: 'profile:planning' })
    await settle()
    expect(w.runs[1]).toEqual(['apply', 'planning', '--for', 'folder', '--defer-off', '--dry-run', '--json'])
  })

test('#16818: a row reveals its whole description under the pointer, and the focused row\'s whole description shows under the list', async ($, on) => {
  const long = 'Planning work: interviews, briefs, plans and the decisions that come before any code is written, in full'
  const list = { exitCode: 0, stdout: JSON.stringify(PROFILES.map(name => ({ name, description: name === 'planning' ? long : `${name} work` }))) }
  world(on, [], { list })
  await run($)
  const ui = await $.ui.mount({ ...PICKER, surface: 'desktop' })
  const focusLine = async () => (await ui.findAll({ type: 'Text' })).find(t => t.text === `planning: ${long}`)
  const row = await ui.find({ key: 'row:planning' })
  expect(row?.type).toBe('Box')
  const reveal = (row?.children as { props?: { display?: string }; hover?: { display?: string }; children?: unknown[] }[]).find(c => c.hover?.display === 'flex')
  expect(reveal?.props?.display).toBe('none')
  expect(JSON.stringify(reveal?.children)).toContain(long)
  expect(await focusLine()).toBeUndefined()
  await $.ui.focus(focusOn('profile:planning'))
  await ui.redraw()
  expect((await focusLine())?.type).toBe('Text')
  await $.ui.focus(focusOn('cancel'))
  await ui.redraw()
  expect(await focusLine()).toBeUndefined()
})

test('#16747: Cancel in the picker pane closes it: nothing chosen, nothing written', async ($, on) => {
  const w = world(on, [])
  expect((await run($)).text).toBe(PICK_IN_PANE)
  const ui = await $.ui.mount({ ...PICKER, surface: 'mobile' })
  await ui.press({ key: 'cancel' })
  await settle()
  await ui.unmount()
  expect(w.logs).toEqual(['No profile chosen; nothing changed.'])
  expect(w.closed).toEqual(['plugin-profile-picker'])
  expect(w.runs).toEqual([['list', '--json']])
})

test('#16816: a second /plugin-profile while the pane is open is refused, and the first pick still settles', async ($, on) => {
  const w = world(on, ['Apply'])
  expect((await run($)).text).toBe(PICK_IN_PANE)
  expect((await run($)).text).toBe('A profile pick is already open in its pane; pick there, or press Cancel and run /plugin-profile again.')
  expect((await run($, 'planning')).text).toBe('A profile pick is already open in its pane; pick there, or press Cancel and run /plugin-profile again.')
  expect(w.panes).toEqual(['plugin-profile-picker'])
  const ui = await $.ui.mount({ ...PICKER, surface: 'terminal' })
  await ui.press({ key: 'profile:review' })
  await settle()
  await ui.unmount()
  expect(writes(w)).toEqual([['apply', 'review', '--for', 'folder', '--defer-off', '--yes']])
  expect(w.logs[w.logs.length - 1]).toMatch(/^Switched this folder to profile review\./)
})

test('#16816: a pick in an open pane is refused while a switch from before waits for its reload', async ($, on) => {
  const w = world(on, ['Apply'])
  let armed = false
  on('state.get', ($: unknown, e: { key: string }, next: (e: unknown) => unknown) =>
    armed && e.key === 'switch' ? { value: { value: { profile: 'build', phase: 'armed' }, version: 1 } } : next(e),
  )
  expect((await run($)).text).toBe(PICK_IN_PANE)
  armed = true
  const ui = await $.ui.mount({ ...PICKER, surface: 'terminal' })
  await ui.press({ key: 'profile:planning' })
  await settle()
  await ui.unmount()
  expect(writes(w)).toEqual([])
  expect(w.logs[w.logs.length - 1]).toMatch(/^A change to this folder's profile is still waiting for its reload/)
})

test('#16816: two row presses before the first settles run one switch', async ($, on) => {
  const w = world(on, ['Apply', 'Apply'])
  await run($)
  const ui = await $.ui.mount({ ...PICKER, surface: 'terminal' })
  await Promise.all([ui.press({ key: 'profile:review' }), ui.press({ key: 'profile:planning' })])
  await settle()
  await ui.unmount()
  expect(w.asks).toEqual([{ question: 'Apply profile review to this folder?', options: ['Cancel', 'Apply'] }])
  expect(writes(w)).toEqual([['apply', 'review', '--for', 'folder', '--defer-off', '--yes']])
})

test('#16816: once the pane closes, /plugin-profile opens it again', async ($, on) => {
  const w = world(on, [])
  expect((await run($)).text).toBe(PICK_IN_PANE)
  const ui = await $.ui.mount({ ...PICKER, surface: 'terminal' })
  await ui.press({ key: 'cancel' })
  await settle()
  await ui.unmount()
  expect((await run($)).text).toBe(PICK_IN_PANE)
  expect(w.panes).toEqual(['plugin-profile-picker', 'plugin-profile-picker'])
})

test('AC6: where the pane cannot be placed, the picker pages through every profile, previews the pick, asks, then writes the on entries', async ($, on) => {
  const w = world(on, [MORE, 'review', 'Apply'], { noPane: true })
  const { text } = await run($)
  expect(w.asks[0].options).toEqual(['build', 'discovery', 'harness-upkeep', MORE])
  expect(w.asks[1].options).toEqual(['interface-design', 'planning', 'review', MORE])
  expect(w.asks[2]).toEqual({ question: 'Apply profile review to this folder?', options: ['Cancel', 'Apply'] })
  expect(w.logs).toContain('Profile review for folder: /p/.claude/settings.local.json')
  expect(w.runs).toEqual([
    ['list', '--json'],
    ['apply', 'review', '--for', 'folder', '--defer-off', '--dry-run', '--json'],
    ['apply', 'review', '--for', 'folder', '--defer-off', '--yes'],
  ])
  expect(text).toContain('Switched this folder to profile review.')
  expect(text).toBe(
    `Switched this folder to profile review. ${NEXT_STEP} The plugin it switches off stays loaded in this session until a later /reload-plugins or the next session start.`,
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

test('#16914: the confirm names sessions in a one-session profile apart, as keeping theirs, with each session id', async ($, on) => {
  const others = [
    { name: 'probe-repo-04', sessionId: '3fa9c1d2-0000-4000-8000-000000000001', oneSessionProfile: 'build' },
    { name: 'probe-repo-9b', sessionId: '7b2e95f0-0000-4000-8000-000000000002', oneSessionProfile: null },
    { name: 'probe-repo-25', sessionId: 'e6efc735-0000-4000-8000-000000000003', oneSessionProfile: 'discovery' },
  ]
  const w = world(on, ['Apply'], { dry: preview({ othersInFolder: others }) })
  await run($, 'review')
  expect(w.asks[0].question).toBe(
    'Other sessions in this folder (probe-repo-9b (session 7b2e95f0)) also get this profile at their next reload or start; to give one its own profile, start it with the launch command instead. Sessions here in a one-session profile keep theirs and do not change: probe-repo-04 (session 3fa9c1d2) in build; probe-repo-25 (session e6efc735) in discovery. Apply profile review to this folder?',
  )
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
    ['apply', 'review', '--for', 'folder', '--finish-pending'],
  ])
  expect(w.logs).toContain('Profile review is in force. The plugin it switches off stays loaded in this session until a later /reload-plugins or the next session start.')
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
  expect(writes(w)[1]).toEqual(['apply', 'review', '--for', 'folder', '--finish-pending'])
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
  expect(writes(w)[1]).toEqual(['apply', 'review', '--for', 'folder', '--finish-pending'])
})

test('#17354: the turn end after a switch finishes it with --finish-pending, never a full apply', async ($, on) => {
  const cli: { apply?: Out } = {}
  const w = world(on, ['Apply'], cli)
  await run($, 'review')
  cli.apply = { exitCode: 0, stdout: 'Nothing to finish: no unfinished switch to review is recorded for /p/.claude/settings.local.json.\n' }
  await turnEnd($)
  await settle()
  expect(writes(w)).toEqual([
    ['apply', 'review', '--for', 'folder', '--defer-off', '--yes'],
    ['apply', 'review', '--for', 'folder', '--finish-pending'],
  ])
  expect(w.runs.some(r => r[0] === 'apply' && r.includes('--yes') && !r.includes('--defer-off'))).toBe(false)
  expect(w.logs).toContain(
    "The switch to review was not finished: this folder's profile changed elsewhere since (a reset, a clear or another switch), so nothing was written.",
  )
  expect(w.logs.some(line => line.startsWith('Profile review is in force'))).toBe(false)
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

test('#16818: a switch that turns off many plugins counts them in the in-force line instead of naming them again', async ($, on) => {
  const off = Array.from({ length: 38 }, (_, i) => `p${i}@melodic-software`)
  const w = world(on, ['Apply'], { dry: preview({ pending: off }) })
  const { text } = await run($, 'review')
  expect(text).toBe(`Switched this folder to profile review. ${NEXT_STEP} The 38 plugins it switches off stay loaded in this session until a later /reload-plugins or the next session start.`)
  await turnEnd($)
  await settle()
  expect(w.logs).toContain('Profile review is in force. The 38 plugins it switches off stay loaded in this session until a later /reload-plugins or the next session start.')
  expect([text, ...w.logs].some(line => line.includes('p0@melodic-software'))).toBe(false)
})

test('#16747: the picker offers No profile, which previews the clear, asks, clears, and reloads at the turn end', async ($, on) => {
  const w = world(on, ['Apply'])
  const text = await runPicking($, w, 'No profile')
  expect(w.logs).toContain('Puts back 3 plugin entries and 0 skill entries to their values before the first apply.')
  expect(w.asks).toEqual([{ question: 'Clear the profile from this folder?', options: ['Cancel', 'Apply'] }])
  expect(w.headers).toEqual(['Profile'])
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
  expect(await runPicking($, w, 'No profile')).toBe('Not cleared; nothing changed.')
  expect(w.runs.filter(r => r[0] === 'clear' && r.includes('--yes'))).toEqual([])
})

test('#16747: a folder with no profile says what loads and how to drop an earlier profile still loaded', async ($, on) => {
  const w = world(on, [], { clearDry: clearPreview({ recorded: false, lines: ['A folder with no recorded profile, in words the tool owns.'] }) })
  const text = await runPicking($, w, 'No profile')
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
  await runPicking($, w, 'No profile')
  expect(w.logs).toContain(sessionLine)
  await turnEnd($)
  await settle()
  expect(w.logs).toContain('This folder has no profile now; this session keeps its one-session profile review.')
  expect(w.logs).not.toContain('This folder has no profile now; this session loaded the plugins your user and project settings name.')
})

const resets = (w: { runs: string[][] }) => w.runs.filter(r => r[0] === 'reset' && !r.includes('--dry-run'))

test('#17354: the picker shows Reset under No profile, previews the reset, asks, resets, and reloads at the turn end', async ($, on) => {
  const w = world(on, ['Apply'])
  const text = await runPicking($, w, 'Reset')
  expect(w.logs).toContain('Reset looked for profile records in the places the tool owns.')
  expect(w.logs).toContain('/p/.claude/settings.local.json: a line the tool owns.')
  expect(w.asks).toEqual([{ question: QUESTION, options: ['Cancel', 'Apply'] }])
  expect(w.runs.slice(1)).toEqual([
    ['reset', '--dry-run', '--json'],
    ['reset', '--yes', '--json', '--preview-id', 'preview-1'],
  ])
  expect(w.logs).toContain('Restored /p/.claude/settings.local.json (profile review).')
  expect(text).toBe(`Reset every profile this machine records. ${NEXT_STEP}`)
  await turnEnd($)
  await settle()
  expect(w.commands).toEqual(['reload-plugins'])
  expect(writes(w)).toEqual([])
  expect(w.logs).toContain('The profiles on this machine are reset; this session loaded the plugins its settings name now.')
})

test('#17354: Cancel at the reset confirm resets nothing', async ($, on) => {
  const w = world(on, ['Cancel'])
  expect(await runPicking($, w, 'Reset')).toBe('Not reset; nothing changed.')
  expect(resets(w)).toEqual([])
  await turnEnd($)
  await settle()
  expect(w.commands).toEqual([])
})

test('#17354: each folder without a record gets its own question, and only Remove passes it to reset; every reset question is headed Reset', async ($, on) => {
  const loose = (file: string) => ({ file, action: 'remove-entries', ask: { file, question: `${file} has no record. Remove its entries?`, ...UNRECORDED } })
  const resetDry = resetPreview([{ file: '/p/.claude/settings.local.json', action: 'restore' }, loose('/a/.claude/settings.local.json'), loose('/b/.claude/settings.local.json')])
  const w = world(on, ['Apply', 'Keep', 'Remove'], { resetDry })
  await runPicking($, w, 'Reset')
  expect(w.headers).toEqual(['Reset', 'Reset', 'Reset'])
  expect(w.asks).toEqual([
    { question: QUESTION, options: ['Cancel', 'Apply'] },
    { question: '/a/.claude/settings.local.json has no record. Remove its entries?', options: ['Keep', 'Remove'] },
    { question: '/b/.claude/settings.local.json has no record. Remove its entries?', options: ['Keep', 'Remove'] },
  ])
  expect(resets(w)).toEqual([['reset', '--yes', '--json', '--preview-id', 'preview-1', '--remove-unrecorded', '/b/.claude/settings.local.json', '--keep-unrecorded', '/a/.claude/settings.local.json']])
})

/** One picker cell: the answers given at the one question and at a folder's own question, the reset it runs (none when no answer is a yes) and what it says. */
const PICKED = '/a/.claude/settings.local.json'
const PICK_ARGS = ['reset', '--yes', '--json', '--preview-id', 'preview-1']
const ALL_RESET = `Reset every profile this machine records. ${NEXT_STEP}`
const OWN_ONLY = `Reset only the files you answered yes for; every file the one question covers keeps its profile. ${NEXT_STEP}`
const pickerCell = (first: string, own: string, runs: string[][], text: string) => async ($: any, on: any) => {
  const ask = { file: PICKED, question: `${PICKED} has no record. Remove its entries?`, ...UNRECORDED }
  const w = world(on, [first, own], { resetDry: resetPreview([{ file: '/p/.claude/settings.local.json', action: 'restore' }, { file: PICKED, action: 'remove-entries', ask }]) })
  expect(await runPicking($, w, 'Reset')).toBe(text)
  expect(w.asks.map(a => a.question)).toEqual([QUESTION, ask.question])
  expect(resets(w)).toEqual(runs)
}

test('#17354: picker cell: Apply, then Remove for the folder without a record', pickerCell('Apply', 'Remove', [[...PICK_ARGS, '--remove-unrecorded', PICKED]], ALL_RESET))
test('#17354: picker cell: Apply, then Keep for the folder without a record', pickerCell('Apply', 'Keep', [[...PICK_ARGS, '--keep-unrecorded', PICKED]], ALL_RESET))
test('#17354: picker cell: Cancel, then Remove for the folder without a record', pickerCell('Cancel', 'Remove', [[...PICK_ARGS, '--keep-recorded', '--remove-unrecorded', PICKED]], OWN_ONLY))
test('#17354: picker cell: Cancel, then Keep for the folder without a record', pickerCell('Cancel', 'Keep', [], 'Not reset; nothing changed.'))

test('#17354: a file whose earlier reset was cut off gets its own question with the answers the tool names, and each answer passes its own flag', async ($, on) => {
  const cut = (file: string) => ({
    file,
    action: 'finish-cut-off',
    ask: { file, question: `An earlier reset of ${file} was cut off and the file changed since. Put back?`, yes: { label: 'Put back', flag: '--finish-cut-off' }, no: { label: 'Keep', flag: '--keep-cut-off' } },
  })
  const dry = JSON.parse(resetPreview([cut('/a/.claude/settings.local.json'), cut('/b/.claude/settings.local.json')]).stdout as string)
  const resetDry = { exitCode: 0, stdout: JSON.stringify({ ...dry, question: null }) }
  const w = world(on, ['Put back', 'Keep'], { resetDry })
  expect(await runPicking($, w, 'Reset')).toBe(`Reset every profile this machine records. ${NEXT_STEP}`)
  expect(w.asks).toEqual([
    { question: 'An earlier reset of /a/.claude/settings.local.json was cut off and the file changed since. Put back?', options: ['Keep', 'Put back'] },
    { question: 'An earlier reset of /b/.claude/settings.local.json was cut off and the file changed since. Put back?', options: ['Keep', 'Put back'] },
  ])
  expect(resets(w)).toEqual([['reset', '--yes', '--json', '--preview-id', 'preview-1', '--finish-cut-off', '/a/.claude/settings.local.json', '--keep-cut-off', '/b/.claude/settings.local.json']])
})

test('#17354: a file question dismissed with Esc is its answer that changes nothing, listed first', async ($, on) => {
  const ask = { file: PICKED, question: `${PICKED} has no record. Remove its entries?`, ...UNRECORDED }
  const w = world(on, ['Apply'], { resetDry: resetPreview([{ file: '/p/.claude/settings.local.json', action: 'restore' }, { file: PICKED, action: 'remove-entries', ask }]) })
  expect(await runPicking($, w, 'Reset')).toBe(ALL_RESET)
  expect(w.asks.map(a => a.options)).toEqual([['Cancel', 'Apply'], ['Keep', 'Remove']])
  expect(resets(w)).toEqual([[...PICK_ARGS, '--keep-unrecorded', PICKED]])
})

test("#17354: each reset question shows the tool's recommended answer and its reason as a hint, and the answer that changes nothing stays first", async ($, on) => {
  const ask = { file: PICKED, question: `${PICKED} has no record. Remove its entries?`, ...UNRECORDED, recommend: { answer: 'no', reason: 'Reset did not write these entries, so they may be your own.' } }
  const dry = JSON.parse(resetPreview([{ file: '/p/.claude/settings.local.json', action: 'restore' }, { file: PICKED, action: 'remove-entries', ask }]).stdout as string)
  const questionRecommend = { asked: { answer: 'yes', reason: 'You asked for a reset (the reason the tool words).' }, unasked: { answer: 'no', reason: 'Nobody asked (the tool words it).' } }
  const w = world(on, ['Apply', 'Keep'], { resetDry: { exitCode: 0, stdout: JSON.stringify({ ...dry, questionRecommend }) } })
  await runPicking($, w, 'Reset')
  const hints = w.logs.filter(line => line.startsWith('Recommended: '))
  expect(hints).toEqual(['Recommended: Apply. You asked for a reset (the reason the tool words).', 'Recommended: Keep. Reset did not write these entries, so they may be your own.'])
  expect(w.asks.map(a => a.options)).toEqual([['Cancel', 'Apply'], ['Keep', 'Remove']])
})

test('#17354: a reset the tool refuses shows its reason and arms no reload', async ($, on) => {
  const refusal = 'not reset: what reset would write changed since the preview; nothing was written. Look at the new preview: reset --dry-run'
  const w = world(on, ['Apply'], { reset: { exitCode: 1, stderr: `${refusal}\n` } })
  expect(await runPicking($, w, 'Reset')).toBe(refusal)
  await turnEnd($)
  await settle()
  expect(w.commands).toEqual([])
})

test('#17354: a reset that skipped a file shows each result line and reloads', async ($, on) => {
  const lines = ['Skipped /p/.claude/settings.local.json: it changed during the reset and is left as the other writer left it; run reset again.']
  const w = world(on, ['Apply'], { reset: { exitCode: 3, stdout: JSON.stringify({ lines }) } })
  expect(await runPicking($, w, 'Reset')).toBe(`Reset did not finish every file; the lines above name each one skipped and why. Run /plugin-profile and pick Reset again for those. ${NEXT_STEP}`)
  expect(w.logs).toContain(lines[0])
  await turnEnd($)
  await settle()
  expect(w.commands).toEqual(['reload-plugins'])
})

test('#17354: after a complete reset, picking Reset says there is nothing to reset and asks nothing', async ($, on) => {
  const done = JSON.parse(resetPreview([]).stdout as string)
  const resetDry = { exitCode: 0, stdout: JSON.stringify({ ...done, question: null, unchangedSinceReset: ['/p/.claude/settings.local.json'] }) }
  const w = world(on, [], { resetDry })
  expect(await runPicking($, w, 'Reset')).toBe('Nothing to reset: each file reset restored earlier is unchanged since.')
  expect(w.asks).toEqual([])
  expect(resets(w)).toEqual([])
})

test('#17354: with nothing recorded the picker says so, asks nothing and resets nothing', async ($, on) => {
  const w = world(on, [], { resetDry: resetPreview([]) })
  expect(await runPicking($, w, 'Reset')).toBe('Nothing to reset: no profile is recorded anywhere reset can find.')
  expect(w.asks).toEqual([])
  expect(resets(w)).toEqual([])
})
