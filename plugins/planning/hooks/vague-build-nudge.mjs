import { realpathSync } from 'node:fs'
import { resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

export const NUDGE =
  'planning vague-build check: this prompt asks to build something and states no problem, users or scope. ' +
  '/planning:interview is the planning plugin step that asks the user those before code is written.'

const BUILD = /^(?:please\s+)?(?:(?:let'?s\s+)?(?:add|build|implement|create|make|introduce|support|set\s+up)|we\s+need|i\s+(?:want|need))\b/i
const SCOPED = /\b(?:because|so\s+that|so\s+\w+\s+can|since|when|whenever|which|who|only|instead)\b|,/i
const CONCRETE = /[`/]|\b[\w-]+\.[a-z]{1,4}\b/i
const MAX_WORDS = 12

export function isVagueBuild(prompt) {
  const text = String(prompt ?? '').trim()
  if (!text || text.startsWith('/') || text.includes('?')) return false
  if (text.split(/\s+/).length > MAX_WORDS) return false
  return BUILD.test(text) && !SCOPED.test(text) && !CONCRETE.test(text.replace(/[.!]+$/, ''))
}

export function decide(payload) {
  if (!payload || typeof payload.prompt !== 'string' || !isVagueBuild(payload.prompt)) return null
  return { hookSpecificOutput: { hookEventName: 'UserPromptSubmit', additionalContext: NUDGE } }
}

async function main() {
  let text = ''
  process.stdin.setEncoding('utf8')
  for await (const chunk of process.stdin) text += chunk
  let payload = null
  try {
    payload = JSON.parse(text)
  } catch {
    return
  }
  const out = decide(payload)
  if (out) process.stdout.write(`${JSON.stringify(out)}\n`)
}

const self = (p) => {
  try {
    return realpathSync(p)
  } catch {
    return resolve(p)
  }
}
if (process.argv[1] && self(process.argv[1]) === self(fileURLToPath(import.meta.url))) {
  main()
    .catch(() => {})
    .finally(() => process.stdout.write('', () => process.exit(0)))
}
