import type { EngineInterface, PluginOptions, Register } from 'claude-code'

// The per-session hook event log, off by default. Off, the module hooks nothing, so no event starts
// a process. On, each observed classic event hands its payload to session-event-log.sh, which
// writes the record the settings row wrote, and SessionEnd also runs session-retention.sh. A mod
// cannot append to a file, so each write is one process.

type ClassicEvent = Readonly<{ hook_event_name: string }>
type Next = (e: never) => Promise<unknown>

const TIMEOUT_MS = 5_000

let config: PluginOptions = {}
const logged = new Set<string>()

// What a settings hook had in its environment: CLAUDE_PLUGIN_OPTION_<KEY> for each option and the
// project root. CLAUDE_EFFORT and TRACEPARENT are cleared, so a value the Claude Code process itself
// holds never stands in for one the event did not carry.
export const scriptEnv = (options: PluginOptions, root: string): Record<string, string> => ({
  ...Object.fromEntries(
    Object.entries(options).map(([key, value]) => [`CLAUDE_PLUGIN_OPTION_${key.toUpperCase()}`, String(value)]),
  ),
  CLAUDE_PROJECT_DIR: root,
  CLAUDE_EFFORT: '',
  TRACEPARENT: '',
})

const logOnce = ($: EngineInterface, key: string, text: string) => {
  if (logged.has(key)) return
  logged.add(key)
  $.ui.log(`harness-ops: ${text}`, { to: 'debug' })
}

async function run($: EngineInterface, script: string, stdin?: string) {
  try {
    const root = await $.session.root()
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
  const writes = [run($, 'session-event-log.sh', JSON.stringify(e))]
  if (e.hook_event_name === 'SessionEnd') writes.push(run($, 'session-retention.sh'))
  const [result] = await Promise.all([next(e as never), ...writes])
  return result
}

function passThrough($: EngineInterface, e: ClassicEvent, next: Next) {
  return next(e as never)
}

export const register: Register = (on, options) => {
  if (options.session_event_log_enabled !== true) return
  config = options
  // scripts/gen-hook-event-registry.sh writes the block below from hook-events.registry.json, one
  // hook per event marked observe; Claude Code reads each event name from a string literal.
  // BEGIN GENERATED: observed events
  on('classic.ConfigChange', record).catch(passThrough)
  on('classic.CwdChanged', record).catch(passThrough)
  on('classic.DirectoryAdded', record).catch(passThrough)
  on('classic.Elicitation', record).catch(passThrough)
  on('classic.ElicitationResult', record).catch(passThrough)
  on('classic.InstructionsLoaded', record).catch(passThrough)
  on('classic.Notification', record).catch(passThrough)
  on('classic.PermissionDenied', record).catch(passThrough)
  on('classic.PermissionRequest', record).catch(passThrough)
  on('classic.PostCompact', record).catch(passThrough)
  on('classic.PostModelSwitch', record).catch(passThrough)
  on('classic.PostToolBatch', record).catch(passThrough)
  on('classic.PostToolUseFailure', record).catch(passThrough)
  on('classic.PreCompact', record).catch(passThrough)
  on('classic.PreModelSwitch', record).catch(passThrough)
  on('classic.SessionEnd', record).catch(passThrough)
  on('classic.SessionStart', record).catch(passThrough)
  on('classic.Setup', record).catch(passThrough)
  on('classic.Stop', record).catch(passThrough)
  on('classic.StopFailure', record).catch(passThrough)
  on('classic.SubagentStart', record).catch(passThrough)
  on('classic.SubagentStop', record).catch(passThrough)
  on('classic.TaskCompleted', record).catch(passThrough)
  on('classic.TaskCreated', record).catch(passThrough)
  on('classic.TeammateIdle', record).catch(passThrough)
  on('classic.UserPromptExpansion', record).catch(passThrough)
  on('classic.UserPromptSubmit', record).catch(passThrough)
  on('classic.WorktreeRemove', record).catch(passThrough)
  // END GENERATED: observed events
}
