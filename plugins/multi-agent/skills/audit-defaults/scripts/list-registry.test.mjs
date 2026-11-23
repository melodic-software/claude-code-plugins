import { test } from 'node:test'
import assert from 'node:assert/strict'
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs'
import { spawnSync } from 'node:child_process'
import { tmpdir } from 'node:os'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { listRegistry } from './list-registry.mjs'

const here = dirname(fileURLToPath(import.meta.url))
const script = join(here, 'list-registry.mjs')

function makeRepo(teamDoc) {
  const dir = mkdtempSync(join(tmpdir(), 'list-registry-test-'))
  if (teamDoc !== undefined) {
    const p = join(dir, 'docs', 'conventions', 'multi-agent')
    mkdirSync(p, { recursive: true })
    writeFileSync(join(p, 'benchmarks.json'), JSON.stringify(teamDoc, null, 2))
  }
  return dir
}

test('lists shipped rows when repository has no team benchmarks file', () => {
  const dir = makeRepo(undefined)
  try {
    const { rows, notes } = listRegistry({ repoRoot: dir })
    assert.ok(rows.length >= 3)
    assert.ok(rows.every(r => r.source === 'shipped'))
    assert.deepEqual(notes, [])
  } finally {
    rmSync(dir, { recursive: true, force: true })
  }
})

test('merges valid team rows and refuses duplicate shipped row ids with a note', () => {
  const dir = makeRepo({
    version: 1,
    rows: [
      {
        id: 'terminal-bench',
        workloads: ['coding'],
        link: 'https://example.org/dup',
        publisher: 'dup',
        provider_own: false,
        status: 'support-only',
        task_set: 'dup',
        expect: 'Dup',
      },
      {
        id: 'team-knowledge-board',
        workloads: ['knowledge'],
        link: 'https://arena.ai/leaderboard/text',
        publisher: 'arena.ai',
        provider_own: false,
        status: 'support-only',
        task_set: 'arena-text',
        expect: 'Arena',
      },
    ],
  })
  try {
    const { rows, notes } = listRegistry({ repoRoot: dir })
    assert.equal(notes.length, 1)
    assert.match(notes[0], /terminal-bench.*duplicates shipped/)
    const team = rows.filter(r => r.source === 'team')
    assert.deepEqual(team.map(r => r.id), ['team-knowledge-board'])
  } finally {
    rmSync(dir, { recursive: true, force: true })
  }
})

test('CLI --json prints valid JSON and rejects invalid team schema with exit 2', () => {
  const goodDir = makeRepo(undefined)
  const badDir = makeRepo({ version: 1, extra_field: true, rows: [] })
  try {
    const ok = spawnSync('node', [script, '--json', '--root', goodDir], { encoding: 'utf8' })
    assert.equal(ok.status, 0)
    const parsed = JSON.parse(ok.stdout)
    assert.ok(Array.isArray(parsed.rows) && parsed.rows.length >= 3)

    const bad = spawnSync('node', [script, '--json', '--root', badDir], { encoding: 'utf8' })
    assert.equal(bad.status, 2)
    assert.match(bad.stderr, /unknown field/)
  } finally {
    rmSync(goodDir, { recursive: true, force: true })
    rmSync(badDir, { recursive: true, force: true })
  }
})
