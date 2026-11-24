import { test } from 'node:test'
import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import { devNull } from 'node:os'
import { row, runFetchBoardsCacheFixture, runFetchBoardsOnce } from './lib/test-fixtures.mjs'

process.env.GIT_CONFIG_GLOBAL ??= devNull
process.env.GIT_CONFIG_NOSYSTEM = '1'

function skipWithoutBash(t) {
  const probe = spawnSync('bash', ['-c', 'echo ok'], { encoding: 'utf8' })
  if (probe.status === 0 && probe.stdout.trim() === 'ok') return false
  t.skip('bash unavailable or sandboxed on this host')
  return true
}

test('AC6: second fetch-boards run on a fixture row within its window has source cache in manifest', (t) => {
  if (skipWithoutBash(t)) return
  const { run1, run2, m1, m2 } = runFetchBoardsCacheFixture(t)
  assert.equal(run1.status, 0, run1.stderr)
  assert.equal(m1.boards.length, 1)
  assert.equal(m1.boards[0].source_id, 'terminal-bench')
  assert.equal(m1.boards[0].state, 'read')
  assert.equal(m1.boards[0].source, 'fixture')
  assert.equal(m1.boards[0].page_date, '2026-11-18')
  assert.equal(run2.status, 0, run2.stderr)
  assert.equal(m2.boards[0].source_id, 'terminal-bench')
  assert.equal(m2.boards[0].state, 'read')
  assert.equal(m2.boards[0].source, 'cache')
  assert.equal(m2.boards[0].page_date, '2026-11-18')
})

test('fetch-boards checks each row expect marker: a page lacking it is unread no-content', (t) => {
  if (skipWithoutBash(t)) return
  const page = '# Leaderboard\n\nUpdated 2026-11-18\n\n| Model | Score |\n|---|---|\n| sparrow-1 | 82.0% |\n'
  const { res, manifest } = runFetchBoardsOnce(
    t,
    [
      row('marked', { link: 'https://www.tbench.ai/marked', expect: 'sparrow-1' }),
      row('shell', { link: 'https://www.tbench.ai/shell', expect: 'Terminal-Bench 2.0' }),
    ],
    { 'www-tbench-ai/marked.md': page, 'www-tbench-ai/shell.md': page },
  )
  assert.equal(res.status, 0, res.stderr)
  const byId = Object.fromEntries(manifest.boards.map((b) => [b.source_id, b]))
  assert.equal(byId.marked.state, 'read')
  assert.equal(byId.shell.state, 'unread')
  assert.equal(byId.shell.reason, 'no-content')
})

test('fetch-boards fetches only rows that can lead when trials are inactive', (t) => {
  if (skipWithoutBash(t)) return
  const page = '# Leaderboard\n\nUpdated 2026-11-18\n\n| Model | Score |\n|---|---|\n| sparrow-1 | 82.0% |\n'
  const rows = [
    row('lead-row', { link: 'https://www.tbench.ai/lead-row', expect: 'sparrow-1' }),
    row('new-row', { link: 'https://www.tbench.ai/new-row', status: 'support-only', expect: 'sparrow-1' }),
    row('own-row', { link: 'https://www.tbench.ai/own-row', provider_own: true, expect: 'sparrow-1' }),
  ]
  const pages = {
    'www-tbench-ai/lead-row.md': page,
    'www-tbench-ai/new-row.md': page,
    'www-tbench-ai/own-row.md': page,
  }

  const noSettings = runFetchBoardsOnce(t, rows, pages)
  assert.equal(noSettings.res.status, 0, noSettings.res.stderr)
  assert.deepEqual(noSettings.manifest.boards.map((b) => b.source_id), ['lead-row'])

  const incompleteTrials = runFetchBoardsOnce(t, rows, pages, {
    settings: { vendors: { trials: true } },
  })
  assert.equal(incompleteTrials.res.status, 0, incompleteTrials.res.stderr)
  assert.deepEqual(incompleteTrials.manifest.boards.map((b) => b.source_id), ['lead-row'])
})

test('fetch-boards fetches support-only and provider-own rows when trials are active', (t) => {
  if (skipWithoutBash(t)) return
  const page = '# Leaderboard\n\nUpdated 2026-11-18\n\n| Model | Score |\n|---|---|\n| sparrow-1 | 82.0% |\n'
  const rows = [
    row('lead-row', { link: 'https://www.tbench.ai/lead-row', expect: 'sparrow-1' }),
    row('new-row', { link: 'https://www.tbench.ai/new-row', status: 'support-only', expect: 'sparrow-1' }),
    row('own-row', { link: 'https://www.tbench.ai/own-row', provider_own: true, expect: 'sparrow-1' }),
  ]
  const pages = {
    'www-tbench-ai/lead-row.md': page,
    'www-tbench-ai/new-row.md': page,
    'www-tbench-ai/own-row.md': page,
  }

  const active = runFetchBoardsOnce(t, rows, pages, {
    settings: { vendors: { trials: true, trials_prove: 3, trials_fail: 2 } },
  })
  assert.equal(active.res.status, 0, active.res.stderr)
  assert.deepEqual(active.manifest.boards.map((b) => b.source_id), ['lead-row', 'new-row', 'own-row'])
})
