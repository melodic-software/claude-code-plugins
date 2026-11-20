import { atom, read, update } from 'claude-code'
import type { ElementTable, EngineInterface } from 'claude-code'

import type { BedroomCard } from '../../types'
import { TITLE_CAPS, describe, extraMsOf, runCommand, type TitleKey } from './core/commands.js'
import { ctxOf } from './core/context.js'
import { SWITCHES, type Switch } from './core/piece.js'
import { isThemeOn } from './core/render.js'
import { volumeOf } from './core/saved.js'
import { WEATHERS } from './core/settings.js'
import { bedName } from './pieces/sound.js'
import { chosenName, namesOf, type Kind } from './pieces/sound-bank.js'
import { DEFAULT_STATE } from './scene/lib.ts'

/** The settings card's rows are named this, then a count: a new row for each `/bedroom`, so the card stands at the transcript's end. */
export const CARD_ROW = 'bedroom-card'
const card = atom({ plugin: 'themes', key: 'bedroom-card' } as const, {}, { shape: 'bedroom-card-1' })
/** Whether a card is up, kept beside the atom so a click in the room with no card up writes nothing more than before. */
let isCardOpen = false
/** Text typed into a title field and not yet set, so a redraw of the card (the minute's tick, another press) keeps it. */
const drafts: Partial<Record<TitleKey, string>> = {}

/** How far the card's buttons move dim, glass, blur and the sound's volume, inside the range each command takes. */
const STEPS = { dim: { by: 10, most: 80 }, glass: { by: 10, most: 95 }, blur: { by: 4, most: 40 }, volume: { by: 10, most: 100 } } as const
type Stepped = keyof typeof STEPS
/** The steps on the look row; volume sits beside the sound button. */
const LOOK: readonly Stepped[] = ['dim', 'glass', 'blur']
/** The settings the look row turns on and off, each with the words that do it. */
const TOGGLES = ['signal', 'hall'] as const
/** The time row's order: from the earliest morning light to the latest evening. The phases' own order (PHASES) is the shader's. */
export const TIME_ORDER = ['predawn', 'dawn', 'morning', 'noon', 'golden', 'dusk', 'evening', 'night'] as const
/** The title fields, two to a row so each is wide enough for its longest title and its set button. */
export const TITLE_ROWS: readonly (readonly TitleKey[])[] = [
  ['console', 'tape'],
  ['pennant', 'pennant-top'],
]
/** The sound bank's pickers, a kind's entries together, and the room's things' switch on the last row. */
export const BANK_ROWS: readonly (readonly Kind[])[] = [
  ['cicadas', 'rain'],
  ['thunder', 'tv'],
]

/**
 * How long a switch's button on the card stays inactive after a press, turning off and turning on, in ms: the half
 * second the app takes to hand the shader a new number, the switch's own change in the shader (a fifth to two fifths
 * of a second), and the console's two-second boot. A switch whose number had to turn back first, or the tape and the
 * console while their change waits its turn, add that wait.
 */
export const CHANGE_MS: Record<Switch, readonly [number, number]> = {
  tv: [900, 1000],
  tape: [900, 900],
  console: [900, 2900],
  pc: [900, 1000],
  light: [1000, 800],
  lamp: [900, 1000],
  lava: [1100, 1100],
}
/** The switches changing after a press on the card, each with the timer that ends it: their buttons draw dim, and a press on one does nothing. */
const changing = new Map<Switch, { cancel: () => void }>()

/** Forgets what was typed into a title's field once the title is set. */
export function forgetDraft(key: string): void {
  delete drafts[key as TitleKey]
}

/** A stepped setting as its command takes it: dim and glass in percent, blur and volume as they are. */
function amountOf($: EngineInterface, name: Stepped): number {
  const saved = ctxOf($).saved
  if (name === 'volume') return volumeOf(saved)
  return name === 'dim' ? Math.round(saved.dim * 100) : name === 'glass' ? Math.round(saved.glass * 100) : saved.blur
}

/** The words a step presses: volume is a word of /bedroom sound. */
const wordsOf = (name: Stepped, amount: number): string => (name === 'volume' ? `sound volume ${amount}` : `${name} ${amount}`)

/** Draws the card again from the module's settings: only the hooks that read the atom redraw, never the room. No answer, or one that is the status line, clears the last one. */
export async function refreshCard($: EngineInterface, said?: string, status?: string): Promise<void> {
  if (!isCardOpen) return
  await update($, card, was => ({ ...was, seen: (was.seen ?? 0) + 1, said: said === undefined || said === status ? undefined : said }))
}

/** A press on the card: the command with those words, its answer shown on the card. */
async function press($: EngineInterface, words: string): Promise<void> {
  let said: string

  try {
    said = await runCommand($, words)
  } catch (error) {
    said = `/bedroom ${words} failed: ${error instanceof Error ? error.message : String(error)}`
  }
  if (words.startsWith('title ')) forgetDraft(words.split(' ')[1] ?? '')
  await refreshCard($, said, describe(ctxOf($)))
}

