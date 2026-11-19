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
const RESET = 'Reset'
/** The tool's exit status for a reset that wrote what it could and named each file it skipped. */
const PARTLY_DONE = 3
const PICKER = 'plugin-profile-picker'
const ROW = 'profile:'
const APPLY = 'Apply'
const CANCEL = 'Cancel'
// $.ui.ask takes two to four labels: a page holds three profiles and MORE.
const PAGE = 3
const NEXT_STEP = `Send any message, or run /${RELOAD} now, to load the change into this session; a new session starts with it.`
const NOT_CHOSEN = 'No profile chosen; nothing changed.'
const NOTHING_TO_FINISH = 'Nothing to finish:'
const PICK_OPEN = `A profile pick is already open in its pane; pick there, or press Cancel and run /${COMMAND} again.`

type Profile = { name: string; description: string | null }
type Preview = {
  upToDate: boolean
  pending: string[]
  mcpOrLspOn: string[]
  prerequisitesMissing: string[]
  othersInFolder?: { name: string; sessionId?: string; oneSessionProfile?: string | null }[]
  lines: string[]
}
type ClearPreview = { recorded: boolean; sessionProfile: string | null; lines: string[] }
/** One answer to a file's own question: the button's label and the flag that passes it to reset. */
type Answer = { label: string; flag: string }
type ResetPreview = { sessionProfile: string | null; previewId: string; question: string | null; folders: { action: string; ask?: { file: string; question: string; yes: Answer; no: Answer } }[]; unchangedSinceReset?: string[]; lines: string[] }

const pending = atom({ plugin: 'plugin-profiles', key: 'switch' } as const, null as Switch | null)
const picker = atom({ plugin: 'plugin-profiles', key: 'picker' } as const, [] as PickerEntry[])
const focused = atom({ plugin: 'plugin-profiles', key: 'focused' } as const, null as string | null)
let settling = false

const cli = async ($: EngineInterface, args: readonly string[]) =>
  $.process.run(['node', `${$.plugin.root}/${CLI}`, ...args], {
    timeoutMs: 60_000,
    env: { CLAUDE_CODE_SESSION_ID: await $.session.id() },
  })

/** Whether the picker pane is up, from the engine's record, which outlives a reload of this module. */
const pickerOpen = async ($: EngineInterface) => (await $.ui.panes()).some(pane => pane.id === PICKER)

const failure = (r: { stdout: string; stderr: string }) => (r.stderr || r.stdout).trim()
const list = (ids: readonly string[]) => ids.join(', ')
const show = ($: EngineInterface, lines: readonly string[]) => {
  for (const line of lines) if (line.trim()) $.ui.log(line)
}
const stayLoaded = (off: readonly string[]) =>
  `${off.length === 1 ? 'The plugin it switches off stays' : `The ${off.length} plugins it switches off stay`} loaded in this session until a later /${RELOAD} or the next session start.`

const registerCommand = ($: EngineInterface) =>
  $.command.register({
    name: COMMAND,
    description: 'Switch this folder to another plugin profile, or clear it: pick, preview, confirm',
    argumentHint: '[profile]',
  })

const entriesOf = (profiles: readonly Profile[]): PickerEntry[] => [
  ...profiles.map(p => ({ name: p.name, description: p.description ?? '' })),
  { name: CLEAR, description: "clear this folder's profile, back to your user and project settings" },
  { name: RESET, description: 'put every folder and the initial profile back to before any profile' },
]
const labelOf = (e: PickerEntry) => (e.description ? `${e.name}: ${e.description}` : e.name)

const outcome = async (run: () => Promise<string>) => {
  try {
    return await run()
  } catch (err) {
    return `Nothing changed: ${err instanceof Error ? err.message : String(err)}`
  }
}

async function picked($: EngineInterface, name: string | undefined) {
  if (settling) return
  settling = true
  try {
    if (!(await pickerOpen($))) return
    await $.ui.close({ id: PICKER }).catch(() => undefined)
    show($, [name ? await outcome(async () => (await waitingLine($)) ?? switchTo($, name)) : NOT_CHOSEN])
  } finally {
    settling = false
  }
}

async function pickByPages($: EngineInterface, entries: readonly PickerEntry[]): Promise<string | undefined> {
  show($, entries.map(labelOf))
  const names = entries.map(e => e.name)
  for (let start = 0; ; start = start + PAGE >= names.length ? 0 : start + PAGE) {
    const options = names.length <= PAGE + 1 ? names : [...names.slice(start, start + PAGE), MORE]
    const answer = (await $.ui.ask('Which profile should this folder use?', { options, header: 'Profile' })).trim()
    if (answer !== MORE || names.length <= PAGE + 1) return answer
  }
}

