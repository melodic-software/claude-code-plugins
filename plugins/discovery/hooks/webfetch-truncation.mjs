#!/usr/bin/env node
// PostToolUse WebFetch hook. When a WebFetch result ends in a truncation
// marker or placeholder line, it adds one line of context saying the result
// covers only part of the page and naming /discovery:read-docs. It never
// blocks and never changes the result.
//
// Detection is structural: the last non-blank line of tool_response.result is
// one bracketed line that starts "[Content truncated" or contains "continues"
// (the phrasings seen in captured payloads and in the visible-text probe,
// fixtures/ and the plugin README), or WebFetch's own read-on note: a
// bracketed line that starts "[WebFetch note:" and ends "to read on, ...
// offset: N." (a note naming "offset" elsewhere, such as in a redirect
// target's query, is not one). That note
// comes with WebFetch's optional `offset` input, so for it the context line
// names re-reading with that offset first. Probed on Claude Code 2.1.296,
// 2026-10-10; evidence in the pull request that carries this change. For what
// WebFetch documents about pages over its read cap, fetch
// https://code.claude.com/docs/en/tools-reference#webfetch-tool-behavior live
// (as of 2026-10-10); recheck when that section documents the note text or the
// `offset` input. There is no length rule, so a page WebFetch summarized with
// no marker goes unflagged; the README says so.
//
// tool_response's shape for WebFetch is not documented on the hooks page
// (https://code.claude.com/docs/en/hooks#posttooluse-input says it "depends on
// the tool"; as of 2026-10-04). The shape used here, an object whose `result`
// holds the text, comes from the captured fixtures (Claude Code 2.1.289).
// Recheck when a capture shows a different shape.
//
// Fail-open: unreadable, oversized or late stdin, or any other shape, prints
// nothing.

import { pathToFileURL } from 'node:url'

export const MAX_STDIN_BYTES = 2 * 1024 * 1024
const IDLE_MS = 2000

const MARKER_LINE = /^\[(?:Content truncated\b[^\]\n]*|[^\]\n]*\bcontinues\b[^\]\n]*)\]$/
const READ_ON_NOTE = /^\[WebFetch note:[^\]\n]*\bto read on\b[^\]\n]*\boffset: \d+\.?\]$/

export const MAX_URL_CHARS = 200

// The requested URL as the context line names it: an http(s) URL's origin and
// path, percent-encoded by the URL parser and cut at MAX_URL_CHARS, so the
// query, the fragment and raw text the model chose never reach the context.
export function pageName(raw) {
  let u
  try { u = new URL(String(raw)) } catch { return 'this page' }
  if (u.protocol !== 'https:' && u.protocol !== 'http:') return 'this page'
  const name = u.origin + u.pathname
  return name.length > MAX_URL_CHARS ? name.slice(0, MAX_URL_CHARS) + '...' : name
}

export function decide(payload) {
  if (!payload || payload.tool_name !== 'WebFetch') return null
  const response = payload.tool_response
  const result = typeof response === 'string' ? response : response && response.result
  if (typeof result !== 'string') return null
  const lines = result.trimEnd().split('\n')
  const last = lines[lines.length - 1].trim()
  const readOn = READ_ON_NOTE.test(last)
  if (!readOn && !MARKER_LINE.test(last)) return null
  const url = pageName(payload.tool_input && payload.tool_input.url)
  // The placeholder line itself is fetched text, so it is never echoed back,
  // not even the offset a read-on note names.
  if (readOn) return `discovery: the WebFetch result for ${url} ends in WebFetch's read-on note, so it covers only part of the page. Call WebFetch again with the same url and the offset the note names to read on, or /discovery:read-docs reads the whole page, or the sections asked for, from the docs cache.`
  return `discovery: the WebFetch result for ${url} ends in a truncation placeholder, so it covers only part of the page. /discovery:read-docs reads the whole page, or the sections asked for, from the docs cache.`
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
  let timer = setTimeout(() => finish(null), IDLE_MS)
  process.stdin.on('data', chunk => {
    size += chunk.length
    if (size > MAX_STDIN_BYTES) return finish(null)
    chunks.push(chunk)
    clearTimeout(timer)
    timer = setTimeout(() => finish(null), IDLE_MS)
  })
  process.stdin.on('end', () => finish(Buffer.concat(chunks).toString('utf8')))
  process.stdin.on('error', () => finish(null))
}

function main() {
  readStdin(raw => {
    if (!raw) return
    let payload
    try {
      payload = JSON.parse(raw)
    } catch {
      return
    }
    const context = decide(payload)
    if (context) {
      process.stdout.write(JSON.stringify({
        hookSpecificOutput: { hookEventName: 'PostToolUse', additionalContext: context },
      }))
    }
  })
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) main()
