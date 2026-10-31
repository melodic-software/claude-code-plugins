import type { Elements, RenderSurface, ThemeKey } from 'claude-code'

import type { LiveCategory, LiveState, LiveView } from '../types'

type Draw = Pick<Elements[RenderSurface], 'Box' | 'Text'>

// 90000 -> 90k, 1000000 -> 1M, 1500000 -> 1.5M.
// A value that rounds up to the next unit is shown in it: 999999 -> 1M, not 1000k.
export const tokens = (n: number): string => {
  const r = Math.round(n)
  const k = Math.round(r / 1_000)
  if (k >= 1_000) return `${+(r / 1_000_000).toFixed(1)}M`
  if (r >= 1_000) return `${k}k`
  return String(r)
}

export const headerText = (v: LiveView): string =>
  `◆ context ${tokens(v.used)} of ${tokens(v.window)}${v.compactsAt !== undefined ? ` · compacts at ${tokens(v.compactsAt)}` : ''} ${Math.round(v.percent)}%`

const entry = (c: LiveCategory): string =>
  `${c.name} ${tokens(c.tokens)} ${c.deferred ? 'deferred' : `${Math.round(c.percent)}%`}`

const isFree = (c: LiveCategory) => c.kind === 'free'

// The skill listing's default budget is 1% of the context window (skillListingBudgetFraction 0.01):
// https://code.claude.com/docs/en/skills#skill-descriptions-are-cut-short, also
// skills/audit/reference/levers.json "skill-listing-budget". Claude Code counts that budget in
// characters, sized from the window's tokens: SLASH_COMMAND_TOOL_CHAR_BUDGET's documented fallback
// of 8,000 characters (https://code.claude.com/docs/en/env-vars) is 1% of a 200k window at 4
// characters per token. So a listing that fills the default budget is about 1% of the window in
// tokens, the unit the row reports, and a row at 1% has reached the default budget. Fixed; no
// option. A raised skillListingBudgetFraction lets the listing pass 1% without being over its
// budget, so the fix text states the row's share and makes no claim about the budget.
const SKILLS_WARN_PERCENT = 1
export const SKILLS_FIX = 'Skills holds 1% or more of the window: run /skill-doctor, or check skillListingBudgetFraction'

// Skills is the one category with a documented level. Its kind is shared with other used rows, so
// this one check reads the name.
const warns = (c: LiveCategory) => c.name === 'Skills' && !c.deferred && c.percent >= SKILLS_WARN_PERCENT

// The engine documents a breakdown row's color as its key in the theme.
const theme = (c: LiveCategory): ThemeKey => c.color as ThemeKey
const WARNING: ThemeKey = 'warning'

// One segment per window row, each as wide as its share of `width`, rounded on the running total
// so the segments always add up to `width`. Deferred rows sit outside the window.
export const Bar = ({ Box, Text }: Draw, categories: LiveCategory[], width: number) => {
  const rows = categories.filter(c => !c.deferred)
  const total = Math.max(1, rows.reduce((sum, c) => sum + c.tokens, 0))
  let before = 0
  const segments = rows.map(c => {
    const start = Math.round((before / total) * width)
    before += c.tokens
    return { c, cells: Math.round((before / total) * width) - start }
  })
  return (
    <Box flexDirection="row">
      {segments
        .filter(s => s.cells > 0)
        .map(({ c, cells }) => (
          <Text color={theme(c)} dimColor={isFree(c)}>
            {(isFree(c) ? '░' : '█').repeat(cells)}
          </Text>
        ))}
    </Box>
  )
}

export const PaneBody = (draw: Draw, { view: v, error }: LiveState, columns: number) => {
  const { Box, Text } = draw
  return (
    <Box flexDirection="column">
      {v !== null ? (
        <Text bold wrap="truncate">
          {headerText(v)}
        </Text>
      ) : null}
      {error !== null ? (
        <Text dimColor wrap="truncate">{`usage unavailable: ${error}`}</Text>
      ) : v === null ? (
        <Text dimColor>waiting for next response</Text>
      ) : null}
      {v !== null && v.categories.length > 0 ? Bar(draw, v.categories, columns) : null}
      {v?.categories.map(c => (
        <Box flexDirection="column">
          <Box flexDirection="row">
            <Text color={theme(c)} dimColor={isFree(c) || c.deferred}>
              {'■ '}
            </Text>
            <Text dimColor={c.deferred} wrap="truncate" {...(warns(c) ? { color: WARNING } : {})}>
              {entry(c)}
            </Text>
          </Box>
          {warns(c) ? (
            <Text color={WARNING} wrap="wrap">
              {`  ${SKILLS_FIX}`}
            </Text>
          ) : null}
        </Box>
      ))}
    </Box>
  )
}

// One line of the window rows. A warned Skills entry is its own Text in the warning color; the
// fix text does not fit the line, so the pane row carries it.
const Legend = ({ Box, Text }: Draw, categories: LiveCategory[]) => {
  const rows = categories.filter(c => !c.deferred)
  const at = rows.findIndex(warns)
  const warned = rows[at]
  if (warned === undefined) return <Text wrap="truncate">{rows.map(entry).join('  ')}</Text>
  const before = rows.slice(0, at).map(c => `${entry(c)}  `).join('')
  const after = rows.slice(at + 1).map(c => `  ${entry(c)}`).join('')
  return (
    <Box flexDirection="row">
      {before !== '' ? <Text wrap="truncate">{before}</Text> : null}
      <Text color={WARNING} wrap="truncate">
        {entry(warned)}
      </Text>
      {after !== '' ? <Text wrap="truncate">{after}</Text> : null}
    </Box>
  )
}

// Five rows: the border's two, then header, bar and a one-line legend of the window rows.
export const Band = (draw: Draw, v: LiveView, columns: number) => {
  const { Box, Text } = draw
  return (
    <Box flexDirection="column" borderStyle="round" borderDimColor>
      <Text bold wrap="truncate">
        {headerText(v)}
      </Text>
      {Bar(draw, v.categories, columns - 2)}
      {Legend(draw, v.categories)}
    </Box>
  )
}
