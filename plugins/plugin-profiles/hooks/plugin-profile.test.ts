import { expect, test } from 'claude-code/testing'

// The /plugin-profile command and its end-of-turn reload. The command-line tool is stubbed by its
// argument vector; scripts/profiles.test.mjs tests the tool itself.

const PROFILES = ['build', 'discovery', 'harness-upkeep', 'interface-design', 'planning', 'review']
const MORE = 'More profiles'

type Out = { exitCode: number; stdout?: string; stderr?: string }
type Preview = { upToDate?: boolean; pending?: string[]; mcpOrLspOn?: string[]; prerequisitesMissing?: string[] }

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
const world = (on: any, answers: string[], cli: { dry?: Out; apply?: Out; list?: Out; reloadHangs?: boolean } = {}) => {
  const w = { runs: [] as string[][], asks: [] as { question: string; options: string[] }[], logs: [] as string[], commands: [] as string[], registered: [] as string[] }
  on('process.run', ($: unknown, e: { argv: readonly string[] }) => {
    const args = e.argv.slice(2)
    w.runs.push([...args])
    const out =
      args[0] === 'list'
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

test('session.start registers /plugin-profile', async ($, on) => {
  const w = world(on, [])
  await $.session.start({ cwd: '/p' } as any)
  expect(w.registered).toEqual(['plugin-profile'])
})

test('AC6: the picker pages through every profile, previews the pick, asks, then writes the on entries', async ($, on) => {
  const w = world(on, [MORE, 'review', 'Apply'])
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
  expect(text).toContain('(songwriting@melodic-software) stay loaded for this session and go at the next session start')
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

test('AC6: a dismissed picker writes nothing', async ($, on) => {
  const w = world(on, [])
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
  expect(w.logs).toContain('plugin-profiles: profile review is in force; the plugins it switches off stay loaded until the next session start.')
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
  expect(text).toContain('A switch to review is still waiting for its reload')
  expect(w.runs.length).toBe(2)
})

test('an off write that fails leaves the switch named as unfinished', async ($, on) => {
  const cli: { apply?: Out } = {}
  const w = world(on, ['Apply'], cli)
  await run($, 'review')
  cli.apply = { exitCode: 1, stderr: 'not applied: busy\n' }
  await turnEnd($)
  await settle()
  expect(w.logs).toContain('plugin-profiles: the switch to review is unfinished (not applied: busy); /plugin-profile review finishes it.')
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
