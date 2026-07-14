# Run-everything mode — full-breadth review

The heavy, exhaustive sweep: run the main-thread orchestrator plugins AND fan out the full leaf roster (`leaf-roster.md` — the 4 finding-producing agents + every discovered ownerless slice), then normalize everything into one severity-ranked report. The leaf fan-out is accelerated by a Workflow when available; a main-thread fallback preserves coverage when it is not.

Trigger: `$ARGUMENTS` is `run-everything` / `everything` / `all`. Distinct from default mode (which auto-scales surfaces to diff size).

## Flow

1. **Pre-launch availability gate** (below) — run BEFORE any launch.
2. **Main-thread orchestrators** — sequentially invoke the optional orchestrator plugins per SKILL.md "Orchestrator plugins". They fan out their OWN agents from the main thread; a Workflow `agent()` is a subagent and cannot dependably spawn them. This exhaustive sweep is where the cross-vendor `codex` surface earns its cost most — when the plugin is present, invoke `/codex:review --wait --base <review-base>` (and `/codex:adversarial-review --wait --base <review-base>` for red-team breadth), since a different model is the one source of uncorrelated blind spots the Claude leaves and orchestrators structurally share. Two flags are load-bearing: `--wait` keeps the review in the foreground (without a flag the command prompts or backgrounds, returning only a status handle, so step 5's synchronous normalization would see an empty surface and silently drop Codex), and `--base` must carry the resolved review diff base (SKILL.md "Shared inputs") so Codex diffs the SAME change set as every other surface — resolve that base (step 3 below) BEFORE this call rather than letting Codex auto-pick the working tree or default branch, which would review a different diff on any PR whose base is not the default branch.
3. **Resolve the roster** — run the discovery recipe in `leaf-roster.md` to get the slice list, and resolve the review diff base (SKILL.md "Shared inputs").
4. **Leaf fan-out** — if the gate passed, substitute the resolved diff base into `REVIEW_DIFF` and the discovered slice names into `OWNERLESS_SLICES` in the script below, then launch it via the Workflow tool. Else take the coverage-parity fallback.
5. **Normalize main-thread** — gather the Workflow's extracted leaf records + the raw orchestrator outputs; run Stage 0 on the orchestrator outputs (the Workflow only extracted the leaf branch), then Stages 1–4 of `findings-normalization.md` over the combined record set. Reconcile per surface against the Workflow's `raw` array: any surface whose raw output is non-empty but yielded zero extracted records gets Stage 0 re-run main-thread on that raw text; whatever still fails to parse goes verbatim into `## Unparsed` — partial extraction never silently drops a surface.
6. **Persist** per `default-mode.md` "Findings-writer contract"; prepend the DEGRADED block when the fallback was taken.

**Diffability pre-check (before step 4):** the untracked-only diagnostic from `default-mode.md` applies here too — with nothing diffable, every leaf would diff an empty tree and return nothing. Emit the diagnostic and skip the launch; do NOT stage files.

## Pre-launch availability gate

The Workflow tool is org-disableable and not present in every session, and a failed launch is silent, not throwable — decide availability BEFORE attempting. Any failure → main-thread fallback:

| Check | Unavailable when |
|---|---|
| `CLAUDE_CODE_DISABLE_WORKFLOWS` env | set to `1` |
| merged settings `disableWorkflows` | `true` |
| Workflow tool absent from this session's toolset | not listed / not loadable |

If availability cannot be positively confirmed, fall back (fail-safe, not fail-open).

## The Workflow script

Constructed at dispatch: copy the script below, substitute `REVIEW_DIFF` (the resolved diff base) and `OWNERLESS_SLICES` (the discovered slice names, each as `'<path-or-name>'`), and pass it via `Workflow({script})`. Design constraints baked in:

- Plain JS — no TypeScript annotations; no `Date.now()`/`Math.random()`/argless `new Date()`.
- Each leaf reads the diff via its OWN Bash (`git diff <REVIEW_DIFF>`); the script layer has no filesystem access.
- Leaves return raw free-text (NO `schema`) — schema over a custom agent's baked-in output prose is unreliable. Only the dedicated extraction agent uses `schema` (a fresh general-purpose agent, where it is reliable).
- Backstop: the script always returns `raw` (every leaf's raw output alongside extracted records) so the main thread can reconcile per surface — partial extraction preserves unparsed surfaces, not just the all-zero case.

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
const REVIEW_DIFF = 'HEAD'          // resolved review diff base
const OWNERLESS_SLICES = []         // discovered project criteria docs (may be empty)

// tier1 = highest-value agents run first as a barrier so that if a finite
// budget exhausts, the lower-value tier2 is what drops (deterministic priority).
const TIER1 = [
  { label: 'security-reviewer',     agentType: 'review-toolkit:security-reviewer' },
  { label: 'architecture-guardian', agentType: 'review-toolkit:architecture-guardian' },
  { label: 'code-reviewer',         agentType: 'review-toolkit:code-reviewer' },
]
const TIER2_AGENTS = [
  { label: 'doc-drift-detector', agentType: 'review-toolkit:doc-drift-detector' },
]
const TIER2_SLICES = OWNERLESS_SLICES.map(s => ({ label: 'slice:' + s, slice: s }))

const AGENT_PROMPT =
  'Review the current change set. Run `git diff ' + REVIEW_DIFF + '` yourself to see the changes, plus ' +
  '`git ls-files --others --exclude-standard` for untracked files. Read the project review criteria and ' +
  'conventions relevant to your concern when present. Report findings in your normal output format.'

function slicePrompt(slice) {
  return 'Read the project review criteria document "' + slice + '". Run `git diff ' + REVIEW_DIFF + '` ' +
    'yourself to see the changes. Review the diff against ONLY that document\'s criteria. List each finding ' +
    'with file:line, a severity tier, and a one-line description. If the diff does not touch this concern, ' +
    'reply "No findings for ' + slice + '."'
}

phase('Review')

const t1 = await parallel(TIER1.map(leaf => () =>
  agent(AGENT_PROMPT, { agentType: leaf.agentType, label: leaf.label, phase: 'Review' })
))
const t2a = await parallel(TIER2_AGENTS.map(leaf => () =>
  agent(AGENT_PROMPT, { agentType: leaf.agentType, label: leaf.label, phase: 'Review' })
))
const t2s = await parallel(TIER2_SLICES.map(leaf => () =>
  agent(slicePrompt(leaf.slice), { label: leaf.label, phase: 'Review' })
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
  'confidence (later stages do that). Preserve EVERY finding — never drop one.\n\n' + extractInput,
  { schema: RECORD_SCHEMA, model: 'sonnet', label: 'stage0-extract', phase: 'Extract' }
)

const records = extracted && extracted.records ? extracted.records : []
return {
  records,
  raw: returned.map(r => ({ label: r.label, output: r.output })),
  nulls,
  ran: roster.map(l => l.label),
}
```

**Null reconciliation:** the reduce returns `nulls` (every leaf that produced no record, regardless of cause) and `ran` (the full expected roster). Render a `## Surfaces` line — `Ran: [...]. Returned no result: [...]` — NO silent caps; every null is named.

**Agent-type namespacing:** the `agentType` values above use the marketplace-installed form (`review-toolkit:<agent>`). When running via `--plugin-dir` or in a context where the plain names resolve, substitute the unqualified names at dispatch.

## Coverage-parity fallback (Workflows unavailable)

Spawn the SAME roster on the main thread via parallel Agent-tool calls (the main thread CAN spawn agents), using the same resolved review diff base, then run Stages 0–4 main-thread. Coverage and the findings contract are identical; what is lost: background execution, out-of-context intermediates, resume caching, and higher concurrency. If a dropped property is load-bearing for the caller, STOP and surface it rather than silently downgrading.

## Degraded notice

When the fallback is taken, prepend a structurally distinct block at the TOP of the chat output AND the persisted file body (a blockquote above `## Findings`):

```text
> DEGRADED: Workflows unavailable (<signal>); ran N leaves on the main thread; dropped:
> background-exec / out-of-context-intermediates / resume-caching / high-concurrency.
> Findings coverage is full; only the execution properties above are lost.
```

## Interrupted-run handling

If the Workflow is interrupted, relaunch with `Workflow({scriptPath, resumeFromRunId})` within the same session — the unchanged prefix of `agent()` calls returns cached. Across sessions, re-run from scratch. The report is written ONCE, main-thread, after the reduce returns — never partially from inside concurrent leaves.
