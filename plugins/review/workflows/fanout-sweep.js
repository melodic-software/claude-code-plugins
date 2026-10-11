export const meta = {
  name: 'fanout-sweep',
  description: 'Fan out review leaf surfaces (plugin reviewer agents and project criteria slices) over one diff base, then extract their findings to records',
  whenToUse: 'Run by /review:fanout run-everything mode, which resolves args: diffBase (required), slices, roles, maxConcurrent, diversity, session. Invoked with no args (a bare slash command), do not call Workflow: tell the user to run /review:fanout run-everything.',
  phases: [
    { title: 'Review', detail: 'named reviewer agents by tier, then one agent per project criteria slice' },
    { title: 'Extract', detail: 'one extraction agent turns raw findings into records' },
  ],
}

let input = args
if (typeof input === 'string') {
  try { input = JSON.parse(input) } catch { input = {} }
}
if (!input || typeof input !== 'object' || Array.isArray(input)) input = {}

const DIFF_BASE = typeof input.diffBase === 'string' ? input.diffBase.trim() : ''
if (!DIFF_BASE) {
  log('no diffBase in args: nothing was dispatched')
  return {
    error: 'missing-diff-base',
    next: 'Resolve the review diff base (/review:fanout "Shared inputs") and launch again with args.diffBase.',
  }
}
// The base reaches each leaf's own `git diff`, so only a ref-shaped value passes.
if (!/^[A-Za-z0-9._\/@^~:{}-]+$/.test(DIFF_BASE) || DIFF_BASE.startsWith('-')) {
  log('diffBase ' + JSON.stringify(DIFF_BASE.slice(0, 80)) + ' is not a git ref: nothing was dispatched')
  return { error: 'bad-diff-base', next: 'Pass the resolved ref or commit id as args.diffBase.' }
}

// lens: one named agent per concern. model: one prompt per distinct fan-out model tier.
const DIVERSITY_IN = input.diversity == null ? 'lens' : input.diversity
let DIVERSITY = typeof DIVERSITY_IN === 'string' ? DIVERSITY_IN.trim() : ''
if (DIVERSITY !== 'lens' && DIVERSITY !== 'model') {
  log('diversity ' + JSON.stringify(String(DIVERSITY_IN).slice(0, 80)) + ' is not lens or model: nothing was dispatched')
  return { error: 'bad-diversity', next: 'Pass args.diversity as "lens" or "model", or omit it for lens.' }
}

const SLICES = (Array.isArray(input.slices) ? input.slices : [])
  .filter(s => typeof s === 'string' && s.trim() !== '')
  .map(s => s.trim())

const MAX_CONCURRENT = Number.isInteger(input.maxConcurrent)
  ? Math.min(16, Math.max(1, input.maxConcurrent))
  : 4

// Role variants as /multi-agent:route emits them. Only the extractor is routed:
// the review leaves, slices included, are named agents that keep their own pins.
const EFFORTS = ['low', 'medium', 'high', 'xhigh', 'max']
const MODELS = ['inherit', 'opus', 'sonnet', 'haiku', 'fable', 'best']
const FALLBACK_ROLES = {
  retrieval: { single: { model: 'sonnet', effort: 'medium' } },
}
const passed = input.roles && typeof input.roles === 'object' ? input.roles : {}
const R = {}
for (const role of Object.keys(FALLBACK_ROLES)) {
  R[role] = {}
  for (const v of ['single']) {
    const got = passed[role] && passed[role][v]
    const ok = got && MODELS.includes(got.model) && EFFORTS.includes(got.effort)
    if (got && !ok) log('roles.' + role + '.' + v + ' is not a {model alias, effort} pair: using the built-in fallback')
    R[role][v] = ok ? got : FALLBACK_ROLES[role][v]
  }
}
if (!input.roles) log('no roles in args: built-in fallbacks apply')

// Model tiers: the distinct fan-out models in the role map, first seen first, deduped by the
// model each resolves to. `inherit` is the session model, args.session's alias; with no known
// alias it counts as frontier, as /multi-agent:route counts an unknown session. The frontier
// aliases stay out, as every fan-out stage does.
const SESSION = typeof input.session === 'string' && MODELS.includes(input.session.trim()) &&
  input.session.trim() !== 'inherit' ? input.session.trim() : ''
