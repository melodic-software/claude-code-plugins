export const CHECK_EVERY = 6
export const LIST_MAX = 50
export const FIELD_MAX = 240
export const CLEAR_AFTER_PROMPTS = 2
export const TYPED_PAST_FREE = 2
export const SKIP_MAX = 16
export const GUIDANCE_MAX = 2000

export const CATEGORIES = ['process', 'decision', 'verification', 'instruction', 'request', 'skill', 'improvement'] as const
export type Category = (typeof CATEGORIES)[number] | 'harness'
export type Fix = { route: 'here'; how: string } | { route: 'session'; how: string; command: string } | { route: 'issue'; how: string }
export type Finding = { finding: string; category: Category; rule: string; evidence: string; fix?: Fix }
export type ParseFailure = { reason: string; lengths?: { finding: number; rule: number; evidence: number } }
export type FinishDetail = ParseFailure | { held: boolean }
export type Parsed = { kind: 'none' } | { kind: 'finding'; value: Finding } | ({ kind: 'unparsable' } & ParseFailure)
export type Trigger = 'step' | 'turn-end' | 'change' | 'gate' | 'harness'

export const isStepCheck = (index: number, agentId: string | undefined, every = CHECK_EVERY) =>
  agentId === undefined && every > 0 && index > 0 && index % every === 0

export const keyOf = (line: string) => line.trim().toLowerCase().replace(/\.+$/, '')

export const remember = (list: readonly string[], line: string, max = LIST_MAX) => [...list.filter(l => keyOf(l) !== keyOf(line)), line].slice(-max)

export const isKnown = (line: string, ...lists: readonly (readonly string[])[]) =>
  lists.some(list => list.some(l => keyOf(l) === keyOf(line)))

export const checksToSkipAfterIgnored = (typedPast: number, { free = TYPED_PAST_FREE, max = SKIP_MAX }: { free?: number; max?: number } = {}) =>
  typedPast <= free ? 0 : Math.min(max, 2 ** (typedPast - free - 1))

const listed = (title: string, lines: readonly string[]) =>
  lines.length === 0 ? '' : `\n${title}\n${lines.map(l => `- ${l}`).join('\n')}\n`

const openBlock = (open: string | undefined) =>
  open === undefined
    ? ''
    : `\nThe person is being shown this earlier finding: "${open}". If the assistant has since fixed it, add the line "resolved: yes" to your answer.\n`

export const isResolved = (text: string) => /^\s*resolved\s*:\s*yes\b/im.test(text)

const UNCLEAR = '\nThe person could not understand an earlier finding: write the finding and the rule in plain words a newcomer can follow, with no term left unexplained.\n'

const KINDS = {
  request: "part of the person's latest request was skipped, left unanswered or answered with something else, or the work drifted from the goal the person stated for this session.",
  skill: "work was done by hand, or another way, where a listed skill's trigger or a written rule assigns it to a skill, or a skill run hit a case its steps do not handle, handled it inefficiently, or ended without offering its `## Next`.",
  improvement: "a step ran far longer than it should have, a bug or failure was seen and not raised, or the work goes against a principle the repository's own loaded docs state.",
} as const
export type OptionalKind = keyof typeof KINDS

const COUNT = ['Four', 'Five', 'Six', 'Seven']

const instructions = (kinds: readonly OptionalKind[]) => `Review this session's work so far for one process fault, judged only against rules and decisions written in this session's own instructions and conversation: instruction files (CLAUDE.md, AGENTS.md, rules files, skill text), handoffs, and decisions the owner stated or that a decision record shown here holds. ${COUNT[kinds.length]} kinds count:
- process: a step the instructions or a skill's procedure require was skipped or run out of order, or a forbidden action was taken.
- decision: the work goes against a decision the owner made, or against the intent and vision they stated.
- verification: something was called done, fixed, passing or merged without the check that proves it, or a check ran and its output went unread.
- instruction: a written rule was broken, such as a command shape, a writing rule, where a file goes, a standard, a review criterion, the plugin philosophy or a code-quality rule.${kinds.map(k => `\n- ${k}: ${KINDS[k]}`).join('')}

Report a fault only when every one of these holds: you can quote the rule or decision; you can name the act in this session that breaks it; the assistant has not already noticed or corrected it; it still matters now. Taste, unwritten preferences and guesses do not count. Most checks find nothing, and that is the expected answer.`

export type PromptExtra = { autoSend?: boolean; kinds?: readonly OptionalKind[]; guidance?: string; repoGuidance?: string; guidanceMax?: number; fieldMax?: number; override?: string; heldCommand?: string }

const guidanceBlock = (whose: string, text: string, max: number) => (text.trim() === '' ? '' : `\n${whose} guidance for these checks:\n${text.trim().slice(0, max)}\n`)

const heldBlock = (command: string | undefined) =>
  command === undefined ? '' : `\nThe assistant is about to run this command; report a fault only if running it now breaks a rule or decision:\n${command}\n`

