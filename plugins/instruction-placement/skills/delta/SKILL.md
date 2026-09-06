---
description: "Re-run the placement audit and report only what MOVED since the last run: new candidates, findings whose source content changed, rules whose globs stopped resolving, and index drift, above a configurable noise budget, so a repeat run costs attention proportional to what actually changed rather than re-presenting a finding set the operator already decided on. Declined findings stay declined and are never resurrected by a re-run, from this checkout or any other. Use when: 'what changed since the last placement audit', 'placement delta', 're-run the instruction-placement audit', 'anything new to move', 'did any rule glob break', 'weekly instruction-placement check', or from a scheduled lane. Read-only. Reports movement and writes nothing but the persisted placement baseline; realign still owns every change."
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
| [`../../context/findings-artifact.md`](../../context/findings-artifact.md) | Status vocabulary, re-run merge semantics, and the baseline-capture obligation — the baseline's frontmatter, its two body tables, and the four rules binding a capture |
| [`../../reference/topic-docs.md`](../../reference/topic-docs.md) | Where the baseline and the findings artifact resolve, and why only one of them carries a branch |
| [`../../context/routing-rubric.md`](../../context/routing-rubric.md) | Only when a genuinely new candidate needs classifying |

This skill does **not** restate the merge semantics, the baseline's shape, or the resolution rungs.
Those documents own them, and a second statement is a second thing to drift.

## The baseline, and why it outlives the checkout

The comparison input is the **placement baseline**: a persisted snapshot of the previous run's
detector spine plus the operator's decisions. It sits in the `baselines/` slot the lifecycle
artifact protocol names ([`../../reference/artifact-protocol.md`](../../reference/artifact-protocol.md)),
at the home the topic-docs binding resolves — one per repository, composed from the repo's own
tracked concern file and a constant slug, **with no branch segment and no checkout discriminator**.

That is the whole reason a decline holds. A path keyed to the checkout makes "I already said no" a
per-worktree fact, and the operator gets asked again from the next one. Resolve the home through the
binding; never compose a path from a machine-global key.

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

1. Resolve the home through the binding and read the stored baseline, then this branch's findings
   artifact. **Neither missing is an error.** No baseline and no artifact: say so and route to the
   full audit rather than silently running one. A baseline present with no artifact for this branch
   is a normal first run on a new branch — the declined set still applies, and it still suppresses.
   *Done when:* a baseline is in hand, or the run has stopped with the route stated.
2. Run the detector and diff its `SECTION` and `RULE` records against the baseline's spine.
   *Done when:* every current record is matched to a prior record or marked unmatched.
3. Classify each difference into one of the five shapes. Only a `new` shape needs the rubric.
   *Done when:* no difference is left unclassified. An unclassified difference is a reporting gap.
4. Re-validate every previously-valid glob; a transition to invalid is `broken-glob`.
   *Done when:* the validator has run over every `RULE` record, not only the changed ones.
5. Check index sync and reachability. *Done when:* both verdicts are recorded, since they are
   independent questions.
6. Suppress every id the baseline's decisions table already carries, then report.
   *Done when:* no id in that table appears in the report under any shape.
7. Report movement, then the suppressed count, then a one-line "nothing else moved".
   *Done when:* the report states a number for both moved and suppressed.
8. Capture the baseline over the stored one: this run's spine, plus the stored decisions merged with
   any `declined` or `applied` status this branch's findings artifact now carries. This is the only
   file the skill writes, and the run must have reached this step to earn it.
   *Done when:* the capture is written, or the run stopped early and the stored baseline is
   untouched.

## Reporting

Lead with the count of moved items and the window. When nothing moved, **say that plainly, with the
window and the suppressed count, and stop**. A delta run whose honest answer is "nothing changed"
should be short and complete, not a page of reassurance.

Never pad a quiet run by re-listing standing findings to look useful.

## Hard rules

- **Read-only on the repository.** The placement baseline is the only write, and it lives in the
  never-committed memory tier. This skill writes no status into the findings artifact. Every change
  to the repository belongs to `realign` behind its per-item gate.
- **Never resurrect a declined finding.** Not as `new`, not as `changed`, not "for review" — and not
  because this run happens to be on a different branch or in a different checkout from the one where
  the decline was recorded.
- **Never drop a decision the baseline carries.** A capture merges; it does not replace. A run that
  did not observe a declined finding has learned nothing about that decision.
- **Never suppress silently.** The suppressed count is part of the report, always.
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
- **The baseline is durable across branches and checkouts, not indestructible.** Its path carries no
  branch and no checkout discriminator, so a decline recorded anywhere in this repository holds
  everywhere the resolved `memory_dir` reaches. On the documented default that root is `.work/`
  inside the checkout, so a freshly created linked worktree starts without it unless the repository
  carries the memory root in via `.worktreeinclude`, and a deleted memory root loses it outright.
  The next run then legitimately has no baseline: that is the route-out case, not a bug.
- **A capture at the wrong moment is a silently useless lane.** Capture at the end, after the
  comparison. A capture taken before the comparison compares this run against itself and reports
  nothing forever, with no error to show for it.
- **A `changed` finding's stale line range is the dangerous part.** It is not a bookkeeping
  detail: `realign` excises by that range, so reporting `changed` without re-deriving the range
  hands the apply lane a number that points at the wrong text.
