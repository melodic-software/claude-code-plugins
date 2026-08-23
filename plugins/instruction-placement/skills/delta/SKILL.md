---
description: "Re-run the placement audit and report only what MOVED since the last run — new candidates, findings whose source content changed, rules whose globs stopped resolving, and index drift — above a configurable noise budget, so a repeat run costs attention proportional to what actually changed rather than re-presenting a finding set the operator already decided on. Declined findings stay declined and are never resurrected by a re-run. Use when: 'what changed since the last placement audit', 'placement delta', 're-run the instruction-placement audit', 'anything new to move', 'did any rule glob break', 'weekly instruction-placement check', or from a scheduled lane. Read-only — reports movement and writes nothing but the refreshed findings artifact; realign still owns every change."
argument-hint: "[--since <ISO date>] [--noise-budget <n>] — default: since the artifact's last run"
user-invocable: true
disable-model-invocation: false
allowed-tools:
  [
    "Bash(${CLAUDE_PLUGIN_ROOT}/scripts/precompute.sh:*)",
    "Bash(${CLAUDE_PLUGIN_ROOT}/scripts/detect.sh:*)",
    "Bash(${CLAUDE_PLUGIN_ROOT}/scripts/glob-tools.sh:*)",
    "Bash(${CLAUDE_PLUGIN_ROOT}/scripts/render-index.sh:*)",
    "Bash(${CLAUDE_PLUGIN_ROOT}/lib/state-key.sh:*)",
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
| [`../../context/findings-artifact.md`](../../context/findings-artifact.md) | Status vocabulary, re-run merge semantics, where the artifact lives |
| [`../../context/routing-rubric.md`](../../context/routing-rubric.md) | Only when a genuinely new candidate needs classifying |

This skill does **not** restate the merge semantics — the artifact contract owns them, and a second
statement is a second thing to drift.

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
code it described gets renamed or moved — an ordinary refactor, nowhere near the rules tree, with no
signal at the time. Nothing else in the plugin notices between `check` runs.

## What is deliberately NOT movement

- **A finding the operator already decided on.** `declined` stays declined and is never re-proposed
  by a re-run; `applied` is not re-reported as new. Resurrecting a decision is how an operator
  learns to stop reading.
- **Content edited without changing its meaning for placement.** A reworded sentence inside a
  section whose scope and class are unchanged is not movement. Compare what the classification
  depends on, not the bytes.
- **Findings below the noise budget.** Default: suppress `new` findings whose confidence is low
  *and* whose released line count is trivial. Report the count of what was suppressed — a delta that
  hides its own filtering is the thing it was built to avoid.

## Workflow

Each step names what "done" looks like, so a partial run is visible rather than assumed complete.

1. Resolve the state key and read the prior artifact. **No prior artifact is not an error** — say so
   and route to the full audit rather than silently running one.
   *Done when:* a prior artifact is in hand, or the run has stopped with the route stated.
2. Run the detector and diff its `SECTION` and `RULE` records against the artifact's record of the
   last run. *Done when:* every current record is matched to a prior record or marked unmatched.
3. Classify each difference into one of the five shapes. Only a `new` shape needs the rubric.
   *Done when:* no difference is left unclassified — an unclassified difference is a reporting gap.
4. Re-validate every previously-valid glob; a transition to invalid is `broken-glob`.
   *Done when:* the validator has run over every `RULE` record, not only the changed ones.
5. Check index sync and reachability. *Done when:* both verdicts are recorded, since they are
   independent questions.
6. Merge into the artifact per its contract, preserving operator decisions.
   *Done when:* no `declined` or `applied` status has changed.
7. Report movement, then the suppressed count, then a one-line "nothing else moved".
   *Done when:* the report states a number for both moved and suppressed.

## Reporting

Lead with the count of moved items and the window. When nothing moved, **say that plainly in one
line and stop** — a delta run whose honest answer is "nothing changed" should cost one line to read,
not a page of reassurance.

Never pad a quiet run by re-listing standing findings to look useful.

## Hard rules

- **Read-only on the repository.** The findings artifact is the only write, and it lives outside the
  tree. Every change to the repository belongs to `realign` behind its per-item gate.
- **Never resurrect a declined finding.** Not as `new`, not as `changed`, not "for review".
- **Never suppress silently.** The suppressed count is part of the report, always.
- **Never re-classify an unchanged finding.** If its source content did not change, its
  classification stands — re-deriving it invites drift between runs for no new information.
- **A missing prior artifact routes out.** This skill reports movement; it is not a full audit
  wearing a different name.

## Gotchas

- **A quiet run is the expected outcome, not a failed one.** The pull toward finding *something* to
  justify the run is exactly what makes a cadence lane useless. One line is a complete answer.
- **"Nothing touched the rules folder" does not make glob re-validation unnecessary.** Globs break
  from refactors elsewhere. Skipping validation on that reasoning misses the single shape that most
  justifies the cadence.
- **Byte-level diffing over-reports.** A reworded sentence in a section whose scope and class are
  unchanged is not movement. Compare what the classification actually depends on.
- **The artifact is ephemeral.** A reclaimed container or removed worktree loses it, and the next
  run then legitimately has no baseline. That is the route-out case, not a bug — and it means
  operator decisions can be lost, which is why `declined` is respected rigorously while it exists.
- **A `changed` finding's stale line range is the dangerous part.** It is not a bookkeeping
  detail: `realign` excises by that range, so reporting `changed` without re-deriving the range
  hands the apply lane a number that points at the wrong text.
