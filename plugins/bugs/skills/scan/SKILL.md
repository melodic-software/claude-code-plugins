---
description: "Proactive hunt for unobserved bugs in resting code: read-only, recall-biased hunter subagents per lens, then a fresh-context refute gate per candidate, reporting only verified five-field findings over a target path, feature or diff, or a rotated lane. Use when the user asks to 'find a bug', 'bug hunt', 'scan for bugs' or 'hunt for bugs in X', or a loop or routine runs the lane rotation. Skip when reviewing a diff (review:code-review), security auditing (review:security-review), root-causing an observed failure (debugging:debug), or checking doc, config, code or architecture claim drift (codebase-health:audit); 'scan repo for issues' is harness-ops:known-issues, and 'file a bug' the user observed is bugs:write."
argument-hint: "[<path|feature|diff>] [--lane <name>] [--track] [--dry-run]"
user-invocable: true
disable-model-invocation: false
shell: bash
metadata:
  workflow-stage: operator
  summary: Proactively hunt resting code for unobserved bugs, verify adversarially, report read-only
  cadence: daily
---

## Repository context. Gather first

Run each as its own Bash call, never combined:

- Current branch, `git branch --show-current`
- Recent commits, `git log --oneline -10`
- Shallow clone, `git rev-parse --is-shallow-repository`

