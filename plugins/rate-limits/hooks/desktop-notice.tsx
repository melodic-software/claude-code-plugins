import type { EngineInterface } from 'claude-code'

type Elements = ReturnType<EngineInterface['ui']['resolve']>
export type DesktopChange = {
  window: string
  event: 'quiet' | 'approach' | 'edge' | 'reset'
  percent: number | undefined
  resetsAt: string | undefined
  threshold: number
}

export const inWords = (ms: number) => {
  const min = Math.max(1, Math.round(ms / 60_000))
  const d = Math.floor(min / 1440)
  const h = Math.floor((min % 1440) / 60)
  const m = min % 60
  return d > 0 ? `${d}d ${h}h` : h > 0 ? (m > 0 ? `${h}h ${m}m` : `${h}h`) : `${m}m`
}

function line(Text: Elements['Text'], c: DesktopChange, nowMs: number) {
  const now = c.percent === undefined ? '' : ` (now ${c.percent}%)`
  if (c.event === 'reset' || c.event === 'quiet')
    return (
      <Text key={c.window}>
        {c.window} limit{' '}
        <Text bold color="success">
          {c.event === 'reset' ? 'reset' : `back below ${c.threshold}%`}
        </Text>
        <Text dimColor>{now}</Text>
      </Text>
    )
  const resetsMs = c.resetsAt === undefined ? NaN : Date.parse(c.resetsAt) - nowMs
  const resets = Number.isFinite(resetsMs) && resetsMs > 0 ? ` · resets in ${inWords(resetsMs)}` : ''
  return (
    <Text key={c.window}>
      {c.window} limit {c.percent === undefined ? '' : 'at '}
      <Text bold color={c.event === 'edge' ? 'error' : 'warning'}>
        {c.percent === undefined ? (c.event === 'edge' ? `past ${c.threshold}%` : `nearing ${c.threshold}%`) : `${c.percent}%`}
      </Text>
      <Text dimColor>
        {' '}
        ({c.percent === undefined ? '' : `${c.event === 'edge' ? 'past' : 'nearing'} ${c.threshold}%`}
        {resets})
      </Text>
    </Text>
  )
}

export function desktopNotice($: EngineInterface, ui: Elements, changes: DesktopChange[], nowMs: number, dismiss: () => void) {
  const { Box, Text, Button } = ui
  return (
    <Box flexDirection="row" alignItems="center" gap={1}>
      <Box flexDirection="column">{changes.map(c => line(Text, c, nowMs))}</Box>
      <Box flexGrow={1} />
      <Button
        key="details"
        label="Details"
        onPress={() => {
          dismiss()
          void $.command.run({ command: 'rate-limits' }).catch(() => $.prompt.suggest({ text: '/rate-limits' }).catch(() => undefined))
        }}
      />
      <Button key="dismiss" label="Dismiss" role="dismiss" onPress={dismiss} />
    </Box>
  )
}
