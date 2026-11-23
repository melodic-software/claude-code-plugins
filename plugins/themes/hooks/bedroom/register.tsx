import type { EngineInterface, Register } from 'claude-code'

import { CARD_ROW, forgetDraft, openCard, readCard, refreshCard, settingsCard, shownIn } from './card.tsx'
import { BUILD } from './core/build.js'
import { handleClick } from './core/clicks.js'
import { minuteOfHalfDay, readNow, startMinuteChain } from './core/clock.js'
import { describe, runCommand } from './core/commands.js'
import { ctxOf, usePieces } from './core/context.js'
import { SCENE, colorProblems, draw, holdShader, isThemeOn, markCovered, markStarted, setLook } from './core/render.js'
import { load } from './core/saved.js'
import { useOptions } from './core/settings.js'
import { failed, flush, note } from './core/telemetry.js'
import { ask, sendMinute, want } from './core/values.js'
import { PIECES, addHooks, startPieces, tickPieces } from './pieces/index.js'

export { CHANGE_MS } from './card.tsx'
export { aspectFrom, hitAt, hitsAt, switchesAt, toViewBox } from './core/clicks.js'
export { TITLE_CAPS, withTitle } from './core/commands.js'

/** Whether session.start has run: a desktop attaching before it leaves the start to session.start. */
let isSessionUp = false
/** Whether the room started in this session: it starts only once a desktop surface is attached. */
let started = false
/** Set while the last desktop window has detached: /bedroom says so. */
let desktopGone = false

/** Registers /bedroom and starts the room, once a session: at session.start with a desktop attached, or on the first desktop attach. */
async function start($: EngineInterface): Promise<void> {
  if (started) return
  started = true
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
}

/** The bedroom theme: wires the hooks to core/, the settings card and the pieces of this build (pieces/index.ts). */
export const register: Register = (on, options) => {
  useOptions(options)
  usePieces(PIECES)
  addHooks(on)

  on('session.start', async ($, e, next) => {
    isSessionUp = true
    started = false
    if (e.surface === 'desktop' || (await $.session.surfaces()).includes('desktop')) await start($)
    return next(e)
  })

  on('session.attach', { surface: 'desktop' }, async ($, e, next) => {
    desktopGone = false
    if (isSessionUp) await start($)
    return next(e)
  })

  on('session.detach', { surface: 'desktop' }, ($, e, next) => {
    if (started) desktopGone = true
    return next(e)
  })

  on('theme.clear', async ($, e, next) => {
    const cleared = await next(e)
    if (next.origin.plugin === $.plugin.name || !isThemeOn()) return cleared
    note(`${next.origin.plugin} cleared the theme while the room is on: setting the room again`)
    try {
      await setLook($, ctxOf($))
      holdShader($, 'the room set again')
      await ask($, 'the room set again')
    } catch (error) {
      note(`setting the room again failed: ${error instanceof Error ? error.message : String(error)}`)
    }
    flush($)
    return cleared
  }).catch(($, e, next) => next(e))

  on('theme.set', async ($, e, next) => {
    const set = await next(e)
    if (next.origin.plugin === $.plugin.name || !isThemeOn()) return set
    note(`${next.origin.plugin} set its theme over the room: the room is covered until /bedroom on`)
    markCovered(next.origin.plugin)
    void refreshCard($).catch(() => undefined)
    flush($)
    return set
  }).catch(($, e, next) => next(e))

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
    const answer = await runCommand($, e.args)
    const text = desktopGone ? `no desktop window shows this session; ${answer}` : answer
    flush($)
    const [word = '', key = ''] = e.args.trim().toLowerCase().split(/ +/)
    if (word === 'title') forgetDraft(key)
    if (e.args.trim() === '') {
      await openCard($)
      return { text, isTextDisplayOnly: true }
    }
    await refreshCard($, undefined, describe(ctxOf($)))
    return { text, isTextDisplayOnly: true }
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
