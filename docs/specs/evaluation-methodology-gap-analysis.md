# Fleet eval corpus vs Agent Skills evaluation pipeline

This document records a gap analysis of the marketplace fleet's `evals/evals.json` corpus (284 skill-level files on
2026-09-28; the corpus grows, so treat the count as a dated snapshot, not a pinned value) against the pipeline described in Anthropic's [evaluating
skills](https://agentskills.io/skill-creation/evaluating-skills) guidance and the `skill-creator`
reference on `claude-plugins-official`.

**Method:** read the official pipeline elements, map each to an existing fleet surface (`evals.json`,
`/evals:plugin-eval`, `/evals:design`, `/skill-quality:check validate-evals`, subagent dispatch
patterns), and record one verdict per row. Where two levels differ (for example plugin versus
skill `evals.json`), the row carries one scoped verdict per level.

**Status of the verdicts:** this is a read-only analysis. Every **adopt** verdict is a proposal,
re-gated to the operator one element at a time (operator decision on #3614, 2026-09-27); no
verdict in the table below is decided here. The operator's decisions are in
"Operator decisions (#5255)" at the end.

| Pipeline element | Fleet today | Verdict | Notes |
|---|---|---|---|
| With-skill vs without-skill baseline runs | `claude plugin eval` runs each plugin case twice (with / without) and writes `aggregate-result.json`; `/evals:plugin-eval` documents the delta read order. Per-skill `evals/evals.json` cases are prompt + `expectations[]` only, with no built-in no-skill arm. | **already-covered** (plugin) / **adopt** (skill `evals.json`) | Plugin-level baselines are covered. Skill-level files should document when a no-skill arm is required and route authors to `plugin eval` or an explicit A/B harness for whole-plugin claims. |
| Workspace / iteration directory layout | Plugin eval uses the CLI's suite layout; consumer repos use `docs/eval-criteria/` via `/evals:design`. No fleet-wide convention for iteration folders beside `.work/` memory slices during skill iteration. | **adopt** | Add a documented iteration layout in `/evals:design` output (criteria doc + eval dir + run artifacts) mirroring skill-creator's propose/run/review folders without requiring that plugin. |
| Assertion discipline (verifiable, specific, countable; not vague or brittle) | `skill-quality` ships `evals.schema.json` and `validate-evals`; cases use `expectations[]` strings. Quality varies by plugin; vague expectations still slip through. | **already-covered** (mechanism) / **adopt** (enforcement) | Keep schema validation; extend lint or review guidance to refuse untestable expectation phrasing (same bar as planning sanity checks). |
| Script-based grading for mechanical checks; blind LLM judge for holistic quality | Methodology reference describes code-graded vs LLM-graded paths. Most fleet `evals.json` files are LLM-grader-shaped natural-language expectations only. | **adopt** | Prefer script or deterministic graders in `evals:validate` / future runner hooks where output is constrainable; reserve LLM judge for holistic rows and document blindness requirements. |
| Benchmark deltas weighing pass-rate against token/time cost | `/evals:plugin-eval` preflight prints `estimate_usd` and reads results with cost awareness; `max_cost_usd` user config caps spend. Skill-level eval files do not record token/time budgets per case. | **already-covered** (plugin-eval) / **adopt** (corpus metadata) | Plugin path is covered. Add optional per-suite metadata for expected cost class so triage can compare pass-rate wins against price. |
| Closed propose → apply → rerun → review loop | `/playbooks:skill-authoring` and `skill-quality` document the loop; nothing in CI reruns evals on skill edits by default. | **adopt** | Wire highest-value skills to optional CI or lane hooks that rerun a bounded eval subset on skill diff (cost-gated), matching the documented loop. |
| Subagent isolation as clean-context eval mechanism | Planning, discovery, implementation, and review plugins dispatch purpose-built agents; plugin eval runs cases in isolated CLI sessions. | **already-covered** | Fleet already treats clean context as default for verification-style work; eval runners should keep prohibiting implementer numbers in verifier briefs (same pattern as `/performance:verify`). |
| Task-completion notification as token/duration metrics source | `/claude-ops:observability` and session tooling expose usage; not wired into eval aggregate JSON for skill `evals.json` runs. | **rejected** (for skill evals.json runner) | Official guidance targets Claude Code task notifications; this repo's skill eval format is static prompt grading, not live harness telemetry. Revisit only if the fleet adopts a single runner that executes cases inside Claude Code and records completion metrics. |
| Compare against `skill-creator` on `claude-plugins-official` before building parallel infra | `/evals:design` and playbooks cite skill-creator and `plugin eval` separation; no automated diff vs upstream skill-creator. | **adopt** | Before expanding fleet runner scope, run a periodic manual or scripted checklist against upstream skill-creator capabilities and record deltas in this file. |

## Proposed adoptions for the operator gate (priority)

1. Skill-level **no-skill arm** documentation and routing (`evals.json` → when to use `plugin eval`).
2. **Script graders** for mechanical expectations in high-traffic skills.
3. **Cost metadata** on suites that run through `plugin eval`.
4. Optional **CI rerun** hook for skill edits (cost-capped).

## Recorded verdict summary

| Row verdict | Rows |
|---|---|
| already-covered only | 1 |
| adopt only | 4 |
| already-covered at one level, adopt at another | 3 |
| rejected | 1 |
| **Total** | **9** |

Acceptance for #3614: each pipeline element above carries **adopt**, **already-covered**, or
**rejected** with reason.

## Operator decisions (#5255)

Item numbers follow the operator-gate list in the issue. Rejected: none.

| Item | Gap-analysis row | Decision | Condition | Work item |
|---|---|---|---|---|
| 1. No-skill arm documentation | With-skill vs without-skill baseline runs | Adopted | Docs only, now | #5393 |
| 2. Script graders for mechanical expectations | Script-based grading for mechanical checks | Adopted | After item 1; pilot on a few high-traffic skills | #5397 |
| 3. Cost metadata on suites | Benchmark deltas weighing pass-rate against token/time cost | Deferred | Until item 1 lands | none yet |
| 4. Cost-capped CI rerun on skill edits | Closed propose, apply, rerun, review loop | Deferred | Until items 2 and 3 land | none yet |
| 5. Assertion-discipline enforcement | Assertion discipline | Adopted | After the assertion-discipline measurement is recorded | #5394 |
| 6. Comparison against upstream `skill-creator` | Compare against `skill-creator` before building parallel infra | Adopted | One-time manual comparison, now | #5395 |
| 7. Iteration directory layout | Workspace / iteration directory layout | Deferred | Until the item 2 pilot shows what authors produce | none yet |
