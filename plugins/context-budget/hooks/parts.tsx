import type { Elements, RenderSurface, ThemeKey } from 'claude-code'

import type { LiveCategory, LiveState, LiveView } from '../types'

type Draw = Pick<Elements[RenderSurface], 'Box' | 'Text'>

// 90000 -> 90k, 1000000 -> 1M, 1500000 -> 1.5M.
export const tokens = (n: number): string => {
  if (n >= 1_000_000) return `${+(n / 1_000_000).toFixed(1)}M`
  if (n >= 1_000) return `${Math.round(n / 1_000)}k`
  return String(n)
}

export const headerText = (v: LiveView): string =>
  `◆ context ${tokens(v.used)} of ${tokens(v.window)}${v.compactsAt !== undefined ? ` · compacts at ${tokens(v.compactsAt)}` : ''} ${Math.round(v.percent)}%`

const entry = (c: LiveCategory): string =>
  `${c.name} ${tokens(c.tokens)} ${c.deferred ? 'deferred' : `${Math.round(c.percent)}%`}`

const isFree = (c: LiveCategory) => c.kind === 'free'

// The engine documents a breakdown row's color as its key in the theme.
const theme = (c: LiveCategory): ThemeKey => c.color as ThemeKey

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
        <Box flexDirection="row">
          <Text color={theme(c)} dimColor={isFree(c) || c.deferred}>
            {'■ '}
          </Text>
          <Text dimColor={c.deferred} wrap="truncate">
            {entry(c)}
          </Text>
        </Box>
      ))}
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
      <Text wrap="truncate">
        {v.categories
          .filter(c => !c.deferred)
          .map(entry)
          .join('  ')}
      </Text>
    </Box>
  )
}
