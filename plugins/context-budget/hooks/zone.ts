import type { EngineInterface } from 'claude-code'

export const ZONE_COLOR: Record<string, string> = { light: 'success', moderate: 'warning', heavy: 'error' }
const STALE_MS = 600_000

// context-usage's published zone, read as status lines read it:
// https://github.com/melodic-software/claude-code-plugins/blob/main/plugins/context-usage/README.md#published-zone-for-status-lines
export async function readZone($: EngineInterface): Promise<string | undefined> {
  const home = (await $.env.get('HOME')) || (await $.env.get('USERPROFILE'))
  const sid = await $.session.id()
  if (!home || !sid) return undefined
  const text = await $.fs.read(`${home}/.claude/context-usage/context/${sid}.json`).catch(() => undefined)
  if (typeof text !== 'string') return undefined
  try {
    const snap = JSON.parse(text) as { zone?: unknown; session_id?: unknown; captured_at?: unknown }
    const at = typeof snap.captured_at === 'string' ? Date.parse(snap.captured_at) : NaN
    const now = await $.clock.now()
    if (snap.session_id !== sid || !(at <= now && at >= now - STALE_MS)) return undefined
    return typeof snap.zone === 'string' && snap.zone in ZONE_COLOR ? snap.zone : undefined
  } catch {
    return undefined
  }
}
