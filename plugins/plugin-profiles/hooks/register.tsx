import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { Switch } from '../types'

// The command-line tool decides every rule (which profiles exist, what an apply writes, when a
// switch is refused); this module only asks the person and runs it.
const CLI = 'scripts/profiles.mjs'
const COMMAND = 'plugin-profile'
const RELOAD = 'reload-plugins'
const MORE = 'More profiles'
const APPLY = 'Apply'
const CANCEL = 'Cancel'
// $.ui.ask takes two to four labels: a page holds three profiles and MORE.
const PAGE = 3

type Profile = { name: string; description: string | null }
type Preview = {
  upToDate: boolean
  pending: string[]
  mcpOrLspOn: string[]
  prerequisitesMissing: string[]
  lines: string[]
}

const pending = atom({ plugin: 'plugin-profiles', key: 'switch' } as const, null as Switch | null)

const cli = ($: EngineInterface, args: readonly string[]) =>
  $.process.run(['node', `${$.plugin.root}/${CLI}`, ...args], { timeoutMs: 60_000 })

const failure = (r: { stdout: string; stderr: string }) => (r.stderr || r.stdout).trim()
const list = (ids: readonly string[]) => ids.join(', ')

const registerCommand = ($: EngineInterface) =>
  $.command.register({
    name: COMMAND,
    description: 'Switch this folder to another plugin profile: pick, preview, confirm',
    argumentHint: '[profile]',
  })

async function pick($: EngineInterface, profiles: readonly Profile[]): Promise<string | undefined> {
  $.ui.log(profiles.map(p => `${p.name}${p.description ? `: ${p.description}` : ''}`).join('\n'))
  const names = profiles.map(p => p.name)
  for (let start = 0; ; start = start + PAGE >= names.length ? 0 : start + PAGE) {
    const options = names.length <= PAGE + 1 ? names : [...names.slice(start, start + PAGE), MORE]
    const answer = (await $.ui.ask('Which profile should this folder use?', { options, header: 'Profile' })).trim()
    if (answer !== MORE || names.length <= PAGE + 1) return answer
  }
}

/** Shows the preview and asks; true only on the person's Apply. */
async function confirm($: EngineInterface, name: string, preview: Preview): Promise<boolean> {
  $.ui.log(preview.lines.join('\n'))
  const reread = preview.mcpOrLspOn.length
    ? `${list(preview.mcpOrLspOn)} ship an MCP or language server, so your next message after the switch re-reads the whole conversation. `
    : ''
  return (await $.ui.ask(`${reread}Apply profile ${name} to this folder?`, { options: [APPLY, CANCEL], header: 'Profile' })) === APPLY
}

async function switchProfile($: EngineInterface, args: string): Promise<string> {
  const waiting = await read($, pending)
  if (waiting) return `A switch to ${waiting.profile} is still waiting for its reload; run /${COMMAND} again after it finishes.`
  let name = args
  if (!name) {
    const listed = await cli($, ['list', '--json'])
    if (listed.exitCode !== 0) return failure(listed)
    try {
      name = (await pick($, JSON.parse(listed.stdout) as Profile[])) ?? ''
    } catch {
      return 'No profile chosen; nothing changed.'
    }
  }
  const dry = await cli($, ['apply', name, '--for', 'folder', '--defer-off', '--dry-run', '--json'])
  if (dry.exitCode !== 0) return failure(dry)
  const preview = JSON.parse(dry.stdout) as Preview
  if (preview.upToDate) return `This folder already uses profile ${name}; nothing to change.`
  if (preview.prerequisitesMissing.length) {
    $.ui.log(preview.lines.join('\n'))
    return `Not applied: ${list(preview.prerequisitesMissing)} miss a required prerequisite, which only a person at a terminal can accept. Decide there: node "${$.plugin.root}/${CLI}" apply ${name} --for folder`
  }
  let yes: boolean
  try {
    yes = await confirm($, name, preview)
  } catch {
    yes = false
  }
  if (!yes) return 'Not applied; nothing changed.'
  const applied = await cli($, ['apply', name, '--for', 'folder', '--defer-off', '--yes'])
  if (applied.exitCode !== 0) return failure(applied)
  await update($, pending, () => ({ profile: name, phase: 'armed' }))
  const stay = preview.pending.length
    ? ` The plugins it switches off (${list(preview.pending)}) stay loaded for this session and go at the next session start.`
    : ''
  return `Switched this folder to profile ${name}. Its plugins load when the next turn ends, with one /${RELOAD} (or run /${RELOAD} now).${stay}`
}

/** Writes the off entries once the reload has run, finishing the switch's off-pending record. */
async function finish($: EngineInterface): Promise<void> {
  const s = await read($, pending)
  if (s?.phase !== 'reloading') return
  await update($, pending, () => null)
  const r = await cli($, ['apply', s.profile, '--for', 'folder', '--yes'])
  $.ui.log(
    r.exitCode === 0
      ? `plugin-profiles: profile ${s.profile} is in force; the plugins it switches off stay loaded until the next session start.`
      : `plugin-profiles: the switch to ${s.profile} is unfinished (${failure(r)}); /${COMMAND} ${s.profile} finishes it.`,
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

  on('command.run', { command: COMMAND }, async ($, e) => {
    try {
      return { text: await switchProfile($, e.args.trim()) }
    } catch (err) {
      return { text: `plugin-profiles: nothing changed: ${err instanceof Error ? err.message : String(err)}` }
    }
  })

  // A reload from the command's own handler does not take, so it waits for the turn's end.
  on('turn.complete', async ($, e, next) => {
    const result = await next(e)
    if (e.agentId === undefined && (await markReloading($))) {
      void $.command.run({ command: RELOAD }).then(
        () => finish($),
        err => $.ui.log(`plugin-profiles: /${RELOAD} did not run: ${err instanceof Error ? err.message : String(err)}`, { to: 'debug' }),
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
