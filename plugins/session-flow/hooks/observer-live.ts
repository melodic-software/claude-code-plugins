export const CHECK_EVERY = 6
export const LIST_MAX = 50
export const FIELD_MAX = 240
export const CLEAR_AFTER_PROMPTS = 2
export const TYPED_PAST_FREE = 2
export const SKIP_MAX = 16

export const CATEGORIES = ['process', 'decision', 'verification', 'instruction'] as const
export type Category = (typeof CATEGORIES)[number]
export type Finding = { finding: string; category: Category; rule: string; evidence: string }
export type Parsed = { kind: 'none' } | { kind: 'finding'; value: Finding } | { kind: 'unparsable' }
export type Trigger = 'step' | 'turn-end'

export const isStepCheck = (index: number, agentId: string | undefined) =>
  agentId === undefined && index > 0 && index % CHECK_EVERY === 0

export const keyOf = (line: string) => line.trim().toLowerCase().replace(/\.+$/, '')

export const remember = (list: readonly string[], line: string) => [...list.filter(l => keyOf(l) !== keyOf(line)), line].slice(-LIST_MAX)

export const isKnown = (line: string, ...lists: readonly (readonly string[])[]) =>
  lists.some(list => list.some(l => keyOf(l) === keyOf(line)))

export const checksToSkipAfterIgnored = (typedPast: number) =>
  typedPast <= TYPED_PAST_FREE ? 0 : Math.min(SKIP_MAX, 2 ** (typedPast - TYPED_PAST_FREE - 1))

const listed = (title: string, lines: readonly string[]) =>
  lines.length === 0 ? '' : `\n${title}\n${lines.map(l => `- ${l}`).join('\n')}\n`

export const buildPrompt = (seen: readonly string[], disputed: readonly string[]) => `<system-reminder>
You are a separate reviewer beside this session, not the assistant doing its work. The assistant keeps working and never sees your reply unless the person sends it. You have no tools and get one reply. Never repeat a secret, token, credential or personal detail, even one that appears above.
</system-reminder>

Review this session's work so far for one process fault, judged only against rules and decisions written in this session's own instructions and conversation: instruction files (CLAUDE.md, AGENTS.md, rules files, skill text), handoffs, and decisions the owner stated or that a decision record shown here holds. Four kinds count:
- process: a step the instructions require was skipped or run out of order, or a forbidden action was taken.
- decision: the work goes against a decision the owner made.
- verification: something was called done, fixed, passing or merged without the check that proves it, or a check ran and its output went unread.
- instruction: a written rule was broken, such as a command shape, a writing rule or where a file goes.

Report a fault only when every one of these holds: you can quote the rule or decision; you can name the act in this session that breaks it; the assistant has not already noticed or corrected it; it still matters now. Taste, unwritten preferences and guesses do not count. Most checks find nothing, and that is the expected answer.
${listed('Already reported (do not report again in any wording):', seen)}${listed('Disputed by the person (never report again):', disputed)}
Answer with plain lines and nothing else, in one of two shapes. Either:

finding: none

or:

finding: <one sentence of at most 200 characters naming what went wrong>
category: <process | decision | verification | instruction>
rule: <the rule or decision, quoted where you can, and where it is written>
evidence: <the act in this session that breaks it>`

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

export const parseReply = (text: string): Parsed => {
  const lines = clean(text).split(/\r?\n/)
  const finding = field(lines, 'finding')
  if (finding === undefined || finding === '') return { kind: 'unparsable' }
  if (/^none\.?$/i.test(finding)) return { kind: 'none' }
  const rule = field(lines, 'rule') ?? ''
  const evidence = field(lines, 'evidence') ?? ''
  const raw = (field(lines, 'category') ?? '').toLowerCase()
  const category = CATEGORIES.find(c => raw.startsWith(c))
  if (rule === '' || category === undefined || [finding, rule, evidence].some(v => v.length > FIELD_MAX)) return { kind: 'unparsable' }
  return { kind: 'finding', value: { finding: /[.!?]$/.test(finding) ? finding : `${finding}.`, category, rule, evidence } }
}

export const ledgerHeader = (sessionId: string) =>
  `---\nsession_id: ${sessionId}\nobserver: live\n---\n\n# Running retro ledger — session\n`

export const ledgerSection = (at: string, trigger: Trigger, turnId: string, step: number, f: Finding) =>
  `\n## Live check ${at} (${trigger}, turn ${turnId}${step >= 0 ? `, step ${step}` : ''})\n\n` +
  `- **${f.category}**: ${f.finding}\n  - Rule: ${f.rule}\n  - Evidence: ${f.evidence || 'not given'}\n  - Status: open\n`

export const disputeLine = (at: string, f: Finding) => `\n- Disputed ${at}: ${f.finding}\n`

export const noteFor = (f: Finding) =>
  ['A side reviewer (session-flow observer) noted this; it is background, not my instruction:', `> ${f.category}: ${f.finding}`, `> Rule: ${f.rule}`, `> Evidence: ${f.evidence || 'not given'}`]
    .map(l => l.replace(/@/g, '@​'))
    .join('\n')
