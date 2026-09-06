---
description: "Re-run the placement audit and report only what MOVED since the last run: new candidates, findings whose source content changed, rules whose globs stopped resolving, and index drift, above a configurable noise budget, so a repeat run costs attention proportional to what actually changed rather than re-presenting a finding set the operator already decided on. Declined findings stay declined and are never resurrected by a re-run, from this checkout or any other. Use when: 'what changed since the last placement audit', 'placement delta', 're-run the instruction-placement audit', 'anything new to move', 'did any rule glob break', 'weekly instruction-placement check', or from a scheduled lane. Read-only. Reports movement and writes nothing but its own memory-tier spine baseline, never the tracked suppression surface; realign still owns every change."
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

The failure it exists to prevent is a specific one. An audit re-run that re-presents the same forty
findings the operator already worked through trains them to skim, and a skimmed report is how a bad
migration gets approved. Reporting only movement keeps the signal-to-noise ratio survivable on a
cadence.

## Read these first

| Read | For |
|---|---|
| [`../../context/findings-artifact.md`](../../context/findings-artifact.md) | Status vocabulary, re-run merge semantics, the baseline-capture obligation, and the finding-id constituents a suppression entry is keyed by |
| [`../../reference/topic-docs.md`](../../reference/topic-docs.md) | Where the spine baseline and the findings artifact resolve, and what survives what |
| [`../../reference/consumer-config.md`](../../reference/consumer-config.md) | The suppression surface: its layers, its per-key merge, the policy-floor inversion, and the report obligations |
| [`../../context/routing-rubric.md`](../../context/routing-rubric.md) | Only when a genuinely new candidate needs classifying |

This skill does **not** restate the merge semantics, the baseline's shape, the suppression entry
format, or the resolution rungs. Those documents own them, and a second statement is a second thing
to drift.

## Two inputs, two homes, and the reason they are different files

**The spine baseline** is the comparison input: a snapshot of the previous run's detector spine, in
the `baselines/` slot the lifecycle artifact protocol names
([`../../reference/artifact-protocol.md`](../../reference/artifact-protocol.md)), branch-keyed, at
the home the topic-docs binding resolves. It is memory tier and checkout-local, which is right for
it: a spine is recomputed by the next run, and one from another checkout would describe a tree this
one does not have.

**The suppression surface** is where an operator's decline lives: the tracked
`.claude/instruction-placement.md`, resolved across the three cascade layers. It is tracked because
that is the only mechanism that crosses checkouts — git moves the file, and the topic-docs contract
refuses to carry a baseline into a worktree at all. Read it, honor every entry it merges to, and
**never write it**: `realign` owns that write, behind its per-item gate.

Putting a decline in the baseline instead would make "I already said no" a per-checkout fact, and
the operator gets asked again from the next worktree. That is the bug this lane exists downstream
of, not a shape to reproduce.

## What counts as movement

Five shapes, in report order. Everything else is suppressed.

| Shape | Trigger | Why it matters |
|---|---|---|
| `new` | A candidate with no prior finding | The only shape that needs fresh classification |
| `changed` | A finding whose source content changed since the last run | Its line range is stale; `realign` would excise the wrong text |
| `broken-glob` | A rule glob that resolved before and does not now | The rule stopped firing, silently, and nobody was told |
| `index-drift` | The index no longer matches the rules on disk | Deferred surfaces became unreachable from subagents |
| `stale` | A finding whose source no longer exists | The content was moved or deleted outside this plugin |

`broken-glob` is the shape that most justifies running this on a cadence. A glob breaks when the
code it described gets renamed or moved, an ordinary refactor, nowhere near the rules tree, with no
signal at the time. Nothing else in the plugin notices between `check` runs.

## What is deliberately NOT movement

- **A finding the operator already decided on.** `declined` stays declined and is never re-proposed
  by a re-run; `applied` is not re-reported as new. Resurrecting a decision is how an operator
  learns to stop reading.
- **Content edited without changing its meaning for placement.** A reworded sentence inside a
  section whose scope and class are unchanged is not movement. Compare what the classification
  depends on, not the bytes.
- **Findings below the noise budget.** Default: suppress `new` findings whose confidence is low
  *and* whose released line count is trivial. Report the count of what was suppressed. A delta that
  hides its own filtering is the thing it was built to avoid.

## Workflow

Each step names what "done" looks like, so a partial run is visible rather than assumed complete.

