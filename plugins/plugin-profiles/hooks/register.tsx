import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { PickerEntry, Switch } from '../types'

// The command-line tool decides every rule (which profiles exist, what an apply writes, when a
// switch is refused); this module only asks the person and runs it.
const CLI = 'scripts/profiles.mjs'
const COMMAND = 'plugin-profile'
const RELOAD = 'reload-plugins'
const MORE = 'More profiles'
const CLEAR = 'No profile'
const PICKER = 'plugin-profile-picker'
const APPLY = 'Apply'
const CANCEL = 'Cancel'
// $.ui.ask takes two to four labels: a page holds three profiles and MORE.
const PAGE = 3
const NEXT_STEP = `Send any message, or run /${RELOAD} now, to load the change into this session; a new session starts with it.`

type Profile = { name: string; description: string | null }
type Preview = {
  upToDate: boolean
  pending: string[]
  mcpOrLspOn: string[]
  prerequisitesMissing: string[]
  othersInFolder?: { name: string }[]
  lines: string[]
}
type ClearPreview = { recorded: boolean; sessionProfile: string | null; lines: string[] }

const pending = atom({ plugin: 'plugin-profiles', key: 'switch' } as const, null as Switch | null)

const cli = async ($: EngineInterface, args: readonly string[]) =>
  $.process.run(['node', `${$.plugin.root}/${CLI}`, ...args], {
    timeoutMs: 60_000,
    env: { CLAUDE_CODE_SESSION_ID: await $.session.id() },
  })

const failure = (r: { stdout: string; stderr: string }) => (r.stderr || r.stdout).trim()
const list = (ids: readonly string[]) => ids.join(', ')
const show = ($: EngineInterface, lines: readonly string[]) => {
  for (const line of lines) if (line.trim()) $.ui.log(line)
}

const registerCommand = ($: EngineInterface) =>
  $.command.register({
    name: COMMAND,
    description: 'Switch this folder to another plugin profile, or clear it: pick, preview, confirm',
    argumentHint: '[profile]',
  })

const picker = atom({ plugin: 'plugin-profiles', key: 'picker' } as const, [] as PickerEntry[])
let choose: ((name: string | undefined) => void) | undefined

const entriesOf = (profiles: readonly Profile[]): PickerEntry[] => [
  ...profiles.map(p => ({ value: p.name, label: `${p.name}${p.description ? `: ${p.description}` : ''}` })),
  { value: CLEAR, label: `${CLEAR}: clear this folder's profile, back to your user and project settings` },
]

async function chosen($: EngineInterface, name: string | undefined) {
  const done = choose
  choose = undefined
  await $.ui.close({ id: PICKER }).catch(() => undefined)
  done?.(name)
}

/** Every profile in one pane; undefined when the person closes it. */
async function pick($: EngineInterface, profiles: readonly Profile[]): Promise<string | undefined> {
  const entries = entriesOf(profiles)
  await update($, picker, () => entries)
  const picked = new Promise<string | undefined>(resolve => (choose = resolve))
  const opened = await $.ui.open({ id: PICKER, title: 'Which profile should this folder use?', focus: true, closeOnEscape: true })
  if (opened.isPlaced) return picked
  choose = undefined
  return pickByPages($, entries)
}

async function pickByPages($: EngineInterface, list: readonly PickerEntry[]): Promise<string | undefined> {
  show($, list.map(e => e.label))
  const names = list.map(e => e.value)
  for (let start = 0; ; start = start + PAGE >= names.length ? 0 : start + PAGE) {
    const options = names.length <= PAGE + 1 ? names : [...names.slice(start, start + PAGE), MORE]
    const answer = (await $.ui.ask('Which profile should this folder use?', { options, header: 'Profile' })).trim()
    if (answer !== MORE || names.length <= PAGE + 1) return answer
  }
}

/** Asks Apply or Cancel; true only on the person's Apply, false when dismissed. */
const confirmed = async ($: EngineInterface, question: string) =>
  (await $.ui.ask(question, { options: [APPLY, CANCEL], header: 'Profile' }).catch(() => CANCEL)) === APPLY

