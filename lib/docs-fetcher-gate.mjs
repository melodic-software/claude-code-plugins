#!/usr/bin/env node
//
//
//
// A plugin subagent reports its plugin-scoped name as agent_type:
// https://code.claude.com/docs/en/hooks#subagentstart.
//

import { createRequire } from 'node:module'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { pathToFileURL } from 'node:url'

const require = createRequire(import.meta.url)

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

// Claude Code substitutes plugin paths with forward slashes on Windows too:
// https://code.claude.com/docs/en/plugins-reference#quoting-and-path-separators
const COMMAND = /^bash +"([^"$`\\\x00-\x1f\x7f]+)" +(--render +)?('[^'"\\\x00-\x20\x7f]+'|[A-Za-z0-9._~:/%=+#-]+)((?: +[1-9][0-9]{0,5}){0,20}) *$/

const fold = s => (process.platform === 'win32' ? s.toLowerCase() : s)
const scriptOf = root => fold(String(root).replace(/\\/g, '/').replace(/\/+$/, '') + '/scripts/docs-raw.sh')

export const MAX_STDIN = 1 << 20

export const RENDER_AGENTS = new Set(['multi-agent:registry-fetcher'])

export function decide(payload, { agentType, root, hosts = [] } = {}) {
  const agent = String((payload && payload.agent_type) || '')
  if (!agentType || agent !== agentType) return null
  const usage = agentType + ' may only run: bash "' + (root || '$CLAUDE_PLUGIN_ROOT') + '/scripts/docs-raw.sh" ' + (RENDER_AGENTS.has(agentType) ? '[--render] ' : '') + '\'<https URL>\' [<section id>...]'
  if (payload.tool_name !== 'Bash') return usage
  if (!root) return 'docs-fetcher denied: the hook received no plugin root. ' + usage
  const m = COMMAND.exec(String((payload.tool_input && payload.tool_input.command) || ''))
  if (!m) return 'docs-fetcher denied: not the one allowed command shape. ' + usage
  if (fold(m[1]) !== scriptOf(root)) return 'docs-fetcher denied: not this plugin\'s docs-raw.sh. ' + usage
  if (m[2] && !RENDER_AGENTS.has(agentType)) return 'docs-fetcher denied: only the registry fetcher may pass --render. ' + usage
  let url
  try {
    url = new URL(m[3].replace(/^'|'$/g, ''))
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

function agentTypeIn(text) {
  const m = /"agent_type"\s*:\s*"((?:[^"\\]|\\.)*)"/.exec(text)
  if (!m) return ''
  try { return JSON.parse('"' + m[1] + '"') } catch { return '' }
}

const UID = process.getuid?.()

export function markerDir(env = process.env) {
  if (env.CLAUDE_PLUGIN_DATA) return join(env.CLAUDE_PLUGIN_DATA, 'docs-fetcher-gate')
  return join(tmpdir(), 'claude-docs-fetcher-gate' + (UID === undefined ? '' : '-' + UID))
}

export function privateDir(dir, uid = UID) {
  const { lstatSync, mkdirSync } = require('node:fs')
  mkdirSync(dir, { recursive: true, mode: 0o700 })
  const s = lstatSync(dir)
  if (!s.isDirectory()) throw new Error(dir + ' is not a directory')
  if (uid !== undefined && (s.uid !== uid || s.mode & 0o077)) throw new Error(dir + ' is not private to this user')
  return dir
}

export function claimOnce(id, dir = markerDir(), uid = UID) {
  const { closeSync, openSync, readdirSync, rmSync, statSync } = require('node:fs')
  const { createHash } = require('node:crypto')
  privateDir(dir, uid)
  for (const f of readdirSync(dir)) {
    try {
      if (Date.now() - statSync(join(dir, f)).mtimeMs > 86400000) rmSync(join(dir, f), { force: true })
    } catch { /* another gate pruned it */ }
  }
  try {
    closeSync(openSync(join(dir, createHash('sha256').update(String(id)).digest('hex')), 'wx'))
    return true
  } catch (e) {
    if (e.code === 'EEXIST') return false
    throw e
  }
}

export function judge(raw, { agentType, root, hosts = [], cut = '', claim = claimOnce } = {}) {
  let payload = null
  if (!cut) {
    try { payload = JSON.parse(raw) } catch { payload = null }
  }
  if (!payload) {
    if (!agentType || agentTypeIn(raw) !== agentType) return null
    if (cut === 'overflow') return 'docs-fetcher denied: the hook input passed ' + MAX_STDIN + ' bytes'
    return cut ? 'docs-fetcher denied: the hook input could not be read' : 'docs-fetcher denied: the hook input is not JSON'
  }
  const reason = decide(payload, { agentType, root, hosts })
  if (reason || String(payload.agent_type || '') !== agentType) return reason
  try {
    if (claim(payload.agent_id || payload.session_id || '')) return null
  } catch {
    return 'docs-fetcher denied: the gate could not record this call'
  }
  return 'docs-fetcher denied: this agent has already run docs-raw.sh once'
}

function main() {
  const [agentType, ...hosts] = process.argv.slice(2)
  const chunks = []
  let size = 0
  let done = false
  const finish = cut => {
    if (done) return
    done = true
    const raw = Buffer.concat(chunks).toString('utf8')
    let reason
    try {
      reason = judge(raw, { agentType, root: process.env.CLAUDE_PLUGIN_ROOT, hosts: hosts.map(h => h.toLowerCase()), cut })
    } catch {
      reason = agentType && agentTypeIn(raw) === agentType ? 'docs-fetcher denied: the gate failed' : null
    }
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
    if (size > MAX_STDIN) finish('overflow')
  })
  process.stdin.on('error', () => finish('error'))
  process.stdin.on('end', () => finish(''))
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) main()
