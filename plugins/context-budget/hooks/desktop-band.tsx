import type { Elements, RenderSurface, ThemeKey } from 'claude-code'

import type { LiveCategory, LiveView } from '../types'
import { tokens, warns } from './parts'

type Draw = Pick<Elements[RenderSurface], 'Box' | 'Text'>

const share = (c: LiveCategory, total: number) => Math.max(1, Math.round((c.tokens / total) * 1000))

export const DesktopBar = ({ Box, Text }: Draw, categories: LiveCategory[], hover: boolean) => {
  const rows = categories.filter(c => !c.deferred && c.tokens > 0)
  const total = Math.max(1, rows.reduce((sum, c) => sum + c.tokens, 0))
  return (
    <Box flexDirection="row" flexGrow={1} height={1}>
      {rows.map(c => (
        <Box
          key={`seg-${c.name}`}
          flexGrow={share(c, total)}
          height={1}
          {...(c.kind === 'free' ? {} : { backgroundColor: c.color as ThemeKey })}
          {...(hover ? { hover: { scope: `seg-${c.name}`, backgroundColor: (c.kind === 'free' ? 'subtle' : 'inactive') as ThemeKey } } : {})}
        >
          <Text> </Text>
        </Box>
      ))}
    </Box>
  )
}

export const DesktopBand = (draw: Draw, v: LiveView) => {
  const { Box, Text } = draw
  const rows = v.categories.filter(c => !c.deferred && c.tokens > 0)
  return (
    <Box key="context-budget-band" flexDirection="row" alignItems="center" gap={1}>
      <Text>
        <Text dimColor>Context </Text>
        <Text bold>{tokens(v.used)}</Text>
        <Text dimColor> / {tokens(v.window)} · </Text>
        <Text>{Math.round(v.percent)}%</Text>
      </Text>
      {DesktopBar(draw, v.categories, true)}
      <Box position="relative" width={30} height={1}>
        {rows.map(c => (
          <Box
            key={`tip-${c.name}`}
            position="absolute"
            top={0}
            left={0}
            right={0}
            display="none"
            justifyContent="flex-end"
            hover={{ scope: `seg-${c.name}`, display: 'flex' }}
          >
            <Text>
              <Text {...(c.kind === 'free' ? {} : { color: c.color as ThemeKey })}>■ </Text>
              <Text bold {...(warns(c) ? { color: 'warning' as ThemeKey } : {})}>
                {c.name}
              </Text>
              <Text dimColor>
                {' '}
                {tokens(c.tokens)} · {Math.round(c.percent)}%
              </Text>
            </Text>
          </Box>
        ))}
      </Box>
    </Box>
  )
}
