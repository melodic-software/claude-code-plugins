# Run-everything mode: full-breadth review

The heavy, exhaustive sweep: run the main-thread orchestrator plugins AND fan out the full leaf roster (`leaf-roster.md`: its finding-producing agents + every discovered ownerless slice), then normalize everything into one severity-ranked report. The leaf fan-out is accelerated by a Workflow when available; a main-thread fallback preserves coverage when it is not.

Trigger: `$ARGUMENTS` is `run-everything` / `everything` / `all`. Distinct from default mode (which auto-scales surfaces to diff size).

## Flow

1. **Pre-launch availability gate** (below). Run BEFORE any launch.
2. **Resolve the review diff base** (SKILL.md "Shared inputs"). Resolve it up front, because the orchestrator step passes it to Codex via `--base` and the leaf fan-out substitutes it into `REVIEW_DIFF`; every surface must diff the same base.
3. **Main-thread orchestrators.** Sequentially invoke the optional orchestrator plugins per SKILL.md "Orchestrator plugins". They fan out their OWN agents and stay on the main thread, never inside the Workflow (rationale: SKILL.md "Orchestrator plugins"). This exhaustive sweep is where the cross-vendor `codex` surface earns its cost most. When the plugin is present, invoke `/codex:review --wait --base <review-base>` (and `/codex:adversarial-review --wait --base <review-base>` for red-team breadth), since a different model is the one source of uncorrelated blind spots the Claude leaves and orchestrators structurally share. Two flags are required: `--wait` keeps the review in the foreground (without a flag the command prompts or backgrounds, returning only a status handle, so the step-6 synchronous normalization would see an empty surface and silently drop Codex), and `--base` carries the step-2 review diff base so Codex diffs the SAME change set as every other surface. Without it Codex auto-picks the working tree or default branch and reviews a different diff on any PR whose base is not the default branch. Coverage boundary: `--base` runs Codex in branch mode (`git diff <base>..HEAD`, committed only), which coincides with the leaves' `git diff <base>` on a clean branch (the review case) but NOT when the branch also carries uncommitted tracked edits. There Codex covers the committed diff while the leaves additionally cover the dirty tree. Name that gap in `## Surfaces` for a mixed branch+dirty run rather than assuming identical change sets.
4. **Resolve the roster.** Run the discovery recipe in `leaf-roster.md` to get the slice list.
5. **Leaf fan-out.** If the gate passed, substitute the step-2 diff base into `REVIEW_DIFF` and the discovered slice names into `OWNERLESS_SLICES` in the script below, then launch it via the Workflow tool. Else take the coverage-parity fallback.
6. **Normalize main-thread.** Gather the Workflow's extracted leaf records + the raw orchestrator outputs; run Stage 0 on the orchestrator outputs (the Workflow only extracted the leaf branch), then Stages 1–4 of `findings-normalization.md` over the combined record set. Reconcile per surface against the Workflow's `raw` array: any surface whose raw output is non-empty but yielded zero extracted records gets Stage 0 re-run main-thread on that raw text; whatever still fails to parse goes verbatim into `## Unparsed`. Partial extraction never silently drops a surface.
7. **Persist** per `findings-file-shape.md` "Findings-writer contract"; prepend the DEGRADED block when the fallback was taken.

**Pre-flight gate first:** SKILL.md's pre-flight gate applies to this mode too. The ask-shape check routes a whole-repo security-audit ask to the `leaf-roster.md` "Deep-scan escalation" before any diff resolution, and an unresolvable base ref or an empty change set (including untracked-only) reports and stops before step 1; with nothing diffable, every leaf would diff an empty tree and return nothing. Do NOT stage files.

## Pre-launch availability gate

The Workflow tool is not present in every session: a user or organization can turn workflows off, and on some plans they stay off until the user turns them on. Decide availability BEFORE attempting a launch. The check is whether the Workflow tool is in this session's toolset (listed or loadable); when it is absent → main-thread fallback. For the switches that turn workflows off, see [Turn workflows off](https://code.claude.com/docs/en/workflows#turn-workflows-off) (as of 2026-10-02; recheck when those switches are renamed).

If availability cannot be positively confirmed, fall back (fail-safe, not fail-open).

## The Workflow script

