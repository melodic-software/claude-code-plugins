import { spawnSync } from 'node:child_process'
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
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
  {
    registry,
    manifest,
    records,
    models = MODELS,
    settings = null,
    stateDir = null,
    cwd = undefined,
    env = undefined,
    extraArgs = [],
  },
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

  if (stateDir !== null) {
    args.push('--state-dir', stateDir)
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

export function twoBoards(t, records, overrides = {}) {
  return makeFixture(t, {
    registry: { version: 1, rows: [row('board-a'), row('board-b')] },
    manifest: { boards: [boardEntry('board-a'), boardEntry('board-b')] },
    records,
    extraArgs: ['--task-type', 'coding'],
    ...overrides,
  })
}

export function seedOutcome(t, outcomes) {
  const dir = mkdtempSync(join(tmpdir(), 'vendor-decide-outcomes-'))
  t.after(() => rmSync(dir, { recursive: true, force: true }))
  const outDir = join(dir, 'outcomes')
  mkdirSync(outDir, { recursive: true })
  outcomes.forEach((doc, idx) => {
    writeFileSync(join(outDir, `outcome-${idx}.json`), JSON.stringify(doc, null, 2))
  })
  return dir
}

export function codexLeadRecords(overrides = {}) {
  return [
    rec('board-a', 'codex', 'sparrow-1', 'lead', overrides),
    rec('board-a', 'claude', 'kestrel-1', 'behind'),
    rec('board-b', 'codex', 'sparrow-1', 'lead', overrides),
    rec('board-b', 'claude', 'kestrel-1', 'behind'),
  ]
}

export function tieWithTokensRecords() {
  return [
    rec('board-a', 'claude', 'kestrel-1', 'tie', { tokens: { value: 140000, unit: 'tokens/task', source: 'board-a' } }),
    rec('board-a', 'codex', 'sparrow-1', 'tie', { tokens: { value: 90000, unit: 'tokens/task', source: 'board-a' } }),
    rec('board-b', 'claude', 'kestrel-1', 'tie', { tokens: { value: 160000, unit: 'tokens/task', source: 'board-b' } }),
    rec('board-b', 'codex', 'sparrow-1', 'tie', { tokens: { value: 110000, unit: 'tokens/task', source: 'board-b' } }),
  ]
}

export function runFetchBoardsCacheFixture(t) {
  const dir = mkdtempSync(join(tmpdir(), 'fetch-boards-test-'))
  t.after(() => rmSync(dir, { recursive: true, force: true }))
  const fixtureDir = join(dir, 'fixtures')
  const cacheDir = join(dir, 'cache')
  const out1 = join(dir, 'out1')
  const out2 = join(dir, 'out2')
  const regPath = join(dir, 'benchmarks.json')

  mkdirSync(join(fixtureDir, 'www-tbench-ai'), { recursive: true })
  writeFileSync(
    join(fixtureDir, 'www-tbench-ai', 'leaderboard.md'),
    '# Terminal-Bench Leaderboard\n\nUpdated 2026-11-18\n\n| Model | Score | CI |\n|---|---|---|\n| sparrow-1 | 82.0% | +/- 1.1% |\n| kestrel-1 | 78.0% | +/- 1.2% |\n',
  )
  writeFileSync(
    regPath,
    JSON.stringify({
      version: 1,
      rows: [
        {
          id: 'terminal-bench',
          workloads: ['coding'],
          link: 'https://www.tbench.ai/leaderboard',
          publisher: 'tbench.ai',
          provider_own: false,
          status: 'permanent',
          task_set: 'terminal-bench',
          expect: 'Terminal-Bench',
          freshness_seconds: 3600,
        },
      ],
    }),
  )

  const toPosix = (p) => p.replace(/\\/g, '/')
  const nowSec = Math.floor(Date.UTC(2026, 10, 22, 12, 0, 0) / 1000)
  const env = {
    ...process.env,
    FETCH_DOCS_FIXTURE_DIR: toPosix(fixtureDir),
    DOCS_CACHE_DIR: toPosix(cacheDir),
    DOCS_CACHE_NOW: String(nowSec),
  }
  const runOnce = (outDir, extraEnv = {}) =>
    spawnSync(
      'bash',
      [
        toPosix(FETCH_BOARDS),
        '--registry', toPosix(regPath),
        '--out', toPosix(outDir),
        '--manifest', toPosix(join(outDir, 'manifest.json')),
        '--cache-dir', toPosix(cacheDir),
      ],
      { encoding: 'utf8', env: { ...env, ...extraEnv } },
    )
  const run1 = runOnce(out1)
  const run2 = runOnce(out2, { DOCS_CACHE_NOW: String(nowSec + 100) })
  return {
    run1,
    run2,
    m1: run1.status === 0 ? JSON.parse(readFileSync(join(out1, 'manifest.json'), 'utf8')) : null,
    m2: run2.status === 0 ? JSON.parse(readFileSync(join(out2, 'manifest.json'), 'utf8')) : null,
  }
}

export function runFetchBoardsOnce(t, rows, pages, { settings } = {}) {
  const dir = mkdtempSync(join(tmpdir(), 'fetch-boards-test-'))
  t.after(() => rmSync(dir, { recursive: true, force: true }))
  const fixtureDir = join(dir, 'fixtures')
  const outDir = join(dir, 'out')
  const regPath = join(dir, 'benchmarks.json')
  for (const [relPath, body] of Object.entries(pages)) {
    mkdirSync(dirname(join(fixtureDir, relPath)), { recursive: true })
    writeFileSync(join(fixtureDir, relPath), body)
  }
  writeFileSync(regPath, JSON.stringify({ version: 1, rows }))
  const toPosix = (p) => p.replace(/\\/g, '/')
  const args = [
    toPosix(FETCH_BOARDS),
    '--registry', toPosix(regPath),
    '--out', toPosix(outDir),
    '--cache-dir', toPosix(join(dir, 'cache')),
  ]
  if (settings) {
    const setPath = join(dir, 'settings.json')
    writeFileSync(setPath, JSON.stringify(settings))
    args.push('--settings', toPosix(setPath))
  }
  const res = spawnSync(
    'bash',
    args,
    {
      encoding: 'utf8',
      env: {
        ...process.env,
        FETCH_DOCS_FIXTURE_DIR: toPosix(fixtureDir),
        DOCS_CACHE_DIR: toPosix(join(dir, 'cache')),
        DOCS_CACHE_NOW: String(Math.floor(Date.UTC(2026, 10, 22, 12, 0, 0) / 1000)),
      },
    },
  )
  return {
    res,
    manifest: res.status === 0 ? JSON.parse(readFileSync(join(outDir, 'manifest.json'), 'utf8')) : null,
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
