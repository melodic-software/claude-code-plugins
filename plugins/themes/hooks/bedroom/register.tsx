import { atom, read, update } from 'claude-code'
import type { ElementTable, EngineInterface, Register, ThemeSetArgs } from 'claude-code'

import type { BedroomCard } from '../../types'
import { makeColors } from '../make-colors.js'
import { bedroomSvg } from './scene.ts'
import { DEFAULT_STATE, HITS, type State, type Titles } from './scene/lib.ts'

const SCENE = 'bedroom'
/** The settings card's rows are named this, then a count: a new row for each `/bedroom`, so the card stands at the transcript's end. */
const CARD_ROW = 'bedroom-card'
const card = atom({ plugin: 'themes', key: 'bedroom-card' } as const, {}, { shape: 'bedroom-card-1' })
/** Whether a card is up, kept beside the atom so a click in the room with no card up writes nothing more than before. */
let isCardOpen = false
/** Whether the theme is set: the card's theme button shows it. */
let isThemeOn = false
/** The key the bedroom's settings are stored under in the themes plugin's store, named for the theme so another theme's cannot collide. */
const STORE_KEY = 'bedroom:saved'
const SWITCHES = ['tv', 'tape', 'console', 'pc', 'light', 'lamp', 'lava'] as const
type Switch = (typeof SWITCHES)[number]

/** What is saved across sessions: the switches, how far back the room sits, and the window's shape for clicks. */
type Saved = { state: State; dim: number; aspect: number; glass: number; blur: number; titles: Titles }

/** The longest title each place in the room holds. The pennant's lines are capped at what its taper fits at the drawn size. */
export const TITLE_CAPS = { console: 24, tape: 24, pennant: 12, 'pennant-top': 16 } as const
type TitleKey = keyof typeof TITLE_CAPS
const TITLE_KEYS = Object.keys(TITLE_CAPS) as TitleKey[]
/** Text typed into a title field and not yet set, so a redraw of the card (the minute's tick, another press) keeps it. */
const drafts: Partial<Record<TitleKey, string>> = {}

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
/** The build /bedroom stats names, so a tester can tell which one the app loaded. */
const BUILD = 'settings-card-1'
/** The switches the shader answers by itself in instant mode: every one, since the shader computes the dusk light. */
const INSTANT: readonly string[] = SWITCHES
let sent: Record<string, number> = {}
/** False after a render that drew the room without the shader: a shader started again takes its switches from `sent`, so the next one re-seeds it. */
let isShaderSeeded = false
const sendAll = (): void => {
  sent = Object.fromEntries(SWITCHES.map(name => [name, saved.state[name] ? 1 : 0]))
}

sendAll()
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

/** Every thing a viewBox point lands on: the shader flips each switch whose rectangle holds a click, so where rectangles overlap a click lands on more than one. */
export function hitsAt(x: number, y: number): string[] {
  return Object.entries(HITS)
    .filter(([, [left, top, width, height]]) => x >= left && x <= left + width && y >= top && y <= top + height)
    .map(([name]) => name)
}

/** The first thing a viewBox point lands on, if any. */
export function hitAt(x: number, y: number): string | undefined {
  return hitsAt(x, y)[0]
}

