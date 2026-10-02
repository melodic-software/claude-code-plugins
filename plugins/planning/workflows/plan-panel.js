export const meta = {
  name: 'plan-panel',
  description: 'Draft independent implementation plans from distinct angles, score them with independent judges, and synthesize one plan from the winner',
  whenToUse: 'Run by /planning:plan for a hard or wide plan, which resolves args: task (required), context, angles, roles, maxConcurrent. Invoked with no args (a bare slash command), do not call Workflow: tell the user to run /planning:plan with the task.',
  phases: [
    { title: 'Draft', detail: 'one planner per angle, each blind to the others' },
    { title: 'Judge', detail: 'independent judges score every draft against the rubric' },
    { title: 'Synthesize', detail: 'one agent builds the plan from the winner and grafts runner-up ideas' },
  ],
}

let input = args
if (typeof input === 'string') {
  try { input = JSON.parse(input) } catch { input = {} }
}
if (!input || typeof input !== 'object' || Array.isArray(input)) input = {}

const TASK = typeof input.task === 'string' ? input.task.trim() : ''
if (!TASK) {
  log('no task in args: nothing was dispatched')
  return {
    error: 'missing-task',
    next: 'Launch again with args.task set to the task to plan (from /planning:plan).',
  }
}
const CONTEXT = typeof input.context === 'string' ? input.context.trim() : ''
if (input.context != null && typeof input.context !== 'string') log('args.context is not a string: ignored')

const DEFAULT_ANGLES = [
  { name: 'mvp-first', focus: 'the smallest change that delivers the goal end to end; defer everything else' },
  { name: 'risk-first', focus: 'the riskiest unknowns first; sequence phases so a wrong assumption fails early and cheaply' },
  { name: 'reuse-first', focus: 'extend what the codebase already has; add no new mechanism where an existing one fits' },
  { name: 'testability-first', focus: 'drive the design from the tests: name the boundaries the tests drive and make each phase verifiable' },
]
const ANGLES = (Array.isArray(input.angles) ? input.angles : [])
  .map(a => (typeof a === 'string' ? { name: a.trim(), focus: a.trim() } : a))
  .filter(a => a && typeof a.name === 'string' && a.name.trim() !== '')
  .map(a => ({ name: a.name.trim(), focus: typeof a.focus === 'string' && a.focus.trim() ? a.focus.trim() : a.name.trim() }))
  .filter((a, i, all) => all.findIndex(b => b.name === a.name) === i)
const angles = ANGLES.length >= 2 ? ANGLES.slice(0, 6) : DEFAULT_ANGLES
if (ANGLES.length === 1) log('one angle is not a panel: using the default angles')
if (ANGLES.length > 6) log('more than 6 angles passed: drafted the first 6, dropped ' + ANGLES.slice(6).map(a => a.name).join(', '))

const JUDGES = Number.isInteger(input.judges) ? Math.min(5, Math.max(1, input.judges)) : 3

const MAX_CONCURRENT = Number.isInteger(input.maxConcurrent)
  ? Math.min(16, Math.max(1, input.maxConcurrent))
  : 4

// Role variants as /multi-agent:route emits them. `single` serves a stage that
// runs one agent; `fanout` a stage that runs several. The fallback names opus
// for every fan-out because the session model is unknown here, and a frontier
// session must never fan out on its own model.
const EFFORTS = ['low', 'medium', 'high', 'xhigh', 'max']
const MODELS = ['inherit', 'opus', 'sonnet', 'haiku', 'fable', 'best']
const FALLBACK_ROLES = {
  worker: { single: { model: 'inherit', effort: 'medium' }, fanout: { model: 'opus', effort: 'medium' } },
  verifier: { single: { model: 'inherit', effort: 'high' }, fanout: { model: 'opus', effort: 'high' } },
  orchestrator: { single: { model: 'inherit', effort: 'high' }, fanout: { model: 'opus', effort: 'high' } },
}
const passed = input.roles && typeof input.roles === 'object' ? input.roles : {}
const R = {}
for (const role of Object.keys(FALLBACK_ROLES)) {
  R[role] = {}
  for (const v of ['single', 'fanout']) {
    const got = passed[role] && passed[role][v]
    const ok = got && MODELS.includes(got.model) && EFFORTS.includes(got.effort)
    if (got && !ok) log('roles.' + role + '.' + v + ' is not a {model alias, effort} pair: using the built-in fallback')
    R[role][v] = ok ? got : FALLBACK_ROLES[role][v]
  }
}
if (!input.roles) log('no roles in args: built-in fallbacks apply (fan-out stages on opus)')

// `inherit` omits opts.model. Effort is always explicit.
function opts(variant) {
  return variant.model === 'inherit' ? { effort: variant.effort } : { model: variant.model, effort: variant.effort }
}

