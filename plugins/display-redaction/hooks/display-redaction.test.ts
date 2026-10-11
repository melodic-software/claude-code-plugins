import type { CommandRunInput, On, RenderComponent, RenderPropsOf } from 'claude-code'
import { type Engine, expect, mock, test } from 'claude-code/testing'
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

// The prop-rewrite style: each match drawn as the mask text.
const TEXT_MODE = { options: { mask_style: 'text' } }

// The hide-email mod in Anthropic's "Mods in Claude Code" video: a bar the color of its own text,
// readable while hovered.
const VIDEO_MASKED = { backgroundColor: '#3B4252', color: '#3B4252' }
const VIDEO_SHOWN = { backgroundColor: '#4C566A', color: '#ECEFF4', bold: true }
const SURFACES = ['terminal', 'desktop', 'vscode', 'mobile'] as const
// The theme keys the engine's types list (ThemeKey); a raw color is any other string.
const THEME_KEYS = [
  'text', 'inverseText', 'inactive', 'subtle', 'suggestion', 'remember', 'success', 'error', 'warning', 'merged',
  'claude', 'permission', 'planMode', 'autoAccept', 'promptBorder', 'bashBorder', 'ide', 'diffAdded', 'diffRemoved',
  'diffAddedDimmed', 'diffRemovedDimmed', 'diffAddedWord', 'diffRemovedWord',
]
// A terminal that advertises full color sets COLORTERM to one of these.
const FULL_COLOR = ['truecolor', '24bit']

type Node = { type?: string; props?: Record<string, unknown>; hover?: unknown; children?: unknown[] }

// Every Text in a drawn tree that shows an at-sign, with its hover and whether its parent Box is
// keyed (a hover outside a keyed Box is refused).
const barsIn = (node: unknown, keyed = false): { text: string; props: unknown; hover: unknown; keyed: boolean }[] => {
  if (typeof node !== 'object' || node === null) return []
  const { type, props, hover, children = [] } = node as Node
  const text = children.filter((c) => typeof c === 'string').join('')
  if (type === 'Text' && text.includes('@')) return [{ text, props, hover, keyed }]
  return children.flatMap((c) => barsIn(c, type === 'Box' && typeof props?.key === 'string'))
}

test('block mode draws each match as a bar the color of its text, readable while hovered', async ($, on) => {
  mock.env(on, { COLORTERM: 'truecolor' })
  for (const surface of SURFACES) {
    const ui = await $.ui.mount({
      plugin: 'display-redaction',
      surface,
      component: 'AssistantMessage',
      props: { text: `Hello **there**.\n\nWrite to ${EMAIL} today.`, isFirstOfReply: true },
    })
    // The real value is the bar's hidden content and appears nowhere else in the drawing.
    expect(barsIn(await ui.drawn())).toEqual([{ text: ` ${EMAIL} `, props: VIDEO_MASKED, hover: VIDEO_SHOWN, keyed: true }])
    expect(JSON.stringify(await ui.drawn()).split(EMAIL).length).toBe(2)
    const markdown = await ui.findAll({ type: 'Markdown' })
    expect(markdown.map((m) => m.props.text)).toEqual(['Hello **there**.'])
    await ui.unmount()
  }
})

test('block mode draws a fenced block with a match as text, the match a bar', async ($, on) => {
  mock.env(on, { COLORTERM: 'truecolor' })
  const ui = await $.ui.mount({
    plugin: 'display-redaction',
    surface: 'terminal',
    component: 'AssistantMessage',
    props: { text: `\`\`\`\nsend ${EMAIL}\n\nthen wait\n\`\`\``, isFirstOfReply: true },
  })
  expect(await ui.findAll({ type: 'Markdown' })).toEqual([])
  const spans = await ui.findAll({ type: 'Text', text: /@/ })
  expect(spans.map((s) => [s.text, s.props.color, s.props.backgroundColor])).toEqual([
    [` ${EMAIL} `, '#3B4252', '#3B4252'],
  ])
})

test('block mode draws a bar in a typed prompt and in command output', async ($, on) => {
  mock.env(on, { COLORTERM: '24bit' })
  const user = await $.ui.mount({
    plugin: 'display-redaction',
    surface: 'desktop',
    component: 'UserMessage',
    props: { text: `mail ${EMAIL}`, origin: ORIGIN, isExpanded: false },
  })
  const command = await $.ui.mount({
    plugin: 'display-redaction',
    surface: 'terminal',
    component: 'CommandOutput',
    props: { command: 'status', args: '', text: `Login: ${EMAIL}`, isErrored: false },
  })
  for (const ui of [user, command]) {
    const spans = await ui.findAll({ type: 'Text', text: /@/ })
    expect(spans.map((s) => s.text)).toEqual([` ${EMAIL} `])
    expect(spans[0]?.props).toMatchObject(VIDEO_MASKED)
  }
})