/**
 * Every question this module asks: the answer that changes nothing is listed first, so it is the pre-selected one, and
 * Esc or a failed prompt is that answer. True only when the person picks the answer that writes.
 */
const chose = async ($: EngineInterface, question: string, safe: string, writes: string, header = 'Profile') =>
  (await $.ui.ask(question, { options: [safe, writes], header }).catch(() => safe)) === writes

/** Asks Cancel or Apply; true only on the person's Apply. */
const confirmed = ($: EngineInterface, question: string) => chose($, question, CANCEL, APPLY)

/** Shows the preview and asks; true only on the person's Apply. */
async function confirm($: EngineInterface, name: string, preview: Preview): Promise<boolean> {
  show($, preview.lines)
  const reread = preview.mcpOrLspOn.length
    ? `${list(preview.mcpOrLspOn)} ship an MCP or language server, so your next message after the switch re-reads the whole conversation. `
    : ''
  const others = preview.othersInFolder ?? []
  const named = (s: { name: string; sessionId?: string }) =>
    s.sessionId && s.sessionId !== s.name ? `${s.name} (session ${s.sessionId.slice(0, 8)})` : s.name
  const sharing = others.filter(s => !s.oneSessionProfile)
  const keeping = others.filter(s => s.oneSessionProfile)
  const gets = sharing.length
    ? `Other sessions in this folder (${list(sharing.map(named))}) also get this profile at their next reload or start; to give one its own profile, start it with the launch command instead. `
    : ''
  const keeps = keeping.length
    ? `Sessions here in a one-session profile keep theirs and do not change: ${keeping.map(s => `${named(s)} in ${s.oneSessionProfile}`).join('; ')}. `
    : ''
  return confirmed($, `${gets}${keeps}${reread}Apply profile ${name} to this folder?`)
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

/** Previews the machine-wide reset, asks once for the recorded files and once per file the tool asks about on its own, then resets. */
async function resetAll($: EngineInterface): Promise<string> {
  const dry = await cli($, ['reset', '--dry-run', '--json'])
  if (dry.exitCode !== 0) return failure(dry)
  const preview = JSON.parse(dry.stdout) as ResetPreview
  show($, preview.lines)
  const askable = preview.folders.flatMap(f => (f.ask ? [f.ask] : []))
  if (!preview.folders.length)
    return preview.unchangedSinceReset?.length
      ? 'Nothing to reset: each file reset restored earlier is unchanged since.'
      : 'Nothing to reset: no profile is recorded anywhere reset can find.'
  if (!preview.question && !askable.length) return 'Nothing to reset; the files above keep their records.'
  const keepRecorded = Boolean(preview.question) && !(await confirmed($, preview.question as string))
  const yes: string[] = []
  const no: string[] = []
  for (const ask of askable) {
    if (await chose($, ask.question, ask.no.label, ask.yes.label, 'Reset')) yes.push(ask.yes.flag, ask.file)
    else no.push(ask.no.flag, ask.file)
  }
  if ((!preview.question || keepRecorded) && !yes.length) return 'Not reset; nothing changed.'
  const answers = [...(keepRecorded ? ['--keep-recorded'] : []), ...yes, ...no]
  const done = await cli($, ['reset', '--yes', '--json', '--preview-id', preview.previewId, ...answers])
  if (done.exitCode !== 0 && done.exitCode !== PARTLY_DONE) return failure(done)
  show($, (JSON.parse(done.stdout) as { lines: string[] }).lines)
  await update($, pending, (): Switch => ({ profile: RESET, phase: 'armed', kind: 'reset', keeps: preview.sessionProfile ?? undefined }))
  if (done.exitCode === 0 && keepRecorded) return `Reset only the files you answered yes for; every file the one question covers keeps its profile. ${NEXT_STEP}`
  return done.exitCode === 0
    ? `Reset every profile this machine records. ${NEXT_STEP}`
    : `Reset did not finish every file; the lines above name each one skipped and why. Run /${COMMAND} and pick Reset again for those. ${NEXT_STEP}`
}

/** The line refusing a new switch while an earlier one waits for its reload, or undefined. */
const waitingLine = async ($: EngineInterface) =>
  (await read($, pending)) ? `A change to this folder's profile is still waiting for its reload: ${NEXT_STEP} Then run /${COMMAND} again.` : undefined

async function switchProfile($: EngineInterface, args: string): Promise<string> {
  if (await pickerOpen($)) return PICK_OPEN
  const waiting = await waitingLine($)
  if (waiting) return waiting
  if (args) return switchTo($, args)
  const listed = await cli($, ['list', '--json'])
  if (listed.exitCode !== 0) return failure(listed)
  const entries = entriesOf(JSON.parse(listed.stdout) as Profile[])
  await update($, picker, () => entries)
  await update($, focused, () => null)
  const opened = await $.ui.open({ id: PICKER, title: 'Which profile should this folder use?', focus: true, closeOnEscape: true })
  if (opened.isPlaced) return 'Pick a profile in the pane; the next step shows what it changes and asks before writing.'
  await $.ui.close({ id: PICKER }).catch(() => undefined)
  const name = await pickByPages($, entries).catch(() => undefined)
  return name ? switchTo($, name) : NOT_CHOSEN
}

async function switchTo($: EngineInterface, name: string): Promise<string> {
  if (name === CLEAR) return clearProfile($)
  if (name === RESET) return resetAll($)
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
  return `Switched this folder to profile ${name}. ${NEXT_STEP}${preview.pending.length ? ` ${stayLoaded(preview.pending)}` : ''}`
}

/** Writes the off entries once the reload has run, only while the folder's record is still this switch's off-pending one. */
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
  if (s.kind === 'reset') {
    $.ui.log(
      s.keeps
        ? `The profiles on this machine are reset; this session keeps its one-session profile ${s.keeps}.`
        : 'The profiles on this machine are reset; this session loaded the plugins its settings name now.',
    )
    return
  }
  const r = await cli($, ['apply', s.profile, '--for', 'folder', '--finish-pending'])
  const off = s.off ?? []
  $.ui.log(
    r.exitCode !== 0
      ? `The switch to ${s.profile} is unfinished (${failure(r)}); /${COMMAND} ${s.profile} finishes it.`
      : r.stdout.startsWith(NOTHING_TO_FINISH)
        ? `The switch to ${s.profile} was not finished: this folder's profile changed elsewhere since (a reset, a clear or another switch), so nothing was written.`
        : `Profile ${s.profile} is in force.${off.length ? ` ${stayLoaded(off)}` : ''}`,
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

  on('ui.render', { component: 'Pane', requestId: PICKER }, async ($, e) => {
    const { Box, Text, Button } = $.ui.resolve(e)
    const entries = await read($, picker)
    if (!entries.length) return <Text dimColor>No profiles to pick.</Text>
    const focus = await read($, focused)
    const shown = entries.find(entry => entry.name === focus)
    return (
      <Box flexDirection="column">
        <Text dimColor>Pick one; the next step shows what it changes and asks before writing.</Text>
        {entries.map((entry, i) => (
          <Box key={`row:${entry.name}`} flexDirection="column">
            <Box flexDirection="row">
              <Button key={`${ROW}${entry.name}`} autoFocus={i === 0 || undefined} onPress={() => void picked($, entry.name)}>
                {entry.name}
              </Button>
              <Text dimColor wrap="truncate-end">
                {entry.description ? ` ${entry.description}` : ''}
              </Text>
            </Box>
            {entry.description ? (
              <Box display="none" hover={{ display: 'flex' }}>
                <Text wrap="wrap">{entry.description}</Text>
              </Box>
            ) : null}
          </Box>
        ))}
        {shown ? (
          <Text wrap="wrap">
            {labelOf(shown)}
          </Text>
        ) : null}
        <Button key="cancel" role="dismiss" onPress={() => void picked($, undefined)}>
          Cancel
        </Button>
      </Box>
    )
  })

  on('ui.focus', { requestId: PICKER }, async ($, e, next) => {
    await update($, focused, () => (e.element?.startsWith(ROW) ? e.element.slice(ROW.length) : null))
    return next(e)
  }).catch(($, e, next) => next(e))

  on('ui.close', { id: PICKER }, async ($, e, next) => {
    const result = await next(e)
    if (e.origin.kind === 'person') $.ui.log(NOT_CHOSEN)
    return result
  }).catch(($, e, next) => next(e))

  on('command.run', { command: COMMAND }, async ($, e) => ({ text: await outcome(() => switchProfile($, e.args.trim())) }))

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