/** Moves a stepped setting one step, through the same command; a step past either end does nothing. */
async function step($: EngineInterface, name: Stepped, way: 1 | -1): Promise<void> {
  const now = amountOf($, name)
  const next = Math.min(STEPS[name].most, Math.max(0, now + way * STEPS[name].by))

  if (next !== now) {
    await press($, wordsOf(name, next))
  }
}

/** Shows or hides the four title fields or the sound bank, each on the two rows the time and the weather leave; one at a time. */
async function togglePanel($: EngineInterface, panel: 'titles' | 'sounds'): Promise<void> {
  await update($, card, was => ({ ...was, titles: panel === 'titles' && was.titles !== true, sounds: panel === 'sounds' && was.sounds !== true, seen: (was.seen ?? 0) + 1 }))
}

/** Runs a press on the card that changes these switches, their buttons inactive until each has changed. */
async function pressChanging($: EngineInterface, words: string, keys: readonly Switch[]): Promise<void> {
  for (const key of keys) {
    changing.get(key)?.cancel()
    changing.set(key, { cancel: () => undefined })
  }
  await press($, words)
  for (const key of keys) {
    const timer = $.clock.after(CHANGE_MS[key][ctxOf($).saved.state[key] ? 1 : 0] + extraMsOf(key), () => {
      changing.delete(key)
      void refreshCard($).catch(() => undefined)
    })

    changing.set(key, timer)
  }
}

