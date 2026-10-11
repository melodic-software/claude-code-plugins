import type { EngineInterface, Register, RenderPropsOf } from 'claude-code'
import { compilePatterns, distinct, maskProps } from './mask.ts'

const MASK = '[hidden]'
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

type Question = { question: string; options: { label: string }[] }

const isRecord = (v: unknown): v is Record<string, unknown> => typeof v === 'object' && v !== null

const isQuestion = (q: unknown): q is Question =>
  isRecord(q) &&
  typeof q.question === 'string' &&
  Array.isArray(q.options) &&
  q.options.every((o) => isRecord(o) && typeof o.label === 'string')

// The AskUserQuestion schema refuses equal question texts and equal option labels within one
// question, and a refused rewrite draws the original; so masked values are kept distinct.
const distinctQuestions = (questions: unknown): unknown => {
  if (!Array.isArray(questions) || !questions.every(isQuestion)) return questions
  const texts = distinct(questions.map((q) => q.question), MASK)
  return questions.map((q, i) => {
    const labels = distinct(q.options.map((o) => o.label), MASK)
    return { ...q, question: texts[i], options: q.options.map((o, j) => ({ ...o, label: labels[j] })) }
  })
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
    const input = m.props.input
    if (m.props.tool !== 'AskUserQuestion' || !isRecord(input) || !('questions' in input)) return m
    return { ...m, props: { ...m.props, input: { ...input, questions: distinctQuestions(input.questions) } } }
  }

  // Each .catch masks whatever failed, so a fault never draws the original props.
  on('ui.render', { component: 'AssistantMessage' }, async ($, e, next) => next((await isDisabled($)) ? e : hide(e, KEYS.AssistantMessage)))
    .catch(($, e, next) => next(hide(e, KEYS.AssistantMessage)))
  on('ui.render', { component: 'UserMessage' }, async ($, e, next) => next((await isDisabled($)) ? e : hide(e, KEYS.UserMessage)))
    .catch(($, e, next) => next(hide(e, KEYS.UserMessage)))
  on('ui.render', { component: 'CommandOutput' }, async ($, e, next) => next((await isDisabled($)) ? e : hide(e, KEYS.CommandOutput)))
    .catch(($, e, next) => next(hide(e, KEYS.CommandOutput)))
  on('ui.render', { component: 'ToolUse' }, async ($, e, next) => next((await isDisabled($)) ? e : hideToolUse(e)))
    .catch(($, e, next) => next(hideToolUse(e)))
  on('ui.render', { component: 'ToolResult' }, async ($, e, next) => next((await isDisabled($)) ? e : hide(e, KEYS.ToolResult)))
    .catch(($, e, next) => next(hide(e, KEYS.ToolResult)))
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
