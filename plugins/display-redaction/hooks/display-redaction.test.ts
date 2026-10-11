import type { CommandRunInput, On, RenderComponent, RenderPropsOf } from 'claude-code'
import { expect, test } from 'claude-code/testing'
import { register } from './register.tsx'

const M = '[hidden]'
const EMAIL = 'kyle@example.com'
const ON_SCREEN = { first: 0, last: 2, of: 3 }
const ORIGIN = { kind: 'composer' } as RenderPropsOf['UserMessage']['origin']
// The engine stamps origin and presentation on a run.
const run = (args: string) => ({ command: 'display-redaction', args }) as CommandRunInput

// The test's hook stands for the engine: it records the props the plugin passed down.
const capture = (on: On, component: RenderComponent) => {
  const seen: { props?: unknown } = {}
  on('ui.render', { component } as { component: 'AssistantMessage' }, ($, e) => {
    seen.props = e.props
    return { type: 'engine', ref: 0 }
  })
  return seen
}

test('masks an email in an assistant reply', async ($, on) => {
  const seen = capture(on, 'AssistantMessage')
  await $.ui.render({
    surface: 'terminal',
    component: 'AssistantMessage',
    requestId: 'm1',
    props: { text: `Write to ${EMAIL} today.`, isFirstOfReply: true },
  })
  expect(seen.props).toEqual({ text: `Write to ${M} today.`, isFirstOfReply: true })
})

test('masks an email in a ToolUse input and keeps onScreen as received', async ($, on) => {
  const seen = capture(on, 'ToolUse')
  await $.ui.render({
    surface: 'terminal',
    component: 'ToolUse',
    requestId: 't1',
    props: {
      tool_use_id: 't1',
      tool: 'Bash',
      input: { command: `open mailto:${EMAIL}`, description: 'Open a mail draft' },
      isRunning: false,
      isErrored: false,
      isInterrupted: false,
      output: { stdout: `sent to ${EMAIL}`, stderr: '', interrupted: false },
      onScreen: ON_SCREEN,
    },
  })
  expect(seen.props).toEqual({
    tool_use_id: 't1',
    tool: 'Bash',
    input: { command: `open mailto:${M}`, description: 'Open a mail draft' },
    isRunning: false,
    isErrored: false,
    isInterrupted: false,
    output: { stdout: `sent to ${M}`, stderr: '', interrupted: false },
    onScreen: ON_SCREEN,
  })
})

test('masks Bash, Read and Edit results and keeps each result shape', async ($, on) => {
  const seen = capture(on, 'ToolResult')
  const cases: [string, unknown, unknown][] = [
    [
      'Bash',
      { stdout: `author ${EMAIL}\n`, stderr: '', interrupted: false, noOutputExpected: false },
      { stdout: `author ${M}\n`, stderr: '', interrupted: false, noOutputExpected: false },
    ],
    [
      'Read',
      {
        type: 'text',
        file: { filePath: '/repo/AUTHORS', content: `${EMAIL}\n`, numLines: 1, startLine: 1, totalLines: 1 },
      },
      {
        type: 'text',
        file: { filePath: '/repo/AUTHORS', content: `${M}\n`, numLines: 1, startLine: 1, totalLines: 1 },
      },
    ],
    [
      'Edit',
      {
        filePath: '/repo/a.txt',
        oldString: 'x',
        newString: EMAIL,
        originalFile: 'x\n',
        structuredPatch: [{ oldStart: 1, oldLines: 1, newStart: 1, newLines: 1, lines: ['-x', `+to: ${EMAIL}`] }],
        userModified: false,
        replaceAll: false,
      },
      {
        filePath: '/repo/a.txt',
        oldString: 'x',
        newString: M,
        originalFile: 'x\n',
        structuredPatch: [{ oldStart: 1, oldLines: 1, newStart: 1, newLines: 1, lines: ['-x', `+to: ${M}`] }],
        userModified: false,
        replaceAll: false,
      },
    ],
  ]
  for (const [tool, output, expected] of cases) {
    await $.ui.render({
      surface: 'terminal',
      component: 'ToolResult',
      requestId: `r-${tool}`,
      props: { tool_use_id: `r-${tool}`, tool, output, isErrored: false, onScreen: null },
    })
    expect(seen.props).toEqual({ tool_use_id: `r-${tool}`, tool, output: expected, isErrored: false, onScreen: null })
  }
})