Constructed at dispatch: copy the script below, substitute `REVIEW_DIFF` (the resolved diff base) and `OWNERLESS_SLICES` (the discovered slice names, each as `'<path-or-name>'`), and pass it via `Workflow({script})`. Design constraints baked in:

- Plain JS: no TypeScript annotations; no `Date.now()`/`Math.random()`/argless `new Date()`.
- Each leaf reads the diff via its OWN Bash (`git diff <REVIEW_DIFF>`); the script layer has no filesystem access.
- Leaves return raw free-text (NO `schema`). Schema over a custom agent's baked-in output prose is unreliable. Only the dedicated extraction agent uses `schema` (a fresh general-purpose agent, where it is reliable).
- Backstop: the script always returns `raw` (every leaf's raw output alongside extracted records) so the main thread can reconcile per surface. Partial extraction preserves unparsed surfaces, not just the all-zero case.

```javascript
export const meta = {
  name: 'review-fanout-run-everything',
  description: 'Fan out review leaf surfaces (plugin agents + project criteria slices), extract findings to records',
  phases: [
    { title: 'Review' },
    { title: 'Extract' },
  ],
}

// Substituted at dispatch by the main thread:
const REVIEW_DIFF = '<UNRESOLVED>'  // resolved review diff base; a missed substitution fails the leaf's git diff
const OWNERLESS_SLICES = []         // discovered project criteria docs (may be empty)

// tier1 = highest-value agents run first as a barrier so that if a finite
// budget exhausts, the lower-value tier2 is what drops (deterministic priority).
const TIER1 = [
  { label: 'security-reviewer',     agentType: 'review:security-reviewer' },
  { label: 'architecture-guardian', agentType: 'review:architecture-guardian' },
  { label: 'code-reviewer',         agentType: 'review:code-reviewer' },
]
const TIER2_AGENTS = [
  { label: 'doc-drift-detector', agentType: 'review:doc-drift-detector' },
]
const TIER2_SLICES = OWNERLESS_SLICES.map(s => ({ label: 'slice:' + s, slice: s }))

// A leaf with a named agent passes no effort, so its definition's effort pin applies. Every
// agent() call without a named agent passes an explicit level (pointer below the script).
const SLICE_EFFORT = 'high'      // slices render review verdicts
const EXTRACT_EFFORT = 'medium'  // mechanical extraction that must keep every finding; never lower

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
  'Review the current change set. Run `git diff ' + REVIEW_DIFF + '` yourself to see the changes, plus ' +
  '`git ls-files --others --exclude-standard` for untracked files. Read the project review criteria and ' +
  'conventions relevant to your concern when present. Report findings in your normal output format.' +
  COVERAGE_CLAUSE

function slicePrompt(slice) {
  return 'Read the project review criteria document "' + slice + '". Run `git diff ' + REVIEW_DIFF + '` ' +
    'yourself to see the changes. Review the diff against ONLY that document\'s criteria. List each finding ' +
    'with file:line, a severity tier, a confidence level (high / medium / low), and a one-line description. ' +
    'If the diff does not touch this concern, reply "No findings for ' + slice + '."' +
    COVERAGE_CLAUSE
}

phase('Review')

const t1 = await parallel(TIER1.map(leaf => () =>
  agent(AGENT_PROMPT, { agentType: leaf.agentType, label: leaf.label, phase: 'Review' })
))
const t2a = await parallel(TIER2_AGENTS.map(leaf => () =>
  agent(AGENT_PROMPT, { agentType: leaf.agentType, label: leaf.label, phase: 'Review' })
))
const t2s = await parallel(TIER2_SLICES.map(leaf => () =>
  agent(slicePrompt(leaf.slice), { label: leaf.label, effort: SLICE_EFFORT, phase: 'Review' })
))

const roster = [...TIER1, ...TIER2_AGENTS, ...TIER2_SLICES]
const outputs = [...t1, ...t2a, ...t2s]
const returned = roster
  .map((leaf, i) => ({ label: leaf.label, output: outputs[i] }))
  .filter(r => r.output != null)
const nulls = roster.filter((_, i) => outputs[i] == null).map(l => l.label)

log('Review: ' + returned.length + '/' + roster.length + ' leaves returned')

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

const extractInput = returned.map(r => '### Surface: ' + r.label + '\n' + r.output).join('\n\n')
const extracted = await agent(
  'You are the Stage-0 extraction step of a review-findings pipeline. Below are raw free-text findings from ' +
  'several review surfaces, each under a "### Surface:" header. Emit one record per finding (surface, file, ' +
  'line, line_basis, category, native_severity, native_confidence, raw_text). Do NOT crosswalk severity or ' +
  'confidence (later stages do that). Preserve EVERY finding, never drop one.\n\n' + extractInput,
  { schema: RECORD_SCHEMA, model: 'sonnet', effort: EXTRACT_EFFORT, label: 'stage0-extract', phase: 'Extract' }
)

const records = extracted && extracted.records ? extracted.records : []
return {
  records,
  raw: returned.map(r => ({ label: r.label, output: r.output })),
  nulls,
  ran: roster.map(l => l.label),
  // the level each leaf was passed; null for a named agent, whose pin the main thread reads
  effort: Object.fromEntries(roster.map(l => [l.label, l.slice ? SLICE_EFFORT : null])),
}
```

**Null reconciliation:** the reduce returns `nulls` (every leaf that produced no record, regardless of cause), `ran` (the full expected roster) and `effort` (per leaf, the level the script passed, or `null` for a named agent). Render a `## Surfaces` line in the form `Ran: [<label>@<level>, ...]. Returned no result: [...]`, with NO silent caps. Every null is named.

**Leaf levels:** render each `ran` entry as `<label>@<level>`, main-thread, after the reduce returns. A slice takes its level from the returned `effort`. A named agent (`effort` is `null`) takes the `effort:` key from its definition's frontmatter: Read `<plugin-root>/agents/<name>.md`, where `<name>` is the `agentType` without its `review:` prefix; a definition with no `effort:` key ran at the session's level, rendered `<label>@session`. The rendered level is the level requested, not proven: we treat a set `CLAUDE_CODE_EFFORT_LEVEL` environment variable as able to override it. Check it with `printenv CLAUDE_CODE_EFFORT_LEVEL`; when it is set, end the `## Surfaces` line with one notice that the variable may override the shown levels.

- **Pointer**: for choosing the two constants' levels, see [Choose an effort level](https://code.claude.com/docs/en/model-config#choose-an-effort-level); for how frontmatter effort ranks against the session level and the environment variable, see [Set the effort level](https://code.claude.com/docs/en/model-config#set-the-effort-level); for the Workflow `agent()` `effort` option, see the bundled workflow-authoring reference. That the Agent tool takes no effort parameter is our reading of its tool schema.
- **As of**: 2026-10-02
- **Recheck trigger**: either model-config section changes, or a Claude Code release note changes the Workflow `agent()` options or adds an effort parameter to the Agent tool.

**Agent-type namespacing:** the `agentType` values above use the marketplace-installed form (`review:<agent>`). When running via `--plugin-dir` or in a context where the plain names resolve, substitute the unqualified names at dispatch.

## Coverage-parity fallback (Workflows unavailable)

Spawn the SAME roster on the main thread via parallel Agent-tool calls (the main thread CAN spawn agents), using the same resolved review diff base, then run Stages 0–4 main-thread. Coverage and the findings contract are identical; what is lost: background execution, out-of-context intermediates, resume caching, and the slices' explicit level. The Agent tool takes no effort parameter, so main-thread slice spawns run at the session's level and render as `<label>@session`; named agents keep their pins. If the caller depends on a dropped property, STOP and surface it rather than silently downgrading.

## Degraded notice

When the fallback is taken, prepend a structurally distinct block at the TOP of the chat output AND the persisted file body (a blockquote above `## Findings`):

```text
> DEGRADED: Workflows unavailable (<signal>); ran N leaves on the main thread; dropped:
> background-exec / out-of-context-intermediates / resume-caching.
> Findings coverage is full; only the execution properties above are lost.
> Slice leaves ran at the session's level (the Agent tool takes no effort); named agents kept their pins.
```

## Interrupted-run handling

If the Workflow is interrupted, ask for a relaunch of the same script. For which agents return saved results, which run again, and when a run can be relaunched from another session, see [Resume after a pause](https://code.claude.com/docs/en/workflows#resume-after-a-pause) (as of 2026-10-02; recheck when the resume or cross-session rules change). The report is written ONCE, main-thread, after the reduce returns, never partially from inside concurrent leaves.
