import type { EngineInterface } from 'claude-code'

import { commandPieces } from '../pieces/index.js'
import type { Titles } from '../scene/lib.ts'
import { BUILD } from './build.js'
import { calibrateNext } from './clicks.js'
import { readNow } from './clock.js'
import { builtPieces, ctxOf } from './context.js'
import { NOT_BUILT, SWITCHES, type Ctx, type Switch } from './piece.js'
import { clearLook, holdShader, isShaderRunning, noteAsked, setLook } from './render.js'
import { defaults } from './saved.js'
import { OVERRIDES, accepts, type Override } from './settings.js'
import { switched } from './switched.js'
import { busiestMinute, failed, note, stats } from './telemetry.js'
import { ACCEPT } from './signals.gen.js'
import { DIRECTION, SECOND_STEP_MS, ask, commandScreen, commandSwitch, type Direction } from './values.js'

/** The longest title each place in the room holds. The pennant's lines are capped at what its taper fits at the drawn size. */
export const TITLE_CAPS = { console: 24, tape: 24, pennant: 12, 'pennant-top': 16 } as const
export type TitleKey = keyof typeof TITLE_CAPS
export const TITLE_KEYS = Object.keys(TITLE_CAPS) as TitleKey[]

/** The titles after /bedroom title KEY TEXT: TEXT capped to fit (the pennant's in capitals, as it is lettered); no TEXT puts the default back. */
export function withTitle(titles: Titles, key: TitleKey, text: string): Titles {
  const next = { ...titles }
  const trimmed = text.trim()

  if (trimmed === '') {
    delete next[key]
  } else {
    next[key] = (key.startsWith('pennant') ? trimmed.toUpperCase() : trimmed).slice(0, TITLE_CAPS[key])
  }

  return next
}

/** The words the pieces own. */
const PIECE_WORDS = ['time', 'weather', 'signal', 'hall', 'sound']
const WORDS = `The switches are ${SWITCHES.join(', ')}; also status, posters, dim, glass, blur, title (console, tape, pennant, pennant-top), shader, instant, sync, stats, calibrate, reset, on, off, ${PIECE_WORDS.join(', ')}, and <setting> default`

/** The status line: what is on and off, the posters and the dim. */
export function describe(ctx: Ctx): string {
  const state = ctx.saved.state
  const on = SWITCHES.filter(name => state[name])
  const off = SWITCHES.filter(name => !state[name])

  return `on: ${on.join(', ') || 'nothing'}. off: ${off.join(', ') || 'nothing'}. posters: ${state.posters}. dim: ${Math.round(ctx.saved.dim * 100)}`
}

/** How much longer than one move the last order to each switch takes to reach the shader, in ms: the card keeps its button inactive that much longer. */
const extra: Partial<Record<Switch, number>> = {}
export function extraMsOf(key: Switch): number {
  return extra[key] ?? 0
}

/** Shows the room alone for SETTLE_MS and brings the shader back, which sets every switch from what is saved. */
async function sync($: EngineInterface, why: string): Promise<void> {
  holdShader($, why)
  await ask($, why)
}

