#!/usr/bin/env node
// PreToolUse gate for a plugin's docs-fetcher agent. The agent holds Bash and
// reads untrusted page text, so inside it a Bash call may run exactly one
// command: this plugin's own docs-raw.sh on one public https URL and optional
// numeric section ids. Anything else, from another script to a pipe, a
// redirect, a second command or an internal address, is denied, so a page that
// tells the agent to run something cannot reach a shell. Every other agent and
// the main thread pass through untouched.
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

// bash "<path>" <url> [<id>...]: the URL single-quoted (no quote inside) or bare
// in a charset the shell gives no meaning to; spaces only between words.
const COMMAND = /^bash +"([^"$`\n]+)" +('[^'\x00-\x20\x7f]+'|[A-Za-z0-9._~:/%=+#-]+)((?: +[1-9][0-9]{0,5}){0,20}) *$/

const norm = p => {
  const s = String(p).replace(/\\/g, '/').replace(/\/+$/, '')
  return process.platform === 'win32' ? s.toLowerCase() : s
}

export function decide(payload, { agentType, root, hosts = [] } = {}) {
  const agent = String((payload && payload.agent_type) || '')
  if (!agentType || agent !== agentType) return null
  const usage = agentType + ' may only run: bash "' + (root || '$CLAUDE_PLUGIN_ROOT') + '/scripts/docs-raw.sh" \'<https URL>\' [<section id>...]'
  if (payload.tool_name !== 'Bash') return usage
  if (!root) return 'docs-fetcher denied: the hook received no plugin root. ' + usage
  const m = COMMAND.exec(String((payload.tool_input && payload.tool_input.command) || ''))
  if (!m) return 'docs-fetcher denied: not the one allowed command shape. ' + usage
  if (norm(m[1]) !== norm(root + '/scripts/docs-raw.sh')) return 'docs-fetcher denied: not this plugin\'s docs-raw.sh. ' + usage
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

function main() {
  const [agentType, ...hosts] = process.argv.slice(2)
  let raw = ''
  process.stdin.on('data', d => { raw += d })
  process.stdin.on('end', () => {
    let payload
    try {
      payload = JSON.parse(raw)
    } catch {
      return
    }
    const reason = decide(payload, { agentType, root: process.env.CLAUDE_PLUGIN_ROOT, hosts: hosts.map(h => h.toLowerCase()) })
    if (reason) {
      process.stdout.write(JSON.stringify({
        hookSpecificOutput: { hookEventName: 'PreToolUse', permissionDecision: 'deny', permissionDecisionReason: reason },
      }))
    }
  })
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) main()