// One retry for a thrown dispatch, a null result is final, and an error naming
// a cap or budget is rethrown without a retry. For agent()'s null and error
// contract, see the bundled /workflow-authoring skill.
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

const BRIEF = 'Task to plan:\n' + TASK + (CONTEXT ? '\n\nContext from the caller:\n' + CONTEXT : '')
const READ_ONLY = ' Read the code and docs you need. Do not edit, create or delete any file, and do not run a command that changes state.'

const DRAFT_SCHEMA = {
  type: 'object',
  properties: {
    plan: { type: 'string', description: 'the full plan in markdown: goal, approach as ordered phases, test strategy, files affected, blast radius, reversibility, risks' },
    key_ideas: { type: 'array', items: { type: 'string' }, description: 'the ideas this angle contributes that another angle would likely miss' },
  },
  required: ['plan', 'key_ideas'],
}

phase('Draft')

const drafted = await inWaves(angles.map(a => () => agentRetry(
  BRIEF + '\n\nDraft an implementation plan from one angle: ' + a.name + ', meaning ' + a.focus + '. ' +
  'Other planners draft from other angles; commit to yours rather than hedging toward a middle. ' +
  'Ground every claim in the files you read and name them.' + READ_ONLY,
  { schema: DRAFT_SCHEMA, label: 'draft:' + a.name, phase: 'Draft', ...opts(R.worker.fanout) }
)), MAX_CONCURRENT)

// Drafts are lettered so judges score the plan, not the angle's name.
const drafts = angles
  .map((a, i) => ({ angle: a.name, out: drafted[i] }))
  .filter(d => d.out && typeof d.out.plan === 'string' && d.out.plan.trim() !== '')
  .map((d, i) => ({ id: String.fromCharCode(65 + i), angle: d.angle, plan: d.out.plan, key_ideas: Array.isArray(d.out.key_ideas) ? d.out.key_ideas : [] }))
const draftNulls = angles.filter(a => !drafts.some(d => d.angle === a.name)).map(a => a.name)

log('Draft: ' + drafts.length + '/' + angles.length + ' drafts returned' +
  (draftNulls.length ? '; no draft from ' + draftNulls.join(', ') : ''))

if (!drafts.length) {
  return { error: 'no-drafts', next: 'No planner returned a draft. Plan on the main thread.', nulls: { drafts: draftNulls, judges: [] }, ran: angles.map(a => a.name) }
}

const RUBRIC = ['goal_fit', 'blast_radius', 'test_strategy', 'reversibility']
const RUBRIC_TEXT =
  'Score each draft from 1 (poor) to 5 (strong) on: goal_fit (does it deliver the stated task, no more and no less), ' +
  'blast_radius (5 = smallest reach for what it delivers, and the reach is named), test_strategy (5 = names the ' +
  'boundaries the tests drive and gives every phase a mechanically verifiable check), reversibility (5 = each ' +
  'phase can be undone or abandoned cheaply).'

const SCORE_SCHEMA = {
  type: 'object',
  properties: {
    scores: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          draft: { type: 'string' },
          goal_fit: { type: 'integer', minimum: 1, maximum: 5 },
          blast_radius: { type: 'integer', minimum: 1, maximum: 5 },
          test_strategy: { type: 'integer', minimum: 1, maximum: 5 },
          reversibility: { type: 'integer', minimum: 1, maximum: 5 },
          rationale: { type: 'string' },
        },
        required: ['draft', 'goal_fit', 'blast_radius', 'test_strategy', 'reversibility', 'rationale'],
      },
    },
    dissent: { type: 'string', description: 'a concern that survives even in the best draft, or an empty string' },
  },
  required: ['scores', 'dissent'],
}

const draftBlock = drafts.map(d => '### Draft ' + d.id + '\n' + d.plan).join('\n\n')

let scores = drafts.map(d => ({ draft: d.id, angle: d.angle, judges: 0, goal_fit: 0, blast_radius: 0, test_strategy: 0, reversibility: 0, total: 0 }))
let judgeNulls = []
let judgeDissent = []
let winner = drafts[0]

