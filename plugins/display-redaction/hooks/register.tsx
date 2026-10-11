import type { EngineInterface, Register, RenderPropsOf } from 'claude-code'
import { compilePatterns, maskProps } from './mask.ts'

const MASK = '[hidden]'
const DISABLED = { plugin: 'display-redaction', key: 'disabled' } as const
const COMMAND = {
  name: 'display-redaction',
  description: 'Mask emails and secrets on screen (on by default); off shows them',
  argumentHint: 'off',
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

const isDisabled = async ($: EngineInterface): Promise<boolean> => (await $.state.get(DISABLED)).value === true

export const register: Register = (on, options) => {
  const { patterns, invalid } = compilePatterns(extraPatterns(options.extra_patterns))
  const hide = <E extends { props: object }>(e: E, keys: readonly string[]): E => ({
    ...e,
    props: maskProps(e.props as Record<string, unknown>, keys, patterns, MASK) as E['props'],
  })

  // Each .catch masks whatever failed, so a fault never draws the original props.
  on('ui.render', { component: 'AssistantMessage' }, async ($, e, next) => next((await isDisabled($)) ? e : hide(e, KEYS.AssistantMessage)))
    .catch(($, e, next) => next(hide(e, KEYS.AssistantMessage)))
  on('ui.render', { component: 'UserMessage' }, async ($, e, next) => next((await isDisabled($)) ? e : hide(e, KEYS.UserMessage)))
    .catch(($, e, next) => next(hide(e, KEYS.UserMessage)))
  on('ui.render', { component: 'CommandOutput' }, async ($, e, next) => next((await isDisabled($)) ? e : hide(e, KEYS.CommandOutput)))
    .catch(($, e, next) => next(hide(e, KEYS.CommandOutput)))
  on('ui.render', { component: 'ToolUse' }, async ($, e, next) => next((await isDisabled($)) ? e : hide(e, KEYS.ToolUse)))
    .catch(($, e, next) => next(hide(e, KEYS.ToolUse)))
  on('ui.render', { component: 'ToolResult' }, async ($, e, next) => next((await isDisabled($)) ? e : hide(e, KEYS.ToolResult)))
    .catch(($, e, next) => next(hide(e, KEYS.ToolResult)))
  on('ui.render', { component: 'AskUserQuestion' }, async ($, e, next) => next((await isDisabled($)) ? e : hide(e, KEYS.AskUserQuestion)))
    .catch(($, e, next) => next(hide(e, KEYS.AskUserQuestion)))
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
    if (e.args.trim().toLowerCase() === 'off') {
      await $.state.set(DISABLED, true)
      await $.ui.log('display-redaction: masking is off for this session')
    } else {
      await $.ui.log(`display-redaction: masking is ${(await isDisabled($)) ? 'off' : 'on'}`)
    }
    return {}
  }).catch(() => ({}))
}