/** Shows the preview and asks; true only on the person's Apply. */
async function confirm($: EngineInterface, name: string, preview: Preview): Promise<boolean> {
  show($, preview.lines)
  const reread = preview.mcpOrLspOn.length
    ? `${list(preview.mcpOrLspOn)} ship an MCP or language server, so your next message after the switch re-reads the whole conversation. `
    : ''
  const sharing = preview.othersInFolder ?? []
  const others = sharing.length
    ? `Other sessions in this folder (${list(sharing.map(s => s.name))}) also get this profile at their next reload or start; to give one its own profile, start it with the launch command instead. `
    : ''
  return confirmed($, `${others}${reread}Apply profile ${name} to this folder?`)
}

async function clearProfile($: EngineInterface): Promise<string> {
  const dry = await cli($, ['clear', '--for', 'folder', '--dry-run', '--json'])
  if (dry.exitCode !== 0) return failure(dry)
  const preview = JSON.parse(dry.stdout) as ClearPreview
  show($, preview.lines)
  if (!preview.recorded)
    return preview.sessionProfile
      ? 'Nothing to clear.'
      : `Nothing to clear; this folder's plugins come from your user and project settings. If this session still has an earlier profile's plugins loaded, run /${RELOAD} to load what the settings say now.`
  if (!(await confirmed($, 'Clear the profile from this folder?'))) return 'Not cleared; nothing changed.'
  const cleared = await cli($, ['clear', '--for', 'folder', '--yes'])
  if (cleared.exitCode !== 0) return failure(cleared)
  await update($, pending, (): Switch => ({ profile: CLEAR, phase: 'armed', kind: 'clear', keeps: preview.sessionProfile ?? undefined }))
  return `Cleared this folder's profile. ${NEXT_STEP}`
}

async function switchProfile($: EngineInterface, args: string): Promise<string> {
  const waiting = await read($, pending)
  if (waiting) return `A change to this folder's profile is still waiting for its reload: ${NEXT_STEP} Then run /${COMMAND} again.`
  let name = args
  if (!name) {
    const listed = await cli($, ['list', '--json'])
    if (listed.exitCode !== 0) return failure(listed)
    try {
      name = (await pick($, JSON.parse(listed.stdout) as Profile[])) ?? ''
    } catch {
      name = ''
    }
    if (!name) return 'No profile chosen; nothing changed.'
  }
  if (name === CLEAR) return clearProfile($)
  const dry = await cli($, ['apply', name, '--for', 'folder', '--defer-off', '--dry-run', '--json'])
  if (dry.exitCode !== 0) return failure(dry)
  const preview = JSON.parse(dry.stdout) as Preview
  if (preview.upToDate) return `This folder already uses profile ${name}; nothing to change.`
  if (preview.prerequisitesMissing.length) {
    show($, preview.lines)
    return `Not applied: ${list(preview.prerequisitesMissing)} miss a required prerequisite, which only a person at a terminal can accept. Decide there: node "${$.plugin.root}/${CLI}" apply ${name} --for folder`
  }
  if (!(await confirm($, name, preview))) return 'Not applied; nothing changed.'
  const applied = await cli($, ['apply', name, '--for', 'folder', '--defer-off', '--yes'])
  if (applied.exitCode !== 0) return failure(applied)
  await update($, pending, (): Switch => ({ profile: name, phase: 'armed', off: preview.pending }))
  const stay = preview.pending.length
    ? ` The plugins it switches off (${list(preview.pending)}) stay loaded in this session until a later /${RELOAD} or the next session start.`
    : ''
  return `Switched this folder to profile ${name}. ${NEXT_STEP}${stay}`
}