/** The switches a viewBox point flips, as the shader flips them: the tape's spine is the tape. */
export function switchesAt(x: number, y: number): string[] {
  return [...new Set(hitsAt(x, y).map(name => (name === 'spine' ? 'tape' : name)))]
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

/** Sets the bedroom's look and notes that the theme is on: a set stands for the session whether or not a surface draws it. */
async function setLook($: EngineInterface): Promise<Awaited<ReturnType<EngineInterface['theme']['set']>>> {
  const set = await $.theme.set(look())

  isThemeOn = true

  return set
}

/** What `/bedroom WORDS` does and answers. The settings card's buttons call it with the words a person would type, so a button and its command cannot differ. */
async function bedroomCommand($: EngineInterface, args: string): Promise<string> {
  const [word = '', value = ''] = args.trim().toLowerCase().split(/ +/)
  const rest = args.trim().split(/ +/).slice(2).join(' ')

  if (word === '' || word === 'status') {
    return describe()
  }
  if (word === 'off') {
    const cleared = await $.theme.clear()

    isThemeOn = false

    return cleared.isDrawn ? 'the theme is cleared' : 'cleared'
  }
  if (word === 'on') {
    const set = await setLook($)

    return set.isDrawn ? 'the room is on' : `not drawn: ${set.reason}`
  }
  if (word === 'instant') {
    isInstant = value === '' ? !isInstant : value === 'on'
    askedAt = performance.now()
    $.ui.invalidate('ui.render')

    return isInstant ? 'instant switching is on: the television changes without sending the room again' : 'instant switching is off: every change sends the room again'
  }
  if (word === 'glass' || word === 'blur') {
    const amount = Number(value)
    const most = word === 'glass' ? 95 : 40

    if (value === '' || !Number.isFinite(amount) || amount < 0 || amount > most) {
      return `give a number from 0 to ${most}, as in /bedroom ${word} ${word === 'glass' ? 30 : 4}. glass is how solid the panels over the room are (now ${Math.round(saved.glass * 100)}); blur is how much they blur it (now ${saved.blur})`
    }
    saved = word === 'glass' ? { ...saved, glass: amount / 100 } : { ...saved, blur: amount }
    await $.store.set(STORE_KEY, saved)
    const set = await setLook($)

    return set.isDrawn ? `glass ${Math.round(saved.glass * 100)}, blur ${saved.blur}` : `not drawn: ${set.reason}`
  }
  if (word === 'title') {
    if (!(TITLE_KEYS as string[]).includes(value)) {
      return `say which: /bedroom title console|tape|pennant|pennant-top <text>; with no text it goes back to the default. Now: ${TITLE_KEYS.map(key => `${key} "${saved.titles[key] ?? 'default'}"`).join(', ')}`
    }
    const key = value as TitleKey
    const titles = withTitle(saved.titles, key, rest)

    delete drafts[key]
    saved = { ...saved, titles }
    askedAt = performance.now()
    $.ui.invalidate('ui.render')
    await $.store.set(STORE_KEY, saved)

    return `the ${key} title is ${titles[key] === undefined ? 'the default' : `"${titles[key]}"`}; this sends the room once`
  }
  if (word === 'stats') {
    return `renders: ${stats.renders}. room sent: ${stats.roomSends}. changed by numbers only: ${stats.valueOnly}. last render asked ${stats.askMs.toFixed(1)} ms after the change, built in ${stats.buildMs.toFixed(1)} ms (slowest ${stats.maxBuildMs.toFixed(1)} ms). room size: ${stats.chars} of 131072 characters. instant: ${isInstant ? 'on' : 'off'}. build: ${BUILD}`
  }
  if (word === 'calibrate') {
    isCalibrating = true

    return 'click the bottom-left corner of the front of the dresser'
  }
  if (word === 'reset') {
    saved = { state: { ...DEFAULT_STATE }, dim: 0, aspect: saved.aspect, glass: DEFAULT_GLASS, blur: DEFAULT_BLUR, titles: saved.titles }
    sendAll()
    await setLook($)
  } else if (word === 'dim') {
    const percent = Number(value)

    if (!Number.isFinite(percent) || percent < 0 || percent > 80) {
      return 'give a number from 0 to 80, as in /bedroom dim 30'
    }
    saved = { ...saved, dim: percent / 100 }
  } else if (word === 'posters') {
    if (value !== 'plain') {
      return 'posters is plain'
    }
    saved = { ...saved, state: { ...saved.state, posters: value } }
  } else if ((SWITCHES as readonly string[]).includes(word)) {
    const key = word as Switch

    if (value !== '' && value !== 'on' && value !== 'off') {
      return `say on or off, as in /bedroom ${word} off; with neither, it flips`
    }
    saved = { ...saved, state: { ...saved.state, [key]: value === '' ? !saved.state[key] : value === 'on' } }
    const place = saved.state[key] ? 1 : 0

    sent = { ...sent, [key]: 0.5 }
    $.clock.after(700, () => {
      sent = { ...sent, [key]: place }
      $.ui.invalidate('ui.render')
    })
  } else {
    return `no such setting. The switches are ${SWITCHES.join(', ')}; also status, posters, dim, glass, blur, title (console, tape, pennant, pennant-top), instant, stats, calibrate, reset, on, off`
  }
  askedAt = performance.now()
  $.ui.invalidate('ui.render')
  await $.store.set(STORE_KEY, saved)

  return describe()
}

/** How far the card's buttons move dim, glass and blur, inside the range each command takes. */
const STEPS = { dim: { by: 10, most: 80 }, glass: { by: 10, most: 95 }, blur: { by: 4, most: 40 } } as const
type Stepped = keyof typeof STEPS
const STEPPED = Object.keys(STEPS) as Stepped[]

/** A stepped setting as its command takes it: dim and glass in percent, blur as is. */
function amountOf(name: Stepped): number {
  return name === 'dim' ? Math.round(saved.dim * 100) : name === 'glass' ? Math.round(saved.glass * 100) : saved.blur
}

/** Draws the card again from the module's settings: only the hooks that read the atom redraw, never the room. An answer that is the status line already on the card clears the last one. */
async function refreshCard($: EngineInterface, said?: string): Promise<void> {
  await update($, card, was => ({ ...was, seen: (was.seen ?? 0) + 1, ...(said !== undefined && { said: said === describe() ? undefined : said }) }))
}

/** A press on the card: the command with those words, its answer shown on the card. */
async function press($: EngineInterface, words: string): Promise<void> {
  let said: string

  try {
    said = await bedroomCommand($, words)
  } catch (error) {
    said = `/bedroom ${words} failed: ${error instanceof Error ? error.message : String(error)}`
  }
  await refreshCard($, said)
}

/** Moves a stepped setting one step, through the same command; a step past either end does nothing. */
async function step($: EngineInterface, name: Stepped, way: 1 | -1): Promise<void> {
  const now = amountOf(name)
  const next = Math.min(STEPS[name].most, Math.max(0, now + way * STEPS[name].by))

  if (next !== now) {
    await press($, `${name} ${next}`)
  }
}

/** Places a new card row at the transcript's end; where no surface draws it, the card shows above the prompt. */
async function openCard($: EngineInterface): Promise<void> {
  const count = ((await read($, card)).placed ?? 0) + 1
  const row = `${CARD_ROW}-${count}`

  await update($, card, was => ({ ...was, row, placed: count, inBand: false, isAway: false, said: undefined }))
  isCardOpen = true
  const placed = await $.ui.place({ id: row })

  if (!placed.isPlaced) {
    await update($, card, was => ({ ...was, inBand: true }))
  }
}

async function closeCard($: EngineInterface): Promise<void> {
  isCardOpen = false
  await update($, card, was => ({ ...was, inBand: false, isAway: true }))
}

type CardElements = Pick<ElementTable<'desktop'>, 'Box' | 'Text' | 'Button' | 'Input'>

/**
 * The settings card. The desktop draws a button's `label`, not its children, so each label carries the state it
 * changes. Every press runs `bedroomCommand` with the words the command takes; the card reads the settings afresh
 * at each draw, so it shows a change made by a click in the room or a typed command too.
 */
function settingsCard($: EngineInterface, { Box, Text, Button, Input }: CardElements, now: BedroomCard) {
  const themeLabel = isThemeOn ? 'theme: on' : 'theme: off'

  return (
    <Box flexDirection="column" borderStyle="round" paddingX={1} gap="md">
      <Box flexDirection="row" justifyContent="space-between" gap={1}>
        <Text bold>Bedroom settings</Text>
        <Button key="close" label="Close" role="dismiss" onPress={() => closeCard($)}>
          Close
        </Button>
      </Box>
      <Text dimColor>{describe()}</Text>
      <Box flexDirection="row" flexWrap="wrap" columnGap="xs" rowGap="xs">
        {SWITCHES.map(name => {
          const label = `${name}: ${saved.state[name] ? 'on' : 'off'}`

          return (
            <Button key={`switch-${name}`} label={label} onPress={() => press($, name)}>
              {label}
            </Button>
          )
        })}
      </Box>
      {STEPPED.map(name => (
        <Box key={`step-${name}`} flexDirection="row" gap={1}>
          <Text>{`${name} ${amountOf(name)}`}</Text>
          <Button key={`${name}-down`} label={`-${STEPS[name].by}`} onPress={() => step($, name, -1)}>
            {`-${STEPS[name].by}`}
          </Button>
          <Button key={`${name}-up`} label={`+${STEPS[name].by}`} onPress={() => step($, name, 1)}>
            {`+${STEPS[name].by}`}
          </Button>
        </Box>
      ))}
      <Box flexDirection="column" gap="xs">
        <Text bold>Titles</Text>
        {TITLE_KEYS.map(key => (
          <Input
            key={`title-${key}`}
            label={`${key} (up to ${TITLE_CAPS[key]})`}
            placeholder="default"
            value={drafts[key] ?? saved.titles[key] ?? ''}
            submitLabel="set"
            onInput={text => {
              drafts[key] = text
            }}
            onSubmit={text => void press($, `title ${key} ${text}`)}
          />
        ))}
        <Text dimColor>Enter sets a title and sends the room once; an empty one puts the default back. Typed: /bedroom title console|tape|pennant|pennant-top TEXT</Text>
      </Box>
      <Box flexDirection="row" flexWrap="wrap" columnGap="xs" rowGap="xs">
        <Button key="reset" label="reset" onPress={() => press($, 'reset')}>
          reset
        </Button>
        <Button key="calibrate" label="calibrate" onPress={() => press($, 'calibrate')}>
          calibrate
        </Button>
        <Button key="theme" label={themeLabel} onPress={() => press($, isThemeOn ? 'off' : 'on')}>
          {themeLabel}
        </Button>
      </Box>
      {now.said === undefined ? [] : [<Text key="said" dimColor>{now.said}</Text>]}
    </Box>
  )
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'bedroom',
      description: 'The bedroom theme of the themes plugin: alone it shows the settings card; status, tv, tape, console, pc, light, lamp, lava (on or off), posters, dim, glass, blur, title (console, tape, pennant, pennant-top), instant, stats, calibrate, reset, on, off',
    })
    const stored = (await $.store.get(STORE_KEY)) as Partial<Saved> | undefined

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
    const set = await setLook($)
    const shown = await read($, card)

    isCardOpen = shown.row !== undefined && shown.isAway !== true
    const tick = (): void => {
      $.clock.after(60_050 - (Date.now() % 60_000), () => {
        $.ui.invalidate('ui.render')
        tick()
      })
    }

    tick()
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
      ? bedroomSvg({ ...saved.state, tv: true, lava: false, pc: true, lamp: false, tape: false, console: false, light: true, titles: saved.titles }, saved.dim)
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
    if (source === lastSource) {
      stats.valueOnly += 1
    } else {
      stats.roomSends += 1
      if (isInstant) {
        holdShaderUntil = performance.now() + SETTLE_MS
        $.clock.after(SETTLE_MS + 200, () => {
          $.ui.invalidate('ui.render')
        })
      }
      lastSource = source
    }
    $.ui.log(`bedroom render ${stats.renders}: asked after ${stats.askMs.toFixed(1)} ms, built in ${buildMs.toFixed(1)} ms, ${source.length} chars, room sent ${stats.roomSends} times`, { to: 'debug' })
    const svg = <Svg source={source} alt="A teenager's bedroom in the country just after sunset" isInteractive />

    if (!isInstant || performance.now() < holdShaderUntil) {
      isShaderSeeded = false

      return svg
    }
    if (!isShaderSeeded) {
      sendAll()
      isShaderSeeded = true
    }

    return (
      <Shader module="./lights.ts" values={{ ...sent, clock: minuteOfHalfDay() }}>
        {svg}
      </Shader>
    )
  })

  on('ui.pointer', async ($, e, next) => {
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
      await $.store.set(STORE_KEY, saved)
      $.ui.toast(`bedroom: clicks calibrated (window shape ${saved.aspect.toFixed(2)})`)
      if (isCardOpen) {
        void refreshCard($, `clicks calibrated (window shape ${saved.aspect.toFixed(2)})`).catch(() => undefined)
      }

      return {}
    }
    const point = toViewBox(e.x, e.y, saved.aspect)
    const names = switchesAt(point.x, point.y)

    if (names.length === 0) {
      return next(e)
    }
    if (names.includes('cat')) {
      $.ui.toast('the cat purrs')

      return {}
    }
    for (const key of names as Switch[]) {
      saved = { ...saved, state: { ...saved.state, [key]: !saved.state[key] } }
      if (!(isInstant && INSTANT.includes(key))) {
        sent = { ...sent, [key]: saved.state[key] ? 1 : 0 }
        askedAt = performance.now()
        $.ui.invalidate('ui.render')
      }
    }
    void $.store.set(STORE_KEY, saved).catch(() => undefined)
    if (isCardOpen) {
      void refreshCard($).catch(() => undefined)
    }

    return {}
  })

  on('command.run', { command: 'bedroom' }, async ($, e) => {
    const text = await bedroomCommand($, e.args)

    if (e.args.trim() === '' && (await $.session.surfaces()).includes('desktop')) {
      await openCard($)

      return { text: `${text}. The settings card is below.` }
    }
    if (isCardOpen) {
      await refreshCard($)
    }

    return { text }
  })

  on('ui.render', { component: 'Placed' }, async ($, e, next) => {
    if (e.props.plugin !== $.plugin.name || !e.props.id.startsWith(CARD_ROW) || e.surface !== 'desktop') {
      return next(e)
    }
    const now = await read($, card)

    if (now.isAway === true || now.row !== e.props.id) {
      return next(e)
    }

    return settingsCard($, $.ui.resolve(e), now)
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (e.surface !== 'desktop') {
      return next(e)
    }
    const now = await read($, card)

    if (now.inBand !== true || now.isAway === true) {
      return next(e)
    }

    return settingsCard($, $.ui.resolve(e), now)
  })
}
