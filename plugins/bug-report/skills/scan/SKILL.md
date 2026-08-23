---
description: "Proactively hunt unobserved bugs in resting code: a read-only two-stage scan — recall-biased per-lens hunter subagents, then a separate fresh-context default-refute gate — over a target path/feature/diff or a rotated lane, emitting only verified 5-field findings. Use when: 'find a bug', 'bug hunt', 'scan for bugs', 'hunt for bugs in <X>'. Skip when: reviewing a diff (`review:code-review`); security auditing (`review:security-review`); root-causing an observed failure (`debugging:debug`); doc/config/code/arch claim drift, all dimensions (`codebase-health:audit`); structural tidying (`code-tidying:tidy`); comment markers (`work-items:scan-todos`); coverage gaps (`testing:audit`, `mutation-testing:audit`). Disambiguation: 'scan repo for issues' is the upstream known-issue registry (`claude-ops:known-issues`); 'file a bug' you already observed is `bug-report:write`. Bare invocation neither edits nor files; `--track` files verified findings as raw intake."
argument-hint: "[<path|feature|diff>] [--lane <name>] [--track] [--dry-run]"
user-invocable: true
disable-model-invocation: false
shell: bash
metadata:
  workflow-stage: operator
  summary: Proactively hunt resting code for unobserved bugs, verify adversarially, report read-only
  cadence: daily
---

