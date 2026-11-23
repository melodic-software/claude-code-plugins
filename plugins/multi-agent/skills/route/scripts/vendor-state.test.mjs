import { test } from 'node:test'
import assert from 'node:assert/strict'
import { spawn, spawnSync } from 'node:child_process'
import { copyFileSync, existsSync, mkdtempSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { hostname, tmpdir } from 'node:os'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const STATE = join(here, 'vendor-state')
const DECIDE = join(here, 'vendor-decide')

const NOW = '2026-11-22'
const RECENT = '2026-11-18'

const MODELS = {
  claude: {
    status: 'ok',
    models: [{ id: 'kestrel-1', version: '1', efforts: ['medium', 'high', 'max'], default_effort: 'medium' }],
    default_model: 'inherit',
    default_effort: 'medium',
  },
  codex: {
    status: 'ok',
    models: [{ id: 'sparrow-1', version: '1', efforts: ['low', 'medium', 'high', 'xhigh'], default_effort: 'high' }],
    default_model: 'sparrow-1',
    default_effort: 'high',
  },
  gemini: {
    status: 'ok',
    models: [{ id: 'finch-1', version: '1' }],
    efforts: ['low', 'medium', 'high'],
    default_model: 'finch-1',
    default_effort: 'high',
  },
}

function makeTempDir(t, prefix = 'vendor-state-test-') {
  const dir = mkdtempSync(join(tmpdir(), prefix))
  t.after(() => rmSync(dir, { recursive: true, force: true }))
  return dir
}

function listFilesRecursive(dir) {
  if (!existsSync(dir)) return []
  const out = []
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const full = join(dir, entry.name)
    if (entry.isDirectory()) out.push(...listFilesRecursive(full))
    else out.push(full)
  }
  return out
}

function runState(args, { env = undefined, script = STATE } = {}) {
  const cleanEnv = env ?? { ...process.env }
  if (!env) delete cleanEnv.CLAUDE_PLUGIN_DATA
  const res = spawnSync(process.execPath, [script, ...args], { encoding: 'utf8', env: cleanEnv })
  let json = null
  if (res.status === 0 && res.stdout.trim()) {
    json = JSON.parse(res.stdout)
  }
  return { code: res.status, stdout: res.stdout, stderr: res.stderr, json }
}

function runStateAsync(args, { env = undefined, script = STATE } = {}) {
  const cleanEnv = env ?? { ...process.env }
  if (!env) delete cleanEnv.CLAUDE_PLUGIN_DATA
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [script, ...args], { env: cleanEnv, stdio: ['ignore', 'pipe', 'pipe'] })
    let stdout = ''
    let stderr = ''
    child.stdout.on('data', (chunk) => { stdout += chunk.toString() })
    child.stderr.on('data', (chunk) => { stderr += chunk.toString() })
    child.on('error', reject)
    child.on('close', (code) => {
      let json = null
      if (code === 0 && stdout.trim()) {
        try {
          json = JSON.parse(stdout)
        } catch {
          json = null
        }
      }
      resolve({ code, stdout, stderr, json })
    })
  })
}

function writeSettings(dir, vendors) {
  const file = join(dir, `settings-${Math.random().toString(16).slice(2)}.json`)
  writeFileSync(file, JSON.stringify({ vendors }, null, 2))
  return file
}

function runDecideFixture(t, { registry, manifest, records, models = MODELS, settings = null, stateDir = null, extraArgs = [] }) {
  const dir = makeTempDir(t, 'vendor-decide-state-')
  const regPath = join(dir, 'benchmarks.json')
  const manPath = join(dir, 'manifest.json')
  const modPath = join(dir, 'models.json')
  const recPath = join(dir, 'records.json')
  writeFileSync(regPath, JSON.stringify(registry, null, 2))
  writeFileSync(manPath, JSON.stringify(manifest, null, 2))
  writeFileSync(modPath, JSON.stringify(models, null, 2))
  writeFileSync(recPath, JSON.stringify(records, null, 2))

  const args = [
    DECIDE,
    '--registry', regPath,
    '--manifest', manPath,
    '--models', modPath,
    '--records', recPath,
    '--now', NOW,
    ...extraArgs,
  ]
  if (settings !== null) {
    const setPath = join(dir, 'settings.json')
    writeFileSync(setPath, JSON.stringify(settings, null, 2))
    args.push('--settings', setPath)
  }
  if (stateDir !== null) {
    args.push('--state-dir', stateDir)
  }

  const cleanEnv = { ...process.env }
  delete cleanEnv.CLAUDE_PLUGIN_DATA
  const res = spawnSync(process.execPath, args, { encoding: 'utf8', env: cleanEnv })
  return {
    code: res.status,
    stdout: res.stdout,
    stderr: res.stderr,
    json: res.status === 0 ? JSON.parse(res.stdout) : null,
  }
}

