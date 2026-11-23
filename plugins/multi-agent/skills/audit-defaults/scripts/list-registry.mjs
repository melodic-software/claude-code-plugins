#!/usr/bin/env node

import { spawnSync } from 'node:child_process'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

const WORK_TYPES = new Set(['coding', 'web-ui', 'knowledge', 'image'])
const ROW_STATUSES = new Set(['permanent', 'support-only'])
const ID_RE = /^[a-z0-9][a-z0-9-]*$/
const TOP_KEYS = new Set(['version', 'note', 'rows'])
const ROW_KEYS = new Set([
  'id',
  'workloads',
  'link',
  'publisher',
  'provider_own',
  'status',
  'task_set',
  'expect',
  'freshness_seconds',
  'enabled',
])

const PLUGIN_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', '..')

function fail(msg) {
  const err = new Error(msg)
  err.exitCode = 2
  throw err
}

function readJson(filePath, label) {
  let raw
  try {
    raw = fs.readFileSync(filePath, 'utf8')
  } catch (err) {
    fail(`cannot read ${label} (${filePath}): ${err.message}`)
  }
  try {
    return JSON.parse(raw)
  } catch (err) {
    fail(`invalid JSON in ${label} (${filePath}): ${err.message}`)
  }
}

export function validateRegistry(doc, label) {
  if (!doc || typeof doc !== 'object' || Array.isArray(doc)) fail(`${label} must be a JSON object`)
  for (const k of Object.keys(doc)) {
    if (!TOP_KEYS.has(k)) fail(`${label} has unknown field '${k}'`)
  }
  if (doc.version !== 1) fail(`${label} version must be 1`)
  if ('note' in doc && (typeof doc.note !== 'string' || doc.note.length === 0)) {
    fail(`${label} note must be a non-empty string`)
  }
  if (!Array.isArray(doc.rows)) fail(`${label} rows must be an array`)

  const seen = new Set()
  for (let i = 0; i < doc.rows.length; i++) {
    const r = doc.rows[i]
    const ctx = `${label}.rows[${i}]`
    if (!r || typeof r !== 'object' || Array.isArray(r)) fail(`${ctx} must be an object`)
    for (const k of Object.keys(r)) {
      if (!ROW_KEYS.has(k)) fail(`${ctx} has unknown field '${k}'`)
    }
    if (typeof r.id !== 'string' || !ID_RE.test(r.id)) fail(`${ctx}.id is invalid`)
    if (seen.has(r.id)) fail(`${label} has duplicate row id '${r.id}'`)
    seen.add(r.id)
    if (!Array.isArray(r.workloads) || r.workloads.length === 0) {
      fail(`${ctx}.workloads must be a non-empty array`)
    }
    const wlSeen = new Set()
    for (const w of r.workloads) {
      if (!WORK_TYPES.has(w) || wlSeen.has(w)) fail(`${ctx}.workloads has invalid or duplicate entry '${w}'`)
      wlSeen.add(w)
    }
    if (typeof r.link !== 'string' || !r.link.startsWith('https://')) fail(`${ctx}.link must be an https URL`)
    if (typeof r.publisher !== 'string' || r.publisher.length === 0) fail(`${ctx}.publisher must be a non-empty string`)
    if (typeof r.provider_own !== 'boolean') fail(`${ctx}.provider_own must be a boolean`)
    if (!ROW_STATUSES.has(r.status)) fail(`${ctx}.status must be permanent or support-only`)
    if (typeof r.task_set !== 'string' || r.task_set.length === 0) fail(`${ctx}.task_set must be a non-empty string`)
    if (typeof r.expect !== 'string' || r.expect.length === 0) fail(`${ctx}.expect must be a non-empty string`)
    if ('freshness_seconds' in r && (!Number.isInteger(r.freshness_seconds) || r.freshness_seconds < 1)) {
      fail(`${ctx}.freshness_seconds must be a positive integer`)
    }
    if ('enabled' in r && typeof r.enabled !== 'boolean') fail(`${ctx}.enabled must be a boolean`)
  }
  return doc
}

function detectRepoRoot(cwd) {
  const res = spawnSync('git', ['rev-parse', '--show-toplevel'], { cwd, encoding: 'utf8' })
  if (res.status !== 0 || !res.stdout) return null
  return res.stdout.trim() || null
}

export function listRegistry({
  shippedPath = path.join(PLUGIN_ROOT, 'reference', 'benchmarks.json'),
  repoRoot = undefined,
  cwd = process.cwd(),
} = {}) {
  const shipped = validateRegistry(readJson(shippedPath, 'shipped registry'), 'shipped registry')
  const shippedIds = new Set(shipped.rows.map(r => r.id))
  const rows = shipped.rows.map(r => ({ ...r, enabled: r.enabled !== false, source: 'shipped' }))
  const notes = []

  const root = repoRoot === undefined ? detectRepoRoot(cwd) : repoRoot
  if (root) {
    const teamPath = path.join(root, 'docs', 'conventions', 'multi-agent', 'benchmarks.json')
    if (fs.existsSync(teamPath) && path.resolve(teamPath) !== path.resolve(shippedPath)) {
      const team = validateRegistry(readJson(teamPath, 'team registry'), 'team registry')
      for (const r of team.rows) {
        if (shippedIds.has(r.id)) {
          notes.push(`team registry row '${r.id}' refused: duplicates shipped row id`)
          continue
        }
        rows.push({ ...r, enabled: r.enabled !== false, source: 'team' })
      }
    }
  }
  return { rows, notes }
}

function parseCli(argv) {
  let json = false
  let root = undefined
  let shipped = path.join(PLUGIN_ROOT, 'reference', 'benchmarks.json')
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i]
    if (a === '--json') {
      json = true
    } else if (a === '--root') {
      if (i + 1 >= argv.length) fail('--root requires a directory')
      root = argv[++i]
    } else if (a === '--registry') {
      if (i + 1 >= argv.length) fail('--registry requires a file path')
      shipped = argv[++i]
    } else if (a === '-h' || a === '--help') {
      process.stdout.write('Usage: list-registry.mjs [--json] [--root <dir>] [--registry <file>]\n')
      process.exit(0)
    } else {
      fail(`unknown argument: ${a}`)
    }
  }
  return { json, root, shipped }
}

function main() {
  try {
    const opts = parseCli(process.argv.slice(2))
    const result = listRegistry({ shippedPath: opts.shipped, repoRoot: opts.root })
    if (opts.json) {
      process.stdout.write(`${JSON.stringify(result, null, 2)}\n`)
    } else {
      for (const r of result.rows) {
        process.stdout.write(`${r.id}\t${r.source}\t${r.status}\t${r.workloads.join(',')}\t${r.link}\n`)
      }
      for (const n of result.notes) process.stderr.write(`list-registry: ${n}\n`)
    }
  } catch (err) {
    process.stderr.write(`list-registry: ${err.message}\n`)
    process.exit(err.exitCode || 2)
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) main()