/** What `/bedroom WORDS` does and answers. The settings card's buttons call it with the words a person would type, so a button and its command cannot differ. */
export async function runCommand($: EngineInterface, args: string): Promise<string> {
  await readNow($)
  const ctx = ctxOf($)
  const words = args.trim().split(/ +/)
  const word = (words[0] ?? '').toLowerCase()
  const value = (words[1] ?? '').toLowerCase()
  const rest = words.slice(2).join(' ')
  note(`/bedroom ${word}`)

  if (word === '' || word === 'status') return describe(ctx)
  if (word === 'off') {
    const cleared = await clearLook($)
    return cleared.isDrawn ? 'the theme is cleared' : 'cleared'
  }
  if (word === 'on') {
    const set = await setLook($, ctx)
    return set.isDrawn ? 'the room is on' : `not drawn: ${set.reason}`
  }
  if ((OVERRIDES as readonly string[]).includes(word) && value === 'default') {
    await ctx.save({ [word]: undefined })
    await ctx.send(`/bedroom ${word} default`, { hurry: true })
    return `${word} follows its setting again (now ${String(ctx.setting(word as Override))})`
  }
  if (word === 'shader' || word === 'instant') {
    if (value !== '' && value !== 'on' && value !== 'off') return `say on or off, as in /bedroom ${word} off`
    const isOn = value === '' ? !ctx.setting('shader') : value === 'on'
    if (!accepts('shader', isOn)) return 'say on or off'
    await ctx.save({ shader: isOn })
    noteAsked()
    await ask($, `/bedroom ${word}`)
    if (word === 'instant') {
      return isOn ? 'instant switching is on: the television changes without sending the room again' : 'instant switching is off: every change sends the room again'
    }
    return isOn
      ? 'the shader is on: the switches change without sending the room again'
      : 'the shader is off for this session, for diagnosis: the hand-drawn room shows alone, with no fades, clock or lamp light, and every change sends it again'
  }
  if (word === 'glass' || word === 'blur') {
    const amount = Number(value)
    const most = word === 'glass' ? 95 : 40
    if (value === '' || !Number.isFinite(amount) || amount < 0 || amount > most) {
      return `give a number from 0 to ${most}, as in /bedroom ${word} ${word === 'glass' ? 30 : 4}. glass is how solid the panels over the room are (now ${Math.round(ctx.saved.glass * 100)}); blur is how much they blur it (now ${ctx.saved.blur})`
    }
    await ctx.save(word === 'glass' ? { glass: amount / 100 } : { blur: amount })
    const set = await setLook($, ctx)
    return set.isDrawn ? `glass ${Math.round(ctx.saved.glass * 100)}, blur ${ctx.saved.blur}` : `not drawn: ${set.reason}`
  }
  if (word === 'title') {
    if (!(TITLE_KEYS as string[]).includes(value)) {
      return `say which: /bedroom title console|tape|pennant|pennant-top <text>; with no text it goes back to the default. Now: ${TITLE_KEYS.map(key => `${key} "${ctx.saved.titles[key] ?? 'default'}"`).join(', ')}`
    }
    const key = value as TitleKey
    const titles = withTitle(ctx.saved.titles, key, rest)
    await ctx.save({ titles })
    noteAsked()
    await ask($, `/bedroom title ${key}`)
    return `the ${key} title is ${titles[key] === undefined ? 'the default' : `"${titles[key]}"`}; this sends the room once`
  }
  if (word === 'stats') {
    return `renders: ${stats.renders}. room sent: ${stats.roomSends}. changed by numbers only: ${stats.valueOnly} (most in one minute this hour: ${busiestMinute(ctx.nowMs)}). last render asked ${stats.askMs.toFixed(1)} ms after the change, built in ${stats.buildMs.toFixed(1)} ms (slowest ${stats.maxBuildMs.toFixed(1)} ms). room size: ${stats.chars} of 131072 characters. shader: ${ctx.setting('shader') ? 'on' : 'off'}. build: ${BUILD}`
  }
  if (word === 'calibrate') {
    calibrateNext()
    return 'click the bottom-left corner of the front of the dresser'
  }
  if (word === 'sync') {
    await sync($, '/bedroom sync')
    return 'the room shows alone for 7 seconds, then the shader comes back with every switch as saved'
  }
  if (word === 'reset') {
    const keep = { aspect: ctx.saved.aspect, titles: ctx.saved.titles }
    for (const key of SWITCHES) extra[key] = 0
    await ctx.save({ ...defaults(), ...keep, time: undefined, weather: undefined, sound: undefined, signal: undefined, hall: undefined, shader: undefined })
    await setLook($, ctx)
    noteAsked()
    await sync($, '/bedroom reset')
    return describe(ctx)
  }
  if (word === 'dim') {
    const percent = Number(value)
    if (!Number.isFinite(percent) || percent < 0 || percent > 80) return 'give a number from 0 to 80, as in /bedroom dim 30'
    await ctx.save({ dim: percent / 100 })
    noteAsked()
    await ask($, '/bedroom dim')
    return describe(ctx)
  }
  if (word === 'posters') {
    if (value !== 'plain') return 'posters is plain'
    await ctx.save({ state: { ...ctx.saved.state, posters: value } })
    noteAsked()
    await ask($, '/bedroom posters')
    return describe(ctx)
  }
  if ((SWITCHES as readonly string[]).includes(word)) {
    const key = word as Switch
    if (value !== '' && value !== 'on' && value !== 'off') return `say on or off, as in /bedroom ${word} off; with neither, it flips`
    const belief = ctx.saved.state[key]
    const isOn = value === '' ? !belief : value === 'on'
    const already = `the ${key} is already ${isOn ? 'on' : 'off'}`
    const synced = `${already}. If the room shows it otherwise, /bedroom sync draws every switch from what is saved`
    if (!isShaderRunning()) {
      if (belief === isOn) return already
      extra[key] = 0
      await ctx.save({ state: { ...ctx.saved.state, [key]: isOn } })
      noteAsked()
      await ask($, `/bedroom ${key}`)
    } else if ((DIRECTION as readonly string[]).includes(key)) {
      const order = commandSwitch(key as Direction, isOn ? 1 : 0, belief)
      if (order === 'already') return synced
      extra[key] = order === 'turned' ? SECOND_STEP_MS : 0
      await ctx.save({ state: { ...ctx.saved.state, [key]: isOn } })
      noteAsked()
      await ask($, `/bedroom ${key}`)
    } else {
      if (belief === isOn) return synced
      await ctx.save({ state: { ...ctx.saved.state, [key]: isOn } })
      noteAsked()
      extra[key] = (await commandScreen($, key as 'tape' | 'console', isOn ? 1 : 0, `/bedroom ${key}`)) + ACCEPT.screen * 1000
    }
    switched($, ctx, key, isOn, 'command')
    return describe(ctx)
  }
  const answer = await commandPieces($, ctx, word, words.slice(1))
  if (answer !== undefined) return answer
  for (const piece of builtPieces()) {
    const handler = piece.commands?.[word]
    if (handler === undefined) continue
    try {
      return await handler(ctx, words.slice(1))
    } catch (error) {
      failed(piece.name, `${word} command`, error)
      return `the ${piece.name} piece could not answer: ${error instanceof Error ? error.message : String(error)}`
    }
  }
  if (PIECE_WORDS.includes(word)) return NOT_BUILT
  return `no such setting. ${WORDS}`
}
