---
description: "Ranked improvements across code, performance, product, config, Claude Code setup, evidence-cited and sized S/M/L; unmeasured targets yield 'instrument this'. Never edits; unattended files work items. Use when: 'what should we improve', 'improvement sweep', 'what could we improve in X', 'tech debt sweep', 'where is the highest-value work', 'what would move the needle', 'run an improvement scan'. Skip: `architecture:improve`, `code-tidying:tidy`, `codebase-health:audit`, `review:fanout`, `work-items:scan-todos`."
argument-hint: "[target] [--small|--medium|--large] [--unattended] [repo-path]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Rank evidence-cited improvement candidates across dimensions; execution goes to the pipeline
---

## Repository context. Gather first

Collect these with **individual** Bash calls, one command per call, never combined into a single
invocation:

- Current branch, `git branch --show-current`
- Recent commits, `git log --oneline -15`
- Working tree status (empty = clean), `git status --porcelain | head -10`
- Shallow repository, `git rev-parse --is-shallow-repository`

The pipe is the bound and belongs in the command: the Bash tool returns the complete output into
context, so a read-time cap ("read only the first 10 entries") bounds nothing.

Treat a failure (not a repository, git unavailable) as an unknown value and carry on. Each call
stays on its own because a worktree-isolated session refuses a compound command that contains
git. The dated record for that refusal, and for the pre-compute composition that makes it bite, is
the
[gather-block convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/gather-block/README.md#the-pre-compute-block-runs-as-one-shell-invocation),
"The pre-compute block runs as one shell invocation".

## Variables

Arguments: `$ARGUMENTS`

## Purpose

Answer "what should we improve here, and how do we know?" across dimensions, grounding every
proposal in cited evidence so the ranking reflects measurement, not taste. This skill discovers
and deliberates only: execution flows through the repo's pipeline (interview → discovery →
planning → implementation → verification).

## Prompt interpretation

Parse `$ARGUMENTS` and the prompt for four independent narrowings; each defaults open:

- **Target scope.** Bare invocation scans the whole repo across every dimension. A targeted ask
  ("improve <feature|path|concept>") first maps the target to its concrete surfaces (files,
  workflows, config, ops touchpoints), then gathers evidence for those only. A concept with no
  resolvable surface is itself a finding (likely instrument-first).
- **Size band.** `--small` / `--medium` / `--large`, or prose ("quick wins only", "big swings"),
  restricts candidates to that band. Default: all sizes, ranked together.