if (drafts.length > 1) {
  phase('Judge')
  const judged = await inWaves(Array.from({ length: JUDGES }, (_, j) => () => agentRetry(
    BRIEF + '\n\nYou are judge ' + (j + 1) + ' of ' + JUDGES + ', scoring independently. ' + RUBRIC_TEXT +
    ' Score every draft by its letter, check its claims against the code where a score turns on them, and give a ' +
    'one-line rationale per draft.' + READ_ONLY + '\n\n' + draftBlock,
    { schema: SCORE_SCHEMA, label: 'judge:' + (j + 1), phase: 'Judge', ...opts(R.verifier.fanout) }
  )), MAX_CONCURRENT)

  // A judge counts only when it scored every draft exactly once; a partial
  // score sheet would rank an unscored draft as zero.
  const complete = r => r && Array.isArray(r.scores) && drafts.every(d =>
    r.scores.filter(x => x && String(x.draft).trim().toUpperCase() === d.id).length === 1)
  judgeNulls = judged.map((r, j) => (complete(r) ? null : 'judge:' + (j + 1))).filter(Boolean)
  const returned = judged.filter(complete)
  judgeDissent = returned.map(r => (typeof r.dissent === 'string' ? r.dissent.trim() : '')).filter(Boolean)
  log('Judge: ' + returned.length + '/' + JUDGES + ' judges returned a complete score sheet' +
    (judgeNulls.length ? '; no usable result from ' + judgeNulls.join(', ') : ''))

  if (!returned.length) {
    return {
      error: 'no-judges',
      next: 'No judge returned scores. Compare the drafts on the main thread.',
      drafts: drafts.map(d => ({ id: d.id, angle: d.angle, plan: d.plan, key_ideas: d.key_ideas })),
      nulls: { drafts: draftNulls, judges: judgeNulls },
      ran: angles.map(a => a.name),
    }
  }

  for (const s of scores) {
    for (const r of returned) {
      const row = r.scores.find(x => x && String(x.draft).trim().toUpperCase() === s.draft)
      if (!row) continue
      s.judges++
      for (const k of RUBRIC) s[k] += Number(row[k]) || 0
    }
    for (const k of RUBRIC) s[k] = s.judges ? Math.round((s[k] / s.judges) * 100) / 100 : 0
    s.total = Math.round(RUBRIC.reduce((t, k) => t + s[k], 0) * 100) / 100
  }
  // Highest mean total wins; a tie keeps angle order.
  const best = scores.reduce((b, s) => (s.total > b.total ? s : b), scores[0])
  winner = drafts.find(d => d.id === best.draft)
} else {
  log('Judge: one draft returned, so it was not scored; it is the winner by default')
}

phase('Synthesize')

const SYNTH_SCHEMA = {
  type: 'object',
  properties: {
    plan: { type: 'string', description: 'the synthesized plan in markdown' },
    grafted: {
      type: 'array',
      items: {
        type: 'object',
        properties: { idea: { type: 'string' }, from: { type: 'string', description: 'the draft letter' } },
        required: ['idea', 'from'],
      },
    },
    dissent: { type: 'array', items: { type: 'string' }, description: 'objections or trade-offs the plan does not resolve' },
  },
  required: ['plan', 'grafted', 'dissent'],
}

const runners = drafts.filter(d => d !== winner)
const scoreLines = scores.map(s => s.draft + ' (' + s.angle + '): total ' + s.total + ' from ' + s.judges + ' judge(s)').join('\n')
const synthesized = await agentRetry(
  BRIEF + '\n\nBuild one implementation plan. Start from the winning draft ' + winner.id + ' and keep its structure. ' +
  'Graft an idea from a runner-up only where it improves goal fit, blast radius, test strategy or reversibility ' +
  'without contradicting the winner, and record each graft with its draft letter. List as dissent every judge ' +
  'concern and runner-up objection the plan does not resolve.' + READ_ONLY +
  '\n\nScores:\n' + scoreLines +
  (judgeDissent.length ? '\n\nJudge concerns:\n- ' + judgeDissent.join('\n- ') : '') +
  '\n\n### Winning draft ' + winner.id + '\n' + winner.plan +
  runners.map(d => '\n\n### Runner-up ' + d.id + '\n' + d.plan + '\nKey ideas: ' + d.key_ideas.join('; ')).join(''),
  { schema: SYNTH_SCHEMA, label: 'synthesize', phase: 'Synthesize', ...opts(R.orchestrator.single) }
)

const synthOk = !!synthesized && typeof synthesized.plan === 'string' && synthesized.plan.trim() !== ''
if (!synthOk) log('Synthesize: no result, so the winning draft is returned unsynthesized')

return {
  task: TASK,
  winner: { id: winner.id, angle: winner.angle },
  plan: synthOk ? synthesized.plan : winner.plan,
  synthesized: synthOk,
  scores,
  grafted: synthOk && Array.isArray(synthesized.grafted) ? synthesized.grafted : [],
  dissent: [...judgeDissent, ...(synthOk && Array.isArray(synthesized.dissent) ? synthesized.dissent : [])],
  drafts: drafts.map(d => ({ id: d.id, angle: d.angle, plan: d.plan, key_ideas: d.key_ideas })),
  nulls: { drafts: draftNulls, judges: judgeNulls },
  ran: angles.map(a => a.name),
  roles: { drafters: R.worker.fanout, judges: R.verifier.fanout, synthesis: R.orchestrator.single },
}
