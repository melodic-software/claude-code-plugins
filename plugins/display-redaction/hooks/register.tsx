import type { EngineInterface, Register, RenderElement, RenderPropsOf } from 'claude-code'
import { blocks, compilePatterns, distinct, maskProps, splitMatches } from './mask.ts'

const MASK = '[hidden]'
// Block style, as the hide-email mod in Anthropic's "Mods in Claude Code" video draws it: a bar the
// color of its own text, readable while the pointer is over its row.
const VIDEO = {
  masked: { backgroundColor: '#3B4252', color: '#3B4252' },
  shown: { backgroundColor: '#4C566A', color: '#ECEFF4', bold: true },
} as const
// A terminal without full color approximates hex to its palette, so it gets theme keys, which
// follow the person's light or dark theme: a mid-gray bar, and the theme's own text inverted.
const THEME = {
  masked: { backgroundColor: 'inactive', color: 'inactive' },
  shown: { backgroundColor: 'text', color: 'inverseText', bold: true },
} as const
type Palette = typeof VIDEO | typeof THEME
const FULL_COLOR = new Set(['truecolor', '24bit'])
// A failed read falls back to theme colors, never to unmasked text.
// Read once per render, and only in block mode; undefined in text mode.
const palette = async ($: EngineInterface, isBlock: boolean): Promise<Palette | undefined> => {
  if (!isBlock) return undefined
  try {
    return FULL_COLOR.has(((await $.env.get('COLORTERM')) ?? '').toLowerCase()) ? VIDEO : THEME
  } catch {
    return THEME
  }
}
// A drawn Text or Markdown refuses these, and a refused tree draws the original text.
const CONTROL = /[\u0000-\u0008\u000b-\u001f\u007f]/
const DISABLED = { plugin: 'display-redaction', key: 'disabled' } as const
const COMMAND = {
  name: 'display-redaction',
  description: 'Mask emails and secrets on screen (on by default); off shows them',
  argumentHint: 'on|off',
  immediate: true,
} as const

// The text-bearing props of each masked component; every other prop is passed on as received.
const KEYS = {
  AssistantMessage: ['text'],
  UserMessage: ['text'],
  CommandOutput: ['text'],
  ToolUse: ['input', 'output'],
  ToolResult: ['output'],
  AskUserQuestion: ['questions'],
  InfoNotice: ['text'],
} as const satisfies { [C in keyof RenderPropsOf]?: readonly (keyof RenderPropsOf[C])[] }

const extraPatterns = (value: unknown): string[] =>
  (Array.isArray(value) ? value : typeof value === 'string' ? value.split('\n') : []).filter((s) => s !== '')

type Question = { question: string; options?: { label: string }[] }

const isRecord = (v: unknown): v is Record<string, unknown> => typeof v === 'object' && v !== null

const isQuestion = (q: unknown): q is Question =>
  isRecord(q) &&
  typeof q.question === 'string' &&
  (q.options === undefined ||
    (Array.isArray(q.options) && q.options.every((o) => isRecord(o) && typeof o.label === 'string')))

// The AskUserQuestion schema refuses equal question texts and equal option labels within one
// question, and a refused rewrite draws the original; so masked values are kept distinct.
const distinctQuestions = (questions: unknown): unknown => {
  if (!Array.isArray(questions) || !questions.every(isQuestion)) return questions
  const texts = distinct(questions.map((q) => q.question), MASK)
  return questions.map((q, i) => {
    if (!q.options) return { ...q, question: texts[i] }
    const labels = distinct(q.options.map((o) => o.label), MASK)
    return { ...q, question: texts[i], options: q.options.map((o, j) => ({ ...o, label: labels[j] })) }
  })
}

// An AskUserQuestion record (the call's input, or its result) with its questions kept distinct.
const distinctAsked = (tool: string, record: unknown): unknown =>
  tool === 'AskUserQuestion' && isRecord(record) && 'questions' in record
    ? { ...record, questions: distinctQuestions(record.questions) }
    : record

type Elements = Pick<ReturnType<EngineInterface['ui']['resolve']>, 'Box' | 'Markdown' | 'Text'>

// The mod's own tree for a text with a match: blocks without one drawn as Markdown, a block with one
// as wrapping Text with each match a bar. Undefined where the text rewrite should draw instead.
function drawMasked(
  { Box, Markdown, Text }: Elements,
  text: string,
  patterns: readonly RegExp[],
  { masked, shown }: Palette,
): RenderElement | undefined {
  if (CONTROL.test(text)) return undefined
  const split = blocks(text).map((block) => ({ block, ...splitMatches(block, patterns) }))
  if (split.every((s) => s.hidden.length === 0)) return undefined
  const drawBlock = ({ block, parts, hidden }: (typeof split)[number], b: number) => {
    if (hidden.length === 0) return <Markdown text={block} />
    const rows = parts.flatMap((part, i) => {
      const value = hidden[i]
      if (part === '' && value === undefined) return []
      const spans = [
        ...(part === '' ? [] : [<Text>{part}</Text>]),
        ...(value === undefined ? [] : [<Text {...masked} hover={shown}>{' ' + value + ' '}</Text>]),
      ]
      return [<Box key={`b${b}m${i}`}>{spans}</Box>]
    })
    return <Box flexWrap="wrap">{rows}</Box>
  }
  return <Box flexDirection="column" gap={1}>{split.map(drawBlock)}</Box>
}

