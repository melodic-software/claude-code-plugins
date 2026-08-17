---
description: "Evidence-first, cross-dimension improvement finder: scans code/architecture, performance, product-level behavior, config/automation outside the codebase (GitHub labels, Actions), and Claude Code operational setup, then returns a ranked candidate list — every candidate cites its evidence (telemetry, CI failure rates, churn hotspots, or, weakest, model judgment) and carries an S/M/L size with a value-to-effort rationale; an unmeasured target makes 'instrument this' the top candidate. Interactive default (pick, interview, pipeline handoff); caller-declared unattended mode persists the report and files top candidates as work items. Never edits anything itself — execution routes through the discovery/planning/implementation pipeline. Use when: 'what should we improve', 'find improvements', 'improvement sweep', 'improve <X>', 'highest-impact improvement', 'tech debt sweep', 'where is the highest-value work', 'what would move the needle', 'run an improvement scan'. Skip when: single-lens architecture deepening (`architecture:improve`), applying small safe code edits (`code-tidying:tidy`), verifying doc/config drift claims (`codebase-health:audit`), reviewing a diff (`review:fanout`), or sweeping TODO markers (`work-items:scan-todos`)."
argument-hint: "[target] [--small|--medium|--large] [--unattended] [repo-path]"
user-invocable: true
disable-model-invocation: false
shell: bash
metadata:
  workflow-stage: anytime
  summary: Rank evidence-cited improvement candidates across dimensions; execution goes to the pipeline
---