/** Writes the off entries once the reload has run, finishing the switch's off-pending record. */
async function finish($: EngineInterface): Promise<void> {
  const s = await read($, pending)
  if (s?.phase !== 'reloading') return
  await update($, pending, () => null)
  if (s.kind === 'clear') {
    $.ui.log(
      s.keeps
        ? `This folder has no profile now; this session keeps its one-session profile ${s.keeps}.`
        : 'This folder has no profile now; this session loaded the plugins your user and project settings name.',
    )
    return
  }
  const r = await cli($, ['apply', s.profile, '--for', 'folder', '--yes'])
  const off = s.off ?? []
  $.ui.log(
    r.exitCode !== 0
      ? `The switch to ${s.profile} is unfinished (${failure(r)}); /${COMMAND} ${s.profile} finishes it.`
      : off.length
        ? `Profile ${s.profile} is in force. The plugins it switches off (${list(off)}) stay loaded in this session until a later /${RELOAD} or the next session start.`
        : `Profile ${s.profile} is in force.`,
  )
}

const markReloading = async ($: EngineInterface) => {
  const s = await read($, pending)
  if (s?.phase !== 'armed') return false
  await update($, pending, () => ({ ...s, phase: 'reloading' }))
  return true
}

export const register: Register = on => {
  // A reload loads this module again and fires session.start, which finishes a switch the reload
  // interrupted; $.state outlives the reload.
  on('session.start', async ($, e, next) => {
    const started = await next(e)
    await registerCommand($)
    void finish($).catch(() => undefined)
    return started
  }).catch(($, e, next) => next(e))

  // No session.start fires after /clear, /resume or /branch, so the next prompt registers again.
  let reregister = false
  on('session.end', async ($, e, next) => {
    reregister = true
    return next(e)
  }).catch(($, e, next) => next(e))
  on('prompt.submit', async ($, e, next) => {
    if (reregister) {
      reregister = false
      await registerCommand($).catch(() => undefined)
    }
    return next(e)
  }).catch(($, e, next) => next(e))

  // A mobile app that does not say it draws Select shows nothing for it, so mobile gets a Button
  // per profile: https://code.claude.com/docs/en/plugins/mods/interface#build-a-tree-from-elements
  on('ui.render', { component: 'Pane', requestId: PICKER }, async ($, e) => {
    const { Box, Text, Select, Button } = $.ui.resolve(e)
    const entries = await read($, picker)
    if (!entries.length) return <Text dimColor>No profiles to pick.</Text>
    return (
      <Box flexDirection="column">
        <Text dimColor>Pick one; the next step shows what it changes and asks before writing.</Text>
        {e.surface === 'mobile' ? (
          entries.map(entry => (
            <Button key={`profile:${entry.value}`} onPress={() => void chosen($, entry.value)}>
              {entry.label}
            </Button>
          ))
        ) : (
          <Select key="profile" label="Profile" autoFocus options={entries} onSelect={value => void chosen($, value)} />
        )}
        <Button key="cancel" role="dismiss" onPress={() => void chosen($, undefined)}>
          Cancel
        </Button>
      </Box>
    )
  })

  on('ui.close', { id: PICKER }, async ($, e, next) => {
    const result = await next(e)
    const done = choose
    choose = undefined
    done?.(undefined)
    return result
  }).catch(($, e, next) => next(e))

  on('command.run', { command: COMMAND }, async ($, e) => {
    try {
      return { text: await switchProfile($, e.args.trim()) }
    } catch (err) {
      return { text: `Nothing changed: ${err instanceof Error ? err.message : String(err)}` }
    }
  })

  // A reload from the command's own handler does not take, so it waits for the turn's end.
  on('turn.complete', async ($, e, next) => {
    const result = await next(e)
    if (e.agentId === undefined && (await markReloading($))) {
      void $.command.run({ command: RELOAD }).then(
        () => finish($),
        err => $.ui.log(`/${RELOAD} did not run: ${err instanceof Error ? err.message : String(err)}`, { to: 'debug' }),
      ).catch(() => undefined)
    }
    return result
  }).catch(($, e, next) => next(e))

  // The person's own /reload-plugins before the turn ends stands in for the queued one.
  on('command.run', { command: RELOAD }, async ($, e, next) => {
    await markReloading($)
    const result = await next(e)
    await finish($).catch(() => undefined)
    return result
  }).catch(($, e, next) => next(e))
}
