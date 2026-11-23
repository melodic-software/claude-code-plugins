import { spawnSync } from 'node:child_process'
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const scriptsDir = dirname(dirname(fileURLToPath(import.meta.url)))
export const DECIDE = join(scriptsDir, 'vendor-decide')
export const FETCH_BOARDS = join(scriptsDir, 'fetch-boards')
export const PLUGIN_ROOT = join(scriptsDir, '..', '..', '..')
export const BENCHMARKS = join(PLUGIN_ROOT, 'reference', 'benchmarks.json')
export const REGISTRY_SCHEMA = join(PLUGIN_ROOT, 'schemas', 'benchmark-registry.schema.json')
export const VERDICT_SCHEMA = join(PLUGIN_ROOT, 'schemas', 'verdict-record.schema.json')
export const CONFIG_SCHEMA = join(PLUGIN_ROOT, 'schemas', 'multi-agent.schema.json')

export const NOW = '2026-11-22'
export const RECENT = '2026-11-18'
export const OLD_DATE = '2026-01-10'

export const MODELS = {
  claude: {
    status: 'ok',
    models: [{ id: 'kestrel-1', efforts: ['medium', 'high', 'max'], default_effort: 'medium' }],
    default_model: 'inherit',
    default_effort: 'medium',
  },
  codex: {
    status: 'ok',
    models: [{ id: 'sparrow-1', efforts: ['low', 'medium', 'high', 'xhigh'], default_effort: 'medium' }],
  },
  gemini: {
    status: 'ok',
    models: [{ id: 'finch-1' }],
    efforts: ['low', 'medium', 'high'],
  },
}

export function makeFixture(
  t,
  { registry, manifest, records, models = MODELS, settings = null, cwd = undefined, env = undefined, extraArgs = [] },
) {
  const dir = mkdtempSync(join(tmpdir(), 'vendor-decide-test-'))
  t.after(() => rmSync(dir, { recursive: true, force: true }))
  const regPath = join(dir, 'benchmarks.json')
  const manPath = join(dir, 'manifest.json')
  const modPath = join(dir, 'models.json')
  writeFileSync(regPath, JSON.stringify(registry, null, 2))
  writeFileSync(manPath, JSON.stringify(manifest, null, 2))
  writeFileSync(modPath, JSON.stringify(models, null, 2))

  const args = [DECIDE, '--registry', regPath, '--manifest', manPath, '--models', modPath, '--now', NOW, ...extraArgs]

  if (settings !== null) {
    const setPath = join(dir, 'settings.json')
    writeFileSync(setPath, JSON.stringify(settings, null, 2))
    args.push('--settings', setPath)
  }

  if (Array.isArray(records) || (records && !records.__perSource)) {
    const recPath = join(dir, 'records.json')
    writeFileSync(recPath, JSON.stringify(records, null, 2))
    args.push('--records', recPath)
  } else if (records && records.__perSource) {
    for (const [sourceId, payload] of Object.entries(records.sources)) {
      const p = join(dir, `records-${sourceId}.json`)
      writeFileSync(p, JSON.stringify(payload, null, 2))
      args.push('--records', `${sourceId}=${p}`)
    }
  }

  const res = spawnSync(process.execPath, args, { encoding: 'utf8', cwd, env })
  return {
    code: res.status,
    stdout: res.stdout,
    stderr: res.stderr,
    json: res.status === 0 ? JSON.parse(res.stdout) : null,
  }
}

export function row(id, overrides = {}) {
  return {
    id,
    workloads: ['coding'],
    link: `https://${id}.example/board`,
    publisher: `pub-${id}`,
    provider_own: false,
    status: 'permanent',
    task_set: `set-${id}`,
    expect: id,
    ...overrides,
  }
}

export function boardEntry(sourceId, overrides = {}) {
  return {
    source_id: sourceId,
    url: `https://${sourceId}.example/board`,
    source: 'fetch',
    state: 'read',
    stale: false,
    reason: null,
    age_seconds: 0,
    page_date: RECENT,
    file: `/tmp/${sourceId}.md`,
    ...overrides,
  }
}

export function rec(sourceId, vendor, model, verdict, overrides = {}) {
  return {
    source_id: sourceId,
    workload: 'coding',
    vendor,
    model,
    version: '1',
    effort: 'high',
    verdict,
    error_range: true,
    page_date: RECENT,
    read: 'live',
    ...overrides,
  }
}

export function gitCleanEnv() {
  return {
    ...process.env,
    GIT_CONFIG_GLOBAL: process.platform === 'win32' ? 'NUL' : '/dev/null',
    GIT_CONFIG_NOSYSTEM: '1',
  }
}