export const buildPrompt = (seen: readonly string[], disputed: readonly string[], open?: string, notRelevant: readonly string[] = [], unclear = false, extra: PromptExtra = {}) => `<system-reminder>
You are a separate reviewer beside this session, not the assistant doing its work. ${extra.autoSend ? 'Your finding is sent to the assistant as a note, so report only what is worth its attention.' : 'The assistant keeps working and never sees your reply unless the person sends it.'} You have no tools and get one reply. Never repeat a secret, token, credential or personal detail, even one that appears above.
</system-reminder>

${extra.override?.trim() || instructions(extra.kinds ?? [])}
${guidanceBlock("The repository's", extra.repoGuidance ?? '', extra.guidanceMax ?? GUIDANCE_MAX)}${guidanceBlock("The person's", extra.guidance ?? '', extra.guidanceMax ?? GUIDANCE_MAX)}${heldBlock(extra.heldCommand)}${listed('Already reported (do not report again in any wording):', seen)}${listed('Disputed by the person (never report again):', disputed)}${listed('Not relevant to the person (do not report these or faults like them):', notRelevant)}${unclear ? UNCLEAR : ''}${openBlock(open)}
Answer with plain lines and nothing else, in one of two shapes. Either:

finding: none

or:

finding: <one sentence of at most 200 characters naming what went wrong>
category: <${['process', 'decision', 'verification', 'instruction', ...(extra.kinds ?? [])].join(' | ')}>
rule: <the rule or decision, quoted where you can, and where it is written, at most ${extra.fieldMax ?? FIELD_MAX} characters>
evidence: <the act in this session that breaks it, at most ${extra.fieldMax ?? FIELD_MAX} characters>

You may add a last line "fix: session" when the fix is larger than or unrelated to this session's work and belongs in a dedicated session, or "fix: issue" when it should be filed as an issue for later; leave it out when the fix belongs in this session.`