/** Places a new card row at the transcript's end; where no surface draws it, the card shows above the prompt. */
export async function openCard($: EngineInterface): Promise<void> {
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

/** At session start: whether a card placed before a reload is still up. */
export async function readCard($: EngineInterface): Promise<void> {
  const shown = await read($, card)
  isCardOpen = shown.row !== undefined && shown.isAway !== true
}

/** The card's state when one is up in this row, or undefined. */
export async function shownIn($: EngineInterface, id: string | undefined, isBand: boolean): Promise<BedroomCard | undefined> {
  const now = await read($, card)
  if (now.isAway === true) return undefined
  if (isBand ? now.inBand !== true : now.row !== id) return undefined
  return now
}

type CardElements = Pick<ElementTable<'desktop'>, 'Box' | 'Text' | 'Button' | 'Input'>

/**
 * The settings card, six rows whatever is open, each kept to the conversation's width (about 1,100 px in the app) so
 * none wraps and nothing is cut off at about 390 px of height: the title with the theme, reset, calibrate, titles and
 * Close; the switches, with room left for three more buttons; the time of day from the earliest light to the latest and
 * the weather, two rows that show the four title fields two to a row while titles is on, or the sound bank's pickers
 * while sounds is on; dim, glass and blur with the signal and the hallway; sound with its volume, the bed playing, the
 * sounds button and the last press's answer on one line. The desktop draws a button's `label`, not its children, so
 * each label carries the state it changes, and the chosen time and weather carry a check. Every press runs the command
 * with the words it takes; the card reads the settings afresh at each draw, so it shows a change made by a click in the
 * room or a typed command too. Shader off is a typed command for diagnosis, not a button.
 */
export function settingsCard($: EngineInterface, { Box, Text, Button, Input }: CardElements, now: BedroomCard) {
  const ctx = ctxOf($)
  const saved = ctx.saved
  const themeLabel = isThemeOn() ? 'theme: on' : 'theme: off'
  const titlesLabel = now.titles === true ? 'titles: hide' : 'titles: show'
  const soundLabel = `sound: ${ctx.setting('sound') ? 'on' : 'off'}`
  const soundsLabel = now.sounds === true ? 'sounds: hide' : 'sounds: show'
  const objectsLabel = `objects: ${saved.objects === false ? 'off' : 'on'}`
  const time = ctx.setting('time')
  const weather = ctx.setting('weather')
  const choice = (row: 'time' | 'weather', word: string, chosen: string) => {
    const label = word === chosen ? `${word} ✓` : word

    return (
      <Button key={`${row}-${word}`} label={label} onPress={() => press($, `${row} ${word}`)}>
        {label}
      </Button>
    )
  }
  const stepper = (name: Stepped) => (
    <Box key={`step-${name}`} flexDirection="row" alignItems="center" columnGap="xs">
      <Text>{`${name} ${amountOf($, name)}`}</Text>
      <Button key={`${name}-down`} label={`-${STEPS[name].by}`} onPress={() => step($, name, -1)}>
        {`-${STEPS[name].by}`}
      </Button>
      <Button key={`${name}-up`} label={`+${STEPS[name].by}`} onPress={() => step($, name, 1)}>
        {`+${STEPS[name].by}`}
      </Button>
    </Box>
  )

  return (
    <Box flexDirection="column" borderStyle="round" paddingX={1} gap="sm">
      <Box key="head" flexDirection="row" flexWrap="wrap" justifyContent="space-between" alignItems="center" columnGap="sm" rowGap="xs">
        <Text bold>Bedroom settings</Text>
        <Box flexDirection="row" flexWrap="wrap" columnGap="xs" rowGap="xs">
          <Button key="theme" label={themeLabel} onPress={() => press($, isThemeOn() ? 'off' : 'on')}>
            {themeLabel}
          </Button>
          <Button
            key="reset"
            label="reset"
            onPress={() =>
              pressChanging(
                $,
                'reset',
                SWITCHES.filter(name => ctxOf($).saved.state[name] !== DEFAULT_STATE[name]),
              )
            }
          >
            reset
          </Button>
          <Button key="calibrate" label="calibrate" onPress={() => press($, 'calibrate')}>
            calibrate
          </Button>
          <Button key="titles" label={titlesLabel} onPress={() => togglePanel($, 'titles')}>
            {titlesLabel}
          </Button>
          <Button key="close" label="Close" role="dismiss" onPress={() => closeCard($)}>
            Close
          </Button>
        </Box>
      </Box>
      <Box key="switches" flexDirection="row" flexWrap="wrap" columnGap="xs" rowGap="xs">
        {SWITCHES.map(name => {
          const isChanging = changing.has(name)
          const label = `${name}: ${saved.state[name] ? 'on' : 'off'}${isChanging ? '…' : ''}`

          return (
            <Button
              key={`switch-${name}`}
              label={label}
              dimColor={isChanging}
              onPress={() => (changing.has(name) ? undefined : pressChanging($, name, [name]))}
            >
              {label}
            </Button>
          )
        })}
      </Box>
      {now.titles === true
        ? TITLE_ROWS.map((keys, row) => (
            <Box key={`title-row-${row + 1}`} flexDirection="row" columnGap="sm">
              {keys.map(key => (
                <Box key={`field-${key}`} flexGrow={1} flexShrink={1} width="50%">
                  <Input
                    key={`title-${key}`}
                    label={key}
                    placeholder={`up to ${TITLE_CAPS[key]}`}
                    value={drafts[key] ?? saved.titles[key] ?? ''}
                    submitLabel="set"
                    onInput={text => {
                      drafts[key] = text
                    }}
                    onSubmit={text => void press($, `title ${key} ${text}`)}
                  />
                </Box>
              ))}
            </Box>
          ))
        : now.sounds === true
          ? BANK_ROWS.map((kinds, row) => (
              <Box key={`bank-row-${row + 1}`} flexDirection="row" flexWrap="wrap" alignItems="center" columnGap="lg" rowGap="xs">
                {kinds.map(kind => (
                  <Box key={`bank-${kind}`} flexDirection="row" alignItems="center" columnGap="xs">
                    <Text>{kind}</Text>
                    {namesOf(kind).map(name => {
                      const label = name === chosenName(saved, kind) ? `${name} ✓` : name
                      return (
                        <Button key={`pick-${kind}-${name}`} label={label} onPress={() => press($, `sound pick ${kind} ${name}`)}>
                          {label}
                        </Button>
                      )
                    })}
                  </Box>
                ))}
                {row === BANK_ROWS.length - 1
                  ? [
                      <Button key="toggle-objects" label={objectsLabel} onPress={() => press($, `sound objects ${saved.objects === false ? 'on' : 'off'}`)}>
                        {objectsLabel}
                      </Button>,
                    ]
                  : []}
              </Box>
            ))
          : [
              <Box key="time" flexDirection="row" flexWrap="wrap" alignItems="center" columnGap="xs" rowGap="xs">
                <Text>time</Text>
                {['auto', ...TIME_ORDER].map(word => choice('time', word, time))}
              </Box>,
              <Box key="weather" flexDirection="row" flexWrap="wrap" alignItems="center" columnGap="xs" rowGap="xs">
                <Text>weather</Text>
                {['auto', ...WEATHERS].map(word => choice('weather', word, weather))}
              </Box>,
            ]}
      <Box key="look" flexDirection="row" flexWrap="wrap" alignItems="center" columnGap="lg" rowGap="xs">
        {LOOK.map(stepper)}
        <Box key="toggles" flexDirection="row" flexWrap="wrap" columnGap="xs" rowGap="xs">
          {TOGGLES.map(name => {
            const isOn = ctx.setting(name)
            const label = `${name}: ${isOn ? 'on' : 'off'}`

            return (
              <Button key={`toggle-${name}`} label={label} onPress={() => press($, `${name} ${isOn ? 'off' : 'on'}`)}>
                {label}
              </Button>
            )
          })}
        </Box>
      </Box>
      <Box key="sound" flexDirection="row" alignItems="center" columnGap="lg">
        <Box key="sound-controls" flexDirection="row" alignItems="center" columnGap="xs" flexShrink={0}>
          <Button key="toggle-sound" label={soundLabel} onPress={() => press($, `sound ${ctx.setting('sound') ? 'off' : 'on'}`)}>
            {soundLabel}
          </Button>
          {stepper('volume')}
          <Text key="bed">{`bed: ${ctx.setting('sound') ? bedName() : 'off'}`}</Text>
          <Button key="sounds" label={soundsLabel} onPress={() => togglePanel($, 'sounds')}>
            {soundsLabel}
          </Button>
        </Box>
        <Box key="said-box" flexGrow={1} flexShrink={1}>
          {now.said === undefined ? [] : [<Text key="said" dimColor maxLines={1}>{now.said}</Text>]}
        </Box>
      </Box>
    </Box>
  )
}