function row(id, overrides = {}) {
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

function boardEntry(sourceId, overrides = {}) {
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

function rec(sourceId, vendor, model, verdict, overrides = {}) {
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

test('D15: foreign CLAUDE_PLUGIN_DATA is refused with exit 2 and writes nothing', (t) => {
  const dir = makeTempDir(t)
  const foreignDir = join(dir, 'external-agents-marketplace')
  mkdirSync(foreignDir, { recursive: true })
  const res = runState(['outcome', '--key', 'codex:sparrow-1:1:high:coding'], {
    env: { ...process.env, CLAUDE_PLUGIN_DATA: foreignDir },
  })
  assert.equal(res.code, 2)
  assert.match(res.stderr, /CLAUDE_PLUGIN_DATA|another plugin|multi-agent-/i)
  assert.deepEqual(listFilesRecursive(foreignDir), [])

  const unsetEnv = { ...process.env }
  delete unsetEnv.CLAUDE_PLUGIN_DATA
  const resUnset = runState(['outcome', '--key', 'codex:sparrow-1:1:high:coding'], { env: unsetEnv })
  assert.equal(resUnset.code, 2)
  assert.match(resUnset.stderr, /CLAUDE_PLUGIN_DATA/i)
})

test('D15: own CLAUDE_PLUGIN_DATA works when uninstalled; install path wins over foreign CLAUDE_PLUGIN_DATA', (t) => {
  const dir = makeTempDir(t)
  const ownDir = join(dir, 'multi-agent-example')
  mkdirSync(ownDir, { recursive: true })
  const resOwn = runState(['outcome', '--key', 'codex:sparrow-1:1:high:coding'], {
    env: { ...process.env, CLAUDE_PLUGIN_DATA: ownDir },
  })
  assert.equal(resOwn.code, 0, resOwn.stderr)
  assert.equal(resOwn.json.result, 'none')

  const installedScript = join(
    dir,
    'plugins',
    'cache',
    'acme-mkt',
    'multi-agent',
    '1.0.0',
    'skills',
    'route',
    'scripts',
    'vendor-state',
  )
  mkdirSync(dirname(installedScript), { recursive: true })
  copyFileSync(STATE, installedScript)

  const foreignDir = join(dir, 'other-plugin-acme')
  mkdirSync(foreignDir, { recursive: true })
  const resInstalled = runState(
    ['seen', '--vendor', 'codex', '--ids', 'sparrow-1'],
    {
      script: installedScript,
      env: { ...process.env, CLAUDE_PLUGIN_DATA: foreignDir },
    },
  )
  assert.equal(resInstalled.code, 0, resInstalled.stderr)
  const expectedData = join(dir, 'plugins', 'data', 'multi-agent-acme-mkt', 'vendor-state', 'seen', 'codex.json')
  assert.equal(existsSync(expectedData), true, `expected ${expectedData} to exist`)
  assert.deepEqual(listFilesRecursive(foreignDir), [])
})

test('AC10/AC11: record writes nothing and exits 0 with a note when trials are off, counts unset, or routing off', (t) => {
  const dataDir = makeTempDir(t)
  const cfgDir = makeTempDir(t)
  const cases = [
    { routing: true, trials: false, trials_prove: 2, trials_fail: 2 },
    { routing: true, trials: true },
    { routing: true, trials: true, trials_prove: 2, trials_fail: null },
    { routing: true, trials: true, trials_prove: null, trials_fail: 2 },
    { routing: false, trials: true, trials_prove: 2, trials_fail: 2 },
  ]
  for (const vendors of cases) {
    const settingsPath = writeSettings(cfgDir, vendors)
    const res = runState([
      'record',
      '--key', 'codex:sparrow-1:1:high:coding',
      '--verdict', 'accepted',
      '--settings', settingsPath,
      '--data-dir', dataDir,
    ])
    assert.equal(res.code, 0, res.stderr)
    assert.equal(res.json.recorded, false)
    assert.ok(typeof res.json.note === 'string' && res.json.note.length > 0)
    assert.deepEqual(listFilesRecursive(dataDir), [])
  }
})

test('record writes one TrialResult per call, promotes to machine-neutral Outcome at threshold, and deletes trial folder', (t) => {
  const dataDir = makeTempDir(t)
  const cfgDir = makeTempDir(t)
  const settingsPath = writeSettings(cfgDir, {
    routing: true,
    trials: true,
    trials_prove: 2,
    trials_fail: 2,
  })
  const key = 'codex:sparrow-1:1:high:coding'

  const r1 = runState([
    'record', '--key', key, '--verdict', 'accepted', '--tokens', '12000',
    '--settings', settingsPath, '--data-dir', dataDir,
  ])
  assert.equal(r1.code, 0, r1.stderr)
  assert.equal(r1.json.recorded, true)
  assert.equal(r1.json.outcome, null)

  const trialFilesAfter1 = listFilesRecursive(join(dataDir, 'vendor-state', 'trials'))
  assert.equal(trialFilesAfter1.length, 1)
  const trialContent = JSON.parse(readFileSync(trialFilesAfter1[0], 'utf8'))
  assert.equal(trialContent.verdict, 'accepted')
  assert.equal(trialContent.tokens, 12000)
  assert.equal(trialContent.key.work_type, 'coding')

  const oBefore = runState(['outcome', '--key', key, '--data-dir', dataDir])
  assert.equal(oBefore.code, 0, oBefore.stderr)
  assert.equal(oBefore.json.result, 'none')

  const r2 = runState([
    'record', '--key', key, '--verdict', 'accepted',
    '--settings', settingsPath, '--data-dir', dataDir,
  ])
  assert.equal(r2.code, 0, r2.stderr)
  assert.equal(r2.json.outcome.result, 'proven')

  const trialFilesAfter2 = listFilesRecursive(join(dataDir, 'vendor-state', 'trials'))
  assert.deepEqual(trialFilesAfter2, [])

  const outcomeFiles = listFilesRecursive(join(dataDir, 'vendor-state', 'outcomes'))
  assert.equal(outcomeFiles.length, 1)
  const rawOutcome = readFileSync(outcomeFiles[0], 'utf8')
  assert.equal(rawOutcome.includes(dataDir), false, 'Outcome must not contain absolute paths')
  assert.equal(rawOutcome.includes(hostname()), false, 'Outcome must not contain host name')

  const oAfter = runState(['outcome', '--key', key, '--data-dir', dataDir])
  assert.equal(oAfter.code, 0, oAfter.stderr)
  assert.equal(oAfter.json.result, 'proven')
  assert.deepEqual(oAfter.json.key, {
    vendor: 'codex',
    model: 'sparrow-1',
    version: '1',
    effort: 'high',
    work_type: 'coding',
  })

  const oOtherWorkType = runState(['outcome', '--key', 'codex:sparrow-1:1:high:web-ui', '--data-dir', dataDir])
  assert.equal(oOtherWorkType.code, 0, oOtherWorkType.stderr)
  assert.equal(oOtherWorkType.json.result, 'none')
})

test('D16: two writers crossing the prove threshold concurrently produce exactly one Outcome and no leftover trials', async (t) => {
  const dataDir = makeTempDir(t)
  const cfgDir = makeTempDir(t)
  const settingsPath = writeSettings(cfgDir, {
    routing: true,
    trials: true,
    trials_prove: 2,
    trials_fail: 2,
  })
  const key = 'codex:sparrow-1:1:high:coding'

  const [a, b] = await Promise.all([
    runStateAsync(['record', '--key', key, '--verdict', 'accepted', '--settings', settingsPath, '--data-dir', dataDir]),
    runStateAsync(['record', '--key', key, '--verdict', 'accepted', '--settings', settingsPath, '--data-dir', dataDir]),
  ])
  assert.ok([0, 3].includes(a.code), `unexpected exit ${a.code}: ${a.stderr}`)
  assert.ok([0, 3].includes(b.code), `unexpected exit ${b.code}: ${b.stderr}`)
  assert.ok(a.code === 0 || b.code === 0)

  const outcomeFiles = listFilesRecursive(join(dataDir, 'vendor-state', 'outcomes'))
  assert.equal(outcomeFiles.length, 1)
  const outcomeDoc = JSON.parse(readFileSync(outcomeFiles[0], 'utf8'))
  assert.equal(outcomeDoc.result, 'proven')
  assert.deepEqual(listFilesRecursive(join(dataDir, 'vendor-state', 'trials')), [])

  const dataDir2 = makeTempDir(t)
  const pre = runState(['record', '--key', key, '--verdict', 'accepted', '--settings', settingsPath, '--data-dir', dataDir2])
  assert.equal(pre.code, 0, pre.stderr)
  const [c, d] = await Promise.all([
    runStateAsync(['record', '--key', key, '--verdict', 'accepted', '--settings', settingsPath, '--data-dir', dataDir2]),
    runStateAsync(['record', '--key', key, '--verdict', 'accepted', '--settings', settingsPath, '--data-dir', dataDir2]),
  ])
  assert.ok([0, 3].includes(c.code), `unexpected exit ${c.code}: ${c.stderr}`)
  assert.ok([0, 3].includes(d.code), `unexpected exit ${d.code}: ${d.stderr}`)
  assert.ok(c.code === 0 || d.code === 0)
  assert.equal(listFilesRecursive(join(dataDir2, 'vendor-state', 'outcomes')).length, 1)
  assert.deepEqual(listFilesRecursive(join(dataDir2, 'vendor-state', 'trials')), [])
})

test('D16/AC19: record after an Outcome is refused (exit 3); proven key re-enters trial only through send-back', (t) => {
  const dataDir = makeTempDir(t)
  const cfgDir = makeTempDir(t)
  const settingsPath = writeSettings(cfgDir, {
    routing: true,
    trials: true,
    trials_prove: 1,
    trials_fail: 2,
  })
  const key = 'codex:sparrow-1:1:high:coding'

  const prove = runState(['record', '--key', key, '--verdict', 'accepted', '--settings', settingsPath, '--data-dir', dataDir])
  assert.equal(prove.code, 0, prove.stderr)
  assert.equal(prove.json.outcome.result, 'proven')

  const afterOutcome = runState(['record', '--key', key, '--verdict', 'rejected', '--settings', settingsPath, '--data-dir', dataDir])
  assert.equal(afterOutcome.code, 3)
  assert.match(afterOutcome.stderr, /outcome already exists/i)
  assert.deepEqual(listFilesRecursive(join(dataDir, 'vendor-state', 'trials')), [])

  const stillProven = runState(['outcome', '--key', key, '--data-dir', dataDir])
  assert.equal(stillProven.code, 0, stillProven.stderr)
  assert.equal(stillProven.json.result, 'proven')

  const sentBack = runState(['send-back', '--key', key, '--data-dir', dataDir])
  assert.equal(sentBack.code, 0, sentBack.stderr)
  assert.equal(sentBack.json.deleted, true)

  const afterSendBack = runState(['outcome', '--key', key, '--data-dir', dataDir])
  assert.equal(afterSendBack.code, 0, afterSendBack.stderr)
  assert.equal(afterSendBack.json.result, 'none')

  const settings2 = writeSettings(cfgDir, { routing: true, trials: true, trials_prove: 2, trials_fail: 2 })
  const reTrial = runState(['record', '--key', key, '--verdict', 'rejected', '--settings', settings2, '--data-dir', dataDir])
  assert.equal(reTrial.code, 0, reTrial.stderr)
  assert.equal(reTrial.json.recorded, true)
  assert.equal(listFilesRecursive(join(dataDir, 'vendor-state', 'trials')).length, 1)

  const fail2 = runState(['record', '--key', key, '--verdict', 'rejected', '--settings', settings2, '--data-dir', dataDir])
  assert.equal(fail2.code, 0, fail2.stderr)
  assert.equal(fail2.json.outcome.result, 'failed')
  assert.deepEqual(listFilesRecursive(join(dataDir, 'vendor-state', 'trials')), [])
})

test('seen reports new model ids with one registry recheck due line and stores the union', (t) => {
  const dataDir = makeTempDir(t)

  const s1 = runState(['seen', '--vendor', 'codex', '--ids', 'sparrow-1', '--data-dir', dataDir])
  assert.equal(s1.code, 0, s1.stderr)
  assert.deepEqual(s1.json.new, ['sparrow-1'])
  assert.deepEqual(s1.json.ids, ['sparrow-1'])
  assert.match(s1.stdout, /registry recheck due/i)

  const s2 = runState(['seen', '--vendor', 'codex', '--ids', 'sparrow-1', '--data-dir', dataDir])
  assert.equal(s2.code, 0, s2.stderr)
  assert.deepEqual(s2.json.new, [])
  assert.deepEqual(s2.json.ids, ['sparrow-1'])
  assert.doesNotMatch(s2.stdout, /registry recheck due/i)

  const s3 = runState(['seen', '--vendor', 'codex', '--ids', 'sparrow-1,sparrow-2', '--data-dir', dataDir])
  assert.equal(s3.code, 0, s3.stderr)
  assert.deepEqual(s3.json.new, ['sparrow-2'])
  assert.deepEqual(s3.json.ids, ['sparrow-1', 'sparrow-2'])
  assert.match(s3.stdout, /registry recheck due/i)

  const s4 = runState(['seen', '--vendor', 'codex', '--ids', 'sparrow-2', '--data-dir', dataDir])
  assert.equal(s4.code, 0, s4.stderr)
  assert.deepEqual(s4.json.new, [])
  assert.deepEqual(s4.json.ids, ['sparrow-1', 'sparrow-2'])
})

test('AC9: routine vendor-decide run with trials off leaves temp data dir completely empty', (t) => {
  const dataDir = makeTempDir(t)
  const res = runDecideFixture(t, {
    registry: { version: 1, rows: [row('board-a')] },
    manifest: { boards: [boardEntry('board-a')] },
    records: [
      rec('board-a', 'codex', 'sparrow-1', 'lead'),
      rec('board-a', 'claude', 'kestrel-1', 'behind'),
    ],
    settings: { routing: true, trials: false },
    stateDir: dataDir,
    extraArgs: ['--task-type', 'coding'],
  })
  assert.equal(res.code, 0, res.stderr)
  assert.equal(res.json.vendor, 'claude')
  assert.equal(res.json.basis, 'default')
  assert.deepEqual(listFilesRecursive(dataDir), [])
})

test('AC2/AC19: vendor-decide routes proven Outcome, excludes failed Outcome, and routes active trials without writing', (t) => {
  const dataDir = makeTempDir(t)
  const cfgDir = makeTempDir(t)
  const proveSettings = writeSettings(cfgDir, { routing: true, trials: true, trials_prove: 1, trials_fail: 2 })

  const provenKey = 'codex:sparrow-1:1:high:coding'
  const rProve = runState(['record', '--key', provenKey, '--verdict', 'accepted', '--settings', proveSettings, '--data-dir', dataDir])
  assert.equal(rProve.code, 0, rProve.stderr)

  const decideProven = runDecideFixture(t, {
    registry: { version: 1, rows: [row('board-a')] },
    manifest: { boards: [boardEntry('board-a')] },
    records: [],
    settings: { routing: true, trials: false },
    stateDir: dataDir,
    extraArgs: ['--task-type', 'coding'],
  })
  assert.equal(decideProven.code, 0, decideProven.stderr)
  assert.equal(decideProven.json.vendor, 'codex')
  assert.equal(decideProven.json.model, 'sparrow-1')
  assert.equal(decideProven.json.effort, 'high')
  assert.equal(decideProven.json.basis, 'proven')

  const decideOtherWorkType = runDecideFixture(t, {
    registry: { version: 1, rows: [row('board-w', { workloads: ['web-ui'] })] },
    manifest: { boards: [boardEntry('board-w')] },
    records: [],
    settings: { routing: true, trials: false },
    stateDir: dataDir,
    extraArgs: ['--task-type', 'web-ui'],
  })
  assert.equal(decideOtherWorkType.code, 0, decideOtherWorkType.stderr)
  assert.equal(decideOtherWorkType.json.vendor, 'claude')
  assert.equal(decideOtherWorkType.json.basis, 'default')

  const modelsV2 = {
    ...MODELS,
    codex: {
      status: 'ok',
      models: [{ id: 'sparrow-1', version: '2', efforts: ['low', 'medium', 'high'], default_effort: 'high' }],
      default_model: 'sparrow-1',
      default_effort: 'high',
    },
  }
  const decideNewVersion = runDecideFixture(t, {
    registry: { version: 1, rows: [row('board-a')] },
    manifest: { boards: [boardEntry('board-a')] },
    records: [],
    models: modelsV2,
    settings: { routing: true, trials: false },
    stateDir: dataDir,
    extraArgs: ['--task-type', 'coding'],
  })
  assert.equal(decideNewVersion.code, 0, decideNewVersion.stderr)
  assert.equal(decideNewVersion.json.vendor, 'claude')
  assert.equal(decideNewVersion.json.basis, 'default')

  const failDir = makeTempDir(t)
  const f1 = runState(['record', '--key', provenKey, '--verdict', 'rejected', '--settings', proveSettings, '--data-dir', failDir])
  assert.equal(f1.code, 0, f1.stderr)
  const f2 = runState(['record', '--key', provenKey, '--verdict', 'rejected', '--settings', proveSettings, '--data-dir', failDir])
  assert.equal(f2.code, 0, f2.stderr)
  assert.equal(f2.json.outcome.result, 'failed')

  const decideFailedConsensus = runDecideFixture(t, {
    registry: { version: 1, rows: [row('board-a'), row('board-b')] },
    manifest: { boards: [boardEntry('board-a'), boardEntry('board-b')] },
    records: [
      rec('board-a', 'codex', 'sparrow-1', 'lead', { version: '1', effort: 'high' }),
      rec('board-a', 'claude', 'kestrel-1', 'behind'),
      rec('board-b', 'codex', 'sparrow-1', 'lead', { version: '1', effort: 'high' }),
      rec('board-b', 'claude', 'kestrel-1', 'behind'),
    ],
    settings: { routing: true, trials: false },
    stateDir: failDir,
    extraArgs: ['--task-type', 'coding'],
  })
  assert.equal(decideFailedConsensus.code, 0, decideFailedConsensus.stderr)
  assert.equal(decideFailedConsensus.json.vendor, 'claude')
  assert.equal(decideFailedConsensus.json.basis, 'default')
  assert.ok(decideFailedConsensus.json.notes.some((n) => /failed/i.test(n) && /codex/i.test(n)))

  const decideActiveTrialSkipFailed = runDecideFixture(t, {
    registry: { version: 1, rows: [row('board-a')] },
    manifest: { boards: [boardEntry('board-a')] },
    records: [],
    settings: { routing: true, trials: true, trials_prove: 3, trials_fail: 2 },
    stateDir: failDir,
    extraArgs: ['--task-type', 'coding'],
  })
  assert.equal(decideActiveTrialSkipFailed.code, 0, decideActiveTrialSkipFailed.stderr)
  assert.equal(decideActiveTrialSkipFailed.json.vendor, 'gemini')
  assert.equal(decideActiveTrialSkipFailed.json.model, 'finch-1')
  assert.equal(decideActiveTrialSkipFailed.json.basis, 'trial')

  const emptyStateDir = makeTempDir(t)
  const decideTrialEmpty = runDecideFixture(t, {
    registry: { version: 1, rows: [row('board-a')] },
    manifest: { boards: [boardEntry('board-a')] },
    records: [],
    settings: { routing: true, trials: true, trials_prove: 3, trials_fail: 2 },
    stateDir: emptyStateDir,
    extraArgs: ['--task-type', 'coding'],
  })
  assert.equal(decideTrialEmpty.code, 0, decideTrialEmpty.stderr)
  assert.equal(decideTrialEmpty.json.vendor, 'codex')
  assert.equal(decideTrialEmpty.json.basis, 'trial')
  assert.deepEqual(listFilesRecursive(emptyStateDir), [])
})
