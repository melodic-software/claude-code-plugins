import type { EngineInterface } from 'claude-code'

import type { Zone } from './zone.ts'

type Elements = ReturnType<EngineInterface['ui']['resolve']>
export type DesktopCrossing = { from: string; to: string; zone: Zone }

export function desktopNotice($: EngineInterface, ui: Elements, c: DesktopCrossing, dismiss: () => void) {
  const { Box, Text, Button } = ui
  const run = (command: string) => () => {
    dismiss()
    void $.command.run({ command }).catch(() => $.prompt.suggest({ text: `/${command}` }).catch(() => undefined))
  }
  return (
    <Box flexDirection="row" alignItems="center" gap={1}>
      <Text>
        Context is now{' '}
        <Text bold color={c.zone === 'heavy' ? 'error' : 'warning'}>
          {c.to}
        </Text>
        <Text dimColor> (was {c.from})</Text>
      </Text>
      <Box flexGrow={1} />
      <Button key="compact" label="Compact" variant="primary" onPress={run('compact')} />
      <Button key="handoff" label="Handoff" onPress={run('session-flow:handoff')} />
      <Button key="details" label="Details" onPress={run('context-usage')} />
      <Button key="dismiss" label="Dismiss" role="dismiss" onPress={dismiss} />
    </Box>
  )
}
