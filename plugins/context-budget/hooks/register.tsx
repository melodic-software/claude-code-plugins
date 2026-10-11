import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register, SessionContextUsage } from 'claude-code'

import type { LiveView } from '../types'

const COMMAND = 'context-budget'
const PANE = 'context-budget-live'
const TITLE = 'Context'
const USAGE = 'usage: /context-budget live'

const view = atom({ plugin: 'context-budget', key: 'view' } as const, null)
const error = atom({ plugin: 'context-budget', key: 'error' } as const, null)

// 90000 -> 90k, 1000000 -> 1M, 1500000 -> 1.5M.
const tokens =(n: number): string => {
  if (n >= 1_000_000) return `${+(n / 1_000_000).toFixed(1)}M`
  if (n >= 1_000) return `${Math.round(n / 1_000)}k`
  return String(n)
}

const toView = (context: SessionContextUsage): LiveView => {
  const b = context.breakdown
  if (b === undefined) {
    return { used: context.tokens ?? 0, window: context.window, percent: context.percent ?? 0, categories: [] }
  }
  return {
    used: b.totalTokens,
    window: b.rawMaxTokens,
    ...(b.autoCompactThreshold !== undefined ? { compactsAt: b.autoCompactThreshold } : {}),
    percent: b.percentage,
    categories: b.categories.map(c => ({
      name: c.name,
      tokens: c.tokens,
      percent: b.rawMaxTokens > 0 ? (c.tokens / b.rawMaxTokens) * 100 : 0,
      kind: c.kind,
      color: c.color,
      deferred: c.isDeferred,
    })),
  }
}

const refresh = async ($: EngineInterface) => {
  try {
    const { context } = await $.session.usage({ breakdown: 'summary' })
    await update($, view, () => toView(context))
    await update($, error, () => null)
  } catch (err) {
    await update($, error, () => (err instanceof Error ? err.message : String(err)))
  }
}

const registerCommand = ($: EngineInterface) =>
  $.command.register({
    name: COMMAND,
    description: 'Live per-category context breakdown; live opens or closes the pane',
    argumentHint: 'live',
    immediate: true,
  })

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await registerCommand($)
    return next(e)
  }).catch(($, e, next) => next(e))

  // No session.start fires after /clear; registering again is harmless when the command survived.
  on('session.end', async ($, e, next) => {
    const ended = await next(e)
    if (e.reason === 'clear') await registerCommand($).catch(() => undefined)
    return ended
  }).catch(($, e, next) => next(e))

  // Answers with no text: the pane is the output, and nothing lands in the transcript Claude reads.
  on('command.run', { command: COMMAND }, async ($, e) => {
    if (e.args.trim() !== 'live') {
      $.ui.toast(USAGE)
      return {}
    }
    if ((await $.ui.panes()).some(pane => pane.id === PANE)) {
      await $.ui.close({ id: PANE })
      return {}
    }
    await refresh($)
    await $.ui.open({ id: PANE, title: TITLE })
    return {}
  }).catch(($, e, next) => next(e))

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text } = $.ui.resolve(e)
    const v = await read($, view)
    const err = await read($, error)
    return (
      <Box flexDirection="column">
        <Text bold wrap="truncate">
          {v === null ? '◆ context' : `◆ context ${tokens(v.used)} of ${tokens(v.window)}`}
        </Text>
        {err !== null ? <Text dimColor>{`usage unavailable: ${err}`}</Text> : null}
      </Box>
    )
  })
}
