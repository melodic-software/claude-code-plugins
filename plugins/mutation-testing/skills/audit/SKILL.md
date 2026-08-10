---
description: "Run diff-scoped mutation analysis and report surviving mutants read-only — the code under test is always restored, and no test is written by this skill. Generates at most one mutant per changed line, executes the covering tests, then delegates the productive-versus-arid-versus-equivalent judgment to a fresh-context reviewer before reporting; ranks files by oracle gap and hands survivors to the test-authoring lane. Use when: 'run mutation testing', 'are my tests actually checking this', 'mutation score for this change', 'my coverage is high but I do not trust it', 'audit test quality', after tests go green and before review. Flags: `--full` (whole configured scope, not the diff), `--paths <globs>`, `--max <n>`, `--no-suppress` (report suppressed arid mutants too)."
argument-hint: "[scope] [--full] [--paths <globs>] [--max <n>] [--no-suppress]"
user-invocable: true
disable-model-invocation: false
shell: bash
metadata:
  workflow-stage: test
  summary: Report surviving mutants on the diff, read-only, with survivors triaged
---

## Pre-computed context

Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`
Working tree status: !`git status --porcelain 2>/dev/null | head -20 || echo "(unavailable)"`
Changed files vs HEAD: !`git diff --name-only HEAD 2>/dev/null || echo "none"`

## Variables

Arguments: `$ARGUMENTS`

## Argument parsing

- **Scope** (optional): a path limiting which changed files are considered. Default: every changed
  file inside the configured `mutate` globs.
- **`--full`**: mutate the whole configured scope instead of the diff. Expensive and rarely correct
  — state the estimated cost from `baseline-suite-ms` and confirm before running.
- **`--paths <globs>`**: mutate these paths regardless of the diff.
- **`--max <n>`**: cap generated mutants for this run, overriding `max-mutants`.
- **`--no-suppress`**: include mutants that the arid-node record would otherwise suppress, marked as
  suppressed. Read-only inspection of the suppression policy; it never edits the record.

## The contract this skill holds

Three properties, stated first because everything below depends on them:

1. **Read-only with respect to the working tree.** A mutant is applied, measured, and reverted. The
   tree at the end of a run is byte-identical to the tree at the start. Per the naming doctrine's
   verb contract, `audit` reports and stops.
2. **No tests are written here.** Survivors are handed to the test-authoring lane. This skill never
   both creates a gap and closes it.
3. **No verdict this skill produces is graded by the context that produced it.** See
   [Phase 4](#phase-4--triage-fresh-context).

## Phase 0 — Preflight

Refuse to proceed, with the specific remediation, when any of these fail:

- **Config missing** → `/mutation-testing:setup apply`.
- **Tool unavailable** → `/mutation-testing:setup check` names the install line.
- **Working tree dirty in a file about to be mutated** → stop. A mutation harness reverts by
  restoring a known state; uncommitted edits in the target make "revert" ambiguous and risk
  discarding the user's work. Ask them to commit or stash first. This is a hard stop, not a warning.
- **Baseline suite red** → stop and report the failure. A red suite kills every mutant and reports a
  perfect score. Run `/testing:diagnose` when the `testing` plugin is installed; otherwise diagnose
  with the project's own test command before returning here.

Record the baseline run's result and wall-clock. Every later "killed" verdict is meaningful only
against a green baseline captured in this run — not against the one `setup` recorded, which may be
stale.

## Phase 1 — Scope

1. Resolve the changed lines: `git diff --unified=0 <diff-target>...HEAD` for the files inside the
   configured `mutate` globs, intersected with any `--paths` or scope argument.
2. Drop lines with no test coverage, if a coverage report is available — a mutant on an uncovered
   line reports "no coverage", which the coverage report already said more cheaply.
3. Apply the arid-node suppression record per
   [`context/suppression.md`](context/suppression.md), which owns this plugin's read of the
   finding-suppression contract. Three things that are easy to get wrong and are not optional:
   an entry suppresses only when **all five** required keys are present and its stored constituents
   hash to its own key; a **personal-layer entry the team layer does not carry does not suppress**
   (this surface inverts the cascade default), and is reported `personal-only, not applied`; and
   matching is by derived `finding_id`, never by bare file:line. Under `--no-suppress` nothing is
   dropped and every entry that would have applied is marked as such.

   Entries are dispositioned **only when their anchored node is one this run generated a mutant
   for** — inside the changed-line set from step 1, after the coverage drop in step 2. Anything else
   is *not-examined*: left untouched and counted, never resolved. Scope by node, not by file: a file
   with a suppressed survivor at line 100 and an unrelated edit at line 10 was "touched" but that
   node was never examined, and treating it as a disappearance would fail the skill's own self-check
   on nearly every run.
4. **Select the covering tests once, and cache the selection.** Test selection is fixed overhead per
   *target*, not per *mutant*; re-deriving it for each mutant is the difference between a run that
   finishes and one that does not.
5. Report the scope before running: files, changed lines, mutants to be generated, suppressed count,
   and the estimated wall-clock from `baseline-suite-ms × mutants`. If a cap truncates the set, say
   what was dropped — a truncated run must never read as a clean one.

## Phase 2 — Generate

**At most one mutant per changed line.** Not every operator at every location. The marginal value of
a second mutant on a line is near zero: if the line is unchecked, one mutant proves it.

Where the configured tool supports diff-scoped generation, use it — `--since`, `--incremental`,
`--git-diff-lines`. Where `tool: manual`, apply the single-operator protocol from the `principles`
skill's `tooling.md`: prefer statement/block removal, then relational-operator inversion.

## Phase 3 — Execute

For each mutant: apply, run the cached covering tests, record the state
(killed / survived / no-coverage / timeout / invalid), revert.

**This phase is a deterministic gate and is deliberately not delegated.** The tests' pass/fail *is*
the verdict; there is no judgment to bias and no independence to buy. Spending a subagent here would
be delegation cost with nothing bought — the narrow exemption the fresh-eyes rule states for
mechanical judgments.

Revert must be guaranteed on every exit path — pass, fail, error, or interrupt. Apply the mutation
as a patch reverted in a trap or `finally`, never as an edit depending on a later step to clean up.

**Verify restoration against the Phase 0 snapshot, not against a clean tree.** Phase 0 rejects a
dirty *target* but permits unrelated dirty files elsewhere, so an unconditional "tree is clean" probe
would report a restoration failure on a repo that merely has unrelated work in progress — and, worse,
would teach the reader to ignore that line. Capture `git status --porcelain` before Phase 3 and
compare the after-state to it: equality is success, any difference in a mutated path is a failed
restore. A failed restore is the run's **headline finding**, naming the paths and the recovery
command — never a footnote, and never something a later phase's output can push off the screen.

## Phase 4 — Triage (fresh context)

Every surviving mutant is one of three things, and the difference is a judgment:

| Disposition | Meaning | Downstream |
|---|---|---|
| **Productive** | A genuine gap — the behavior is unchecked | Hand to the test-authoring lane |
| **Equivalent** | Semantically identical to the original; no test can kill it | **Not** a suppression — the check is wrong for that node |
| **Arid** | Killable, but killing it would not improve the suite | Propose a suppression entry, with a reason |

**This judgment is delegated to a fresh-context (non-fork) subagent, mandatorily.** It is the
`self-grade` bias class: a context that generated the mutants and ran them is the weakest place to
decide whether its own findings are worth reporting, and a fork inherits that reasoning rather than
removing it. Hand over the artifact — the mutated line, its surrounding code, and the tests that
covered it — never the reasoning that produced the mutant.

For the **equivalence** call specifically, prefer a cross-vendor advisor when one is installed and
set up (invoked per its own documentation), falling back to the same-vendor fresh-context subagent.
Equivalence is formally undecidable, so the risk is a correlated blind spot rather than a lapse of
attention, and that is the case the top rung of the ladder exists for.

**An equivalence verdict must cite evidence.** "No test can detect this" asserted from inspection
alone is exactly where this technique manufactures false confidence. Require the demonstration: what
was run, what was identical, and under which inputs. A verdict that cannot cite one is reported as
*unclassified*, not as equivalent.

## Phase 5 — Report

Per file, ranked by **oracle gap**, not by score. The gap is defined once, in the `principles`
skill's [`${CLAUDE_PLUGIN_ROOT}/skills/principles/reference/metrics.md`](../principles/reference/metrics.md), and this skill does not restate it:

```text
oracle gap = mutation score − code coverage
```

A large **negative** gap is the bad direction — exercised but not checked. So rank **ascending**,
most negative first. The top row is where the reader's belief about the suite is most wrong, which
is the only thing this metric is good for.

```text
## Mutation audit — <scope>, vs <diff-target>

