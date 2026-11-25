import type { EngineInterface } from 'claude-code'

import type { Finding } from './observer-live.ts'

type Elements = ReturnType<EngineInterface['ui']['resolve']>
export type BandActions = {
  noted: () => unknown
  send: () => unknown
  dispute: () => unknown
  why: () => unknown
  dismiss: () => unknown
}

export const OFF_HINT = 'pause: /observer off · for good: observer_step_check, observer_turn_end_check in /plugin configure session-flow'

export type AskedActions = { helpful: () => unknown; notRelevant: () => unknown; unclear: () => unknown; turnOff: () => unknown; close: () => unknown }

export const askedRow = (ui: Elements, icon: string, act: AskedActions) => {
  const { Box, Button, Text } = ui
  return (
    <Box marginTop={1} marginBottom={1} gap={2}>
      <Text dimColor>
        <Text color="warning">{icon} </Text>
        observer · Dismissed.
      </Text>
      <Button key="helpful" hotkey="5" label="That was helpful" plain onPress={act.helpful} />
      <Button key="not-relevant" hotkey="6" label="Not relevant" plain onPress={act.notRelevant} />
      <Button key="unclear" hotkey="7" label="Couldn't understand" plain onPress={act.unclear} />
      <Button key="turn-off" hotkey="8" label="Turn off checks" plain onPress={act.turnOff} />
      <Button key="close" hotkey="9" label="Close" plain dimColor onPress={act.close} />
    </Box>
  )
}

export const band = (ui: Elements, icon: string, f: Finding, source: string, isOpen: boolean, cost: string, act: BandActions) => {
  const { Box, Button, Text } = ui
  return (
    <Box flexDirection="column" marginTop={1} marginBottom={1}>
      <Text wrap="truncate">
        <Text color="warning">{icon} </Text>
        <Text dimColor>observer · </Text>
        <Text color="warning">{f.category}</Text>
        <Text dimColor> ({source})</Text>
        <Text> · {f.finding}</Text>
      </Text>
      {isOpen ? (
        <Box flexDirection="column" paddingLeft={2}>
          <Text wrap="wrap">{f.finding}</Text>
          <Text wrap="wrap">
            <Text dimColor>rule: </Text>
            {f.rule}
          </Text>
          <Text wrap="wrap">
            <Text dimColor>evidence: </Text>
            {f.evidence || 'not given'}
          </Text>
          <Text dimColor wrap="truncate">
            {cost}
          </Text>
          <Text dimColor wrap="truncate">
            {OFF_HINT}
          </Text>
        </Box>
      ) : null}
      <Box gap={2}>
        <Button key="send" hotkey="5" label="Send to Claude" plain onPress={act.send} />
        <Button key="noted" hotkey="6" label="Noted" plain onPress={act.noted} />
        <Button key="dispute" hotkey="7" label="Dispute" plain onPress={act.dispute} />
        <Button key="why" hotkey="8" label={isOpen ? 'Hide' : 'Why'} plain onPress={act.why} />
        <Button key="dismiss" hotkey="9" label="Dismiss" plain dimColor onPress={act.dismiss} />
      </Box>
    </Box>
  )
}
