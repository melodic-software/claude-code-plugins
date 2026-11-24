#!/usr/bin/env node

import { spawnSync } from 'node:child_process'
import crypto from 'node:crypto'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'
import { installedDataDir } from '../../route/scripts/lib/trials.mjs'

const PLUGIN_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', '..')
const ID_RE = /^[a-z0-9][a-z0-9-]*$/
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/
const CHECKS = ['live', 'dated', 'error_range', 'current_models']
const MARGIN_AUDITS = 1
const MARGIN_DAYS = 7
const MAX_AGE_DAYS = 365

const USAGE = [
  'Usage:',
  '  registry-history.mjs record --input <file> [--audits <n>] [--days <n>]',
  '                              [--user-file <role_map_file>] [--data-dir <dir>]',
  '',
  '--input holds the registry-audit workflow result, or its historyRecords array.',
  'Without --audits or --days, vendors.promotion_audits and vendors.promotion_days',
  'resolve through scripts/resolve-roles.sh.',
  '',
].join('\n')

function fail(msg) {
  const err = new Error(msg)
  err.exitCode = 2
  throw err
}

export function dayNumber(date) {
  if (typeof date !== 'string' || !DATE_RE.test(date)) return null
  const ms = Date.parse(`${date}T00:00:00Z`)
  if (!Number.isFinite(ms) || new Date(ms).toISOString().slice(0, 10) !== date) return null
  return Math.round(ms / 86400000)
}

export function resolveDataDir(explicitDir, env = process.env, root = PLUGIN_ROOT) {
  if (explicitDir) return path.resolve(explicitDir)
  const installed = installedDataDir(root)
  if (installed) return installed
  const given = env.CLAUDE_PLUGIN_DATA
  if (given && /^multi-agent-/.test(path.win32.basename(given))) return path.resolve(given)
  fail('CLAUDE_PLUGIN_DATA is unset or belongs to another plugin, and this copy is not an installed plugin, so there is nowhere to keep registry history')
}

export function validateRecord(raw) {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return null
  if (typeof raw.row_id !== 'string' || !ID_RE.test(raw.row_id)) return null
  if (dayNumber(raw.date) === null) return null
  const c = raw.checks
  if (!c || typeof c !== 'object' || !CHECKS.every(k => typeof c[k] === 'boolean')) return null
  return {
    row_id: raw.row_id,
    date: raw.date,
    checks: Object.fromEntries(CHECKS.map(k => [k, c[k]])),
  }
}

export function mergeRecords(existing, incoming) {
  const byDate = new Map()
  for (const r of [...existing, ...incoming]) byDate.set(r.date, r)
  return [...byDate.values()].sort((a, b) => dayNumber(a.date) - dayNumber(b.date))
}

function suffixMeeting(records, count, span) {
  const newest = dayNumber(records[records.length - 1].date)
  for (let i = records.length - 1; i >= 0; i--) {
    if (records.length - i >= count && newest - dayNumber(records[i].date) >= span) return i
  }
  return -1
}

export function retain(records, { audits, days }) {
  if (!records.length) return []
  const start = suffixMeeting(records, audits + MARGIN_AUDITS, days + MARGIN_DAYS)
  return start < 0 ? records : records.slice(start)
}

const passes = r => CHECKS.every(k => r.checks[k])

export function evaluatePromotion(records, { audits, days }) {
  const streak = []
  for (let i = records.length - 1; i >= 0 && passes(records[i]); i--) streak.unshift(records[i])
  const span = streak.length ? dayNumber(streak[streak.length - 1].date) - dayNumber(streak[0].date) : 0
  if (streak.length >= audits && span >= days) {
    return { promote: true, audits: streak.map(r => r.date) }
  }
  const failed = streak.length < records.length ? records[records.length - 1 - streak.length] : null
  const reason = failed
    ? `failed ${CHECKS.filter(k => !failed.checks[k]).join(', ')} on ${failed.date}; ${streak.length} passing audits since`
    : `${streak.length} passing audits over ${span} days; needs ${audits} over ${days}`
  return { promote: false, audits: streak.map(r => r.date), reason }
}

function readRowFile(file) {
  try {
    const doc = JSON.parse(fs.readFileSync(file, 'utf8'))
    return Array.isArray(doc.records) ? doc.records.map(validateRecord).filter(Boolean) : []
  } catch (err) {
    if (err.code === 'ENOENT') return []
    process.stderr.write(`registry-history: unreadable history file ${file} is replaced: ${err.message}\n`)
    return []
  }
}

function writeRowFile(dir, rowId, records) {
  const file = path.join(dir, `${rowId}.json`)
  const tmp = path.join(dir, `${rowId}.${process.pid}.${crypto.randomBytes(6).toString('hex')}.tmp`)
  fs.writeFileSync(tmp, `${JSON.stringify({ row_id: rowId, records }, null, 2)}\n`, 'utf8')
  fs.renameSync(tmp, file)
}

