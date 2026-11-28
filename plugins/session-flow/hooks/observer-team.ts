import { readOptions } from './observer-machine.ts'

const TEAM_KEYS = { skill_check: 'observer_skill_check', improvement_check: 'observer_improvement_check', defer_kinds: 'observer_defer_kinds', codify_threshold: 'observer_codify_threshold' } as const

export type TeamLayer = { raw: Record<string, unknown>; guidance: string; notes: string[]; rejected: string[] }

export const teamLayer = (stdout: string): TeamLayer => {
  const team = JSON.parse(stdout) as { observer?: Record<string, unknown>; guidance?: unknown; notes?: unknown }
  const raw: Record<string, unknown> = {}
  const rejected: string[] = []
  for (const [key, option] of Object.entries(TEAM_KEYS)) {
    const v = team.observer?.[key]
    if (v === undefined) continue
    const value = Array.isArray(v) ? v.join(',') : v
    if (readOptions({ [option]: value }).invalid.length === 0) raw[option] = value
    else rejected.push(`team:${key}`)
  }
  const notes = Array.isArray(team.notes) ? team.notes.filter((n): n is string => typeof n === 'string' && n !== '') : []
  return { raw, guidance: typeof team.guidance === 'string' ? team.guidance : '', notes, rejected }
}
