import { expect, test } from 'claude-code/testing'
import cases from '../scripts/context-zone.fixtures.mjs'
import { followWindow, resolveZone } from './zone.ts'

const NOW = 1_791_050_400
const iso = (s: number) => new Date(s * 1000).toISOString().replace(/\.\d{3}Z$/, 'Z')

const text = (value: unknown): string | null => {
  if (value === null) return null
  if (typeof value === 'object' && !Array.isArray(value)) {
    const v = value as Record<string, unknown>
    if ('raw' in v) return String(v.raw)
    const m = typeof v.captured_at === 'string' ? /^@now([+-]\d+)?$/.exec(v.captured_at) : null
    if (m) return JSON.stringify({ ...v, captured_at: iso(NOW + Number(m[1] ?? 0)) })
  }
  return JSON.stringify(value)
}

type Case = { name: string; sid: string; snapshot: unknown; zones: unknown; word: string; notices: string[] }

test('fixture: the shared file holds at least 100 cases', () => {
  expect((cases as Case[]).length).toBeGreaterThanOrEqual(100)
})

for (const c of cases as Case[]) {
  test(`fixture: ${c.name}`, () => {
    expect(resolveZone({ sid: c.sid, snapshot: text(c.snapshot), zones: text(c.zones), nowSec: NOW })).toEqual({ word: c.word, notices: c.notices })
  })
}

type Snap = { context_window: { context_window_size?: number }; bands?: { auto_compact_window?: unknown } }
const lowered = (cases as Case[]).filter(c => typeof (c.snapshot as Snap | null)?.bands?.auto_compact_window === 'number')
test('fixture: the shared file holds a lowered-window case', () => {
  expect(lowered.some(c => c.word !== 'light')).toBe(true)
})
for (const c of lowered) {
  test(`fixture, as the mod resolves it: ${c.name}`, () => {
    const { bands, ...body } = c.snapshot as Snap
    const size = body.context_window.context_window_size ?? 0
    const follow = (b: Parameters<typeof followWindow>[0]) => followWindow(b, size, bands?.auto_compact_window as number)
    expect(resolveZone({ sid: c.sid, snapshot: text(body), zones: text(c.zones), nowSec: NOW, follow }).word).toBe(c.word)
  })
}

const fresh = (capturedAt: string) =>
  JSON.stringify({ captured_at: capturedAt, session_id: 's1', context_window: { used_percentage: 20, current_usage: {} } })
test('captured_at: a calendar-invalid value that would normalize into the window reads unknown', () => {
  const marchSecond = Date.parse('2026-03-02T00:00:30Z') / 1000
  expect(resolveZone({ sid: 's1', snapshot: fresh('2026-02-30T00:00:00Z'), zones: null, nowSec: marchSecond }).word).toBe('unknown')
  expect(resolveZone({ sid: 's1', snapshot: fresh('2026-03-02T00:00:00Z'), zones: null, nowSec: marchSecond }).word).toBe('light')
  const nextMinute = Date.parse('2026-10-04T00:00:30Z') / 1000
  expect(resolveZone({ sid: 's1', snapshot: fresh('2026-10-03T23:59:60Z'), zones: null, nowSec: nextMinute }).word).toBe('unknown')
  expect(resolveZone({ sid: 's1', snapshot: fresh('2026-10-03T24:00:00Z'), zones: null, nowSec: nextMinute }).word).toBe('unknown')
})

test('staleness: 600 s old is fresh, 601 s old and 61 s in the future are not', () => {
  const at = (offset: number) => resolveZone({ sid: 's1', snapshot: fresh(iso(NOW + offset)), zones: null, nowSec: NOW }).word
  expect([at(-600), at(-601), at(60), at(61)]).toEqual(['light', 'unknown', 'light', 'unknown'])
})
