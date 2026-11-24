import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register, SessionContextUsage } from 'claude-code'

import type { LiveMode, LiveState, LiveView } from '../types'
import { DesktopBand } from './desktop-band'
import { Band, PaneBody } from './parts'

const COMMAND = 'context-budget'
const PANE = 'context-budget-live'
const TITLE = 'Context'
const USAGE = 'usage: /context-budget live [pane|band|off]'
const MODES: readonly LiveMode[] = ['pane', 'band', 'off']

const isMode = (value: unknown): value is LiveMode => MODES.includes(value as LiveMode)

const live = atom({ plugin: 'context-budget', key: 'live' } as const, { view: null, error: null })

const figures = (context: SessionContextUsage): LiveView | null =>
  context.tokens === undefined ? null : { used: context.tokens, window: context.window, percent: context.percent ?? 0, categories: [] }

const toView = (context: SessionContextUsage): LiveView | null => {
  const b = context.breakdown
  if (b === undefined) return figures(context)
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

let latest = 0

const refresh = async ($: EngineInterface) => {
  const seq = ++latest
  let state: LiveState
  try {
    const { context } = await $.session.usage({ breakdown: 'summary' })
    state =
      context.tokens === undefined
        ? { view: null, error: null }
        : { view: toView(context), error: context.breakdown === undefined ? 'no breakdown in this session' : null }
  } catch (err) {
    const plain = await $.session.usage().catch(() => undefined)
    state = { view: plain === undefined ? null : figures(plain.context), error: err instanceof Error ? err.message : String(err) }
  }
  if (seq === latest) await update($, live, () => state)
}

const paneOpen = async ($: EngineInterface) => (await $.ui.panes()).some(pane => pane.id === PANE)

const NATIVE = 'The Desktop app shows this breakdown under Context in the session details panel; /context-budget live band keeps it above the prompt'

const desktopOnly = async ($: EngineInterface) => {
  const surfaces = await $.session.surfaces()
  return surfaces.includes('desktop') && !surfaces.includes('terminal')
}

const openPane = async ($: EngineInterface) => {
  if (await desktopOnly($)) {
    $.ui.toast(NATIVE)
    return
  }
  await refresh($)
  await $.ui.open({ id: PANE, title: TITLE })
}

const registerCommand = ($: EngineInterface) =>
  $.command.register({
    name: COMMAND,
    description: 'Live per-category context breakdown: live toggles the pane; live pane, band or off sets the display',
    argumentHint: 'live [pane|band|off]',
    immediate: true,
  })

export const register: Register = (on, options) => {
  const mode = atom({ plugin: 'context-budget', key: 'mode' } as const, isMode(options.live_display) ? options.live_display : 'pane')

  on('session.start', async ($, e, next) => {
    await registerCommand($)
    return next(e)
  }).catch(($, e, next) => next(e))

  let reregister = false

  on('session.end', async ($, e, next) => {
    reregister = true
    latest++
    await update($, live, () => ({ view: null, error: null }))
    return next(e)
  }).catch(($, e, next) => next(e))

  on('prompt.submit', async ($, e, next) => {
    if (reregister) {
      reregister = false
      await registerCommand($).catch(() => undefined)
    }
    return next(e)
  }).catch(($, e, next) => next(e))

  on('command.run', { command: COMMAND }, async ($, e) => {
    const [sub, arg, ...rest] = e.args.trim().split(/\s+/)
    if (sub !== 'live' || rest.length > 0 || (arg !== undefined && !isMode(arg))) {
      $.ui.toast(USAGE)
      return {}
    }
    if (arg === undefined) {
      if ((await read($, mode)) === 'off') {
        $.ui.toast('live display is off: /context-budget live pane or band turns it on')
      } else if (await paneOpen($)) {
        await $.ui.close({ id: PANE })
      } else {
        await openPane($)
      }
      return {}
    }
    await update($, mode, () => arg)
    if (arg === 'off') {
      if (await paneOpen($)) await $.ui.close({ id: PANE })
      return {}
    }
    if (arg === 'band' || (await paneOpen($))) await refresh($)
    else await openPane($)
    return {}
  }).catch(($, e, next) => next(e))

  on('session.measure', async ($, e, next) => {
    if (e.changed.includes('context') && ((await read($, mode)) === 'band' || (await paneOpen($)))) await refresh($)
    return next(e)
  }).catch(($, e, next) => next(e))

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => PaneBody($.ui.resolve(e), await read($, live), e.props.bodyColumns))

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const theirs = await next(e)
    if (e.props.hasSurvey || (await read($, mode)) !== 'band') return theirs
    const { view: v, error } = await read($, live)
    if (v === null || v.categories.length === 0 || error !== null) return theirs
    const draw = $.ui.resolve(e)
    const { Box } = draw
    return (
      <Box flexDirection="column">
        {e.surface === 'desktop' ? DesktopBand(draw, v) : Band(draw, v, e.props.bodyColumns)}
        {theirs}
      </Box>
    )
  }).catch(($, e, next) => next(e))
}
