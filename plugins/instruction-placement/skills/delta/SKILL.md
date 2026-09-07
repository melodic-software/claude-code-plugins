---
description: "Re-run the placement audit and report only what MOVED since the last run: new candidates, findings whose source content changed, rules whose globs stopped resolving, and index drift, above a configurable noise budget, so a repeat run costs attention proportional to what actually changed rather than re-presenting a finding set the operator already decided on. Declined findings stay declined and are never resurrected by a re-run, from this checkout or any other. Use when: 'what changed since the last placement audit', 'placement delta', 're-run the instruction-placement audit', 'anything new to move', 'did any rule glob break', 'weekly instruction-placement check', or from a scheduled lane. Read-only. Reports movement and writes nothing but memory-tier records (the refreshed findings artifact and its own spine baseline), never the tracked suppression surface; realign still owns every change."
argument-hint: "[--since <ISO date>] [--noise-budget <n>]. Default: since the artifact's last run"
user-invocable: true
disable-model-invocation: false
allowed-tools:
  [
    "Bash(${CLAUDE_PLUGIN_ROOT}/scripts/precompute.sh:*)",
    "Bash(${CLAUDE_PLUGIN_ROOT}/scripts/detect.sh:*)",
    "Bash(${CLAUDE_PLUGIN_ROOT}/scripts/glob-tools.sh:*)",
    "Bash(${CLAUDE_PLUGIN_ROOT}/scripts/render-index.sh:*)",
    "Read",
    "Grep",
    "Glob",
    "Write",
  ]
shell: bash
metadata:
  workflow-stage: anytime
  summary: Report only what moved since the last placement audit
---

## Pre-computed context

!`"${CLAUDE_PLUGIN_ROOT}/scripts/precompute.sh" audit 2>/dev/null || echo "- Orientation unavailable"`

## Purpose

A full audit is worth running rarely and reading carefully. This is the lane for the other times: it
answers **what moved**, so a repeat run costs attention proportional to actual change.

The failure it prevents is specific. An audit re-run that re-presents the same forty findings the
operator already worked through trains them to skim, and a skimmed report is how a bad migration
gets approved. Reporting only movement keeps the signal survivable on a cadence.

## Read these first

| Read | For |
|---|---|
| [`../../context/findings-artifact.md`](../../context/findings-artifact.md) | Status vocabulary, re-run merge semantics, the baseline-capture obligation, and the finding-id constituents a suppression entry is keyed by |
| [`../../reference/topic-docs.md`](../../reference/topic-docs.md) | Where the spine baseline and the findings artifact resolve, and what survives what |
| [`../../reference/consumer-config.md`](../../reference/consumer-config.md) | The suppression surface: its layers, its per-key merge, the policy-floor inversion, and the report obligations |
| [`../../context/routing-rubric.md`](../../context/routing-rubric.md) | Only when a genuinely new candidate needs classifying |

This skill does **not** restate the merge semantics, the baseline's shape, the suppression entry
format, or the resolution rungs. Those documents own them; a second statement is a second drift.

## Two inputs, two homes, and the reason they are different files

**The spine baseline** is the comparison input: a snapshot of the previous run's detector spine, in
the `baselines/` slot the lifecycle artifact protocol names
([`../../reference/artifact-protocol.md`](../../reference/artifact-protocol.md)), branch-keyed, at
the home the topic-docs binding resolves. Memory tier and checkout-local, which is right for it: a
spine is recomputed next run, and one from another checkout describes a tree this one lacks.

**The suppression surface** is where an operator's decline lives: the tracked
`.claude/instruction-placement.md`, resolved across the three cascade layers. It is tracked because
that is the only mechanism that crosses checkouts: git moves the file, and the topic-docs contract
refuses to carry a baseline into a worktree at all. Read it, honor every entry it merges to, and
**never write it**: `realign` owns that write, behind its per-item gate.

A decline in the baseline would be a per-checkout fact, and the operator gets asked again from the
next worktree. That is the bug this lane exists downstream of.

## What counts as movement

Five shapes, in report order. Everything else is suppressed.

