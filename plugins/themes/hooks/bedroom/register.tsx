import type { Register } from 'claude-code'

import { CARD_ROW, forgetDraft, openCard, readCard, refreshCard, settingsCard, shownIn } from './card.tsx'
import { BUILD } from './core/build.js'
import { handleClick } from './core/clicks.js'
import { minuteOfHalfDay, readNow, startMinuteChain } from './core/clock.js'
import { describe, runCommand } from './core/commands.js'
import { ctxOf, usePieces } from './core/context.js'
import { SCENE, colorProblems, draw, markStarted, setLook } from './core/render.js'
import { load } from './core/saved.js'
import { useOptions } from './core/settings.js'
import { failed, flush, note } from './core/telemetry.js'
import { ask, sendMinute, want } from './core/values.js'
import { PIECES, addHooks, startPieces, tickPieces } from './pieces/index.js'

export { CHANGE_MS } from './card.tsx'
export { aspectFrom, hitAt, hitsAt, switchesAt, toViewBox } from './core/clicks.js'
export { TITLE_CAPS, withTitle } from './core/commands.js'

/** The bedroom theme: wires the hooks to core/, the settings card and the pieces of this build (pieces/index.ts). */
export const register: Register = (on, options) => {
  useOptions(options)
  usePieces(PIECES)
  addHooks(on)

  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'bedroom',
      description:
        'The bedroom theme of the themes plugin: alone it shows the settings card in the desktop app; status, tv, tape, console, pc, light, lamp, lava (on or off), time, date, weather, signal, hall, shader, sound, posters, dim, glass, blur, title (console, tape, pennant, pennant-top), sync, stats, calibrate, reset, on, off',
    })
    await load($)
    await readNow($)
    markStarted()
    const unpainted = colorProblems.find(line => line.startsWith("Desktop won't paint"))
    if (unpainted !== undefined) $.ui.toast(unpainted)
    const set = await setLook($, ctxOf($))
    note(`loaded build ${BUILD}: ${set.isDrawn ? 'drawn' : `not drawn, ${set.reason}`}`)
    await readCard($)
    await startPieces($, ctxOf($))
    await startMinuteChain($, async gap => {
      const ctx = ctxOf($)
      for (const piece of PIECES) {
        try {
          await piece.tick?.(ctx)
        } catch (error) {
          failed(piece.name, 'tick', error)
        }
      }
      await tickPieces($, ctx)
      want('clock', minuteOfHalfDay(ctx.nowMs))
      await sendMinute($, ctx.fields(), gap)
      void refreshCard($).catch(() => undefined)
    })
    flush($)
    if (!set.isDrawn) $.ui.toast(`bedroom is not drawn: ${set.reason}`)
    await ask($, 'the session starting')
    return next(e)
  })

  on('ui.render', { component: 'Backdrop' }, ($, e, next) => {
    if (e.props.plugin !== $.plugin.name || e.props.scene !== SCENE || e.surface !== 'desktop') return next(e)
    const { Shader, Svg } = $.ui.resolve(e)
    const drawing = draw($, ctxOf($))
    const svg = <Svg source={drawing.source} alt="A teenager's bedroom in the country" isInteractive />
    if (drawing.values === undefined) return svg
    return (
      <Shader module="./lights.ts" values={drawing.values}>
        {svg}
      </Shader>
    )
  })

  on('ui.pointer', async ($, e, next) => {
    if (e.scene !== SCENE) return next(e)
    const struck = await handleClick($, e)
    flush($)
    if (struck === undefined) return next(e)
    void refreshCard($, struck === 'calibrated' ? `clicks calibrated (window shape ${ctxOf($).saved.aspect.toFixed(2)})` : undefined).catch(() => undefined)
    return {}
  })

  on('command.run', { command: 'bedroom' }, async ($, e) => {
    const text = await runCommand($, e.args)
    flush($)
    const [word = '', key = ''] = e.args.trim().toLowerCase().split(/ +/)
    if (word === 'title') forgetDraft(key)
    if (e.args.trim() === '') {
      await openCard($)
      return { text }
    }
    await refreshCard($, undefined, describe(ctxOf($)))
    return { text }
  })

  on('ui.render', { component: 'Placed' }, async ($, e, next) => {
    if (e.props.plugin !== $.plugin.name || !e.props.id.startsWith(CARD_ROW) || e.surface !== 'desktop') return next(e)
    const now = await shownIn($, e.props.id, false)
    if (now === undefined) return next(e)
    return settingsCard($, $.ui.resolve(e), now)
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (e.surface !== 'desktop') return next(e)
    const now = await shownIn($, undefined, true)
    if (now === undefined) return next(e)
    return settingsCard($, $.ui.resolve(e), now)
  })
}