test('masks the text of a user prompt, a command output, a question dialog and a notice', async ($, on) => {
  const user = capture(on, 'UserMessage')
  const command = capture(on, 'CommandOutput')
  const ask = capture(on, 'AskUserQuestion')
  const notice = capture(on, 'InfoNotice')
  await $.ui.render({
    surface: 'terminal',
    component: 'UserMessage',
    requestId: 'u1',
    props: { text: `mail ${EMAIL}`, origin: ORIGIN, isExpanded: false },
  })
  await $.ui.render({
    surface: 'terminal',
    component: 'CommandOutput',
    requestId: 'c1',
    props: { command: 'status', args: '', text: `Login: ${EMAIL}`, isErrored: false },
  })
  const question = (who: string) => ({
    question: `Send to ${who}?`,
    header: 'Recipient',
    options: [
      { label: 'Yes', description: `Mail ${who}` },
      { label: 'No', description: 'Skip' },
    ],
    multiSelect: false,
  })
  await $.ui.render({
    surface: 'terminal',
    component: 'AskUserQuestion',
    requestId: 'q1',
    props: { tool: 'AskUserQuestion', questions: [question(EMAIL)] },
  })
  await $.ui.render({
    surface: 'terminal',
    component: 'InfoNotice',
    requestId: 'n1',
    props: { text: `Signed in as ${EMAIL}`, command: '/status' },
  })
  expect(user.props).toEqual({ text: `mail ${M}`, origin: ORIGIN, isExpanded: false })
  expect(command.props).toEqual({ command: 'status', args: '', text: `Login: ${M}`, isErrored: false })
  expect(ask.props).toEqual({ tool: 'AskUserQuestion', questions: [question(M)] })
  expect(notice.props).toEqual({ text: `Signed in as ${M}`, command: '/status' })
})

test('masks an extra pattern from the options', { options: { extra_patterns: ['ACME-\\d{4}'] } }, async ($, on) => {
  const seen = capture(on, 'AssistantMessage')
  await $.ui.render({
    surface: 'terminal',
    component: 'AssistantMessage',
    requestId: 'm1',
    props: { text: 'Ticket ACME-1234 is open.', isFirstOfReply: false },
  })
  expect(seen.props).toEqual({ text: `Ticket ${M} is open.`, isFirstOfReply: false })
})

test('logs the count of invalid extra patterns once, never the pattern text', {
  options: { extra_patterns: ['(secret+)+', 'ACME-\\d{4}'] },
}, async ($, on) => {
  const lines: string[] = []
  on('ui.log', ($, e) => {
    lines.push(e.text)
    return { value: undefined }
  })
  on('command.register', () => ({ value: { command: 'display-redaction' } }))
  on('session.start', ($, e) => ({ cwd: e.cwd }))
  await $.session.start({ cwd: '/repo', surface: 'terminal', isInteractive: true })
  expect(lines).toEqual(['display-redaction: skipped 1 invalid extra_patterns entry'])
})

// The AskUserQuestion schema refuses equal question texts, or equal option labels within one
// question; a refused rewrite draws the original, so masking must keep them distinct.
const twoAddresses = (a: string, b: string, header: string) => ({
  question: `Mail ${a}?`,
  header,
  options: [
    { label: `Mail ${a}`, description: 'first' },
    { label: `Mail ${b}`, description: 'second' },
  ],
  multiSelect: false,
})

test('keeps masked question texts and option labels distinct', async ($, on) => {
  const seen = capture(on, 'AskUserQuestion')
  await $.ui.render({
    surface: 'terminal',
    component: 'AskUserQuestion',
    requestId: 'q1',
    props: {
      tool: 'AskUserQuestion',
      questions: [twoAddresses('a@example.com', 'b@example.com', 'To'), twoAddresses('c@example.com', 'd@example.com', 'Cc')],
    },
  })
  expect(seen.props).toEqual({
    tool: 'AskUserQuestion',
    questions: [
      {
        question: `Mail [hidden 1]?`,
        header: 'To',
        options: [
          { label: 'Mail [hidden 1]', description: 'first' },
          { label: 'Mail [hidden 2]', description: 'second' },
        ],
        multiSelect: false,
      },
      {
        question: `Mail [hidden 2]?`,
        header: 'Cc',
        options: [
          { label: 'Mail [hidden 1]', description: 'first' },
          { label: 'Mail [hidden 2]', description: 'second' },
        ],
        multiSelect: false,
      },
    ],
  })
  expect(JSON.stringify(seen.props)).not.toContain('@example.com')
})

