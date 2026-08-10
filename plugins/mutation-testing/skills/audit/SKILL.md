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
3. Apply the arid-node suppression record: drop mutants whose location matches an entry, unless
   `--no-suppress`.
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
Before reporting, verify the tree is clean; a run that cannot restore it reports that as its
headline finding, not as a footnote.

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

Per file, ranked by **oracle gap** (coverage − covered-code mutation score), not by score. The top
row is where the reader's belief about the suite is most wrong, which is the only thing this metric
is good for.

```text
## Mutation audit — <scope>, vs <diff-target>

Baseline: <green, N ms>   Mutants: <n> generated, <n> suppressed<, n dropped by cap>

| File | Coverage | Covered-code score | Gap | Survivors |
|---|---|---|---|---|

### Survivors
| File:line | Operator | Mutation | Disposition | Why |
|---|---|---|---|---|

### Proposed suppressions
<entries for arid survivors, each with a written reason, for the user to accept>

### Unclassified
<survivors whose equivalence claim could not cite evidence>
```

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
- **Record accepted arid mutants** — append to `.claude/mutation-testing-arid.md` per the
  finding-suppression convention: a written `reason` and a `date` per entry, never a bare id list.
  The user accepts each entry; this skill proposes and never writes suppressions unprompted.

## What this skill does NOT do

- Write or modify tests, or leave any mutation in the tree.
- Write suppressions without the user accepting them.
- Fail a build on a score. There is no threshold to configure; see the `principles` skill's
  `scaling-and-suppression.md`.
- Answer test-design questions. Those belong to `/tdd:principles` when installed; otherwise use the
  project's own test-design guidance.
