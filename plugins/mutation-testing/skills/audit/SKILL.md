---
description: "Run diff-scoped mutation analysis and report surviving mutants — the code under test is always restored, tracked source is never modified, and no test is written by this skill. Generates at most one mutant per changed line, executes the covering tests, then delegates the productive-versus-arid-versus-equivalent judgment to a fresh-context reviewer before reporting; ranks files by oracle gap and hands survivors to the test-authoring lane. Use when: 'run mutation testing', 'are my tests actually checking this', 'mutation score for this change', 'my coverage is high but I do not trust it', 'audit test quality', 'persist the surviving mutants for the fix pass', after tests go green and before review. Flags: `--full` (whole configured scope, not the diff), `--paths <globs>`, `--max <n>`, `--no-suppress` (report suppressed arid mutants too), `--persist-findings` (also write the survivors as a findings file the review fix pass consumes)."
argument-hint: "[scope] [--full] [--paths <globs>] [--max <n>] [--no-suppress] [--persist-findings]"
user-invocable: true
disable-model-invocation: false
shell: bash
metadata:
  workflow-stage: test
  summary: Report surviving mutants on the diff without touching tracked source, survivors triaged
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
- **`--persist-findings`**: after reporting, also write the survivors as a findings file the
  `review:fanout` `fix` action consumes ([Phase 6](#phase-6--persist-opt-in)). Off by default.

## The contract this skill holds

Three properties, stated first because everything below depends on them:

1. **Read-only with respect to tracked source.** A mutant is applied, measured, and reverted.
   Every revert is verified against the Phase 0 snapshot, so a run **either** ends with tracked
   source byte-identical to tracked source at the start **or** ends in failure naming what it could
   not restore — never in a reported outcome over edited source. The first revert that cannot be
   verified is that failure: no later phase runs and nothing is persisted
   ([Phase 3](#phase-3--execute)). Per the
   naming doctrine's verb contract, `audit` reports and stops — and bare invocation does exactly
   that. `--persist-findings` is the explicit user override that verb contract sanctions
   (the marketplace's `docs/PLUGIN-PHILOSOPHY.md` verb table). Its two writes — the findings file,
   and the self-ignore guard's own `.gitignore` when it heals a root — are each **proven outside
   tracked space before either is made**, never in tracked source and never in a file another
   producer owns.
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

**Capture `git status --porcelain` here.** This is *the Phase 0 snapshot* every later restoration
check compares against, and the rest of this skill refers to it by that name. It is taken before the
first mutant is applied and never re-taken: a snapshot refreshed mid-run would absorb the very
difference it exists to detect.

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
(killed / survived / no-coverage / timeout / invalid), revert, **verify the revert**.

**This phase is a deterministic gate and is deliberately not delegated.** The tests' pass/fail *is*
the verdict; there is no judgment to bias and no independence to buy. Spending a subagent here would
be delegation cost with nothing bought — the narrow exemption the fresh-eyes rule states for
mechanical judgments.

Revert must be guaranteed on every exit path — pass, fail, error, or interrupt. Apply the mutation
as a patch reverted in a trap or `finally`, never as an edit depending on a later step to clean up.
**The verification below runs on those paths too.** A trap fires outside the loop, so the loop's own
comparison never sees a crashed or interrupted run; the trap's revert is followed by the same
comparison, and a trap-path revert whose comparison does not match — or cannot be made — is a failed
restore reported as one. A revert that merely *ran* is not a revert that *worked*, and the crash path
is where that difference is most likely to bite.

**Verify restoration against the Phase 0 snapshot, not against a clean tree.** Phase 0 rejects a
dirty *target* but permits unrelated dirty files elsewhere, so an unconditional "tree is clean" probe
would report a restoration failure on a repo that merely has unrelated work in progress — and, worse,
would teach the reader to ignore that line. Compare the after-state against that snapshot: equality
is success, any difference in a mutated path is a failed restore.

**How often to compare depends on who owns the mutant loop, and both answers are mandatory.**

- **This skill owns the loop** (`tool: manual`, and any path where this skill applies and reverts):
  compare **after every revert, inside the loop** — a failed restore means the trap itself failed, so
  the next mutant would be applied on top of unrestored source, every verdict after that describes a
  tree nobody wrote, and an end-of-loop comparison cannot even say which mutant broke it.
- **The configured tool owns the loop** ([Phase 2](#phase-2--generate)'s diff-scoped delegation —
  the tool applies, runs, and reverts internally and returns only results): this skill cannot
  interpose, so it compares **once, when the tool returns**, and that comparison is required rather
  than a nicety. Say what it cannot do instead of pretending otherwise: it cannot name the mutant
  that broke the restore and it cannot stop the tool mid-run, so its report says the run is
  unattributable as well as failed. Never treat the tool's own exit status as the restoration
  verdict — a harness that reverts by writing the file back reports success for a write it never
  re-read.

**The first failed restore ends the run.** It is terminal, not a finding reported beside the others:

- Apply no further mutants — binding on the skill-owned loop; on the tool-owned one the run is
  already over, which is precisely why the remaining two are what carry the rule there.
- Enter no later phase — no triage, no ranked report, and **no findings file, `--persist-findings`
  or not**.
- Return a **failure** verdict naming every unrestored path and the recovery command. The failure is
  the whole report; nothing may push it off the screen.

Stopping rather than reporting is what `docs/conventions/liveness-assertion/README.md` "Core
contract" item 1 requires of a surface that cannot vouch for its own outcome, and continuing would
produce both false-green shapes that doc names at once. The ranked report would read exactly like a
normal run while tracked source sits mutated; and under `--persist-findings` the run would hand an
apply relay a conforming findings file whose every `Location` asserts a restored tree — findings
measured against a state that no longer exists, fenced onto source that is now corrupt.

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

Not examined this run: <n> entries whose anchored nodes fell outside the scope above
(counted at node granularity — an entry in a file this run touched elsewhere still counts here).

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

Then stop, unless `--persist-findings` was passed. Remediation is delegated. This phase is reached
only by a run whose reverts all verified; a failed restore ended it at Phase 3.

## Phase 6 — Persist (opt-in)

Runs **only** under `--persist-findings`, and only on a run whose every revert Phase 3 verified.
Without the flag this phase does not exist and Phase 5 is the end of the run; without a verified
restoration there is no Phase 5 either, because the run already ended in failure. The flag is not the
only gate, and treating it as one is the defect: it decides whether *conforming* findings are
persisted, never whether the tree they describe still exists.

**This gate reads Phase 3's verdict; it never re-derives one.** The comparison against the Phase 0
snapshot has already run by the time this phase is reachable, so a run that persists over a failed
restore is not missing a check — it is declining to read one it already holds.

The flag exists because the survivors this skill detects are real findings with
no route to a remediation surface: writing one conforming file is that route, and it needs no wiring
on the consuming side — the `review:fanout` `fix` action locates its input by frontmatter, never by
provenance.

The mechanics are owned by [`context/persist-findings.md`](context/persist-findings.md), which reads
the detector-findings producer contract for this plugin. Six things there are easy to get wrong and
are not optional: the destination comes from the contract's **whole** rung order, taking its
**non-interactive collapse** for the rungs that confirm or ask, never a hardcoded default;
**both** of the phase's writes — the findings file and the self-ignore guard's `.gitignore` — are
proven outside tracked space before **either** is made, against the checkout that governs the
destination rather than the invoking worktree, and with the guard's own write proven before the guard
heals rather than reported afterwards (a memory root inside tracked space leaves `git status`
identical either way and so cannot detect itself, while a root outside the worktree is a layout the
consumer supports and a worktree-anchored probe could only ever refuse); `Tier` and `Confidence` are
computed from the Phase 4 **verdict class** and never from the
finding's prose, with `Confidence: low` never emitted; every cell describes a mutant this run
actually executed, never an illustrative one; a run that examined mutants writes even when it found
nothing, while a run that examined **none** writes nothing at all; and an existing path is never
overwritten.

Persisting does not trade away the property in "The contract this skill holds": this phase is
reachable only from a run whose every revert verified, and a destination that cannot be proven
outside tracked space is not written to at all.

**Known limitation, routed not solved.** A mutation finding's remediation lands in the covering test,
not at its `Location`, so a consumer that fences each fix to `Location` cannot reach the target. The
spoke records why this producer neither retargets `Location` nor invents a column; the disposition
belongs to `melodic-software/claude-code-plugins#2681`.

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
  by a cap. **A run cut short by a failed restore is not this case** — it reports failure, not a
  partial result ([Phase 3](#phase-3--execute)). A partial report describes a tree that is intact;
  that one is not.
- **Reaching for "equivalent" is the standard way this technique manufactures false confidence.**
  It is the convenient explanation for any survivor whose test is hard to write. Require the
  demonstration; report the claim as unclassified when none exists.
- **A persisted findings file written to the wrong directory fails silently.** Nothing reports the
  miss: the run says it persisted, the file exists, and the consumer never scans that path. It is the
  failure mode of resolving only the documented default on a repo that configured its own memory
  root, which is why Phase 6 runs the whole rung order rather than its last rung.
- **A high mutation score is not a correctness argument.** The coupling effect covers faults composed
  of local errors. It says nothing about a wrong algorithm, a missing requirement, a concurrency
  interleaving, or an unexpressed security property.

## What this skill does NOT do

- Write or modify tests, or leave any mutation in the tree.
- Persist anything on bare invocation. The findings file is written only under `--persist-findings`,
  and only into a memory tier proven to sit outside tracked space.
- Apply its own findings, or read the consumer's consumption ledger. It writes one file and stops;
  what happens to that file belongs to the `fix` action.
- Write suppressions without the user accepting them.
- Fail a build on a score. There is no threshold to configure; see the `principles` skill's
  `scaling-and-suppression.md`.
- Answer test-design questions. Those belong to `/tdd:principles` when installed; otherwise use the
  project's own test-design guidance.
