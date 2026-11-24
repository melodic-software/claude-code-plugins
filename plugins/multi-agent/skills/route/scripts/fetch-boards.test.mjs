import { test } from 'node:test'
import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import { readFileSync } from 'node:fs'
import { devNull } from 'node:os'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { row, runFetchBoardsCacheFixture, runFetchBoardsOnce } from './lib/test-fixtures.mjs'

const FIXTURES = join(dirname(fileURLToPath(import.meta.url)), 'fixtures')

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

test('fetch-boards dates captured boards by their page dates, never by a model snapshot date', (t) => {
  if (skipWithoutBash(t)) return
  const captured = (name) => readFileSync(join(FIXTURES, name), 'utf8')
  const board = (id) => row(id, { link: `https://www.tbench.ai/${id}`, expect: 'Leaderboard' })
  const { res, manifest } = runFetchBoardsOnce(
    t,
    [
      row('aa-image-t2i', {
        link: 'https://artificialanalysis.ai/image/leaderboard/text-to-image',
        expect: 'AA-Image-T2I',
      }),
      row('terminal-bench', { link: 'https://www.tbench.ai/leaderboard', expect: 'TERMINAL-BENCH' }),
      board('heading'),
      board('changelog'),
      board('updated'),
      board('id-suffix'),
    ],
    {
      'artificialanalysis-ai/image/leaderboard/text-to-image.md': captured('aa-image-t2i-page.md'),
      'www-tbench-ai/leaderboard.md': captured('terminal-bench-page.md'),
      'www-tbench-ai/heading.md': '# Leaderboard\n\n## v1.1.1 (2026-11-18)\n',
      'www-tbench-ai/changelog.md': '# Leaderboard\n\n- Added 3 models (2026-11-18)\n',
      'www-tbench-ai/updated.md': '# Leaderboard\n\nLast updated (2026-11-18)\n',
      'www-tbench-ai/id-suffix.md':
        '# Leaderboard\n\n| [GPT 5.4 Mini](/models/openai_gpt-5.4-mini-2026-03-17)  |  Mini-SWE-agent |\n',
    },
  )
  assert.equal(res.status, 0, res.stderr)
  const dateOf = Object.fromEntries(manifest.boards.map((b) => [b.source_id, b.page_date]))
  assert.deepEqual(dateOf, {
    'aa-image-t2i': null,
    'terminal-bench': '2026-11-18',
    heading: '2026-11-18',
    changelog: '2026-11-18',
    updated: '2026-11-18',
    'id-suffix': null,
  })
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
