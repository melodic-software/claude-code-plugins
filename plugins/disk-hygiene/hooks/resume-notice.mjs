#!/usr/bin/env node
// SessionStart notice for a session resumed after /disk-hygiene:clean ran in it (#9853).
//
// The clean skill's frontmatter belt (the PowerShell deletion prompts and the
// deny-by-default Bash lane) is registered in the process that invoked the
// skill. A Windows probe found it absent after `claude -p --resume`, which
// starts a new process on the same session id. The UserPromptExpansion row in
// hooks.json writes `<marker-root>/clean-invoked/<session>.launched` through
// run-python-hook.sh's `--launch-marker`; on `source: resume` this script looks
// for that marker and, when it is there, tells the model to make no deletes or
// overwrites until the user types /disk-hygiene:clean again, which registers
// the belt again. It is a notice, not a gate.
//
//   node resume-notice.mjs --marker-root <dir>
//
// It always exits 0 and prints nothing unless the source is `resume` and a
// marker exists. Candidates mirror run-python-hook.sh's `_marker_candidates`:
// the marker root, then (off Windows) `${TMPDIR:-/tmp}/disk-hygiene-clean-invoked`.
// On Windows the launcher's tmp fallback is a Git Bash path this script does
// not resolve, so only the marker root counts there; with
// ${CLAUDE_PLUGIN_DATA} expanded the launcher writes the marker root first.
import { existsSync, realpathSync } from 'node:fs'
import { join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

export const SUBDIR = 'clean-invoked'
const DATA_PLACEHOLDER = '${CLAUDE_PLUGIN_DATA}'

export const NOTICE =
  'disk-hygiene: this session was resumed after /disk-hygiene:clean ran in it. ' +
  "The clean skill's guard (its PowerShell deletion prompts and deny-by-default Bash lane) " +
  'is registered only in the process that invoked the skill, so it is not active now. ' +
  'Until the user types /disk-hygiene:clean again, make no delete, move to the Recycle Bin, ' +
  'or overwrite of any file through any tool, even one the user approved before the resume. ' +
  'If a cleanup step is pending, ask the user to type /disk-hygiene:clean to re-arm the guard first.'

export function markerCandidates(session, { markerRoot, env, platform }) {
  const safe = String(session).replace(/[^a-zA-Z0-9_-]/g, '_')
  if (!safe) return []
  const name = `${safe}.launched`
  const out = []
  if (markerRoot && markerRoot !== DATA_PLACEHOLDER) out.push(join(markerRoot, SUBDIR, name))
  if (platform !== 'win32') out.push(join(env.TMPDIR || '/tmp', `disk-hygiene-${SUBDIR}`, name))
  return out
}

export function decide(payload, ctx) {
  if (!payload || payload.source !== 'resume') return null
  const session = typeof payload.session_id === 'string' ? payload.session_id : ''
  if (!session || /[^\x20-\x7e]/.test(session)) return null
  const exists = ctx.exists ?? existsSync
  if (!markerCandidates(session, ctx).some((p) => exists(p))) return null
  return { hookSpecificOutput: { hookEventName: 'SessionStart', additionalContext: NOTICE } }
}

export const MAX_STDIN_BYTES = 1 << 20
export const STDIN_DEADLINE_MS = 2000

// Read the payload without waiting for EOF: stop at the first chunk that
// completes a JSON object, at the size cap, or at the deadline, so a pipe that
// stays open cannot hold session start for the hook's whole timeout.
export function readPayload(stream, { maxBytes = MAX_STDIN_BYTES, deadlineMs = STDIN_DEADLINE_MS } = {}) {
  return new Promise((settle) => {
    let text = ''
    let done = false
    const parse = () => {
      try {
        return JSON.parse(text)
      } catch {
        return undefined
      }
    }
    const finish = (value) => {
      if (done) return
      done = true
      clearTimeout(timer)
      stream.pause()
      settle(value)
    }
    const timer = setTimeout(() => finish(parse()), deadlineMs)
    stream.setEncoding('utf8')
    stream.on('data', (chunk) => {
      text += chunk
      if (text.length > maxBytes) return finish(undefined)
      const value = parse()
      if (value !== undefined) finish(value)
    })
    stream.on('end', () => finish(parse()))
    stream.on('error', () => finish(undefined))
  })
}

async function main(argv) {
  const at = argv.indexOf('--marker-root')
  const markerRoot = at >= 0 ? (argv[at + 1] ?? '') : ''
  const payload = await readPayload(process.stdin)
  const out = payload ? decide(payload, { markerRoot, env: process.env, platform: process.platform }) : null
  if (out) process.stdout.write(`${JSON.stringify(out)}\n`)
}

// Node realpaths the main entry, so compare real paths: a launch through a
// symlinked or junctioned plugin path must still reach main().
function realPath(p) {
  try {
    return realpathSync(p)
  } catch {
    return resolve(p)
  }
}
if (process.argv[1] && realPath(process.argv[1]) === realPath(fileURLToPath(import.meta.url))) {
  // A failed notice must never break session start; exit even if stdin stays open.
  main(process.argv.slice(2))
    .catch(() => {})
    .finally(() => process.stdout.write('', () => process.exit(0)))
}