test('keeps option labels distinct in an AskUserQuestion tool row', async ($, on) => {
  const seen = capture(on, 'ToolUse')
  await $.ui.render({
    surface: 'terminal',
    component: 'ToolUse',
    requestId: 't2',
    props: {
      tool_use_id: 't2',
      tool: 'AskUserQuestion',
      input: { questions: [twoAddresses('a@example.com', 'b@example.com', 'To')] },
      isRunning: true,
      isErrored: false,
      isInterrupted: false,
    },
  })
  const input = (seen.props as { input: { questions: { question: string; options: { label: string }[] }[] } }).input
  expect(input.questions[0]?.question).toBe('Mail [hidden]?')
  expect(input.questions[0]?.options.map((o) => o.label)).toEqual(['Mail [hidden 1]', 'Mail [hidden 2]'])
})

test('/display-redaction off passes text through unmasked', async ($, on) => {
  const seen = capture(on, 'AssistantMessage')
  await $.command.run(run('off'))
  await $.ui.render({
    surface: 'terminal',
    component: 'AssistantMessage',
    requestId: 'm1',
    props: { text: `Write to ${EMAIL}.`, isFirstOfReply: true },
  })
  expect(seen.props).toEqual({ text: `Write to ${EMAIL}.`, isFirstOfReply: true })
})

test('/display-redaction on after off masks again', async ($, on) => {
  const seen = capture(on, 'AssistantMessage')
  await $.command.run(run('off'))
  await $.command.run(run('on'))
  await $.ui.render({
    surface: 'terminal',
    component: 'AssistantMessage',
    requestId: 'm1',
    props: { text: `Write to ${EMAIL}.`, isFirstOfReply: true },
  })
  expect(seen.props).toEqual({ text: `Write to ${M}.`, isFirstOfReply: true })
})

test('the command answers with no text, so nothing reaches the model', async ($) => {
  const result = await $.command.run(run('off'))
  expect(result.text).toBe(undefined)
})

test('masks while no choice has been recorded', async ($, on) => {
  const seen = capture(on, 'UserMessage')
  await $.ui.render({
    surface: 'desktop',
    component: 'UserMessage',
    requestId: 'u1',
    props: { text: `reply to ${EMAIL}`, origin: ORIGIN, isExpanded: true },
  })
  expect(seen.props).toEqual({ text: `reply to ${M}`, origin: ORIGIN, isExpanded: true })
})

test('draws masked when the hook fails', async ($, on) => {
  const seen = capture(on, 'AssistantMessage')
  // A refused state read makes the render hook throw.
  on('state.get', () => ({ deny: 'state unavailable' }))
  await $.ui.render({
    surface: 'terminal',
    component: 'AssistantMessage',
    requestId: 'm1',
    props: { text: `Write to ${EMAIL}.`, isFirstOfReply: true, onScreen: ON_SCREEN },
  })
  expect(seen.props).toEqual({ text: `Write to ${M}.`, isFirstOfReply: true, onScreen: ON_SCREEN })
})

test('passes a reply with nothing to mask through unchanged', async ($, on) => {
  const seen = capture(on, 'AssistantMessage')
  const props = { text: 'Run the tests, then open the pull request.', isFirstOfReply: true, isSummary: true as const }
  await $.ui.render({ surface: 'terminal', component: 'AssistantMessage', requestId: 'm1', props })
  expect(seen.props).toEqual(props)
})

test('re-registers the command when /clear ends the session', async ($, on) => {
  const registered: string[] = []
  on('command.register', ($, e) => {
    registered.push(e.name)
    return { value: { command: e.name } }
  })
  on('session.end', ($, e) => ({ sessionId: e.sessionId }))
  await $.session.end({ reason: 'other', sessionId: 's0', resume: { id: 's0' } })
  expect(registered).toEqual([])
  await $.session.end({ reason: 'clear', sessionId: 's1', resume: { id: 's1' } })
  expect(registered).toEqual(['display-redaction'])
})

test('every hook the module registers carries a .catch', () => {
  const registrations: { event: string; caught: boolean }[] = []
  const recording = ((event: string) => {
    const entry = { event, caught: false }
    registrations.push(entry)
    return {
      catch: () => {
        entry.caught = true
      },
    }
  }) as unknown as On
  register(recording, {})
  expect(registrations.length).toBeGreaterThan(0)
  expect(registrations.filter((r) => !r.caught)).toEqual([])
})