## Pre-computed context

Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`
Recent commits: !`git log --oneline -15 2>/dev/null || echo "no commits"`
Working tree status: !`git status --porcelain 2>/dev/null | head -10 || echo "(unavailable)"`
Shallow repository: !`git rev-parse --is-shallow-repository 2>/dev/null || echo "unknown"`

## Variables

Arguments: `$ARGUMENTS`

## Purpose

This skill answers "what should we improve here, and how do we know?" — the second half of that
question is its identity. Review evaluates a diff; planning designs already-chosen work; the
specialized finders each hunt one lens. This skill forms its own cross-dimension judgment about
what is worth improving in a target — code, product behavior, process surfaces, operational setup —
and grounds every proposal in cited evidence, so ranking reflects measurement, not taste. It
discovers and deliberates only: execution always flows through the repo's normal pipeline
(interview → discovery → planning → implementation → verification), and this skill edits nothing in
any mode.

## Prompt interpretation

Parse `$ARGUMENTS` and the invoking prompt for four independent narrowings; each defaults open:

- **Target scope.** Bare invocation scans the whole repo across every dimension below. A targeted
  ask — "improve <feature>", "improve <path>", "improve <concept>" — narrows the scan: map the
  named feature/path/concept to its concrete surfaces (files, workflows, config, ops touchpoints)
  before gathering evidence, and gather evidence for those surfaces only. A concept with no
  resolvable surface is itself a finding (likely instrument-first, below).
- **Size band.** `--small` / `--medium` / `--large` (or equivalent prose: "quick wins only", "big
  swings") restricts candidates to that size band. Default: all sizes, ranked together.
- **Repo as parameter.** One repo per invocation. An explicit repo path in the arguments makes that
  checkout the target; otherwise the current repo is. Fleet-wide sweeps are out of scope — compose
  with `repo-fleet-hygiene` externally, one invocation per repo.
- **Mode.** Interactive is the default. Unattended is entered ONLY when the caller declares it (see
  Unattended mode) — never inferred from context.

## Scan dimensions

The scan walks this inventory explicitly, so it cannot silently collapse to code-only. For each
dimension, gather whatever evidence its tier sources yield, then propose candidates:

| Dimension | Examples of what to look at |
|---|---|
| Code / architecture | Churn×complexity hotspots, coupling and seam friction, dead or duplicated surface |
| Performance | Slow CI, slow tests, slow builds, known-slow runtime paths named by telemetry |
| Product-level behavior | Error rates, failure-prone user flows, gaps between documented and measured behavior |
| Config / automation outside the codebase | GitHub labels, Actions workflows, synchronizations, branch protections, bot config |
| Claude Code operational setup | Cloud environments, MCP servers, hooks, permission rules, plugin/skill configuration |

**Docs/markdown improvement is OUT** — owned lanes (`docs-hygiene`, `codebase-health`) cover it;
finding a docs candidate means naming the owning lane, not adding it to this list.

## Evidence ladder

The skill's core mechanic. Every candidate cites its evidence, and its rung on this ladder sets the
confidence attached to the ranking (strongest first):

1. **Measured telemetry** — production/application metrics, error rates, cost or latency data from
   a Tier 1/2 source.
2. **Repo and CI history** — churn×complexity hotspots, CI failure ratios and duration trends,
   dependency staleness. Mechanical, reproducible, repo-native.
3. **Structural presence signals** — test-coverage presence/absence, TODO density, missing
   automation where a class of toil demonstrably recurs.
4. **Model judgment** — the weakest rung: this session's read of the target. Always labeled as
   such, never dressed up as measurement.

Two hard rules follow:

- **Instrument-first.** When the target has no measurement at all — no telemetry, no usable CI
  history, nothing above rung 4 — the top-ranked candidate becomes "instrument this so future runs
  can rank on data": a concrete baseline/instrumentation proposal (what to measure, where the
  signal lands), handed to the pipeline like any other improvement. This mirrors the SRE
  error-budget posture: measurement precedes prioritization.
- **Gaps are recorded, never papered over.** An evidence source that is unavailable (no GitHub
  access path, shallow clone, no telemetry configured) produces an explicit evidence-gap line in
  the output. Absence of evidence is reported; it is never fabricated, estimated, or silently
  skipped.

## Evidence sources (tiered, presence-gated)

- **Tier 0 — repo-native, always available.** Git churn/hotspot analysis (recipe:
  context/hotspots.md, including its shallow-history gate), CI health via GitHub Actions run data
  (recipe: context/ci-health.md), dependency staleness from the repo's own manifests,
  test-coverage presence, TODO density. These ship with the skill and need nothing installed.
- **Tier 1 — local Claude Code telemetry.** When `claude-ops:observability` is installed, consult
  it for session/cost/hook telemetry relevant to the operational-setup dimension.
- **Tier 2 — configured application telemetry.** Whatever MCP telemetry sources the consumer
  declares through the `.claude/improvement.md` config cascade (team file + `.local` overlay +
  user-global; key contract in the plugin's reference/config.md). Never hardcode a vendor; if no
  source is configured, Tier 2 is an evidence gap, and product-level candidates fall back down the
  ladder.

**GitHub access-path probe ladder.** For CI and repo-platform data, probe in order: GitHub MCP
tools (`actions_*` and repo tools) → `gh` CLI → none. On "none", record the evidence gap and rank
without CI evidence — never reconstruct CI health from guesswork.

## Lane delegation as scan input

Where an installed specialized finder covers a dimension more deeply, consult it presence-gated and
fold its findings into this skill's candidate list as inputs — delegate, never re-inline its
method:

- `architecture:improve` (deepening lens) — depth for the code/architecture dimension.
- `claude-config:audit-automation-gaps` — depth for the Claude Code operational-setup dimension.
- Other installed finders that announce an improvement-shaped scan may be consulted the same way.

Delegated findings keep their lane attribution in the evidence citation, and they compete in the
same ranked list as native candidates. Where no lane is installed, the skill's own Tier 0 scan for
that dimension stands alone — reuse-or-replace: never re-implement what an owned lane already does.

## Candidate output shape

One ranked list, highest value-to-effort first. Every row carries:

| Field | Content |
|---|---|
| Rank | Position; the highest-impact candidate leads |
| Candidate | One-line improvement statement, concrete enough to hand to an interview |
| Dimension | Which scan dimension it belongs to |
| Size | S / M / L |
| Evidence | Citation: source + specifics (e.g. "hotspot: 14 commits/90d × high indentation"), and its ladder rung |
| Confidence | Derived from the evidence rung, stated plainly |
| Value-to-effort | WSJF-style rationale: cost of delay (value, urgency, risk reduction) against job size |

Scoring and dedupe mechanics: context/ranking.md. Evidence-gap lines appear after the list so the
reader knows what the ranking could not see.

## Interactive flow

1. Present the ranked candidate list (shape above), evidence gaps included.
2. The user picks a candidate.
3. Interview on the pick — via `/planning:interview` when available — to reach a shared shape:
   what improvement, why now, what evidence, what done looks like.
4. Hand off to the pipeline: `/discovery:explore` (internal unknowns) or `/discovery:research`
   (external unknowns) as needed, then `/planning:plan`. The handoff artifact is the interview's
   output, with the candidate's evidence citation attached.
5. Offer the remainder: unpicked candidates can be filed via `work-items:track` when installed —
   the user decides which, if any.

Where a named pipeline skill is not installed in the consuming project, summarize the equivalent
handoff shape inline instead of blocking — but absence of a pipeline skill is never license to
implement the improvement in this session.

## Unattended mode

Entered only when the **caller declares it** in the invocation prompt (a routine wrapper, a
scheduled job, an orchestrating skill) — never sniffed from the environment, per the fleet's
declared-by-the-caller convention. In unattended mode:

- **No questions.** No interview, no picks, no confirmation prompts. Decisions resolve by the
  defaults below or by the invocation prompt's overrides.
- **The report is persisted** — the full ranked list plus evidence-gap lines — under
  `${CLAUDE_PLUGIN_DATA}`, keyed per project per the plugin-data-report-keying convention (report
  shape and keying: context/unattended.md).
- **Top candidates are filed** via `work-items:track` when installed (absent tracker = report
  only, noted in the report). Filing behavior:
  - *Dedupe against open work items first* — baseline behavior, not a tuning knob; filing a
    duplicate is a bug.
  - *Adaptive filing cap* — a soft default bounding how many items one run files (following
    `work-items:work-loop`'s adaptive-cap precedent), overridable by the invocation prompt.
  - *Dismissed-candidate memory* — candidates an operator previously dismissed are suppressed by
    default; also prompt-overridable. The routine prompt wrapping this skill is the tuning surface.
- **Nothing else mutates, and nothing self-disposes.** The run is read-only apart from the report
  and the filed items; it never picks a candidate, never prioritizes the queue, never starts
  implementation. Prioritization of filed items is human-gated always — the autonomy catalog's
  `tech-debt-sweep` C1 contract.

## Execution requests

"Go implement this" — interactively or as a follow-up — routes through the pipeline, never through
this skill's own hands: interview the pick → `/discovery:explore` / `/discovery:research` →
`/planning:plan` → `/implementation:implement` → `/verification:confirm`, each delegated to its
skill. This skill performs no code edits in any mode; an execution request changes where the
handoff goes, not what this skill is allowed to touch.

## What this skill does NOT do / Skip when

Reuse-or-replace posture: each boundary below names an owned lane this skill delegates to or steps
aside for — it re-implements none of them.

| Skip when the ask is | Owned by | Why not here |
|---|---|---|
| Single-lens architecture depth (shallow modules, Design-It-Twice) | `architecture:improve` | That lens is consulted as a scan input; going deep on architecture alone is its job |
| Applying small safe code edits | `code-tidying:tidy` | This skill never edits; tidying mutates by contract |
| Verifying docs/config/code drift claims | `codebase-health:audit` | Claim verification, not improvement discovery |
| Reviewing a diff before merge | `review:fanout` | Diff-scoped and reactive; this skill scans existing state proactively |
| Sweeping TODO/FIXME markers into items | `work-items:scan-todos` | Marker sweep is one narrow signal; here TODO density is evidence, not the deliverable |

**Verb contract.** `find` reads as read-only, and it is: bare invocation reports and stops. The
caller's unattended declaration IS the explicit mutation override that authorizes work-item filing —
the same shape as the `audit` verb's autofix override — and it authorizes exactly that: report
persistence and presence-gated filing. No other mutation exists in any mode; there is no flag,
prompt, or mode that makes this skill edit the target.

## Gotchas

Known traps, seeded from the research this skill was grounded on:

- **Shallow or truncated clones poison churn rankings.** The hotspot recipe's history-depth gate
  (context/hotspots.md) runs first; a window the history does not cover downgrades churn to a
  recorded evidence gap — confidently-wrong rankings from partial history are worse than no
  ranking.
- **Never call the Actions `/timing` endpoint** — it is deprecating. CI health iterates
  `/actions/runs` by `created` date windows (never deep pagination) and derives failure ratios,
  duration trends, and `run_attempt` retries per context/ci-health.md.
- **Unattended is declared, never detected.** There is no supported way to observe
  non-interactivity; guessing it converts an interactive user's session into a silent filing run.
- **No access path ≠ healthy CI.** A missing GitHub access path is an evidence-gap line, not a
  reason to estimate CI health from the working tree's vibes.