const isDisabled = async ($: EngineInterface): Promise<boolean> => (await $.state.get(DISABLED)).value === true

export const register: Register = (on, options) => {
  const { patterns, invalid } = compilePatterns(extraPatterns(options.extra_patterns))
  const hide = <E extends { props: object }>(e: E, keys: readonly string[]): E => ({
    ...e,
    props: maskProps(e.props as Record<string, unknown>, keys, patterns, MASK) as E['props'],
  })
  const hideQuestions = <E extends { props: RenderPropsOf['AskUserQuestion'] }>(e: E): E => {
    const m = hide(e, KEYS.AskUserQuestion)
    return { ...m, props: { ...m.props, questions: distinctQuestions(m.props.questions) } }
  }
  const hideToolUse = <E extends { props: RenderPropsOf['ToolUse'] }>(e: E): E => {
    const m = hide(e, KEYS.ToolUse)
    const { tool, input, output } = m.props
    if (tool !== 'AskUserQuestion') return m
    const props = { ...m.props, input: distinctAsked(tool, input) }
    return { ...m, props: 'output' in m.props ? { ...props, output: distinctAsked(tool, output) } : props }
  }
  const hideToolResult = <E extends { props: RenderPropsOf['ToolResult'] }>(e: E): E => {
    const m = hide(e, KEYS.ToolResult)
    return { ...m, props: { ...m.props, output: distinctAsked(m.props.tool, m.props.output) } }
  }

  const isBlock = options.mask_style !== 'text'
  const draw = (elements: Elements, text: string, colors: Palette | undefined) =>
    colors && drawMasked(elements, text, patterns, colors)

  // Each .catch masks whatever failed, so a fault never draws the original props.
  on('ui.render', { component: 'AssistantMessage' }, async ($, e, next) => {
    if (await isDisabled($)) return next(e)
    return draw($.ui.resolve(e), e.props.text, await palette($, isBlock)) ?? next(hide(e, KEYS.AssistantMessage))
  }).catch(($, e, next) => next(hide(e, KEYS.AssistantMessage)))
  // A task notification or another party's message the engine draws as a compact row; only the
  // person's own prompt is drawn whole.
  on('ui.render', { component: 'UserMessage' }, async ($, e, next) => {
    if (await isDisabled($)) return next(e)
    const isOwn = e.props.task === undefined && e.props.from === undefined
    return (isOwn ? draw($.ui.resolve(e), e.props.text, await palette($, isBlock)) : undefined) ??
      next(hide(e, KEYS.UserMessage))
  }).catch(($, e, next) => next(hide(e, KEYS.UserMessage)))
  on('ui.render', { component: 'CommandOutput' }, async ($, e, next) => {
    if (await isDisabled($)) return next(e)
    return draw($.ui.resolve(e), e.props.text, await palette($, isBlock)) ?? next(hide(e, KEYS.CommandOutput))
  }).catch(($, e, next) => next(hide(e, KEYS.CommandOutput)))
  on('ui.render', { component: 'ToolUse' }, async ($, e, next) => next((await isDisabled($)) ? e : hideToolUse(e)))
    .catch(($, e, next) => next(hideToolUse(e)))
  on('ui.render', { component: 'ToolResult' }, async ($, e, next) => next((await isDisabled($)) ? e : hideToolResult(e)))
    .catch(($, e, next) => next(hideToolResult(e)))
  on('ui.render', { component: 'AskUserQuestion' }, async ($, e, next) => next((await isDisabled($)) ? e : hideQuestions(e)))
    .catch(($, e, next) => next(hideQuestions(e)))
  on('ui.render', { component: 'InfoNotice' }, async ($, e, next) => next((await isDisabled($)) ? e : hide(e, KEYS.InfoNotice)))
    .catch(($, e, next) => next(hide(e, KEYS.InfoNotice)))

  on('session.start', async ($, e, next) => {
    await $.command.register(COMMAND)
    if (invalid.length > 0) {
      const noun = invalid.length === 1 ? 'entry' : 'entries'
      await $.ui.log(`display-redaction: skipped ${invalid.length} invalid extra_patterns ${noun}`)
    }
    return next(e)
  }).catch(($, e, next) => next(e))

  // `/clear` starts a new session with no session.start, so the command is declared again.
  on('session.end', async ($, e, next) => {
    const result = await next(e)
    if (e.reason === 'clear') await $.command.register(COMMAND)
    return result
  }).catch(($, e, next) => next(e))

  // The answer carries no text: a command's output row is stored where the model reads it.
  on('command.run', { command: 'display-redaction' }, async ($, e) => {
    const arg = e.args.trim().toLowerCase()
    if (arg === 'off' || arg === 'on') {
      await $.state.set(DISABLED, arg === 'off')
      await $.ui.log(`display-redaction: masking is ${arg} for this session`)
    } else {
      await $.ui.log(`display-redaction: masking is ${(await isDisabled($)) ? 'off' : 'on'}`)
    }
    return {}
  }).catch(() => ({}))
}