- **Repo.** One repo per invocation: an explicit repo path, else the current repo. When the target
  is not the session's working directory, resolve its root once (`git -C <repo-path> rev-parse
  --show-toplevel`) and anchor EVERY probe to it (`git -C <root>` here and in the `context/`
  recipes, file reads under that root), so evidence never silently comes from the invoking repo;
  re-run the gather calls with `-C <root>`. Fleet-wide sweeps are out of scope: compose with
  `repo-fleet-hygiene` externally, one invocation per repo.
- **Mode.** Interactive by default. Unattended only when the caller declares it (Unattended mode).

## Scan dimensions

Walk this inventory explicitly so the scan never collapses to code-only. For each dimension,
gather what its tier sources yield, then propose candidates:

| Dimension | Examples of what to look at |
|---|---|
| Code / architecture | Churn×complexity hotspots, coupling and seam friction, dead or duplicated surface |
| Performance | Slow CI, slow tests, slow builds, known-slow runtime paths named by telemetry |
| Product-level behavior | Error rates, failure-prone user flows, gaps between documented and measured behavior |
| Config / automation outside the codebase | GitHub labels, Actions workflows, synchronizations, branch protections, bot config |
| Claude Code operational setup | Cloud environments, MCP servers, hooks, permission rules, plugin/skill configuration |

**Docs/markdown improvement is OUT.** Owned lanes (`docs-hygiene`, `codebase-health`) cover it: a
docs candidate names the owning lane and stays off the ranked list.

## Evidence ladder

Every candidate cites its evidence; its rung sets the ranking confidence (strongest first):

1. **Measured telemetry**. Production/application metrics, error rates, cost or latency data from
   a Tier 1/2 source.
2. **Repo and CI history**. Churn×complexity hotspots, CI failure ratios and duration trends,
   dependency staleness.
3. **Structural presence signals**. Test-coverage presence/absence, TODO density, missing
   automation where a class of toil demonstrably recurs.
4. **Model judgment**, the weakest rung, always labeled as such, never dressed up as measurement.

Two hard rules:

- **Instrument-first.** When the target has nothing above rung 4 (no telemetry, no usable CI
  history), the top-ranked candidate is "instrument this so future runs can rank on data": a
  concrete baseline proposal (what to measure, where the signal lands), handed to the pipeline
  like any other improvement. This mirrors the SRE error-budget posture: measurement precedes
  prioritization.
- **Gaps are recorded, never papered over.** An unavailable source (no GitHub access path, shallow
  clone, no telemetry configured) produces an explicit evidence-gap line. Absence of evidence is
  reported, never fabricated, estimated, or silently skipped.

## Evidence sources (tiered, presence-gated)

- **Tier 0. Repo-native, always available.** Git churn/hotspots (context/hotspots.md, including
  its shallow-history gate), CI health from GitHub Actions run data (context/ci-health.md),
  dependency staleness from the repo's manifests, test-coverage presence, TODO density.
- **Tier 1. Local Claude Code telemetry.** When `harness-ops:observability` is installed, consult
  it for session/cost/hook telemetry for the operational-setup dimension.
- **Tier 2. Configured application telemetry.** The MCP telemetry sources the consumer declares
  through the `.claude/improvement.md` config cascade (team file + `.local` overlay +
  user-global; key contract in the plugin's reference/config.md). Never hardcode a vendor; with no
  source configured, Tier 2 is an evidence gap and product-level candidates fall down the ladder.

**GitHub access-path probe ladder.** For CI and repo-platform data, probe in order: GitHub MCP
tools (`actions_*` and repo tools) → `gh` CLI → none. On "none", record the evidence gap and rank
without CI evidence, never reconstruct CI health from guesswork.

## Lane delegation as scan input

Where an installed finder covers a dimension more deeply, consult it presence-gated and fold its
findings in as inputs. Delegate, never re-inline its method:

- `architecture:improve` (deepening lens) for the code/architecture dimension.
- `harness-config:audit-automation-gaps` for the Claude Code operational-setup dimension.
- `/code-metrics:audit-duplication`, when among the available skills, for copy count and clone
  trend: run it with `--json --keep --all` and read the document it prints (`--keep` keeps it as
  the next run's trend baseline). A class's copy count is its number of instances; read only the
  `trend` code-metrics computes (including new and grown classes), never an earlier report. Copy
  count ranks spread (context/ranking.md). A growing class becomes a candidate whose next step is
  a lint proposal, written through the findings hand-off under
  `<memory_dir>/improvement/<branch-slug>/` (context/unattended.md "Growing clone classes"). When
  code-metrics is not available, or no detector ran, record a `gap:` line for duplication.
- Other installed finders that announce an improvement-shaped scan, the same way.

Delegated findings keep their lane attribution in the evidence citation and compete in the same
ranked list. With no lane installed, the Tier 0 scan for that dimension stands alone.

In unattended mode, consult only lanes that run without interaction; skip an interview- or
confirmation-driven lane with a `gap:` line naming it, and never simulate a user to drive it.

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

Scoring and dedupe: context/ranking.md. Evidence-gap lines follow the list so the reader knows
what the ranking could not see.

## Interactive flow

1. Present the ranked list, evidence gaps included.
2. The user picks a candidate.
3. Interview on the pick: invoke `/planning:interview` via the Skill tool when available, to settle
   what improvement, why now, what evidence, and what done looks like.
4. Hand off, invoking each via the Skill tool: `/discovery:explore` (internal unknowns) or
   `/discovery:research` (external unknowns) as needed, then `/planning:plan`, with the interview
   output and the candidate's evidence citation as the handoff. A pick that fits one small PR may
   instead go to `/improvement:improve`, invoked via the Skill tool with the candidate as target.
5. Offer to file unpicked candidates via `/work-items:track` when installed; the user decides
   which, if any.

Where a named pipeline skill is not installed, summarize the equivalent handoff inline instead of
blocking; a missing pipeline skill never licenses implementing the improvement in this session.

## Unattended mode

Entered only when the **caller declares it** in the invocation prompt (a routine wrapper, a
scheduled job, an orchestrating skill), never sniffed from the environment, per the fleet's
declared-by-the-caller convention. In unattended mode:

- **No questions.** No interview, picks, or confirmations; decisions resolve by the defaults below
  or the invocation prompt's overrides.
- **The report is persisted**, the full ranked list plus evidence-gap lines, under
  `${CLAUDE_PLUGIN_DATA}`, keyed per project per the plugin-data-report-keying convention (shape
  and keying: context/unattended.md).
- **Top candidates are filed** via `work-items:track` when installed (absent tracker = report only,
  noted in the report):
  - *Dismissed-candidate memory, at candidate assembly.* Suppress candidates an operator
    previously dismissed before ranking, so they consume no cap slot or tracker query. A soft
    default the invocation prompt can override.
  - *Dedupe against open work items, at filing time.* Search before creating each item. Baseline
    behavior, not a knob: a duplicate is a bug.
  - *Adaptive filing cap*, a soft default bounding how many items one run files (following
    `work-items:work-loop`'s adaptive cap), overridable by the invocation prompt.

  Consultation order and its rationale: context/ranking.md.
- **Nothing else mutates, and nothing self-disposes.** Read-only apart from the report, the filed
  items, and the code-metrics writes the verb contract names. It never picks a candidate,
  prioritizes the queue, or starts implementation: prioritizing filed items is always
  human-gated, the autonomy catalog's `tech-debt-sweep` C1 contract.

## Execution requests

"Go implement this", interactively or as a follow-up, routes through the pipeline, never this
skill's own hands: interview the pick → `/discovery:explore` / `/discovery:research` →
`/planning:plan` → `/implementation:implement` → `/verification:confirm`, each invoked via the
Skill tool. An execution request changes where the handoff goes, not what this skill may touch.

## What this skill does NOT do / Skip when

Each row names an owned lane this skill delegates to or steps aside for; it re-implements none.

| Skip when the ask is | Owned by | Why not here |
|---|---|---|
| Single-lens architecture depth (shallow modules, Design-It-Twice) | `architecture:improve` | That lens is consulted as a scan input; going deep on architecture alone is its job |
| Doing one improvement now ("improve this", "fix one thing") | `improvement:improve` | This skill ranks and never edits; `improve` picks one gap and ships it as one PR |
| Applying small safe code edits | `code-tidying:tidy` | This skill never edits; tidying mutates by contract |
| Verifying docs/config/code drift claims | `codebase-health:audit` | Claim verification, not improvement discovery |
| Reviewing a diff before merge | `review:fanout` | Diff-scoped and reactive; this skill scans existing state proactively |
| Sweeping TODO/FIXME markers into items | `work-items:scan-todos` | Marker sweep is one narrow signal; here TODO density is evidence, not the deliverable |

**Verb contract.** `find` never edits the target's tracked files. What it writes depends on the
mode:

- **Interactive** (bare invocation): it reports and stops, apart from the code-metrics writes
  below.
- **Unattended**: the caller's declaration IS the explicit mutation override, the same shape as
  the `audit` verb's autofix override, and it authorizes exactly two more things: the report
  persisted under `${CLAUDE_PLUGIN_DATA}/find/<state-key>/` (with the dismissed-candidate memory
  beside it) and presence-gated work-item filing.
- **Either mode, only when code-metrics is enabled**:
  - `/code-metrics:audit-duplication --json --keep`, which this skill runs, keeps its report in
    code-metrics' own data directory, `reports/<state-key>/audit-duplication-<UTC stamp>.json`
    (code-metrics keeps the newest 20 per project), the baseline of the next run's trend;
  - for a growing clone class, this skill writes one review-findings file,
    `<memory_dir>/improvement/<branch-slug>/<UTC stamp>-clone-growth.md`, and, on its first
    memory-tier write, a `.gitignore` containing `*` in `<memory_dir>` when that file is absent
    (context/unattended.md "Growing clone classes").

No other mutation exists in any mode; no flag, prompt, or mode makes this skill edit the target's
tracked files.

## Spoke paths

The `context/` files write the plugin's root directory as `<plugin-root>`, which is
`${CLAUDE_PLUGIN_ROOT}`. Put that path in place of the placeholder before running a command or
writing it into a brief: those files arrive through the Read tool as plain bytes, so a `${…}`
token in them would reach the Bash tool unsubstituted, and the Bash tool's environment has no
`CLAUDE_PLUGIN_ROOT` to expand it from. Basis: the plugins reference,
<https://code.claude.com/docs/en/plugins/manifest-reference#where-each-variable-resolves>, verified
2026-10-07; recheck when that table adds supporting files to where a `${…}` reference resolves.

## Next

- Picked candidate fits one small PR: /improvement:improve TARGET.
- Picked candidate needs design or several PRs: /planning:interview.

## Gotchas

- **Shallow or truncated clones poison churn rankings.** The hotspot recipe's history-depth gate
  (context/hotspots.md) runs first; a window the history does not cover downgrades churn to a
  recorded evidence gap. A confidently wrong ranking from partial history is worse than none.
- **Never call the Actions `/timing` endpoint**: GitHub marks it as closing down. The dated record
  for that, and for the documented 1,000-result bound behind the windowing rule, is in
  context/ci-health.md. CI health iterates `/actions/runs` by `created` date windows (never deep
  pagination) and derives failure ratios, duration trends, and `run_attempt` retries per that file.
- **Unattended is declared, never detected.** Non-interactivity cannot be observed; guessing turns
  an interactive user's session into a silent filing run.
- **No access path ≠ healthy CI.** A missing GitHub access path is an evidence-gap line, never a
  reason to estimate CI health from the working tree.