## Pre-computed context

Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`
Recent commits: !`git log --oneline -10 2>/dev/null || echo "no history (shallow or fresh clone)"`
Shallow clone: !`git rev-parse --is-shallow-repository 2>/dev/null || echo "unknown"`
Lane config: !`ls "${CLAUDE_PROJECT_DIR:-.}/.claude/bug-report.md" 2>/dev/null || echo "absent — bundled default lanes apply"`

## Variables

Arguments: `$ARGUMENTS`

## Purpose

`/bug-report:scan` is the front of the bug lifecycle: it hunts defects **nobody has observed yet**, in
code that is resting. Every other finding-producer in reach needs an oracle first — a diff, a failing
test, a stack trace, a factual claim, a comment marker. This one needs none of them.

One invocation is **one bounded pass**: hunt a target (or a rotated lane), verify each candidate
through a separate fresh-context gate, report what survives in the plugin's five-field shape, stop.
That makes it equally usable interactively ("find a bug in the billing module"), from a `/loop`, or as
a daily operator routine — the same bounded unit either way.

The design premise, taken from published practice: per-run recall is low and the raw false-positive
rate is high, so **recall and precision are separated into two stages**. Hunters are told to be
generous; the verification gate is told to refute. A finding that reaches the report survived an agent
whose job was to kill it.

## Verb contract — read-only toward the repository

Bare invocation is **read-only**: it never edits code, never branches, never pushes, never files a
tracker item. Filing sits behind `--track`, and model auto-invocation never supplies `--track` on its
own — a user (or a standing lane rule) must ask for it.

**Reconciliation:** persisting the findings report and its cursor block under `${CLAUDE_PLUGIN_DATA}`
is plugin-owned state, not target-repo mutation. The scanned repository's working tree, index, and
history are untouched by a bare run. `--dry-run` goes further: it emits the findings to stdout and
persists **nothing** — no report file, no cursor advance, no filing.

Durable cursor state never lives in `.work/`. Anything a wrapping session leaves under `.work/` is a
checkout-local cache that a fresh clone or a `git clean` erases; the ladder below must re-derive the
cursor from rungs 1–3 without it, and never treats a cache note as authority.

## Modes

| Argument | Mode | Behavior |
|---|---|---|
| `<path>` / `<feature>` / `<diff-ish ref>` | **Targeted** | Hunt exactly that scope. No lane rotation, no cursor advance. |
| `--lane <name>` | **Named lane** | Hunt the named lane's globs. Advances the cursor to that lane. |
| *(empty)* | **Rotation** | Self-select the next lane via the cursor ladder, then hunt it. |
| `--track` | **Filing** | After reporting, file verified findings as raw intake (see below), subject to the team's `filing_posture`. Composable with any mode. |
| `--dry-run` | **Plan-and-report only** | Full hunt + verification, report to stdout, zero persistence and zero cursor advance. Composable with any mode; overrides `--track`. |

Lane definitions (`lanes`, `filing_posture`) resolve from `.claude/bug-report.md` per the cascade
contract — keys, layers, and merge semantics live in
[`${CLAUDE_PLUGIN_ROOT}/reference/config.md`](../../reference/config.md), which is their single home.
When no layer declares lanes, use the bundled generic default lanes in
[`context/lenses.md`](context/lenses.md).

## Cursor ladder (rotation mode)

Which lane comes next is derived **statelessly**, first rung that answers wins:

1. **Tracker history.** When the `work-items` plugin is installed and a tracker binding resolves,
   search items (`--state all`) for the provenance line `Filed by /bug-report:scan (lane: <name>)`.
   The most recently filed lane is the previous lane; take the next one in declaration order. Confirm
   the search actually ran against a bound tracker before trusting an empty result — an unbound
   tracker returns nothing, which is not the same answer as "no prior scan filings".
2. **Persisted-report cursor.** Otherwise resolve the report directory by the **same precedence
   persistence uses** — Step 4 below defers to `/bug-report:write`'s Step 4, and so does this rung;
   reading a directory reports no longer land in is how a configured `output_dir` silently strands the
   cursor. Then search **backward from the newest report** for the newest one carrying a *valid*
   rotation cursor block — one that names the rotation lane (see
   [`context/findings-report.md`](context/findings-report.md)) — and use it the same way. Reports
   without such a block are skipped, not read as a cursor: `/bug-report:write`'s reports share that
   directory and carry none, and a targeted scan's report must never advance rotation. If no report
   carries one, fall through to rung 3.
3. **Date-derived floor.** Otherwise pick deterministically: index the declared lane list by
   `(days since 1970-01-01 UTC) mod (lane count)`. Zero state, no history, still rotates daily.

State the rung you used in the report — an operator reading a rotation run should be able to tell
tracker-derived rotation from the zero-state floor.

**Reset semantics.** Deleting the plugin-data reports (or scanning from a fresh machine) drops the run
to rung 3, which is a valid state, not an error. `<project-slug>` is the kebab-cased basename of the
project root, so two checkouts sharing a basename (`~/work/api` and `~/oss/api`) share one cursor
directory — name the absolute project root in the report so a reader can spot the collision. Two
sessions started the same day on a zero-state checkout will select the **same** lane; that is accepted
for V1 (the dedupe steps below absorb the duplicate findings) rather than jittered, because a
deterministic floor is what makes daily coverage predictable.

## Budget

- **Stop condition:** 3 verified findings, or the lane's budget-bounded sample is complete.
- **Candidate cap:** at most 10 candidates per hunt wave reach the verification gate. Rank by
  evidence strength and drop the tail rather than widening the wave.
- **Refill cap:** if a whole wave is refuted, at most **2** refill waves. Then report the refuted set
  and stop — an unbounded refill loop is a token sink against a ~1:50 signal-to-noise base rate.
- **"Lane exhausted" means the sample is complete, not that the lane is bug-free.** V1 is
  budget-bounded sampling; never claim exhaustive coverage of a lane in the report.

Zero verified findings is a clean, successful outcome. Do **not** invent a finding to justify the run.

## The scan pipeline

Process one unit at a time — one target, or one lane. A unit is closed when its verified findings are
reported and deduped (and filed, under `--track`); only then does the cursor advance.

### Step 1 — Resolve scope

Resolve the mode, the lane globs, and `filing_posture` from the config cascade. Enumerate the concrete
file list. If the enumeration exceeds ~40 files, narrow to the highest-signal subset (recently
changed, highest fan-in, most branch-dense) and say in the report that you sampled.

**Done when** you can name the exact file list the hunters will read.

### Step 2 — Dispatch hunters (recall stage)

Dispatch **one subagent per lens** over the resolved scope, each with the four-part contract —
objective, output format, tool/source guidance, task boundaries — spelled out in
[`context/lenses.md`](context/lenses.md). Size the fan-out to the surface: a single small file may
warrant one or two lenses; a full lane warrants all five. Every hunter is read-only, must attach a
verbatim evidence quote to every candidate, and is explicitly told that **returning no candidate is a
valid and expected outcome**.

**Done when** every dispatched lens has returned, and the merged candidate list is capped at 10.

### Step 3 — Verification gate (precision stage)

Dispatch a **separate fresh-context subagent per candidate** using the prompt contract in
[`context/verification-gate.md`](context/verification-gate.md). The hunter that found a candidate
never grades it — a model re-checking its own work rubber-stamps it. The gate's default stance is
**refute**: it must try to construct the concrete input path that triggers the claimed fault, and if it
cannot, the candidate dies. **If uncertain, it is NOT a finding.**

Survivors are labeled `reproduced` (a check was actually run) or `verified-by-reading` (the fault is
established from the source, with the reproduction argument stated). Refuted candidates are **retained
with their refuting argument** — a high-kill gate catches some true positives, so they are never
silently dropped.

**Done when** every candidate carries a verdict and a label or a refuting argument.

### Step 4 — Assemble and dedupe the report

Format per [`context/findings-report.md`](context/findings-report.md): the five fields per finding
(from `/bug-report:write`'s shape), plus the evidence label and lens id, then the refuted tail and the
cursor metadata block. Before persisting, run the same duplicate scan `/bug-report:write` performs
over the output directory — see Step 2 ("Survey before you write") in
[`${CLAUDE_PLUGIN_ROOT}/skills/write/SKILL.md`](../write/SKILL.md) — and drop or merge findings that
restate a prior report.

Persist to the path `/bug-report:write --file` resolves (its Step 4 owns that precedence:
`output_dir`, then `${CLAUDE_PLUGIN_DATA}/bug-reports/<project-slug>/`, then a project-local
fallback). Do not reinvent either mechanism here. Under `--dry-run`, skip persistence entirely.

**Done when** the report is emitted, and (outside `--dry-run`) persisted with its path stated.

### Step 5 — `--track` filing (explicit only)

**Posture gate first.** Resolve `filing_posture` from the config cascade — see
[`${CLAUDE_PLUGIN_ROOT}/reference/config.md`](../../reference/config.md), whose bundled default is
`manual-only` when no layer declares it. When it resolves to `manual-only`, file nothing: print one
notice — "filing skipped: filing_posture is manual-only (<layer, or bundled default>); report-only" —
and stop at the report, the same degrade shape as an absent `work-items`. Only `allowed` reaches the
beats below.

Then presence-gated on `work-items`. Follow the dogfood-filing beats by invoking
`/work-items:track add` — never by pathing into another plugin's files:

1. **Dedupe.** Search items over `--state all` first; sameness is judged by underlying cause, not
   wording. An open match gets a comment instead of a second item; a closed match is reopened or
   linked from a fresh item.
2. **Categorize as raw intake.** A scan filing records what was observed, not a verified diagnosis.
3. **File** through `track add`, which owns the body template and the argv-safe write. The body
   carries the five fields, and a provenance line — `Filed by /bug-report:scan (lane: <name>)` — which
   is what rung 1 of the cursor ladder later recognizes.
4. **Mark `needs-triage` on the right axis, resolved from the live label set.** Priority axis: pass
   `--priority needs-triage` on the `track add` call, replacing the filing floor (never two
   `priority:` labels). Status axis: apply the status marker as a separate label after creation.
   **Create no labels** — if the marker does not exist in the live set, say so and file without it.
   The filer does not self-triage.

**Degrade:** if `work-items` is absent, or no tracker binding resolves, do not improvise a filing path.
Print one notice — "filing skipped: <reason>; report-only" — and stop at the report.

**Done when** each verified finding is filed, matched to an existing item, or explicitly skipped with a
printed reason.

### Step 6 — Hand off

Recommend, do not auto-invoke:

- A verified finding worth root-causing or fixing → `/debugging:debug`.
- A finding tagged security-relevant → the `/review:security-review` lane, which owns that surface.
- Nothing verified → say so plainly and name the lane and rung, so the next run rotates on.

## What this skill does NOT do

- **Does not fix anything.** No edits, no patches, no PRs — even for an obviously trivial defect.
- **Does not file on bare invocation.** Filing needs `--track`.
- **Does not review a diff.** That is `/review:code-review`'s lane; this reads resting code.
- **Does not verify factual claims** in docs or config against code — all four `codebase-health:audit`
  dimensions own that.
- **Does not chase coverage gaps** (`testing:audit`, `mutation-testing:audit`), structural drift
  (`code-tidying:tidy`), or comment markers (`work-items:scan-todos`).
- **Does not emit `type: review-findings` frontmatter.** That frontmatter alone routes a report into
  the `/review:fanout` fix relay; a scan report is intake, not a detector-findings artifact.

## Gotchas

- **The hunter never grades itself.** If you collapse Steps 2 and 3 into one agent, precision collapses
  with them. The gate is a separate fresh-context dispatch, per candidate.
- **No evidence quote, no finding.** A candidate without a verbatim quote of the offending source is
  retracted at the gate, not "investigated further".
- **Refuted is reported, not deleted.** The refuted tail is a feature: it lets a human overturn a
  wrong kill, and it stops the same dead candidate resurfacing next run.
- **`--dry-run` must not advance the cursor.** A dry run that persists a cursor silently skips a lane
  on the next real run.
- **`--track` is not `--file`.** `--file` is `/bug-report:write`'s flag for persisting a report to
  disk; the same token here would mean tracker mutation. This skill uses `--track` for filing.
- **Shallow clones degrade, they do not fail.** The git-hotspot lens skips with a printed notice when
  history is absent; the other four lenses are unaffected.
- **A lane with no verified findings is a result.** Report it, advance the cursor, do not refill past
  the cap looking for something to say.

## Cross-references

- [`context/lenses.md`](context/lenses.md) — the five hunter lens contracts, the evidence-quote and
  no-candidate rules, and the bundled generic default lanes
- [`context/verification-gate.md`](context/verification-gate.md) — the default-refute gate prompt and
  the retained-refuted output contract
- [`context/findings-report.md`](context/findings-report.md) — report format, evidence labels, refuted
  tail, cursor metadata block
- [`${CLAUDE_PLUGIN_ROOT}/reference/config.md`](../../reference/config.md) — `.claude/bug-report.md`
  keys, layers, and merge semantics
- [`${CLAUDE_PLUGIN_ROOT}/skills/write/SKILL.md`](../write/SKILL.md) — the five-field report shape, the
  duplicate scan, and the persistence path precedence this skill reuses