const clean = (text: string) =>
  text.replace(/\u001b\[[0-9;?]*[ -/]*[@-~]/g, '').replace(/[\u0000-\u0008\u000b-\u001f\u007f]/g, '')

const field = (lines: readonly string[], label: string) => {
  const re = new RegExp(`^[-*>\\s]*${label}\\s*:\\s*(?:\\*\\*)?\\s*(.*)$`, 'i')
  for (const line of lines) {
    const m = re.exec(line)
    if (m) return (m[1] ?? '').trim().replace(/^["'`]|["'`]$/g, '').trim()
  }
  return undefined
}

const cap = (text: string, max: number) => (text.length > max ? `${text.slice(0, max - 1)}…` : text)

export const parseReply = (text: string, fieldMax = FIELD_MAX): Parsed => {
  const lines = clean(text).split(/\r?\n/)
  const finding = field(lines, 'finding')
  if (finding === undefined || finding === '') return { kind: 'unparsable', reason: 'no_finding' }
  if (/^none\.?$/i.test(finding)) return { kind: 'none' }
  const rule = field(lines, 'rule') ?? ''
  const evidence = field(lines, 'evidence') ?? ''
  const raw = (field(lines, 'category') ?? '').toLowerCase()
  const category = CATEGORIES.find(c => raw.startsWith(c))
  const lengths = { finding: finding.length, rule: rule.length, evidence: evidence.length }
  const reason = rule === '' ? 'no_rule' : category === undefined ? 'bad_category' : finding.length > fieldMax ? 'field_too_long:finding' : undefined
  if (reason) return { kind: 'unparsable', reason, lengths }
  const route = (field(lines, 'fix') ?? '').toLowerCase()
  const fix: Fix | undefined = route.startsWith('session') ? { route: 'session', how: 'take it to a dedicated session', command: '' } : route.startsWith('issue') ? { route: 'issue', how: "file it as an issue under the repository's filing rules" } : undefined
  return { kind: 'finding', value: { finding: /[.!?]$/.test(finding) ? finding : `${finding}.`, category, rule: cap(rule, fieldMax), evidence: cap(evidence, fieldMax), ...(fix ? { fix } : {}) } }
}

export const fixText = (fix: Fix) => (fix.route === 'session' ? `${fix.how}: ${fix.command}` : `${fix.route}: ${fix.how}`)

export const ledgerHeader = (sessionId: string) =>
  `---\nsession_id: ${sessionId}\nobserver: live\n---\n\n# Running retro ledger — session\n`

export const ledgerSection = (at: string, trigger: Trigger, turnId: string, step: number, f: Finding) =>
  `\n## Live check ${at} (${trigger}${turnId ? `, turn ${turnId}` : ''}${step >= 0 ? `, step ${step}` : ''})\n\n` +
  `- **${f.category}**: ${f.finding}\n  - Rule: ${f.rule}\n  - Evidence: ${f.evidence || 'not given'}\n${f.fix ? `  - Fix: ${fixText(f.fix)}\n` : ''}  - Status: open\n`

const LEDGER_LABEL = { confirmed: 'Confirmed', disputed: 'Disputed', resolved: 'Resolved by the assistant', 'auto-sent': 'Auto-sent' } as const

export const ledgerLine = (kind: keyof typeof LEDGER_LABEL, at: string, f: Finding, detail?: string) =>
  `\n- ${LEDGER_LABEL[kind]} ${at}${detail ? ` (${detail})` : ''}: ${f.finding}\n`

export const PERSON_NOTE = 'A side reviewer (session-flow observer) noted this; it is background, not my instruction:'

export const AUTO_NOTE =
  "The session-flow observer, a side reviewer beside this session, flagged this. It is not the person's instruction. If it holds, stop and fix it before your next action, and say so in one line; if not, say why in one line and continue."

export const noteFor = (f: Finding, voice: 'person' | 'plugin' = 'person', lead = voice === 'person' ? PERSON_NOTE : AUTO_NOTE) =>
  [lead, `> ${f.category}: ${f.finding}`, `> Rule: ${f.rule}`, `> Evidence: ${f.evidence || 'not given'}`, ...(f.fix ? [`> Fix: ${fixText(f.fix)}`] : [])]
    .map(l => l.replace(/@/g, '@​'))
    .join('\n')

export const COLD_CACHE_WRITE = 20_000

type Row = {
  trigger?: string
  outcome?: string
  answer?: string
  delivery?: string
  observerTurn?: string
  latencyMs?: number
  usage?: { output_tokens?: number; cache_read_input_tokens?: number; cache_creation_input_tokens?: number }
  harness?: string
  finding?: boolean
  cause?: string
}

const countOf = (pick: (r: Row) => string | undefined, from: readonly Row[]) =>
  Object.entries(
    from.reduce<Record<string, number>>((m, r) => {
      const key = pick(r)
      if (key !== undefined) m[key] = (m[key] ?? 0) + 1
      return m
    }, {}),
  )
    .map(([key, n]) => `${key} ${n}`)
    .join(', ')

const k = (n: number) => (n >= 1000 ? `${Math.round(n / 1000)}K` : `${n}`)

export const summarize = (rows: readonly Row[]) => {
  const checks = rows.filter(r => r.trigger !== undefined)
  const harness = rows.filter(r => r.harness !== undefined)
  const misses = harness.filter(r => r.harness === 'cache-miss').length
  const harnessLine = harness.length === 0 ? [] : [`harness: ${countOf(r => r.harness, harness.filter(r => r.harness !== 'cache-miss' || r.finding)) || 'none'} reported; ${misses} cache miss(es) seen`]
  if (checks.length === 0) return ['no checks yet', ...harnessLine].join('\n')
  const sum = (pick: (r: Row) => number | undefined) => checks.reduce((n, r) => n + (pick(r) ?? 0), 0)
  const countBy = countOf
  const read = sum(r => r.usage?.cache_read_input_tokens)
  const written = sum(r => r.usage?.cache_creation_input_tokens)
  const out = sum(r => r.usage?.output_tokens)
  const cold = checks.filter(r => (r.usage?.cache_creation_input_tokens ?? 0) > COLD_CACHE_WRITE).length
  const answers = countBy(r => r.answer, rows)
  const sent = rows.filter(r => r.answer === 'auto_sent')
  const failed = rows.filter(r => r.answer === 'auto_send_failed').length
  const turns = rows.filter(r => r.observerTurn !== undefined)
  const turnSum = (pick: (r: Row) => number | undefined) => turns.reduce((n, r) => n + (pick(r) ?? 0), 0)
  const auto =
    sent.length + failed + turns.length === 0
      ? []
      : [
          `auto-sent ${sent.length}${sent.length > 0 ? ` (${countBy(r => r.delivery, sent)})` : ''}${failed > 0 ? `, failed ${failed}` : ''}; observer turns ${turns.length}` +
            (turns.length > 0 ? `: ${k(turnSum(r => r.usage?.cache_read_input_tokens))} cache read, ${k(turnSum(r => r.usage?.output_tokens))} output` : ''),
        ]
  return [
    `${checks.length} checks (${countBy(r => r.trigger, checks)}); outcomes: ${countBy(r => r.outcome, checks)}`,
    `tokens: ${k(read)} cache read, ${k(written)} cache written, ${k(out)} output; ${k(Math.round(read / checks.length))} read per check`,
    `latency: ${Math.round(sum(r => r.latencyMs) / 1000)}s total, ${Math.round(sum(r => r.latencyMs) / checks.length / 1000)}s per check${cold > 0 ? `; ${cold} cold-cache check(s)` : ''}`,
    `answers: ${answers || 'none'}`,
    ...auto,
    ...harnessLine,
  ].join('\n')
}
