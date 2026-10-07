#!/usr/bin/env node
// GENERATED from lib/docs-fetcher-gate.mjs by scripts/sync-shared-copies.sh. Do not edit this copy:
// edit the canonical source, then rerun the script.
// PreToolUse gate for a plugin's docs-fetcher agent. The agent holds Bash and
// reads untrusted page text, so inside it a Bash call may run exactly one
// command: this plugin's own docs-raw.sh on one public https URL and optional
// numeric section ids. Anything else, from another script to a pipe, a
// redirect, a second command or an internal address, is denied, so a page that
// tells the agent to run something cannot reach a shell. The one allowed
// command gets no decision, so the session's own permission rules still apply
// to it. Every other agent and the main thread pass through untouched.
//
//   node docs-fetcher-gate.mjs <agent-type> [<host>...]
//
// <agent-type> is the plugin-scoped name the gate applies to, such as
// multi-agent:docs-fetcher. Hosts, when given, are the only ones a URL may name,
// and such a URL may carry no query string. The script must sit at
// $CLAUDE_PLUGIN_ROOT/scripts/docs-raw.sh, the root the hook process receives.
//
// A plugin subagent reports its plugin-scoped name as agent_type:
// https://code.claude.com/docs/en/hooks#subagentstart (as of 2026-10-04;
// recheck when that section changes the agent_type a plugin subagent reports).
//
// Fail-closed inside the named agent (a command it cannot parse is denied);
// fail-open everywhere else.

import { pathToFileURL } from 'node:url'

// A public DNS name or a public dotted-quad IPv4: the same check the workflows
// run on the URLs they hand this agent.
export function isPublicHost(host) {
  host = String(host).toLowerCase().replace(/\.$/, '')
  if (!/^[a-z0-9.-]+$/.test(host)) return false
  const labels = host.split('.')
  if (labels.length < 2 || labels.some(l => !l)) return false
  if (/(^|\.)(localhost|local|internal|localdomain|home|lan)$/.test(host)) return false
  const numeric = l => /^(0x[0-9a-f]*|\d+)$/.test(l)
  if (!labels.every(numeric)) {
    if (numeric(labels[labels.length - 1])) return false
    if (/(^|\.)(nip\.io|sslip\.io|xip\.io|traefik\.me|localtest\.me|lvh\.me|vcap\.me|1u\.ms|rbndr\.us)$/.test(host)) return false
    if (/(^|[.-])\d{1,3}[.-]\d{1,3}[.-]\d{1,3}[.-]\d{1,3}([.-]|$)/.test(host)) return false
    if (labels.slice(0, -1).some(l => /^(0x)?[0-9a-f]{8}$/.test(l) && /\d/.test(l))) return false
    return true
  }
  if (labels.length !== 4 || !labels.every(l => /^(0|[1-9]\d{0,2})$/.test(l) && Number(l) <= 255)) return false
  const [a, b] = labels.map(Number)
  return !(a === 0 || a === 10 || a === 127 || a >= 224 || (a === 169 && b === 254) ||
    (a === 172 && b >= 16 && b <= 31) || (a === 192 && b === 168) || (a === 100 && b >= 64 && b <= 127))
}

// bash "<path>" <url> [<id>...]: the URL single-quoted or bare in a charset the
// shell gives no meaning to; spaces only between words. No backslash in the
// path: inside double quotes `\"` keeps the string open past the quote this
// pattern saw, so the URL's text would run as shell. Claude Code substitutes
// plugin paths with forward slashes on Windows too.
const COMMAND = /^bash +"([^"$`\\\x00-\x1f\x7f]+)" +('[^'"\\\x00-\x20\x7f]+'|[A-Za-z0-9._~:/%=+#-]+)((?: +[1-9][0-9]{0,5}){0,20}) *$/

// The script path the root names, with forward slashes; compared without case
// on Windows, whose paths ignore it.
const fold = s => (process.platform === 'win32' ? s.toLowerCase() : s)
const scriptOf = root => fold(String(root).replace(/\\/g, '/').replace(/\/+$/, '') + '/scripts/docs-raw.sh')

// A payload past this many bytes is never a docs-raw call: it is read no
// further (hook-precision rule 3) and denied inside the agent.
export const MAX_STDIN = 1 << 20

export function decide(payload, { agentType, root, hosts = [] } = {}) {
  const agent = String((payload && payload.agent_type) || '')
  if (!agentType || agent !== agentType) return null
  const usage = agentType + ' may only run: bash "' + (root || '$CLAUDE_PLUGIN_ROOT') + '/scripts/docs-raw.sh" \'<https URL>\' [<section id>...]'
  if (payload.tool_name !== 'Bash') return usage
  if (!root) return 'docs-fetcher denied: the hook received no plugin root. ' + usage
  const m = COMMAND.exec(String((payload.tool_input && payload.tool_input.command) || ''))
  if (!m) return 'docs-fetcher denied: not the one allowed command shape. ' + usage
  if (fold(m[1]) !== scriptOf(root)) return 'docs-fetcher denied: not this plugin\'s docs-raw.sh. ' + usage
  let url
  try {
    url = new URL(m[2].replace(/^'|'$/g, ''))
  } catch {
    return 'docs-fetcher denied: the URL does not parse'
  }
  if (url.protocol !== 'https:') return 'docs-fetcher denied: not an https URL'
  if (url.username || url.password) return 'docs-fetcher denied: the URL carries userinfo'
  if (!isPublicHost(url.hostname)) return 'docs-fetcher denied: ' + url.hostname + ' is not a public host'
  if (hosts.length) {
    if (url.search) return 'docs-fetcher denied: the URL carries a query string'
    if (!hosts.includes(url.hostname.toLowerCase())) return 'docs-fetcher denied: ' + url.hostname + ' is not one of ' + hosts.join(', ')
  }
  return null
}

// The agent_type the bytes name, for input that does not parse whole.
function agentTypeIn(text) {
  const m = /"agent_type"\s*:\s*"((?:[^"\\]|\\.)*)"/.exec(text)
  if (!m) return ''
  try { return JSON.parse('"' + m[1] + '"') } catch { return '' }
}

// The hook input as read: overflow marks a read cut off at MAX_STDIN.
export function judge(raw, { agentType, root, hosts = [], overflow = false } = {}) {
  let payload = null
  if (!overflow) {
    try { payload = JSON.parse(raw) } catch { payload = null }
  }
  if (payload) return decide(payload, { agentType, root, hosts })
  if (!agentType || agentTypeIn(raw) !== agentType) return null
  return overflow ? 'docs-fetcher denied: the hook input passed ' + MAX_STDIN + ' bytes' : 'docs-fetcher denied: the hook input is not JSON'
}

function main() {
  const [agentType, ...hosts] = process.argv.slice(2)
  const chunks = []
  let size = 0
  let done = false
  const finish = overflow => {
    if (done) return
    done = true
    const reason = judge(Buffer.concat(chunks).toString('utf8'), {
      agentType, root: process.env.CLAUDE_PLUGIN_ROOT, hosts: hosts.map(h => h.toLowerCase()), overflow,
    })
    if (reason) {
      process.stdout.write(JSON.stringify({
        hookSpecificOutput: { hookEventName: 'PreToolUse', permissionDecision: 'deny', permissionDecisionReason: reason },
      }))
    }
    process.stdin.destroy()
  }
  process.stdin.on('data', d => {
    if (done) return
    chunks.push(d)
    size += d.length
    if (size > MAX_STDIN) finish(true)
  })
  process.stdin.on('end', () => finish(false))
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) main()
