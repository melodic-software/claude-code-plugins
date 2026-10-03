#!/usr/bin/env node
// PreToolUse gate for the drift-audit workflow's web stage. Inside a
// multi-agent:drift-checker subagent, a WebFetch is allowed only to an https
// URL on a first-party docs host with no query string and no userinfo, so a
// checker that holds quoted repository claims cannot be steered into fetching
// an address that carries them out. Every other agent and the main thread pass
// through untouched.
//
// The hook input carries agent_type when the hook fires inside a subagent:
// https://code.claude.com/docs/en/hooks#common-input-fields (as of 2026-10-02;
// recheck when that table changes the agent_type field).
//
// Fail-closed inside drift-checker (a URL it cannot parse is denied);
// fail-open everywhere else.

import { pathToFileURL } from 'node:url'

export const FETCH_HOSTS = [
  'code.claude.com',
  'platform.claude.com',
  'docs.claude.com',
  'docs.anthropic.com',
  'www.anthropic.com',
]

export function decide(payload) {
  const agent = String((payload && payload.agent_type) || '')
  if (!/(^|:)drift-checker$/.test(agent)) return null
  if (payload.tool_name !== 'WebFetch') return 'drift-checker may only use WebFetch'
  let url
  try {
    url = new URL(String((payload.tool_input && payload.tool_input.url) || ''))
  } catch {
    return 'drift-checker fetch denied: the URL does not parse'
  }
  if (url.protocol !== 'https:') return 'drift-checker fetch denied: not an https URL'
  if (url.username || url.password) return 'drift-checker fetch denied: the URL carries userinfo'
  if (url.search) return 'drift-checker fetch denied: the URL carries a query string'
  if (!FETCH_HOSTS.includes(url.hostname.toLowerCase())) {
    return 'drift-checker fetch denied: ' + url.hostname + ' is not a first-party docs host (' + FETCH_HOSTS.join(', ') + ')'
  }
  return null
}

function main() {
  let raw = ''
  process.stdin.on('data', d => { raw += d })
  process.stdin.on('end', () => {
    let payload
    try {
      payload = JSON.parse(raw)
    } catch {
      return
    }
    const reason = decide(payload)
    if (reason) {
      process.stdout.write(JSON.stringify({
        hookSpecificOutput: { hookEventName: 'PreToolUse', permissionDecision: 'deny', permissionDecisionReason: reason },
      }))
    }
  })
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) main()
