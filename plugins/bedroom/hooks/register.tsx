import type { Register, ThemeSetArgs } from 'claude-code'

import { makeColors } from './make-colors.js'
import { bedroomSvg } from './scene.ts'
import { DEFAULT_STATE, HITS, type State } from './scene/lib.ts'

const SCENE = 'bedroom'
const SWITCHES = ['tv', 'tape', 'console', 'pc', 'light', 'lamp', 'lava'] as const
type Switch = (typeof SWITCHES)[number]

/** What is saved across sessions: the switches, how far back the room sits, and the window's shape for clicks. */
type Saved = { state: State; dim: number; aspect: number; glass: number; blur: number; titles: Titles }
/** The titles written in the room, kept on this machine only: the console game's and the tape's. Absent, the made-up defaults show. */
type Titles = { console?: string; tape?: string }

const DEFAULT_ASPECT = 2000 / 1062
const CALIBRATION_POINT = { x: 1110, y: 906 }

const DEFAULT_GLASS = 0
const DEFAULT_BLUR = 0
let saved: Saved = { state: { ...DEFAULT_STATE }, dim: 0, aspect: DEFAULT_ASPECT, glass: DEFAULT_GLASS, blur: DEFAULT_BLUR, titles: {} }
let isCalibrating = false
let isInstant = true

/** What /bedroom stats reports. The times are this module's own: the app's drawing time cannot be read from a mod. */
const stats = { renders: 0, roomSends: 0, valueOnly: 0, buildMs: 0, maxBuildMs: 0, askMs: 0, chars: 0 }
let askedAt: number | undefined
const BUILD = 'wave1-nocursor-36'
const IS_DUSK_COMPUTED = true
const INSTANT = IS_DUSK_COMPUTED ? ['tv', 'lava', 'pc', 'lamp', 'tape', 'console', 'light'] : ['tv', 'lava', 'pc', 'lamp', 'tape', 'console']
let sent: Record<string, number> = {}
const sendAll = (): void => {
  sent = Object.fromEntries(SWITCHES.map(name => [name, saved.state[name] ? 1 : 0]))
}

sendAll()
/** The last things that happened, newest last, written to telemetry.json in the mod's folder. */
const events: string[] = []
let lastCause = 'load'

function note(line: string): void {
  events.push(`${new Date().toISOString()} ${line}`)
  if (events.length > 200) {
    events.shift()
  }
}
let lastSource = ''
const SETTLE_MS = 7000
let holdShaderUntil = 0

const { theme, problems } = makeColors({
  label: 'Bedroom',
  only: 'dark',
  roles: { accent: '#5b8cff', danger: '#e0564a', success: '#6fbf6a', warning: '#e8a23c', pro: '#b48be0' },
  dark: {
    gray: {
      anchors: {
        'surface-0': '#0f1120',
        'surface-1': '#15182a',
        'surface-2': '#1a1e33',
        'surface-3': '#1e223a',
        'text-primary': '#efe9db',
        'text-secondary': '#c9c3b6',
        'text-muted': '#a39fa8',
      },
    },
  },
})

function look(): ThemeSetArgs {
  return {
    colors: theme,
    backdrop: { scene: SCENE, glass: { blur: saved.blur, tint: '#0b0d18', opacity: saved.glass } },
  }
}

/** A click, given as fractions of the window, in the scene's own viewBox units. The scene is 1600 by 1000, cropped to fill. */
export function toViewBox(x: number, y: number, aspect: number): { x: number; y: number } {
  const width = Math.min(1600, 1000 * aspect)
  const height = Math.min(1000, 1600 / aspect)

  return { x: 800 + (x - 0.5) * width, y: 500 + (y - 0.5) * height }
}

/** The thing a viewBox point lands on, if any. */
export function hitAt(x: number, y: number): string | undefined {
  for (const [name, [left, top, width, height]] of Object.entries(HITS)) {
    if (x >= left && x <= left + width && y >= top && y <= top + height) {
      return name
    }
  }

  return undefined
}