| Shape | Trigger | Why it matters |
|---|---|---|
| `new` | A candidate with no prior finding | The only shape that needs fresh classification |
| `changed` | A finding whose source content changed since the last run | Its line range is stale; `realign` would excise the wrong text |
| `broken-glob` | A rule glob the baseline recorded `valid` that does not resolve now | The rule stopped firing, silently, and nobody was told. A transition, so it needs the stored verdict |
| `index-drift` | The index no longer matches the rules on disk | Deferred surfaces became unreachable from subagents |
| `stale` | A finding whose source no longer exists | The content was moved or deleted outside this plugin |

`broken-glob` is the shape that most justifies a cadence: a glob breaks when the code it described
is renamed, an ordinary refactor nowhere near the rules tree, with no signal at the time and nothing
else noticing between `check` runs.

## What is deliberately NOT movement

- **A finding the operator already decided on.** `declined` stays declined and is never re-proposed;
  `applied` is not re-reported as new. Resurrecting a decision is how an operator learns to stop
  reading.
- **Content edited without changing its meaning for placement.** A reworded sentence in a section
  whose scope and class are unchanged is not movement. Compare what the classification depends on,
  not the bytes.
- **Findings below the noise budget.** Default: suppress `new` findings whose confidence is low
  *and* whose released line count is trivial, and report the count. A delta that hides its own
  filtering is the thing it was built to avoid.

## Workflow

Each step names what "done" looks like, so a partial run is visible rather than assumed complete.

1. Resolve the home through the binding, read this branch's spine baseline and findings artifact,
   and resolve the suppression surface across its three layers; a missing surface is the ordinary
   no-suppressions state. All four baseline/artifact combinations resolve explicitly, none an error:

   | Baseline | Artifact | Disposition |
   |---|---|---|
   | present | present | The ordinary cycle. Compare against the stored spine. |
   | present | absent | A `realign` or a cleanup removed the artifact. Compare against the spine, and say the report carries no statuses this cycle. |
   | **absent** | **present** | **Bootstrap.** The commonest shape after a first `audit`, and after any first run in a fresh worktree. Run the detector and **capture its output as this cycle's baseline**; report only what the artifact can settle, and say the cycle is a bootstrap. |
   | absent | absent | Say so and route to the full audit rather than silently running one. |

   **A bootstrap does not build its spine out of the artifact.** The artifact holds classified
   candidates and held-back records, not every `SECTION` and `RULE` the detector emits, so a spine
   derived from it is partial and the *next* cycle reports every record it never carried as `new`.
   The detector's output is the only complete spine, so a bootstrap captures that. It reports only
   what the artifact can settle: `changed` and `stale` over the findings it carries. It reports no
   `new` (with no prior spine every record is unmatched, and a candidate audit considered and
   rejected is indistinguishable from one that appeared since) and no `broken-glob` (that class is
   a transition from a stored `valid` verdict, and the artifact records a proposed glob for a
   candidate, never a prior verdict for an existing rule).

   **Say the cost out loud, because this is the one cycle that can absorb a finding unreported.** A
   candidate that arose between the `audit` and this bootstrap enters the captured spine without
   ever being reported, and no later cycle sees it as movement. That is the one sanctioned exception
   to the hard rule below, and it is bounded by the artifact's age: name that age in the report, and
   where the artifact is old enough that the tree has moved on, **route to a full `audit` instead of
   bootstrapping**. A stale bootstrap trades a silent loss for a saved sweep, which is the wrong way
   round.

   A fresh worktree legitimately has no baseline, and in every row it still honors every entry the
   suppression surface carries.
   *Done when:* the row is named in the report, and the merged suppression set is resolved with each
   entry's contributing layer.
2. Run the detector and diff its `SECTION` and `RULE` records against the baseline's spine. *Done
   when:* every current record is matched to a prior record or marked unmatched.
3. Classify each difference into one of the five shapes. Only a `new` shape needs the rubric.
   *Done when:* no difference is left unclassified. An unclassified difference is a reporting gap.
4. Re-validate **every** glob, not only the previously-valid ones, and compare each result against
   the verdict the baseline's `RULE` row stored. `valid` to invalid is `broken-glob`; invalid to
   invalid is still-broken and counts as suppressed, not as movement.
   *Done when:* the validator has run over every `RULE` record, and each carries both its stored
   verdict and this run's.
5. Check index sync and reachability. *Done when:* both verdicts are recorded, since they are
   independent questions.
6. Derive each surviving finding's `finding_id` and suppress every one the merged surface carries;
   also suppress what this branch's artifact records as `declined` or `applied`.
   *Done when:* no suppressed id appears in the report under any shape, and every entry that did
   **not** suppress (personal-only, malformed, or not evaluated this run) is listed with its
   layer.