1. Resolve the home through the binding, read this branch's spine baseline and findings artifact,
   and resolve the suppression surface across its three layers. **A missing baseline or artifact is
   not an error**; a missing suppression surface is the ordinary no-suppressions state. With neither
   baseline nor artifact, say so and route to the full audit rather than silently running one. A
   fresh worktree legitimately has no baseline and still honors every entry the surface carries.
   *Done when:* a baseline is in hand or the run has stopped with the route stated, and the merged
   suppression set is resolved with each entry's contributing layer.
2. Run the detector and diff its `SECTION` and `RULE` records against the baseline's spine.
   *Done when:* every current record is matched to a prior record or marked unmatched.
3. Classify each difference into one of the five shapes. Only a `new` shape needs the rubric.
   *Done when:* no difference is left unclassified. An unclassified difference is a reporting gap.
4. Re-validate every previously-valid glob; a transition to invalid is `broken-glob`.
   *Done when:* the validator has run over every `RULE` record, not only the changed ones.
5. Check index sync and reachability. *Done when:* both verdicts are recorded, since they are
   independent questions.
6. Derive each surviving finding's `finding_id` and suppress every one the merged surface carries;
   also suppress what this branch's artifact records as `declined` or `applied`.
   *Done when:* no suppressed id appears in the report under any shape, and every entry that did
   **not** suppress — personal-only, malformed, or not evaluated this run — is listed with its
   layer.
7. Report movement, then the suppressed count and the suppression section, then a one-line "nothing
   else moved". *Done when:* the report states a number for both moved and suppressed.
8. Capture this run's spine over the stored baseline. That capture is the skill's only *artifact*
   write and the run must have reached this step to earn it; the slice scaffolding the binding
   requires — the memory root's `.gitignore`, the slice `INDEX.md`, the branch home and its
   `baselines/` directory — is created by the same first memory-tier write when absent.
   *Done when:* the capture is written, or the run stopped early and the stored baseline is
   untouched.

## Reporting

Lead with the count of moved items and the window. When nothing moved, **say that plainly, with the
window and the suppressed count, and stop**. A delta run whose honest answer is "nothing changed"
should be short and complete, not a page of reassurance.

Never pad a quiet run by re-listing standing findings to look useful.

## Hard rules

- **Read-only on the repository.** Every write this skill makes is memory tier and never committed:
  the spine baseline plus the slice scaffolding the binding requires. It writes no status into the
  findings artifact and **never writes the suppression surface** — that is a tracked file, and
  `realign` owns it behind the per-item gate. Every change to the repository belongs to `realign`.
- **Never resurrect a declined finding.** Not as `new`, not as `changed`, not "for review" — and not
  because this run happens to be on a different branch or in a different checkout from the one where
  the decline was recorded. The surface is what makes that possible; honoring it is not optional.
- **Never suppress silently.** The suppressed count and the suppression section are part of the
  report, always — including every entry that did not suppress and why.
- **Never re-classify an unchanged finding.** If its source content did not change, its
  classification stands. Re-deriving it invites drift between runs for no new information.
- **A missing prior artifact routes out.** This skill reports movement; it is not a full audit
  wearing a different name.

## Gotchas

- **A quiet run is the expected outcome, not a failed one.** The pull toward finding *something* to
  justify the run is exactly what makes a cadence lane useless. A short answer that states the
  window and the suppressed count is the whole report.
- **"Nothing touched the rules folder" does not make glob re-validation unnecessary.** Globs break
  from refactors elsewhere. Skipping validation on that reasoning misses the single shape that most
  justifies the cadence.
- **Byte-level diffing over-reports.** A reworded sentence in a section whose scope and class are
  unchanged is not movement. Compare what the classification actually depends on.
- **The baseline is disposable and the suppression surface is not — do not confuse their jobs.** The
  baseline is memory tier, branch-keyed, and invisible from any other checkout; a fresh worktree
  legitimately has none, and that is the route-out case rather than a bug. A decline recorded on the
  tracked surface is still in force in that same worktree, because git carried the file. Reporting a
  suppressed finding as new because the baseline was absent is the failure this split exists to
  prevent.
- **A capture at the wrong moment is a silently useless lane.** Capture at the end, after the
  comparison. A capture taken before the comparison compares this run against itself and reports
  nothing forever, with no error to show for it.
- **A `changed` finding's stale line range is the dangerous part.** It is not a bookkeeping
  detail: `realign` excises by that range, so reporting `changed` without re-deriving the range
  hands the apply lane a number that points at the wrong text.