const drawBar = async ($: Engine) => {
  const ui = await $.ui.mount({
    plugin: 'display-redaction',
    surface: 'terminal',
    component: 'AssistantMessage',
    props: { text: `Write to ${EMAIL} today.`, isFirstOfReply: true },
  })
  return barsIn(await ui.drawn())
}

// Without full color the terminal approximates a hex color, so the bar uses the person's theme.
const expectThemeBar = (bars: ReturnType<typeof barsIn>) => {
  expect(bars.length).toBe(1)
  const { text, props, hover } = bars[0] as { text: string; props: Record<string, unknown>; hover: Record<string, unknown> }
  expect(text).toBe(` ${EMAIL} `)
  expect(props.color).toBe(props.backgroundColor)
  expect(THEME_KEYS.includes(props.color as string)).toBe(true)
  expect(THEME_KEYS.includes(hover.color as string)).toBe(true)
  expect(THEME_KEYS.includes(hover.backgroundColor as string)).toBe(true)
  expect(hover.color).not.toBe(hover.backgroundColor)
}

for (const value of FULL_COLOR) {
  test(`block mode uses the video colors where COLORTERM is ${value}`, async ($, on) => {
    mock.env(on, { COLORTERM: value })
    expect((await drawBar($)).map((b) => [b.props, b.hover])).toEqual([[VIDEO_MASKED, VIDEO_SHOWN]])
  })
}

test('block mode uses theme colors, a solid bar, when COLORTERM is unset', async ($, on) => {
  mock.env(on, {})
  expectThemeBar(await drawBar($))
})

test('block mode uses theme colors when COLORTERM names less than full color', async ($, on) => {
  mock.env(on, { COLORTERM: '256color' })
  expectThemeBar(await drawBar($))
})

test('block mode uses theme colors, still masked, when the environment cannot be read', async ($, on) => {
  on('env.get', () => ({ deny: 'environment unavailable' }))
  expectThemeBar(await drawBar($))
})

test('text mode rewrites the text whatever the color support', TEXT_MODE, async ($, on) => {
  mock.env(on, { COLORTERM: 'truecolor' })
  const seen = capture(on, 'AssistantMessage')
  await $.ui.render({
    surface: 'terminal',
    component: 'AssistantMessage',
    requestId: 'm1',
    props: { text: `Write to ${EMAIL} today.`, isFirstOfReply: true },
  })
  expect(seen.props).toEqual({ text: `Write to ${M} today.`, isFirstOfReply: true })
})

test('block mode rewrites a task notification row, which the engine draws compact', async ($, on) => {
  const seen = capture(on, 'UserMessage')
  const task = { id: 't1' } as unknown as RenderPropsOf['UserMessage']['task']
  await $.ui.render({
    surface: 'terminal',
    component: 'UserMessage',
    requestId: 'u2',
    props: { text: `done for ${EMAIL}`, origin: ORIGIN, isExpanded: false, task },
  })
  expect(seen.props).toEqual({ text: `done for ${M}`, origin: ORIGIN, isExpanded: false, task })
})

test('block mode rewrites text holding a control character a drawn Text refuses', async ($, on) => {
  const seen = capture(on, 'CommandOutput')
  await $.ui.render({
    surface: 'terminal',
    component: 'CommandOutput',
    requestId: 'c2',
    props: { command: 'status', args: '', text: `\u001b[1mLogin:\u001b[0m ${EMAIL}`, isErrored: false },
  })
  expect(seen.props).toEqual({ command: 'status', args: '', text: `\u001b[1mLogin:\u001b[0m ${M}`, isErrored: false })
})