const TIERS = []
if (DIVERSITY === 'model') {
  for (const role of ['orchestrator', 'worker', 'verifier', 'retrieval']) {
    const f = passed[role] && passed[role].fanout
    if (!f || !MODELS.includes(f.model) || !EFFORTS.includes(f.effort)) continue
    const m = f.model === 'inherit' ? SESSION : f.model
    if (!m) {
      log('roles.' + role + '.fanout is inherit and args.session names no model: an unknown session model is left out of model diversity')
    } else if (m === 'fable' || m === 'best') {
      log('roles.' + role + '.fanout is ' + m + ': a frontier tier is left out of model diversity')
    } else if (!TIERS.includes(m)) {
      TIERS.push(m)
    }
  }
  if (TIERS.length < 2) {
    log('diversity model found ' + TIERS.length + ' fan-out tier(s) in roles, fewer than two: the lens roster runs')
    DIVERSITY = 'lens'
  }
}
const vf = passed.verifier && passed.verifier.fanout
const TIER_EFFORT = vf && EFFORTS.includes(vf.effort) ? vf.effort : 'high'

// `inherit` omits opts.model. Effort is always explicit.
function opts(variant) {
  return variant.model === 'inherit' ? { effort: variant.effort } : { model: variant.model, effort: variant.effort }
}

// Our rule: one retry for a thrown dispatch, a null result is final, and an
// error naming a cap or budget is rethrown without a retry. For agent()'s
// null and error contract, see the bundled /workflow-authoring skill.
async function agentRetry(prompt, o) {
  for (let attempt = 1; ; attempt++) {
    try {
      return await agent(prompt, o)
    } catch (e) {
      const msg = String((e && e.message) || e)
      if (attempt >= 2 || /cap reached|budget/i.test(msg)) throw e
      log(o.label + ': dispatch failed (' + msg.slice(0, 120) + '), retrying once')
    }
  }
}

// Run thunks at most `cap` at a time, in order; a failed thunk yields null.
async function inWaves(thunks, cap) {
  const out = []
  for (let i = 0; i < thunks.length; i += cap) {
    out.push(...(await parallel(thunks.slice(i, i + cap))))
  }
  return out
}

// Tier 1 runs first so that if a finite budget runs out, tier 2 is what drops.
// Named agents carry their own model and effort pins, so no option overrides them.
const TIER1 = [
  { label: 'security-reviewer', agentType: 'review:security-reviewer' },
  { label: 'architecture-guardian', agentType: 'review:architecture-guardian' },
  { label: 'code-reviewer', agentType: 'review:code-reviewer' },
]
const TIER2_AGENTS = [{ label: 'doc-drift-detector', agentType: 'review:doc-drift-detector' }]
const TIER2_SLICES = SLICES.map(s => ({ label: 'slice:' + s, slice: s }))
// Slices run as brief-reviewer, whose tools exclude Agent and Skill, so a slice cannot fan out.
const SLICE_AGENT = 'review:brief-reviewer'

// SKILL.md "Dispatch contract": every finding-producing leaf prompt carries this clause verbatim.
const COVERAGE_CLAUSE =
  ' Your goal at this stage is coverage: it is better to surface a finding that later gets filtered ' +
  'out than to silently drop a real bug. Report every issue you find, including ones you are ' +
  'uncertain about or consider low-severity. Do not filter for importance or confidence at this ' +
  'stage, a separate normalization pass deduplicates and ranks findings downstream. For each ' +
  'finding, include your confidence level (high / medium / low) and an estimated severity. You are ' +
  'done when every changed file has been reviewed for your concern; if part of the change set ' +
  'cannot be reviewed, name that part and return what you have.'

const AGENT_PROMPT =
  'Review the current change set. Run `git diff ' + DIFF_BASE + '` yourself to see the changes, plus ' +
  '`git ls-files --others --exclude-standard` for untracked files. Read the project review criteria and ' +
  'conventions relevant to your concern when present. Report findings in your normal output format.' +
  COVERAGE_CLAUSE