Baseline: <green, N ms>   Mutants: <n> generated, <n> suppressed<, n dropped by cap>

| File | Coverage | Covered-code score | Gap | Survivors |
|---|---|---|---|---|

### Survivors
| File:line | Operator | Mutation | Disposition | Why |
|---|---|---|---|---|

### Suppressed
| finding_id | Site | check / claim | Reason | Date | Layer |
|---|---|---|---|---|---|

### Suppressions that did NOT apply
<each `personal-only, not applied` entry, naming promotion to the team layer as the remedy;
each malformed entry, naming which required key is missing or that its constituents do not
hash to its key; each stale entry whose finding is gone or whose operator was retired>

Not examined this run: <n> entries whose surfaces fell outside the scope above.

### Proposed suppressions
<complete entries for arid survivors — all five keys with the id derived from them — for the
user to accept>

### Unclassified
<survivors whose equivalence claim could not cite evidence>
```

The two suppression sections are obligations of the finding-suppression contract, not report
garnish: a suppression the operator wrote that the contract **declined to enact** is exactly as
important to show as one that applied, and provenance per entry is what distinguishes a team floor
from a personal draft.

Report the covered-code score as the headline and the plain mutation score beside it — the first
answers "are my tests weak", the second mixes that with "do I have tests at all".

Then stop. Remediation is delegated.

## Remediation — delegated

- **Write the killing tests** — `/testing:write` when the `testing` plugin is installed, handed the
  survivor list. Otherwise report the survivors and let the user author tests with their project's
  own conventions; do not author them here.
- **Verify the new test actually kills the mutant** — re-run this skill scoped to that file. This is
  the property that makes the loop trustworthy: the agent that wrote the test cannot grade itself
  into a pass, because the harness re-runs the mutant. A test that does not turn the mutant red has
  not closed the gap, however plausible it reads.
- **Record accepted arid mutants** — append to `.claude/mutation-testing-arid.md` per
  [`context/suppression.md`](context/suppression.md). A complete entry carries all five required keys
  (`check`, `claim`, `sites`, `reason`, `date`) with the `finding_id` derived from the constituents,
  never hand-written. The user accepts each entry; this skill proposes and never writes suppressions
  unprompted, and writes only the **team** layer — a personal-layer entry would not suppress anything.
  An **equivalent** mutant is never recorded here; the convention's record is not for a finding that
  is simply wrong.

## Gotchas

Failure modes documented from the literature and from measurement, not anticipated in the abstract.
Each one produces a *plausible* result, which is what makes them worth listing.

- **A red baseline reports a perfect score.** Every mutant is "killed" by a test that was already
  failing. This is the most dangerous failure mode because the number looks excellent. Phase 0 stops
  on it; never skip that probe to save a suite run.
- **Flaky tests inflate the score by an unknown margin.** A flaky failure kills a mutant by accident.
  There is no correction factor — either fix the flakes or report the score with the caveat attached.
- **Test selection is fixed overhead per target, not per mutant.** Measured in this repository: for
  the most-depended-on shared library, selection alone exceeded 120 seconds while the resulting
  suite set was 64 of 390 suites; a leaf file selected 2. Re-deriving the selection inside the
  mutant loop is the difference between a run that finishes and one that does not.
- **A timeout counts as detected, and that is correct** — an infinite loop *is* a detected behavior
  change. But a score leaning heavily on timeouts is being carried by wall-clock rather than
  assertions; report the timeout share when it is large.
- **"No coverage" is not a weak test, it is an absent one.** Keeping it out of the headline number
  is the entire reason the covered-code score is the one reported.
- **A partially-completed run must report as partial.** Mutants that never ran are named as not-run —
  never counted as killed, never silently omitted. The same rule applies to a mutant set truncated
  by a cap.
- **Reaching for "equivalent" is the standard way this technique manufactures false confidence.**
  It is the convenient explanation for any survivor whose test is hard to write. Require the
  demonstration; report the claim as unclassified when none exists.
- **A high mutation score is not a correctness argument.** The coupling effect covers faults composed
  of local errors. It says nothing about a wrong algorithm, a missing requirement, a concurrency
  interleaving, or an unexpressed security property.

## What this skill does NOT do

- Write or modify tests, or leave any mutation in the tree.
- Write suppressions without the user accepting them.
- Fail a build on a score. There is no threshold to configure; see the `principles` skill's
  `scaling-and-suppression.md`.
- Answer test-design questions. Those belong to `/tdd:principles` when installed; otherwise use the
  project's own test-design guidance.
