---
description: "Re-run the placement audit and report only what MOVED since the last run: new candidates, findings whose source content changed, rules whose globs stopped resolving, and index drift, above a configurable noise budget, so a repeat run costs attention proportional to what actually changed rather than re-presenting a finding set the operator already decided on. Declined findings stay declined and are never resurrected by a re-run. Use when: 'what changed since the last placement audit', 'placement delta', 're-run the instruction-placement audit', 'anything new to move', 'did any rule glob break', 'weekly instruction-placement check', or from a scheduled lane. Read-only on the repository; its only writes are the refreshed findings artifact and its delta baseline, and realign still owns every change."
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
| [`../../context/findings-artifact.md`](../../context/findings-artifact.md) | Status vocabulary, re-run merge semantics, the delta baseline's frontmatter, body, and capture rules |
| [`../../reference/topic-docs.md`](../../reference/topic-docs.md) | Where the artifact and the baseline land: the rung order, the branch slug, the self-ignore guard |
| [`../../context/routing-rubric.md`](../../context/routing-rubric.md) | Only when a genuinely new candidate needs classifying |

This skill does **not** restate the merge semantics, and it does not restate the baseline's shape or
its location. The artifact contract and the placement binding own them, and a second statement is a
second thing to drift.

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

1. Resolve the home through the binding, then read `findings.md` and the baseline at
   `baselines/delta-baseline.md` from it. **Neither one missing is an error.** Dispose of what is
   there:
   - **Both present, and the baseline's `branch:` matches the resolved branch identity.** This is
     the baseline. Note its `source-date`; where it predates the immediately preceding cycle, the
     window widens and the report says so.
   - **Both present, `branch:` does not match.** No baseline, naming both branches. The stored file
     is kept, not overwritten, and the run takes the bootstrap path below.
   - **`findings.md` present, no baseline.** A **bootstrap cycle**. Capture the artifact's spine
     rows and its declined records, per the contract's capture rules, over
     `baselines/delta-baseline.md` in the same home **before comparing anything**, then continue
     with that capture as this cycle's baseline. Say in the report that this is a bootstrap and
     that a status change made before it is unobservable this cycle. This is the only path by
     which a first baseline comes to exist: `audit` and `realign` write none, so the delta run
     after any audit takes it.
   - **`findings.md` absent.** Route out. Name the resolved path you looked in, say that no
     artifact is there, and route to the full audit rather than silently running one. On a
     freshly upgraded plugin, name the retired pre-0.12.0 plugin-data tree as the likely cause,
     in one clause and without reading it: a home the upgrade left behind and a plugin that never
     ran look identical from here, and that sentence is what lets an operator tell them apart.

   Never widen the search, and never diff the artifact against itself in place of a baseline: the
   artifact is rewritten by every audit and edited by every realign, so that comparison measures
   whatever last touched the file. A bootstrap is not that comparison. It snapshots the artifact
   once, dated, and every later cycle compares against the snapshot rather than the live file.
   *Done when:* a baseline is in hand, stored or bootstrapped, or the run has stopped with the
   missing artifact path named and the route stated.
2. Run the detector and diff its `SECTION` and `RULE` records against **the baseline's** spine rows.
   *Done when:* every current record is matched to a baseline row or marked unmatched.
3. Classify each difference into one of the five shapes. Only a `new` shape needs the rubric.
   *Done when:* no difference is left unclassified. An unclassified difference is a reporting gap.
4. Re-validate every previously-valid glob; a transition to invalid is `broken-glob`.
   *Done when:* the validator has run over every `RULE` record, not only the changed ones.
5. Check index sync and reachability. *Done when:* both verdicts are recorded, since they are
   independent questions.
6. Merge into the artifact per its contract, preserving operator decisions.
   *Done when:* no `declined` or `applied` status has changed.
7. Report movement, then the suppressed count, then a one-line "nothing else moved".
   *Done when:* the report states a number for both moved and suppressed.
8. Capture this cycle's spine and its declined records over `baselines/delta-baseline.md`, in the
   same resolved home, for the next cycle to compare against. A cycle that stopped short at any
   earlier step **writes no capture** and leaves the stored baseline exactly as it is.
   *Done when:* the capture is written, or the run has stated that the stored baseline was kept and
   why.

## Reporting

Lead with the count of moved items and the window. When nothing moved, **say that plainly, with the
window and the suppressed count, and stop**. A delta run whose honest answer is "nothing changed"
should be short and complete, not a page of reassurance.

Never pad a quiet run by re-listing standing findings to look useful.

## Hard rules

- **Read-only on the repository.** The findings artifact and its delta baseline are the only writes,
  both in the memory tier the binding resolves, both self-ignored. Every change to the repository
  belongs to `realign` behind its per-item gate.
- **One slot for the baseline, on both sides.** It is read from and written to
  `baselines/delta-baseline.md` in the resolved home and nowhere else. A read path and a write path
  that disagree produce no error: the lane bootstraps from the artifact on every cycle while quietly
  depositing a capture nobody reads, and the comparison collapses back into diffing the live
  artifact.
  [`../../scripts/artifact-home.test.sh`](../../scripts/artifact-home.test.sh) pins the two against
  each other.
- **Never resurrect a declined finding.** Not as `new`, not as `changed`, not "for review". The
  baseline carries its own declined records forward for exactly this, so a lost or rewritten
  artifact cannot undo a decline.
- **Never suppress silently.** The suppressed count is part of the report, always.
- **Never re-classify an unchanged finding.** If its source content did not change, its
  classification stands. Re-deriving it invites drift between runs for no new information.
- **A missing artifact routes out, by name; a missing baseline beside a present artifact
  bootstraps, and says so.** This skill reports movement; it is not a full audit wearing a
  different name. State the resolved path that came up empty, so an absence is something an
  operator can see rather than something the report quietly absorbs.
- **A baseline the run did not consume is never overwritten.** Moving the comparison's origin past a
  cycle nobody compared loses whatever moved in between, and no later cycle ever reports it.

## Gotchas

- **A quiet run is the expected outcome, not a failed one.** The pull toward finding *something* to
  justify the run is exactly what makes a cadence lane useless. A short answer that states the
  window and the suppressed count is the whole report.
- **"Nothing touched the rules folder" does not make glob re-validation unnecessary.** Globs break
  from refactors elsewhere. Skipping validation on that reasoning misses the single shape that most
  justifies the cadence.
- **Byte-level diffing over-reports.** A reworded sentence in a section whose scope and class are
  unchanged is not movement. Compare what the classification actually depends on.
- **Both files are ephemeral, and they fail independently.** A branch switch, a removed worktree, or
  a reclaimed container loses the memory tier. Losing both is the route-out case. Losing the
  baseline while the artifact stands is the bootstrap case. Losing the artifact while the baseline
  stands is a route-out that leaves the stored baseline untouched. None is a bug, so check for each
  by name rather than treating one as evidence of the other.
- **A baseline from before 0.12.0 does not exist, and neither does the artifact.** The retired
  plugin-data location the binding records is not read, deliberately: consulting it would keep the
  worktree-hashed key alive as a parallel second home. The first run after upgrading is therefore a
  route-out that names the newly resolved home and the retired tree as the likely reason, which is
  how the move announces itself rather than a fault. The `audit` that follows establishes the
  artifact, and the delta run after that bootstraps the baseline from it.
- **A `changed` finding's stale line range is the dangerous part.** It is not a bookkeeping
  detail: `realign` excises by that range, so reporting `changed` without re-deriving the range
  hands the apply lane a number that points at the wrong text.
