# general-improvement-skill

## Brief

### TLDR

New plugin `improvement` with one skill, `/improvement:find`: an evidence-first, cross-dimension
improvement finder. Point it at any target — a repo, a feature, a concept, a process surface —
with a vague or specific prompt; it produces a ranked, evidence-cited list of improvement
candidates (all sizes, led by highest value-to-effort), deliberates on the picked candidate
through an interview, and hands off to the existing planning pipeline. Routine-runnable
unattended: persists the ranked report and files top candidates as work items, implementing the
autonomy catalog's `tech-debt-sweep` routine contract.

### Goal

Give the fleet its missing "what should we improve here, and how do we know?" entry point:
a finder that forms its own judgment about code/product/process/ops-level improvements,
grounded in evidence, feeding — never bypassing — the existing interview → discovery →
planning → implementation → verification pipeline.

### Constraints

- **Finder-forward hybrid.** The skill's own scan is primary. It delegates to installed
  specialized lanes presence-gated only where they add value (e.g. `architecture:improve`'s
  deepening lens as one input), and never re-implements what an owned lane already does
  (reuse-or-replace posture).
- **Evidence ladder is the core mechanic.** Every candidate cites its evidence (telemetry,
  error/CI failure rates, churn hotspots, or — weakest — model judgment from reading the
  target); ranking confidence is a function of evidence strength; when the target has no
  measurement, the top-ranked candidate becomes "instrument this so future runs can rank on
  data," handed to the pipeline like any other improvement.
- **Evidence sources are tiered and presence-gated.** Tier 0 (always available, ships in V1):
  repo-native signals — git churn/hotspots, CI health via the GitHub MCP, dependency
  staleness, test-coverage presence, TODO density. Tier 1: local Claude Code telemetry via
  `claude-ops:observability` when installed. Tier 2: application telemetry (e.g. Azure App
  Insights, logs) through whatever MCP server the evidence-source config declares — a
  three-layer config cascade in the style of `codebase-health`, never hardcoded Azure. V1
  ships Tier 0 fully plus the gating mechanism.
- **Improvement dimensions** include code/architecture, performance, product-level behavior,
  config/automation outside the codebase (GitHub labeling, Actions, synchronizations), and
  Claude Code operational setup (cloud environments, MCP servers, web sessions).
  Markdown/docs improvement is OUT — owned by existing lanes.
- **Read-only finder; pipeline-mediated execution.** The skill never edits code inline. By
  default it discovers and deliberates only. On an explicit user instruction ("go implement
  this") it proceeds ONLY by chaining the repo's normal skill pipeline — interview →
  `/discovery:explore` / `/discovery:research` → `/planning:plan` →
  `/implementation:implement` → `/verification:confirm` — delegating to those skills.
- **Dual-mode.** Interactive default: present ranked candidates → talk-through interview on
  the pick → pipeline handoff artifact; the rest can be filed as work items. Unattended
  (declared by the caller, e.g. a routine): no questions; persist the ranked report; file top
  candidates via `work-items:track` when installed; never mutates, never self-disposes —
  the `tech-debt-sweep` C1 contract, prioritization human-gated.
- **Unattended noise controls** *(pending Q11 confirmation)*: default cap of 5 filed items
  per run (configurable), dedupe against open work items before filing, and a persisted
  memory of dismissed candidates so rejected findings are not refiled.
- **Scope: one repo per invocation**, repo as a parameter; routines target repos
  individually; fleet-wide sweeps are a later composition with `repo-fleet-hygiene`.
- **Sizes:** find across small/medium/large; rank by value-to-effort; lead with the
  highest-impact candidate; a prompt or flag narrows the size band.
- **Naming/publishing:** plugin `improvement` (noun, true of every skill under it), skill
  `find` (imperative verb; namespace supplies the object). Full publish gate: plugin.json,
  `./`-prefixed marketplace entry with taxonomy category, `claude plugin validate --strict`,
  regenerate CATALOG + cheat-sheet, `skill-quality:check`, leaf-name registry check,
  explicit "Skip when / NOT for" boundaries against `architecture:improve`,
  `code-tidying:tidy`, `codebase-health:audit`, `review:fanout`, and `work-items:scan-todos`.

### Acceptance criteria

- Bare `/improvement:find` on a repo yields a ranked candidate list; every candidate carries
  an evidence citation, a size (S/M/L), and a value-to-effort rationale; the list leads with
  the highest-impact item.
- A targeted prompt ("improve <feature>", "improve this concept") narrows the scan scope
  accordingly.
- Against a target with no measurement, the top candidate is an instrumentation/baseline
  recommendation, explained as such.
- Interactive mode: picking a candidate enters an interview and ends with a handoff the
  planning pipeline can consume.
- Unattended mode (caller-declared): produces the persisted report, files work items
  presence-gated within the noise-control contract, asks no questions.
- Execution requests route through the pipeline skills; the skill itself performs no code
  edits in any mode.
- Ships past the full publish gate (validate --strict, skill-quality:check, catalog and
  cheat-sheet regenerated) with boundary clauses in the description.

### Captured assumptions

- Marketplace self-improvement (improving this repo's plugins/skills) rides the generic
  dimensions; no special-case marketplace logic in V1.
- The unattended caller-declaration mechanism follows the fleet's existing convention
  (declared by the caller, never sniffed).

### Out of scope (V1)

- Docs/markdown improvement (owned lanes).
- Fleet-wide sweeps (later composition with `repo-fleet-hygiene`).
- Plugin-candidate discovery (deferred, Q10).
- A polished Azure App Insights adapter (deferred, Q12); the Tier 2 gate covers a
  user-configured MCP in the meantime.
- Metrics dashboards/trend visualization; auto-apply/auto-merge of any improvement.

### Deferred questions

- Q10 — arbiter: USER-RESERVED — Plugin-candidate discovery ("what plugin candidates do we
  have, new or existing"): later sibling skill under `improvement` or `plugin-quality`;
  revisit after V1 ships.
- Q12 — arbiter: /planning:plan — Timing of a first-class App Insights/Azure telemetry
  adapter beyond the generic Tier 2 MCP gate.

## Plan

*(Empty — `/planning:plan` fills this section.)*