A failure (not a repository, git unavailable) is an unknown value; carry on. These stay body Bash
calls rather than pre-compute lines because a worktree-isolated session refuses a compound command
that contains git. The dated record for how the pre-compute block is composed is
owned by `/source-control:worktree` (its gather-block record, "The pre-compute block runs as one
shell invocation"); how injected commands run is read at
[skills: how injected commands run](https://code.claude.com/docs/en/skills#how-injected-commands-run).
As of: 2026-10-11. Recheck triggers: the gather-block section moves, is renamed, or changes how the
block is composed; the skills section changes how a block's commands are run.

## Pre-computed context

Lane config: !`ls "${CLAUDE_PROJECT_DIR:-.}/.claude/bugs.md" 2>/dev/null || echo "absent — bundled default lanes apply"`

Consumer gotchas:
!`bash "${CLAUDE_PLUGIN_ROOT}/scripts/concat-gotchas.sh" || echo "(consumer gotchas unavailable)"`

## Variables

Arguments: `$ARGUMENTS`

## Purpose

Hunt defects **nobody has observed yet** in resting code; no diff, failing test, or stack trace is
needed. One invocation is **one bounded pass**: hunt a target or a rotated lane, verify each
candidate through a separate fresh-context gate, report what survives in the plugin's five-field
shape, stop. Per-run recall is low and the raw false-positive rate high, so recall and precision
are separate stages: hunters are told to be generous, the gate is told to refute.

## Verb contract. Read-only toward the repository

A bare invocation never edits code, branches, pushes, or files a tracker item. Filing sits behind
`--track`, which model auto-invocation never supplies on its own: a user or a standing lane rule
must ask for it. Out of scope, with their owners: coverage gaps (`/testing:audit`,
`/mutation-testing:audit`), structural drift (`/code-tidying:tidy`), and comment markers
(`/work-items:scan-todos`).

Persisting the findings report and its cursor block under `${CLAUDE_PLUGIN_DATA}` is plugin-owned
state, not repository mutation. `--dry-run` persists **nothing**: no report file, no cursor advance,
no filing.

Durable cursor state never lives in `.work/`: a fresh clone or `git clean` erases it. The ladder
re-derives the cursor from rungs 1–3 and never treats a cache note there as authority.

**Cloud or scheduled runs.** `${CLAUDE_PLUGIN_DATA}` is ephemeral on a cloud session and unreachable
from the next scheduled run on another host. Pass `--track` there: a filed item is the only output
that survives, and it is what rung 1 of the cursor ladder reads back. Without `--track` such a run's
findings live only in the transcript.

## Modes

| Argument | Mode | Behavior |
|---|---|---|
| `<path>` / `<feature>` / `<diff-ish ref>` | **Targeted** | Hunt exactly that scope. No lane rotation, no cursor advance. |
| `--lane <name>` | **Named lane** | Hunt the named lane's globs. Advances the cursor to that lane. |
| *(empty)* | **Rotation** | Self-select the next lane via the cursor ladder, then hunt it. |
| `--track` | **Filing** | After reporting, file verified findings as raw intake, subject to `filing_posture` and the Step 7 ladder. Composable with any mode. |
| `--dry-run` | **Plan-and-report only** | Full hunt + verification, report to stdout, zero persistence and zero cursor advance. Composable with any mode; overrides `--track`. |

`lanes` and `filing_posture` resolve from `.claude/bugs.md`; keys, layers, and merge semantics live
only in [`${CLAUDE_PLUGIN_ROOT}/reference/config.md`](../../reference/config.md). When no layer
declares lanes, use the bundled generic default lanes in [`context/lenses.md`](context/lenses.md).

## Cursor ladder (rotation mode)

The next lane is derived **statelessly**; the first rung that answers wins:

1. **Tracker history.** When the `work-items` plugin is installed and a tracker binding resolves,
   search items (`--state all`) for the provenance line `Filed by /bugs:scan (lane: <name>)`. The
   most recently filed lane is the previous lane; take the next one in declaration order. The search
   must be an **exact match** on that line (the seam's search verb, or the provider's literal body
   match with the string quoted): a fuzzy search cannot tell "no match" from "missed". With only a
   fuzzy search, or no search run against a bound tracker, print why and fall through. An unbound
   tracker's empty result is not "no prior scan filings".
2. **Persisted-report cursor.** Resolve the report directory by the **same precedence persistence
   uses** (`/bugs:write`'s Step 4, as Step 5 does); reading a directory reports no longer land in is
   how a configured `output_dir` strands the cursor. Search **backward from the newest report** for
   the newest one carrying a valid rotation cursor block, one that names the rotation lane (see
   [`context/findings-report.md`](context/findings-report.md)), and take the next lane after it the
   same way. Skip reports without one:
   `/bugs:write`'s reports share the directory and carry none, and a targeted scan's report must
   never advance rotation. If none carries one, fall through.
3. **Date-derived floor.** Index the declared lane list by
   `(days since 1970-01-01 UTC) mod (lane count)`.

State the rung used in the report.

**Reset semantics.** Deleted reports or a fresh machine drop the run to rung 3, a valid state, not
an error. `<project-slug>` is the project root's kebab-cased basename, so two checkouts sharing a
basename (`~/work/api` and `~/oss/api`) share one cursor directory: name the absolute project root in the report. Two zero-state
sessions on the same day select the **same** lane; accept it (dedupe absorbs the duplicates) rather
than jitter it, because the deterministic floor is what makes daily coverage predictable.

## Budget

- **Stop condition:** 3 verified findings, or the lane's budget-bounded sample is complete.
- **Candidate cap:** at most 10 candidates per hunt wave reach the gate (5 on a small scope). Rank by
  evidence strength and drop the tail rather than widening the wave; the dropped tail is reported,
  never discarded.
- **Refill cap:** if a whole wave is refuted, at most **2** refill waves, then report the refuted set
  and stop. An unbounded refill loop is a token sink against a ~1:50 signal-to-noise base rate.
- **"Lane exhausted" means the sample is complete, not that the lane is bug-free.** Never claim
  exhaustive coverage.

Zero verified findings is a successful outcome: report it, advance the cursor, and do not refill
past the cap or invent a finding to justify the run.

### Sizing. Model by stage, breadth by scope, effort as the ceiling

Apply in this order.

**Model by stage.** Each stage's model comes from the multi-agent role map, passed through the
Agent tool's per-spawn `model` parameter, and the gates' effort through its `effort` parameter. Name
roles, never aliases. When `/multi-agent:route` resolves in this session, run
`/multi-agent:route all session=<this session's model alias>` once per run. Pass the role's `fanout`
variant model when the stage dispatches more than one agent and its `single` variant when it
dispatches one (a one-lens run, a one-candidate wave); omit the model when `omit_model` is true.
Hunters pass no `effort`, so they run at the session level. Gates are non-fork spawns of a generic
subagent with no pin of their own, so each gate passes its variant's `effort`. A gate never runs on a
weaker model than the hunters it checks: when its resolved model (the session's, if omitted) is
weaker, pass the hunters' model instead. A gate never runs below the session effort either: when its
resolved effort is lower, pass no `effort`.

| Stage | Role |
|---|---|
| Hunters (Step 2) | `retrieval` |
| Gates (Step 4) | `verifier` |
| Main thread | the session's model, nothing passed; orchestration and triage only |

When `/multi-agent:route` does not resolve, omit the model for both stages so they inherit the
session's, except when the session model is frontier or unknown, where pass `opus`; say once in the
report that enabling the multi-agent plugin makes this routing configurable. With no role map, gates
pass no `effort` either. Pointer: for the per-spawn
`effort` and its precedence, see <https://code.claude.com/docs/en/sub-agents#choose-an-effort-level>.
As of: 2026-10-10. Recheck trigger: that section changes precedence or which spawns honor `effort`.

Name the model and effort each stage was dispatched with in the run metadata: the level passed, or
`session` when none was. A dispatch the harness rejects means the role map names an alias this
session cannot use: report it rather than substitute one.

**Breadth by scope.** After Step 1 enumerates the files (test suites excluded), classify the scope:

| Scope | Definition (files, or lines after hotspot ranking) | Lenses | Gate cap per wave |
|---|---|---|---|
| small | 5 files or 1,000 lines or fewer | 1 to 2, the highest-ranked for the surface | 5 |
| medium | 20 files or 5,000 lines or fewer | 2 to 3 | 10 |
| large | above | 4, or 5 when the scope renders user-facing data | 10, refill waves allowed |

A targeted run over one file is small; a full lane is usually large. The scope class, lens count,
and models used go in the run metadata.

**Effort as the ceiling.** The [Effort](#effort) row bounds lenses and refill waves; scope picks
within it, never above it. A `low` run over a large lane still dispatches one lens.

### Effort

Caller effort for this run is `${CLAUDE_EFFORT}`. If that reads as a literal placeholder rather than
an effort level, the body was read directly instead of skill-loaded: treat the run as `high`.
Pointer: the substitution and the
values it can take are read at
[skills: available string substitutions](https://code.claude.com/docs/en/skills#available-string-substitutions).
As of: 2026-10-11. Recheck trigger: that section renames the variable or changes its values.

Effort scales the **recall stage only**. The gate never relaxes: every candidate faces a separate
fresh-context refuting subagent at every level, and "if uncertain, it is NOT a finding" binds at
`low` exactly as at `max`.

| Effort | Lenses dispatched (step 2) | Refill waves | Stop condition |
|---|---|---|---|
| `low` | 1, the highest-ranked lens for the scope | 0 | first verified finding |
| `medium` | 2 | 1 | 2 verified findings |
| `high`, `xhigh`, `max` | up to 5, sized to the scope per the sizing table | 2 | 3 verified findings |

The gate cap per wave holds at every level. Name the effort level and lens count in the run
metadata, so a `low` run reads as the narrower sample it is rather than as a clean lane.

## The scan pipeline

Process one unit (one target, or one lane) at a time. A unit is closed when its verified findings
are reported, deduped, and (under `--track` with `filing_posture` allowing it) filed; only then does
the cursor advance.

### Step 1. Resolve scope

Resolve the mode, lane globs, and `filing_posture` from the config cascade. Enumerate the file list
and drop test suites (`*.test.*`, `test_*`, `*.Tests.ps1`): hunters read a test to learn a unit's
contract and never hunt the test itself. Over ~40 files, narrow to the highest-signal subset
(recently changed, highest fan-in, most branch-dense) and say in the report that you sampled.
Compute the hotspot reading order in [`context/lenses.md`](context/lenses.md), one git command per
Bash call; on a shallow clone, print the skip notice and continue unranked. Classify the scope per
the [sizing table](#sizing-model-by-stage-breadth-by-scope-effort-as-the-ceiling).

**Done when** you can name the exact file list, its reading order, and the scope class.

### Step 2. Dispatch hunters (recall stage)

Dispatch **one subagent per lens** over the scope, on the hunter role, each with the four-part
contract (objective, output format, tool and source guidance, task boundaries) in
[`context/lenses.md`](context/lenses.md). The scope class picks the lens count; the [Effort](#effort)
row is the ceiling. Dispatch lens 5 only when the scope renders user-facing data (components,
templates, views, messages, reports). Every hunter is read-only, attaches a verbatim evidence quote
to every candidate, may follow one hop outside the scope (a direct caller or callee of a scoped
file) and tags such a candidate `out-of-lane`, and is told that **returning no candidate is a valid
and expected outcome**.

**Done when** every dispatched lens has returned.

### Step 3. Triage the candidate list (main thread, before any gate)

1. **Seed from the prior tail.** On a rotation or named-lane run, read the newest persisted report
   for this lane (the directory rung 2 reads) and add its "Candidates not gated" rows ahead of the
   hunters' output; at equal evidence strength they rank first. Skipping the seed re-buys what the
   last run already paid for. A row whose quoted location no longer exists goes to the side
   observations. A targeted run seeds nothing.
2. **Merge same-cause candidates.** Keep one candidate carrying both lens ids and the stronger
   evidence quote; the gate sees it once.
3. **Drop cosmetic-impact candidates.** A candidate whose stated impact is a comment, a log string,
   or a report field nothing consumes moves to the side observations, ungated.
4. **Rank by evidence strength and cut to the gate cap.** The tail above the cap goes to the
   report's "Candidates not gated" section, which item 1 reads back next run.

**Done when** the list is at or under the gate cap and every merged or dropped candidate is accounted
for in the report.

### Step 4. Verification gate (precision stage)

Dispatch a **separate fresh-context subagent per candidate**, on the gate role, with the prompt
contract in [`context/verification-gate.md`](context/verification-gate.md). The hunter that found a
candidate never grades it. The gate's default stance is **refute**: it must construct the concrete
input path that triggers the fault, or the candidate dies. **If uncertain, it is NOT a finding.**

Survivors are labeled `reproduced` (a check was actually run) or `verified-by-reading` (established
from the source, with the reproduction argument stated). Refuted candidates are **retained with
their refuting argument**: some kills are wrong, a human can overturn one, and the record stops the
same dead candidate resurfacing. A gate's one-line side observation goes to the side observations.

**Done when** every candidate carries a verdict and a label or a refuting argument.

### Step 5. Assemble and dedupe the report

Format per [`context/findings-report.md`](context/findings-report.md): the five fields per finding,
plus evidence label, lens id, and scope tag; then the refuted tail, the candidates not gated, the
side observations, and on a rotation run the cursor block with the sampled scope list (a targeted
run emits the no-cursor line instead). Before persisting, run the duplicate scan `/bugs:write`
performs over the output directory (its Step 2, "Survey before you write", in
[`${CLAUDE_PLUGIN_ROOT}/skills/write/SKILL.md`](../write/SKILL.md)), and drop or merge findings
that restate a prior report.

Persist to the path `/bugs:write --file` resolves (its Step 4 owns the precedence: `output_dir`,
then `${CLAUDE_PLUGIN_DATA}/bug-reports/<project-slug>/`, then a project-local fallback); do not
reinvent it. Write the file with the **Write tool**: a shell redirect or heredoc is what a
repository's write guards block, and the plugin data directory is outside any scratch exemption.
Under `--dry-run`, skip persistence.

**Done when** the report is emitted, and (outside `--dry-run`) persisted with its path stated.

### Step 6. `--track` filing (explicit only)

**Posture gate first.** Resolve `filing_posture` per
[`${CLAUDE_PLUGIN_ROOT}/reference/config.md`](../../reference/config.md) (bundled default
`manual-only`). On `manual-only`, file nothing: print "filing skipped: filing_posture is manual-only
(<layer, or bundled default>); report-only" and stop at the report. Only `allowed` continues.

Apply the Step 7 ladder: on an interactive run file only the findings it routes to the tracker; on
an unattended run file every verified finding. Then, presence-gated on `work-items`, invoke
`/work-items:track add`, never path into another plugin's files:

1. **Dedupe.** Search items over `--state all` first, judging sameness by underlying cause, not
   wording. An open match gets a comment instead of a second item; a closed match is reopened or
   linked from a fresh item.
2. **Categorize as raw intake.** A scan filing records what was observed, not a verified diagnosis.
3. **File** through `track add`, which owns the body template and the argv-safe write. The body
   carries the five fields and the provenance line `Filed by /bugs:scan (lane: <name>)`, which
   rung 1 of the cursor ladder recognizes.
4. **Mark `needs-triage` from the live label set** when that exact name exists. **Create no
   labels**; if it is missing, say so and file without it. The filer does not self-triage.

**Degrade:** if `work-items` is absent or no tracker binding resolves, do not improvise a filing
path. Print "filing skipped: <reason>; report-only" and stop at the report.

**Done when** each verified finding is filed, matched to an existing item, or skipped with a printed
reason.

### Step 7. Hand off through the filing ladder

The scan edits nothing. One ladder routes each verified finding, so a small fix does not become a
tracker item and an unattended run never strands work in a transcript:

| Run | Finding | Route |
|---|---|---|
| interactive | **local**: its fix stays inside one plugin or module, changes no documented contract, and has an existing test file to extend | fix it now, in this session and branch, through `/implementation:implement` (or the project's own fix lane) |
| interactive | non-local, or needs a design decision | file it with `--track`, or ask the operator |
| any | security-relevant | file it, and route to the `/review:security-review` lane, which owns that surface |
| unattended (a loop, a routine, a lane rule that passes `--track`) | any | file it; nobody is present to fix it, and the tracker is the only durable output |

"Unattended" is declared by the caller, never inferred from the environment. Recommend the route;
do not auto-invoke it. A finding worth root-causing first goes to `/debugging:debug`. With nothing
verified, say so and name the lane and rung, so the next run rotates on.

## Next

- Verified local finding, interactive run: `/implementation:implement`.
- Verified non-local or security-relevant finding: `/work-items:track add`, then
  `/review:security-review` for the security-relevant ones.
- A finding that needs root-causing before a fix: `/debugging:debug`.

## Gotchas

- **The hunter never grades itself.** Collapse Steps 2 and 4 into one agent and precision collapses
  with them: a model re-checking its own work rubber-stamps it.
- **A cheaper hunter is fine; a cheaper gate is not.** The gate's reproduction is the whole
  precision claim, so it stays on the `verifier` role whatever the hunters ran on, and no scope
  class lowers its stance.
- **Triage merges and drops; it never confirms.** Every candidate that survives triage still faces
  the gate; a candidate dropped as cosmetic is written to the side observations.
- **No evidence quote, no finding.** A candidate without a verbatim quote of the offending source is
  retracted at the gate, not "investigated further".
- **`--dry-run` must not advance the cursor.** A dry run that persists a cursor silently skips a lane
  on the next real run.
- **`--track` is not `--file`.** `--file` is `/bugs:write`'s flag for persisting a report to disk;
  the same token here would mean tracker mutation.
- **Never declare `type: review-findings` on a scan report.** That frontmatter alone routes a report
  into the `/review:fanout` fix relay; a scan report is intake.
- **Consumer gotchas extend these.** The pre-computed block holds the `## Gotchas` sections of the
  `.claude/bugs.md` layers (user-global, team, local overlay) in layer order; apply them to this
  invocation. A missing layer is absent, not an error. A generalizable line belongs in this
  shipped skill via an issue, not in the consumer file.

## Reference index. Load on demand

| File | Load when |
|---|---|
| [`context/lenses.md`](context/lenses.md) | Step 2, writing each hunter's dispatch prompt; also holds the hotspot ranking and the bundled default lanes. |
| [`context/verification-gate.md`](context/verification-gate.md) | Step 4, before dispatching the refute gate on a candidate. |
| [`context/findings-report.md`](context/findings-report.md) | Step 5, emitting the report, and rung 2 reading a prior cursor back. |
| [`${CLAUDE_PLUGIN_ROOT}/reference/config.md`](../../reference/config.md) | A `.claude/bugs.md` key decides the run (lane, rotation, filing posture) and its layer is unclear. |
| [`${CLAUDE_PLUGIN_ROOT}/skills/write/SKILL.md`](../write/SKILL.md) | Emitting a finding in the five-field shape, running the duplicate scan, or resolving where reports persist. |