7. Report movement, then the suppressed count and the suppression section, then a one-line "nothing
   else moved". *Done when:* the report states a number for both moved and suppressed.
8. **Merge what this run discovered into this branch's findings artifact, per its re-run merge
   semantics, before step 9, always.** A `new` finding and a re-derived `changed` line range are
   the run's only durable output for `realign`, which reads the artifact and never the spine. Skip
   this and the discovery is lost twice over: `realign` has nothing to act on, and the next cycle's
   spine already contains the record, so it is no longer movement and is never reported again.
   Statuses stay the operator's: write records, never a `Status`, with the one exception the
   artifact contract fixes: an `accepted` finding whose source changed resets to `pending`, since
   an acceptance is scoped to the text the operator read and `realign` excises by range. A finding
   the suppression surface covers is not merged in as `pending`.
   *Done when:* every reported `new` finding exists in the artifact as `pending` with its
   `Suppression key`, every `changed` finding's line range is the one this run derived, and no
   `changed` finding is left `accepted`.
9. Capture this run's spine over the stored baseline. The run must have reached this step to earn
   the capture; the slice scaffolding the binding requires (the memory root's `.gitignore`, the
   slice `INDEX.md`, the branch home and its `baselines/` directory) is created by the same first
   memory-tier write when absent.
   *Done when:* the capture is written, or the run stopped early and the stored baseline is
   untouched.

## Reporting

Lead with the count of moved items and the window. When nothing moved, **say that plainly, with the
window and the suppressed count, and stop**. A delta run whose honest answer is "nothing changed"
should be short and complete, not a page of reassurance.

Never pad a quiet run by re-listing standing findings to look useful.

## Hard rules

- **Read-only on the repository.** Every write is memory tier and never committed: the refreshed
  findings artifact, the spine baseline, and the slice scaffolding the binding requires. It writes
  **records, never a `Status`** (bar the one reset the artifact contract fixes), and **never writes
  the suppression surface**, a tracked file `realign` owns behind the per-item gate. Every change to
  the repository belongs to `realign`.
- **Never resurrect a declined finding.** Not as `new`, not as `changed`, not "for review", and not
  because this run is on a different branch or in a different checkout from the one where the
  decline was recorded. The surface makes that possible; honoring it is not optional.
- **Never suppress silently.** The suppressed count and the suppression section are part of the
  report, always, including every entry that did not suppress and why.
- **Never re-classify an unchanged finding.** If its source content did not change, its
  classification stands. Re-deriving it invites drift between runs for no new information.
- **Only the both-absent row routes out.** With either the baseline or the artifact in hand there is
  a comparison to make, since an artifact alone bootstraps. With neither there is nothing to report
  movement against, and this skill is not a full audit wearing a different name.
- **Never advance the baseline past an unrecorded discovery.** The merge happens first, every cycle.
  Capturing the spine first leaves a baseline that says the finding is old while no artifact record
  says it exists. Nothing errors, and the finding is gone from both sides. The bootstrap row is the
  one sanctioned exception, and it is required to say so in its report.

## Gotchas

- **A quiet run is the expected outcome, not a failed one.** The pull toward finding *something* to
  justify the run is exactly what makes a cadence lane useless. A short answer that states the
  window and the suppressed count is the whole report.
- **"Nothing touched the rules folder" does not make glob re-validation unnecessary.** Globs break
  from refactors elsewhere. Skipping validation on that reasoning misses the single shape that most
  justifies the cadence.
- **The baseline is disposable and the suppression surface is not; do not confuse their jobs.** The
  baseline is memory tier, branch-keyed, and invisible from any other checkout; a fresh worktree
  legitimately has none, and with an artifact present that is the bootstrap row rather than a bug.
  A decline on the tracked surface is still in force in that worktree, because git carried the file.
  Reporting a suppressed finding as new because the baseline was absent is the failure this split
  exists to prevent.
- **A capture at the wrong moment is a silently useless lane.** Capture at the end, after the
  comparison. Capturing first compares this run against itself and reports nothing forever, with no
  error to show for it.
- **A `changed` finding's stale line range is the dangerous part.** It is not a bookkeeping
  detail: `realign` excises by that range, so reporting `changed` without re-deriving the range
  hands the apply lane a number that points at the wrong text.
