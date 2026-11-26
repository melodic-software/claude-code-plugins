import type { EngineInterface, PluginOptions, Register } from 'claude-code'

type ClassicEvent = Readonly<{ hook_event_name: string }>
type Next = (e: never) => Promise<unknown>

const TIMEOUT_MS = 5_000

let config: PluginOptions = {}
const logged = new Set<string>()

export const scriptEnv = (options: PluginOptions, root: string): Record<string, string> => ({
  ...Object.fromEntries(
    Object.entries(options).map(([key, value]) => [`CLAUDE_PLUGIN_OPTION_${key.toUpperCase()}`, String(value)]),
  ),
  CLAUDE_PROJECT_DIR: root,
  CLAUDE_EFFORT: '',
  TRACEPARENT: '',
})

export const categoryFilter = (value: unknown): ((category: string) => boolean) => {
  const text = value === undefined ? '' : String(value)
  if (text === '') return () => true
  const listed = new Set(text.replaceAll(',', ' ').split(/[ \t\n]+/))
  return category => listed.has(category)
}

const logOnce = ($: EngineInterface, key: string, text: string) => {
  if (logged.has(key)) return
  logged.add(key)
  $.ui.log(`session-telemetry: ${text}`, { to: 'debug' })
}

async function run($: EngineInterface, script: string, stdin?: string) {
  try {
    const root = (await $.env.get('CLAUDE_PROJECT_DIR')) || (await $.session.root())
    const result = await $.process.run(['node', `${$.plugin.root}/hooks/exec-bash.mjs`, `${$.plugin.root}/hooks/${script}`], {
      cwd: root,
      env: scriptEnv(config, root),
      ...(stdin === undefined ? {} : { stdin }),
      timeoutMs: TIMEOUT_MS,
    })
    if (result.exitCode !== 0) logOnce($, `${script}-exit`, `${script} exited ${result.exitCode}: ${result.stderr.trim()}`)
  } catch (error) {
    logOnce($, `${script}-threw`, `${script} did not run: ${error instanceof Error ? error.message : String(error)}`)
  }
}

async function record($: EngineInterface, e: ClassicEvent, next: Next) {
  const payload = JSON.stringify(e)
  if (e.hook_event_name !== 'SessionEnd') {
    $.clock.after(0, () => void run($, 'session-event-log.sh', payload))
    return next(e as never)
  }
  const recorded = categoryFilter(config.session_event_log_categories)('session')
  const [result] = await Promise.all([
    next(e as never),
    recorded && run($, 'session-event-log.sh', payload),
    run($, 'session-retention.sh'),
  ])
  return result
}

function passThrough($: EngineInterface, e: ClassicEvent, next: Next) {
  return next(e as never)
}

export const register: Register = (on, options) => {
  if (options.session_event_log_enabled !== true) return
  config = options
  const wants = categoryFilter(options.session_event_log_categories)
  // BEGIN GENERATED: observed events
  if (wants('config')) on('classic.ConfigChange', record).catch(passThrough)
  if (wants('config')) on('classic.CwdChanged', record).catch(passThrough)
  if (wants('config')) on('classic.DirectoryAdded', record).catch(passThrough)
  if (wants('mcp')) on('classic.Elicitation', record).catch(passThrough)
  if (wants('mcp')) on('classic.ElicitationResult', record).catch(passThrough)
  if (wants('config')) on('classic.InstructionsLoaded', record).catch(passThrough)
  if (wants('turn')) on('classic.Notification', record).catch(passThrough)
  if (wants('permission')) on('classic.PermissionDenied', record).catch(passThrough)
  if (wants('permission')) on('classic.PermissionRequest', record).catch(passThrough)
  if (wants('compaction')) on('classic.PostCompact', record).catch(passThrough)
  if (wants('model')) on('classic.PostModelSwitch', record).catch(passThrough)
  if (wants('tool')) on('classic.PostToolBatch', record).catch(passThrough)
  if (wants('tool')) on('classic.PostToolUseFailure', record).catch(passThrough)
  if (wants('compaction')) on('classic.PreCompact', record).catch(passThrough)
  if (wants('model')) on('classic.PreModelSwitch', record).catch(passThrough)
  on('classic.SessionEnd', record).catch(passThrough)
  if (wants('session')) on('classic.SessionStart', record).catch(passThrough)
  if (wants('session')) on('classic.Setup', record).catch(passThrough)
  if (wants('turn')) on('classic.Stop', record).catch(passThrough)
  if (wants('turn')) on('classic.StopFailure', record).catch(passThrough)
  if (wants('agent')) on('classic.SubagentStart', record).catch(passThrough)
  if (wants('agent')) on('classic.SubagentStop', record).catch(passThrough)
  if (wants('task')) on('classic.TaskCompleted', record).catch(passThrough)
  if (wants('task')) on('classic.TaskCreated', record).catch(passThrough)
  if (wants('agent')) on('classic.TeammateIdle', record).catch(passThrough)
  if (wants('prompt')) on('classic.UserPromptExpansion', record).catch(passThrough)
  if (wants('prompt')) on('classic.UserPromptSubmit', record).catch(passThrough)
  if (wants('worktree')) on('classic.WorktreeRemove', record).catch(passThrough)
  // END GENERATED: observed events
}