test('masks an email in an assistant reply', TEXT_MODE, async ($, on) => {
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

test('masks the text of a user prompt, a command output, a question dialog and a notice', TEXT_MODE, async ($, on) => {
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

test('masks an extra pattern from the options', { options: { mask_style: 'text', extra_patterns: ['ACME-\\d{4}'] } }, async ($, on) => {
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
const ASKED = [twoAddresses('a@example.com', 'b@example.com', 'To'), twoAddresses('c@example.com', 'd@example.com', 'Cc')]

type Drawn = { question: string; header: string; options: { label: string; description: string }[] }
const isDistinct = (list: readonly string[]) => new Set(list).size === list.length

// What the schema enforces holds, nothing original shows, and the other fields are as asked.
const expectDistinctMasked = (questions: unknown) => {
  const drawn = questions as Drawn[]
  expect(drawn.length).toBe(2)
  expect(isDistinct(drawn.map((q) => q.question))).toBe(true)
  for (const q of drawn) {
    expect(q.question).toContain('[hidden')
    expect(q.options.length).toBe(2)
    expect(isDistinct(q.options.map((o) => o.label))).toBe(true)
  }
  expect(drawn.map((q) => q.header)).toEqual(['To', 'Cc'])
  expect(drawn.map((q) => q.options.map((o) => o.description))).toEqual([['first', 'second'], ['first', 'second']])
  expect(JSON.stringify(drawn)).not.toContain('@example.com')
}

test('keeps masked question texts and option labels distinct in the dialog', async ($, on) => {
  const seen = capture(on, 'AskUserQuestion')
  await $.ui.render({
    surface: 'terminal',
    component: 'AskUserQuestion',
    requestId: 'q1',
    props: { tool: 'AskUserQuestion', questions: ASKED },
  })
  const props = seen.props as { tool: string; questions: unknown }
  expect(props.tool).toBe('AskUserQuestion')
  expectDistinctMasked(props.questions)
})

test('keeps masked questions distinct in an AskUserQuestion tool row, input and output', async ($, on) => {
  const seen = capture(on, 'ToolUse')
  await $.ui.render({
    surface: 'terminal',
    component: 'ToolUse',
    requestId: 't2',
    props: {
      tool_use_id: 't2',
      tool: 'AskUserQuestion',
      input: { questions: ASKED },
      isRunning: false,
      isErrored: false,
      isInterrupted: false,
      output: { questions: ASKED, answers: { 'Mail a@example.com?': 'Mail b@example.com' } },
    },
  })
  const props = seen.props as { input: { questions: unknown }; output: { questions: unknown; answers: object } }
  expectDistinctMasked(props.input.questions)
  expectDistinctMasked(props.output.questions)
  expect(JSON.stringify(props.output.answers)).not.toContain('@example.com')
})

test('keeps masked questions distinct in an AskUserQuestion result', async ($, on) => {
  const seen = capture(on, 'ToolResult')
  await $.ui.render({
    surface: 'terminal',
    component: 'ToolResult',
    requestId: 'r-ask',
    props: { tool_use_id: 'r-ask', tool: 'AskUserQuestion', output: { questions: ASKED, answers: {} }, isErrored: false },
  })
  expectDistinctMasked((seen.props as { output: { questions: unknown } }).output.questions)
})

test('masks the error text an errored tool result draws', async ($, on) => {
  const seen = capture(on, 'ToolResult')
  // An errored call's output is the error text the model read.
  await $.ui.render({
    surface: 'terminal',
    component: 'ToolResult',
    requestId: 'r-err',
    props: { tool_use_id: 'r-err', tool: 'Bash', output: `Error: no mailbox for ${EMAIL}`, isErrored: true },
  })
  expect(seen.props).toEqual({ tool_use_id: 'r-err', tool: 'Bash', output: `Error: no mailbox for ${M}`, isErrored: true })
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

test('/display-redaction on after off masks again', TEXT_MODE, async ($, on) => {
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

test('masks while no choice has been recorded', TEXT_MODE, async ($, on) => {
  const seen = capture(on, 'UserMessage')
  await $.ui.render({
    surface: 'desktop',
    component: 'UserMessage',
    requestId: 'u1',
    props: { text: `reply to ${EMAIL}`, origin: ORIGIN, isExpanded: true },
  })
  expect(seen.props).toEqual({ text: `reply to ${M}`, origin: ORIGIN, isExpanded: true })
})

// A refused state read makes every render hook throw, so its .catch draws.
const failState = (on: On) => on('state.get', () => ({ deny: 'state unavailable' }))

test('draws the whole text as the mask when the hook fails, running no pattern', async ($, on) => {
  const seen = capture(on, 'AssistantMessage')
  failState(on)
  await $.ui.render({
    surface: 'terminal',
    component: 'AssistantMessage',
    requestId: 'm1',
    props: { text: `Write to ${EMAIL}.`, isFirstOfReply: true, onScreen: ON_SCREEN },
  })
  expect(seen.props).toEqual({ text: M, isFirstOfReply: true, onScreen: ON_SCREEN })
})

test('a failed tool row hook draws every string of its input and output as the mask', async ($, on) => {
  const seen = capture(on, 'ToolUse')
  failState(on)
  await $.ui.render({
    surface: 'terminal',
    component: 'ToolUse',
    requestId: 't3',
    props: {
      tool_use_id: 't3',
      tool: 'Bash',
      input: { command: 'echo hi', description: 'Say hi' },
      isRunning: false,
      isErrored: false,
      isInterrupted: false,
      output: { stdout: 'hi\n', stderr: '', interrupted: false },
    },
  })
  expect(seen.props).toEqual({
    tool_use_id: 't3',
    tool: 'Bash',
    input: { command: M, description: M },
    isRunning: false,
    isErrored: false,
    isInterrupted: false,
    output: { stdout: M, stderr: M, interrupted: false },
  })
})

test('a failed question hook draws distinct masks for every question and label', async ($, on) => {
  const seen = capture(on, 'AskUserQuestion')
  failState(on)
  const plain = (q: string) => ({
    question: q,
    header: 'Pick',
    options: [
      { label: 'Yes', description: 'first' },
      { label: 'No', description: 'second' },
    ],
    multiSelect: false,
  })
  await $.ui.render({
    surface: 'terminal',
    component: 'AskUserQuestion',
    requestId: 'q2',
    props: { tool: 'AskUserQuestion', questions: [plain('Go on?'), plain('Stop?')] },
  })
  const drawn = (seen.props as { questions: Drawn[] }).questions
  expect(isDistinct(drawn.map((q) => q.question))).toBe(true)
  for (const q of drawn) {
    expect(q.question.startsWith('[hidden')).toBe(true)
    expect(isDistinct(q.options.map((o) => o.label))).toBe(true)
    expect(q.options.every((o) => o.label.startsWith('[hidden'))).toBe(true)
  }
})

// Every text in a drawn tree that is not a masked bar: Markdown text and Text without a background.
const visibleTexts = (node: unknown): string[] => {
  if (typeof node !== 'object' || node === null) return []
  const { type, props, children = [] } = node as Node
  if (type === 'Markdown') return [String(props?.text ?? '')]
  if (type === 'Text' && props?.backgroundColor === undefined) {
    return [children.filter((c) => typeof c === 'string').join('')]
  }
  return children.flatMap(visibleTexts)
}

test('block mode hides an encrypted private key whose headers end in a blank line', async ($, on) => {
  mock.env(on, { COLORTERM: 'truecolor' })
  const key = '-----BEGIN RSA PRIVATE KEY-----\nProc-Type: 4,ENCRYPTED\nDEK-Info: AES-128-CBC,0A1B\n\nMIIsecretbody\n-----END RSA PRIVATE KEY-----'
  const ui = await $.ui.mount({
    plugin: 'display-redaction',
    surface: 'terminal',
    component: 'AssistantMessage',
    props: { text: `Here:\n\n${key}\n\nDone.`, isFirstOfReply: true },
  })
  const visible = visibleTexts(await ui.drawn()).join('\n')
  expect(visible).toContain('Done.')
  expect(visible).not.toContain('MIIsecretbody')
  expect(visible).not.toContain('ENCRYPTED')
})

test('block mode hides an extra pattern that spans a blank line', {
  options: { extra_patterns: ['TOP\\n\\nBOTTOM'] },
}, async ($, on) => {
  mock.env(on, { COLORTERM: 'truecolor' })
  const ui = await $.ui.mount({
    plugin: 'display-redaction',
    surface: 'terminal',
    component: 'AssistantMessage',
    props: { text: 'a TOP\n\nBOTTOM b', isFirstOfReply: true },
  })
  const visible = visibleTexts(await ui.drawn()).join('\n')
  expect(visible).not.toContain('TOP')
  expect(visible).not.toContain('BOTTOM')
})

test('block mode rewrites text holding a C1 control character a drawn Text refuses', async ($, on) => {
  mock.env(on, { COLORTERM: 'truecolor' })
  const seen = capture(on, 'AssistantMessage')
  await $.ui.render({
    surface: 'terminal',
    component: 'AssistantMessage',
    requestId: 'm-c1',
    props: { text: `Write\u0085${EMAIL} today.`, isFirstOfReply: true },
  })
  expect(seen.props).toEqual({ text: `Write\u0085${M} today.`, isFirstOfReply: true })
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