export function recordAudit({ dataDir, input, audits, days }) {
  const dir = path.join(dataDir, 'registry-history')
  fs.mkdirSync(dir, { recursive: true })
  const notes = []
  const incoming = new Map()
  const candidates = new Set()
  for (const raw of input) {
    const rec = validateRecord(raw)
    if (!rec) {
      notes.push('an invalid history record was skipped')
      continue
    }
    incoming.set(rec.row_id, rec)
    if (raw.source === 'shipped' && raw.status === 'support-only') candidates.add(rec.row_id)
  }

  const promotions = []
  const pending = []
  let dropped = 0
  let auditDay = null
  for (const [rowId, rec] of incoming) {
    const merged = mergeRecords(readRowFile(path.join(dir, `${rowId}.json`)), [rec])
    const kept = retain(merged, { audits, days })
    dropped += merged.length - kept.length
    writeRowFile(dir, rowId, kept)
    auditDay = Math.max(auditDay ?? -Infinity, dayNumber(rec.date))
    if (!candidates.has(rowId)) continue
    const verdict = evaluatePromotion(kept, { audits, days })
    if (verdict.promote) {
      promotions.push({
        source_id: rowId,
        field: 'status',
        from: 'support-only',
        to: 'permanent',
        reason: `passed every check in ${verdict.audits.length} audits from ${verdict.audits[0]} to ${verdict.audits[verdict.audits.length - 1]}`,
        audits: verdict.audits,
      })
    } else {
      pending.push({ source_id: rowId, reason: verdict.reason })
    }
  }

  let removedRows = 0
  if (auditDay !== null) {
    for (const name of fs.readdirSync(dir)) {
      if (!name.endsWith('.json') || incoming.has(name.slice(0, -5))) continue
      const recs = readRowFile(path.join(dir, name))
      const newest = recs.length ? dayNumber(recs[recs.length - 1].date) : null
      if (newest === null || auditDay - newest > MAX_AGE_DAYS) {
        fs.rmSync(path.join(dir, name), { force: true })
        removedRows++
      }
    }
  }

  const diff = promotions.length
    ? ['--- a/reference/benchmarks.json', '+++ b/reference/benchmarks.json',
      ...promotions.flatMap(p => [`@@ row ${p.source_id} @@`, '-  "status": "support-only"', '+  "status": "permanent"'])].join('\n')
    : null
  return { history_dir: dir, recorded: incoming.size, dropped, removed_rows: removedRows, promotions, pending, diff, notes }
}

function positiveInt(value, flag) {
  if (!/^[1-9]\d*$/.test(String(value))) fail(`${flag} must be an integer >= 1`)
  return Number(value)
}

function resolveSettings(userFile) {
  const args = [path.join(PLUGIN_ROOT, 'scripts', 'resolve-roles.sh'), 'worker', '--session-model', 'opus']
  if (userFile) args.push('--user-file', userFile)
  const res = spawnSync('bash', args, { encoding: 'utf8' })
  if (res.status !== 0) fail(`could not resolve the promotion settings: ${(res.stderr || '').trim().slice(0, 200)}`)
  const vendors = JSON.parse(res.stdout).vendors || {}
  return {
    audits: positiveInt(vendors.promotion_audits, 'vendors.promotion_audits'),
    days: positiveInt(vendors.promotion_days, 'vendors.promotion_days'),
  }
}

function parseCli(argv) {
  const [cmd, ...rest] = argv
  if (!cmd || cmd === '-h' || cmd === '--help') {
    process.stdout.write(USAGE)
    process.exit(cmd ? 0 : 2)
  }
  if (cmd !== 'record') fail(`unknown command: ${cmd}`)
  const allowed = new Set(['--input', '--audits', '--days', '--user-file', '--data-dir'])
  const opts = {}
  for (let i = 0; i < rest.length; i++) {
    if (!allowed.has(rest[i])) fail(`unknown argument: ${rest[i]}`)
    if (i + 1 >= rest.length) fail(`${rest[i]} requires a value`)
    opts[rest[i].slice(2)] = rest[++i]
  }
  if (!opts.input) fail('--input is required')
  return opts
}

function main() {
  try {
    const opts = parseCli(process.argv.slice(2))
    let doc
    try {
      doc = JSON.parse(fs.readFileSync(opts.input, 'utf8'))
    } catch (err) {
      fail(`cannot read --input (${opts.input}): ${err.message}`)
    }
    const input = Array.isArray(doc) ? doc : doc && Array.isArray(doc.historyRecords) ? doc.historyRecords : null
    if (!input) fail('--input must be a JSON array of history records or an object with historyRecords')
    const resolved = 'audits' in opts && 'days' in opts ? null : resolveSettings(opts['user-file'])
    const audits = 'audits' in opts ? positiveInt(opts.audits, '--audits') : resolved.audits
    const days = 'days' in opts ? positiveInt(opts.days, '--days') : resolved.days
    const result = recordAudit({ dataDir: resolveDataDir(opts['data-dir']), input, audits, days })
    process.stdout.write(`${JSON.stringify({ settings: { audits, days }, ...result }, null, 2)}\n`)
  } catch (err) {
    process.stderr.write(`registry-history: ${err.message}\n`)
    process.exit(err.exitCode || 1)
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) main()