function slicePrompt(slice) {
  return 'Read the project review criteria document "' + slice + '". Run `git diff ' + DIFF_BASE + '` ' +
    'yourself to see the changes. Review the diff against ONLY that document\'s criteria. List each finding ' +
    'with file:line, a severity tier, a confidence level (high / medium / low), and a one-line description. ' +
    'If the diff does not touch this concern, reply "No findings for ' + slice + '."' +
    COVERAGE_CLAUSE
}

// Model diversity runs lane-verifier, which inherits the model and pins no effort, so the
// tier's model and effort apply to it.
const TIER_AGENT = 'review:lane-verifier'
const TIER_PROMPT = 'Your role is hunter, across every concern rather than one lens. ' + AGENT_PROMPT

phase('Review')

let roster
let outputs
if (DIVERSITY === 'model') {
  roster = TIERS.map(t => ({ label: 'model:' + t, tier: t }))
  outputs = await inWaves(roster.map(leaf => () => agentRetry(TIER_PROMPT, {
    agentType: TIER_AGENT, label: leaf.label, phase: 'Review',
    ...opts({ model: leaf.tier === SESSION ? 'inherit' : leaf.tier, effort: TIER_EFFORT }),
  })), MAX_CONCURRENT)
} else {
  const named = leaf => () => agentRetry(AGENT_PROMPT, { agentType: leaf.agentType, label: leaf.label, phase: 'Review' })
  const t1 = await inWaves(TIER1.map(named), MAX_CONCURRENT)
  const t2a = await inWaves(TIER2_AGENTS.map(named), MAX_CONCURRENT)
  const t2s = await inWaves(TIER2_SLICES.map(leaf => () =>
    agentRetry(slicePrompt(leaf.slice), { agentType: SLICE_AGENT, label: leaf.label, phase: 'Review' })
  ), MAX_CONCURRENT)
  roster = [...TIER1, ...TIER2_AGENTS, ...TIER2_SLICES]
  outputs = [...t1, ...t2a, ...t2s]
}
const returned = roster
  .map((leaf, i) => ({ label: leaf.label, output: outputs[i] }))
  .filter(r => r.output != null)
const nulls = roster.filter((_, i) => outputs[i] == null).map(l => l.label)

log('Review: ' + returned.length + '/' + roster.length + ' leaves returned' +
  (nulls.length ? '; no result from ' + nulls.join(', ') : ''))

phase('Extract')

const RECORD_SCHEMA = {
  type: 'object',
  properties: {
    records: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          surface: { type: 'string' },
          file: { type: ['string', 'null'] },
          line: { type: ['integer', 'null'] },
          line_basis: { type: 'string' },
          category: { type: 'string' },
          native_severity: { type: ['string', 'null'] },
          native_confidence: { type: ['string', 'null'] },
          raw_text: { type: 'string' },
        },
        required: ['surface', 'category', 'raw_text'],
      },
    },
  },
  required: ['records'],
}

let records = []
if (returned.length) {
  const extractInput = returned.map(r => '### Surface: ' + r.label + '\n' + r.output).join('\n\n')
  const extracted = await agentRetry(
    'You are the Stage-0 extraction step of a review-findings pipeline. Below are raw free-text findings from ' +
    'several review surfaces, each under a "### Surface:" header. Emit one record per finding (surface, file, ' +
    'line, line_basis, category, native_severity, native_confidence, raw_text). Do NOT crosswalk severity or ' +
    'confidence (later stages do that). Preserve EVERY finding, never drop one.\n\n' + extractInput,
    // stage-normalizer inherits the model and pins no effort, so the routed variant applies to it.
    { agentType: 'review:stage-normalizer', schema: RECORD_SCHEMA, label: 'stage0-extract', phase: 'Extract', ...opts(R.retrieval.single) }
  )
  records = extracted && Array.isArray(extracted.records) ? extracted.records : []
} else {
  log('Extract: no leaf returned, so nothing was extracted')
}

return {
  diffBase: DIFF_BASE,
  records,
  raw: returned.map(r => ({ label: r.label, output: r.output })),
  nulls,
  ran: roster.map(l => l.label),
  roles: { extract: R.retrieval.single },
  diversity: DIVERSITY,
  ...(DIVERSITY === 'model' ? { tiers: TIERS } : {}),
}
