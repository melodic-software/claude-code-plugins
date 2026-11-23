#!/usr/bin/env node

import { pathToFileURL } from 'node:url'

export const MAX_STDIN_BYTES = 2 * 1024 * 1024
const IDLE_MS = 2000

const MARKER_LINE = /^\[(?:Content truncated\b[^\]\n]*|[^\]\n]*\bcontinues\b[^\]\n]*)\]$/
const READ_ON_NOTE = /^\[WebFetch note:[^\]\n]*\bto read on\b[^\]\n]*\boffset: \d+\.?\]$/

export const MAX_URL_CHARS = 200

export function pageName(raw) {
  let u
  try { u = new URL(String(raw)) } catch { return 'this page' }
  if (u.protocol !== 'https:' && u.protocol !== 'http:') return 'this page'
  const name = u.origin + u.pathname
  return name.length > MAX_URL_CHARS ? name.slice(0, MAX_URL_CHARS) + '...' : name
}

export function decide(payload) {
  if (payload?.tool_name !== 'WebFetch') return null
  const response = payload.tool_response
  const result = typeof response === 'string' ? response : response?.result
  if (typeof result !== 'string') return null
  const last = result.trimEnd().split('\n').pop().trim()
  const readOn = READ_ON_NOTE.test(last)
  if (!readOn && !MARKER_LINE.test(last)) return null
  const url = pageName(payload.tool_input?.url)
  const ending = readOn ? "WebFetch's read-on note" : 'a truncation placeholder'
  const next = readOn
    ? 'Call WebFetch again with the same url and the offset the note names to read on, or /discovery:read-docs'
    : '/discovery:read-docs'
  return `discovery: the WebFetch result for ${url} ends in ${ending}, so it covers only part of the page. ${next} reads the whole page, or the sections asked for, from the docs cache.`
}

function readStdin(done) {
  const chunks = []
  let size = 0
  let finished = false
  const finish = text => {
    if (finished) return
    finished = true
    clearTimeout(timer)
    process.stdin.destroy()
    done(text)
  }
  const timer = setTimeout(() => finish(null), IDLE_MS)
  process.stdin.on('data', chunk => {
    size += chunk.length
    if (size > MAX_STDIN_BYTES) return finish(null)
    chunks.push(chunk)
    timer.refresh()
  })
  process.stdin.on('end', () => finish(Buffer.concat(chunks).toString('utf8')))
  process.stdin.on('error', () => finish(null))
}

function main() {
  readStdin(raw => {
    if (!raw) return
    let payload
    try { payload = JSON.parse(raw) } catch { return }
    const context = decide(payload)
    if (context) {
      process.stdout.write(JSON.stringify({
        hookSpecificOutput: { hookEventName: 'PostToolUse', additionalContext: context },
      }))
    }
  })
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) main()