/** The minute of the half day, 0 to 719, by the computer's own local time: what the VCR clock shows. */
function minuteOfHalfDay(): number {
  const now = new Date()

  return (now.getHours() % 12) * 60 + now.getMinutes()
}

function describe(): string {
  const on = SWITCHES.filter(name => saved.state[name])
  const off = SWITCHES.filter(name => !saved.state[name])

  return `on: ${on.join(', ') || 'nothing'}. off: ${off.join(', ') || 'nothing'}. posters: ${saved.state.posters}. dim: ${Math.round(saved.dim * 100)}`
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'bedroom',
      description: 'The bedroom theme: tv, tape, console, pc, light, lamp, lava (on or off), posters, dim, glass, blur, title, instant, stats, calibrate, reset, off',
    })
    const stored = (await $.store.get('saved')) as Partial<Saved> | undefined

    if (stored !== undefined) {
      saved = {
        state: { ...DEFAULT_STATE, ...stored.state },
        dim: typeof stored.dim === 'number' ? stored.dim : 0,
        aspect: typeof stored.aspect === 'number' ? stored.aspect : DEFAULT_ASPECT,
        glass: typeof stored.glass === 'number' ? stored.glass : DEFAULT_GLASS,
        blur: typeof stored.blur === 'number' ? stored.blur : DEFAULT_BLUR,
        titles: typeof stored.titles === 'object' && stored.titles !== null ? stored.titles : {},
      }
      sendAll()
    }
    const unpainted = problems.find(line => line.startsWith("Desktop won't paint"))

    if (unpainted !== undefined) {
      $.ui.toast(unpainted)
    }
    const set = await $.theme.set(look())

    note(`loaded build ${BUILD}: ${set.isDrawn ? 'drawn' : `not drawn, ${set.reason}`}; local time ${new Date().toTimeString()}`)
    const tick = (): void => {
      $.clock.after(60_050 - (Date.now() % 60_000), () => {
        lastCause = 'the minute turning'
        $.ui.invalidate('ui.render')
        tick()
      })
    }

    tick()
    void $.fs.write(`${$.plugin.root}/telemetry.json`, JSON.stringify({ build: BUILD, stats, events }, null, 1)).catch(() => undefined)
    if (!set.isDrawn) {
      $.ui.toast(`bedroom is not drawn: ${set.reason}`)
    }

    return next(e)
  })

  on('ui.render', { component: 'Backdrop' }, ($, e, next) => {
    if (e.props.plugin !== $.plugin.name || e.props.scene !== SCENE || e.surface !== 'desktop') {
      return next(e)
    }
    const { Shader, Svg } = $.ui.resolve(e)
    const startedAt = performance.now()
    const source = isInstant
      ? bedroomSvg({ ...saved.state, tv: true, lava: false, pc: true, lamp: false, tape: false, console: false, light: IS_DUSK_COMPUTED ? true : saved.state.light, titles: saved.titles }, saved.dim)
      : bedroomSvg({ ...saved.state, titles: saved.titles }, saved.dim)
    const buildMs = performance.now() - startedAt

    stats.renders += 1
    stats.buildMs = buildMs
    stats.maxBuildMs = Math.max(stats.maxBuildMs, buildMs)
    stats.chars = source.length
    if (askedAt !== undefined) {
      stats.askMs = startedAt - askedAt
      askedAt = undefined
    }
    note(`render ${stats.renders} after ${lastCause}: ${source === lastSource ? 'numbers only' : 'ROOM SENT'}, asked after ${stats.askMs.toFixed(0)} ms, built in ${buildMs.toFixed(1)} ms, instant ${isInstant ? 'on' : 'off'}, state ${JSON.stringify(saved.state)}`)
    if (source === lastSource) {
      stats.valueOnly += 1
    } else {
      stats.roomSends += 1
      if (isInstant) {
        holdShaderUntil = performance.now() + SETTLE_MS
        note(`room changed while the shader ran: drawing the room alone for ${SETTLE_MS} ms`)
        $.clock.after(SETTLE_MS + 200, () => {
          lastCause = 'the room settling'
          $.ui.invalidate('ui.render')
        })
      }
      lastSource = source
    }
    void $.fs.write(`${$.plugin.root}/telemetry.json`, JSON.stringify({ build: BUILD, stats, events }, null, 1)).catch(() => undefined)
    $.ui.log(`bedroom render ${stats.renders}: asked after ${stats.askMs.toFixed(1)} ms, built in ${buildMs.toFixed(1)} ms, ${source.length} chars, room sent ${stats.roomSends} times`, { to: 'debug' })
    const svg = <Svg source={source} alt="A teenager's bedroom in the country just after sunset" isInteractive />

    if (!isInstant || performance.now() < holdShaderUntil) {
      return svg
    }

    return (
      <Shader module="./lights.ts" values={{ ...sent, clock: minuteOfHalfDay() }}>
        {svg}
      </Shader>
    )
  })

  on('ui.pointer', async ($, e, next) => {
    try {
    if (e.scene !== SCENE) {
      return next(e)
    }
    if (isCalibrating) {
      isCalibrating = false
      const across = e.x - 0.5
      const down = e.y - 0.5
      const width = across > 0.02 ? (CALIBRATION_POINT.x - 800) / across : 1600
      const height = down > 0.02 ? (CALIBRATION_POINT.y - 500) / down : 1000
      const aspect = width < 1590 ? width / 1000 : height < 990 ? 1600 / height : 1.6

      saved = { ...saved, aspect: Math.min(4, Math.max(0.5, aspect)) }
      await $.store.set('saved', saved)
      $.ui.toast(`bedroom: clicks calibrated (window shape ${saved.aspect.toFixed(2)})`)

      return {}
    }
    const point = toViewBox(e.x, e.y, saved.aspect)
    const struck = hitAt(point.x, point.y)
    const name = struck === 'spine' ? 'tape' : struck

    lastCause = `click at ${e.x.toFixed(3)},${e.y.toFixed(3)} (room ${point.x.toFixed(0)},${point.y.toFixed(0)}) on ${name ?? 'nothing'}${name !== undefined && !INSTANT.includes(name) && name !== 'cat' ? ', which sends the room' : ''}`
    note(lastCause)

    if (name === undefined) {
      return next(e)
    }
    if (name === 'cat') {
      $.ui.toast('the cat purrs')

      return {}
    }
    const key = name as Switch

    saved = { ...saved, state: { ...saved.state, [key]: !saved.state[key] } }
    note(`${key} is now ${saved.state[key] ? 'on' : 'off'}`)
    if (!(isInstant && INSTANT.includes(key))) {
      sent = { ...sent, [key]: saved.state[key] ? 1 : 0 }
      askedAt = performance.now()
      $.ui.invalidate('ui.render')
    }
    void $.store.set('saved', saved).catch(() => undefined)

    return {}
    } finally {
      void $.fs.write(`${$.plugin.root}/telemetry.json`, JSON.stringify({ build: BUILD, stats, events }, null, 1)).catch(() => undefined)
    }
  })

  on('command.run', { command: 'bedroom' }, async ($, e) => {
    const [word = '', value = ''] = e.args.trim().toLowerCase().split(/ +/)
    const rest = e.args.trim().split(/ +/).slice(2).join(' ')

    lastCause = `/bedroom ${word} ${value}`.trim()
    note(lastCause)

    if (word === '') {
      return { text: describe() }
    }
    if (word === 'off') {
      const cleared = await $.theme.clear()

      return { text: cleared.isDrawn ? 'the theme is cleared' : 'cleared' }
    }
    if (word === 'on') {
      const set = await $.theme.set(look())

      return { text: set.isDrawn ? 'the room is on' : `not drawn: ${set.reason}` }
    }
    if (word === 'instant') {
      isInstant = value === '' ? !isInstant : value === 'on'
      askedAt = performance.now()
      $.ui.invalidate('ui.render')

      return { text: isInstant ? 'instant switching is on: the television changes without sending the room again' : 'instant switching is off: every change sends the room again' }
    }
    if (word === 'glass' || word === 'blur') {
      const amount = Number(value)
      const most = word === 'glass' ? 95 : 40

      if (value === '' || !Number.isFinite(amount) || amount < 0 || amount > most) {
        return { text: `give a number from 0 to ${most}, as in /bedroom ${word} ${word === 'glass' ? 30 : 4}. glass is how solid the panels over the room are (now ${Math.round(saved.glass * 100)}); blur is how much they blur it (now ${saved.blur})` }
      }
      saved = word === 'glass' ? { ...saved, glass: amount / 100 } : { ...saved, blur: amount }
      await $.store.set('saved', saved)
      const set = await $.theme.set(look())

      return { text: set.isDrawn ? `glass ${Math.round(saved.glass * 100)}, blur ${saved.blur}` : `not drawn: ${set.reason}` }
    }
    if (word === 'title') {
      if (value !== 'console' && value !== 'tape') {
        return { text: `say which: /bedroom title console <text> or /bedroom title tape <text>; with no text it goes back to the default. Now: console "${saved.titles.console ?? 'default'}", tape "${saved.titles.tape ?? 'default'}"` }
      }
      const titles = { ...saved.titles }

      if (rest === '') {
        delete titles[value]
      } else {
        titles[value] = rest.slice(0, 24)
      }
      saved = { ...saved, titles }
      askedAt = performance.now()
      $.ui.invalidate('ui.render')
      await $.store.set('saved', saved)

      return { text: `the ${value}'s title is ${rest === '' ? 'the default' : `"${titles[value]}"`}; this sends the room once` }
    }
    if (word === 'stats') {
      return {
        text: `renders: ${stats.renders}. room sent: ${stats.roomSends}. changed by numbers only: ${stats.valueOnly}. last render asked ${stats.askMs.toFixed(1)} ms after the change, built in ${stats.buildMs.toFixed(1)} ms (slowest ${stats.maxBuildMs.toFixed(1)} ms). room size: ${stats.chars} of 131072 characters. instant: ${isInstant ? 'on' : 'off'}. build: ${BUILD}`,
      }
    }
    if (word === 'calibrate') {
      isCalibrating = true

      return { text: 'click the bottom-left corner of the front of the dresser' }
    }
    if (word === 'reset') {
      saved = { state: { ...DEFAULT_STATE }, dim: 0, aspect: saved.aspect, glass: DEFAULT_GLASS, blur: DEFAULT_BLUR, titles: saved.titles }
      sendAll()
      await $.theme.set(look())
    } else if (word === 'dim') {
      const percent = Number(value)

      if (!Number.isFinite(percent) || percent < 0 || percent > 80) {
        return { text: 'give a number from 0 to 80, as in /bedroom dim 30' }
      }
      saved = { ...saved, dim: percent / 100 }
    } else if (word === 'posters') {
      if (value !== 'plain') {
        return { text: 'posters is plain' }
      }
      saved = { ...saved, state: { ...saved.state, posters: value } }
    } else if ((SWITCHES as readonly string[]).includes(word)) {
      const key = word as Switch

      if (value !== '' && value !== 'on' && value !== 'off') {
        return { text: `say on or off, as in /bedroom ${word} off; with neither, it flips` }
      }
      saved = { ...saved, state: { ...saved.state, [key]: value === '' ? !saved.state[key] : value === 'on' } }
      const place = saved.state[key] ? 1 : 0

      sent = { ...sent, [key]: 0.5 }
      $.clock.after(700, () => {
        sent = { ...sent, [key]: place }
        $.ui.invalidate('ui.render')
      })
    } else {
      return { text: `no such setting. The switches are ${SWITCHES.join(', ')}; also posters, dim, glass, blur, title, instant, stats, calibrate, reset, on, off` }
    }
    askedAt = performance.now()
    $.ui.invalidate('ui.render')
    await $.store.set('saved', saved)

    return { text: describe() }
  })
}
