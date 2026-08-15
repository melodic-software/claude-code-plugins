# Work classes

Normative leaf of the [guardrail contract](../guardrails.md): the per-class risk-property
bundles behind the matrix rows, and the promotion/demotion discipline for its promotable
cells.

## Risk-property bundles

Each class is a bundle of four risk properties: blast radius, reversibility, input
provenance, and verifiability. The bundle — not the task's surface description — is what
assigns a class.

### `C1` — read-only

Audits, research, reports. "Read-only" scopes REPOSITORY surfaces: a `C1` run performs no
repository mutation. Writes to the governed queue and tracker — work-item filing, queue
comments, audit-trail artifacts — are PERMITTED: they are the class's output channel and land
on the queue's audit trail, not in the repository. Blast radius is informational only, and
there is nothing to revert; but the exfiltration surface remains, which is why the
min-isolation floor is `L2`, not `L0`. Verifiability is output-shape checking.

### `C2` — mechanical maintenance

Dependency bumps, lint/format, sync. Deterministic and trivially reversible; input
provenance is the org's own automation; verifiability is complete — deterministic blocking
gates decide the outcome without judgment.

### `C3` — scoped change

A briefed fix or small feature. Blast radius is bounded by the brief; tests exist, so
reversal is a bounded revert; verifiability combines deterministic gates with AI review.

### `C4` — structural

Refactors, migrations, contract changes. Blast radius is cross-cutting and reversal is hard,
so human review and human merge are mandatory, always, and the class escalates for upfront
plan approval before execution.

### `C5` — untrusted-provenance

Fork PRs, external contributions, unvetted repositories. The input provenance itself is
untrusted, and it dominates every other property. The class's min-isolation cell, `L3`, is
the floor the runner design pack's `C5`-dispatch gate cites: no `C5` item is dispatched onto
any execution surface below `L3`, and the class's merge policy never promotes.

#### Executable provenance tests

`C5` is assigned by field tests on the provider's own metadata — never by classifier judgment
alone, and never by anything recorded in the item's own body (the untrusted surface being
classified). Two surfaces carry the tests; they answer different provenance questions and do
not substitute for one another.

**Pull request — the code's provenance.** Two tests on the PR's cycle-start snapshot, either
one marking the PR `C5`, each failing closed to `C5` when its field is missing or unreadable:

- **Fork test:** the head repository is not the base (`isCrossRepository: true`, or
  `headRepositoryOwner` differing from the base owner).
- **Trust test:** `C5` unless one arm positively passes — `authorAssociation` `OWNER` or
  `MEMBER`, or the author is a structural bot (`[bot]` login suffix or provider `Bot` type)
  listed in the TARGET repository's team-tracked, default-branch
  `babysit_loop_trusted_internal_bot_logins` (grammar, binding, and fail-closed empty set:
  `plugins/source-control/reference/config-resolution.md`, "the C5 trust test's one reviewed
  widening"). A listing never bypasses the fork test.

A fork PR closing an internally classified `C2`/`C3` issue is still `C5` — the class travels
with the code's provenance, not the issue it closes.

**Issue — the intake's provenance.** One trust test on the issue's cycle-start snapshot,
failing closed to `C5` when any field it needs is missing or unreadable:

- **Trust test:** `C5` unless one arm positively passes — the issue author's
  `authorAssociation` is `OWNER` or `MEMBER`, or the author is a structural bot whose login
  matches an entry in the same TARGET repository's team-tracked, default-branch
  `babysit_loop_trusted_internal_bot_logins` list the PR trust test uses (same grammar,
  binding, and fail-closed empty set — repository-owned automation identities are never org
  `MEMBER` accounts, so without this second arm the org's own lane bots would be classified as
  untrusted on the issue surface as they were on the PR surface before #1525). Neither arm
  positively passing — including when `authorAssociation` is absent or unreadable — is `C5`.

The issue test keys on the issue author only. It is not a lookup of anything in the issue's
title, body, or comments; those surfaces are attacker-writable and are evaluated as data,
never as admission input.

**Composition.** The PR tests and the issue test are independent: a same-repository PR from a
trusted member closing an issue filed by an outside collaborator is `C5` on the issue and not
`C5` on the PR; a fork PR closing an internally triaged issue is `C5` on the PR regardless of
the issue author's association. Classification at triage and admission stamps the bundle the
tests resolve; the tests are the executable trigger, not a second opinion on a stamped label.

## Promotion and demotion

This promotion apparatus — numeric predicate, human-ratified flip, automatic fail-closed
demotion — is this contract's quantification of the Boris playbook's qualitative bar that no
autonomy scales before the loop has "earned widespread trust": the trust requirement is the
playbook's, the evidence predicate over telemetry that measures it is this contract's.

Every promotable matrix cell carries a per-cell promotion trigger with one contract-fixed
shape: an **evidence predicate over queryable telemetry** — verification outcomes recorded
per the [telemetry contract](../telemetry.md) are the evidence base.

- **Promotion is a human-ratified knob flip — never automatic.** A satisfied predicate makes
  the cell ELIGIBLE; a human ratifies the flip, and the flip is recorded as a reviewable
  change on the governance surface.
- **Demotion is automatic and fail-closed.** Contrary evidence lowers the cell's effective
  state immediately, without waiting for human action; the cell re-earns promotion from
  there through the same evidence predicate.
- **Promotion never overrides unanimity.** A promoted `C2`/`C3` auto-merge cell still does not
  auto-proceed on checker dissent: the promoted state is a ceiling, and dissent withholds the
  automatic transition the same way contrary evidence lowers the cell — the same mechanism, not
  a second one beside it. Requiring unanimous checker agreement is a
  [verification-topology](verification-topology.md) invariant, never a promotable knob; that
  leaf states what is checked at binding-validity time and what awaits the runner.

## Suggested default predicates

The predicate shape is contract-fixed; the threshold values in the table below are suggested
defaults the org binds (org-bindable values). The two subsections after the table are not
defaults and carry no bindable threshold: one fixes what may never enter a predicate at all, the
other records a candidate term as deliberately deferred.

| Cell | Suggested default predicate |
|---|---|
| `C2` auto-merge | ≥ 20 autonomous C2 completions over ≥ 14 days with 100% deterministic-gate pass and 0 human-reverted merges |
| `C3` auto-merge | ≥ 20 autonomous C2 merges over ≥ 14 days with 0 demotion events, plus ≥ 10 autonomous C3 completions with 100% deterministic-gate pass, 0 human-reverted merges, and 0 human-confirmed missed-blocking AI-review findings |
| `C3` AI review advisory → blocking | ≥ 30 advisory reviews with 0 human-confirmed missed-blocking findings |
| `C4` / `C5` merge | never promotes — human merge always; no evidence predicate exists for these cells |

**Demotion evidence set** (one event suffices): any post-merge gate failure, any
human-reverted merge, any verification divergence. Demotion cascades along
predicate dependencies: `C3` auto-merge is earned on the `C2` auto-merge track
record, and its automatic transition is gated on the `C3` AI-review cell being
blocking, so contrary evidence against either prerequisite demotes `C3`
auto-merge with it.

### What may never enter a predicate

**An acceptance or merge rate is never a promotion input, and it is not an efficacy signal**
— in either role, at any cell, at any threshold. Findings across observational, regression, and
randomized designs point the same way: artifact quality is weakly-to-not coupled to whether a
change is accepted. The one verified at primary source, and the strongest statement of it, is
Lenarduzzi et al.'s: *"code quality turned out not to affect the acceptance of a pull request at
all."* A predicate built on acceptance would therefore promote throughput while claiming to
measure trustworthiness.

This does not touch the predicates above, and the distinction is worth stating because two of their
terms sit close to the line.

**`0 human-reverted merges` is a correctness signal, not an acceptance rate.** A revert is a human
asserting the change was wrong after it landed; an acceptance rate counts how much got merged. The
first is evidence about the work, the second about the pipeline.

**A merge COUNT over a fixed window is a volume floor, not an acceptance rate.** The `C3` term
`≥ 20 autonomous C2 merges over ≥ 14 days` says only that enough autonomous work has landed for a
track record to exist at all. The two behave oppositely under exactly the move that makes an
acceptance metric untrustworthy: a ratio rises when its denominator shrinks, so attempting less —
or attempting only what is certain to land — raises it with no change in the work itself. A count
has no denominator to shrink. Selectivity leaves it flat, and clearing it takes absolute output.
Conjoined with the same row's `100% deterministic-gate pass`, `0 human-reverted merges`, and
`0 demotion events`, the count bounds how much evidence exists while those terms carry the
correctness claim.

The full term inventory above is completion counts, merge counts over a fixed window,
deterministic-gate pass rates, revert counts, and demotion events — correctness-side or
volume-side by construction, never a ratio of accepted to attempted.

### Reviewer-burden term — DEFERRED, with a trigger

A reviewer-burden term (how much human review effort a cell's output actually costs) is a
**candidate predicate input, deliberately not a live term.** It is recorded rather than omitted
because a designated planning pass was asked to settle it and silence would leave that obligation
unfilled.

**Why deferred:** the term needs a denominator, and a denominator needs the org-scale trust-path
requirements this contract already defers at solo volume — a population to divide by, a non-merge
outcome signal, and a lookback window with a demotion rule. Absent those, "reviewer burden" is a
count with nothing to normalize against: it moves with volume rather than with trustworthiness, and
a term that moves with volume rewards a cell for producing less. A metric in name only.

**Trigger to reconsider:** the volume at which all three requirements are satisfiable is reached,
and a non-merge outcome signal exists. Reaching only the volume is not the trigger.

**Standing constraint on any future tuner.** If a tuner is ever built, its signal set stays
**disjoint** from promotion evidence. Overlap is a self-dealing loop: a tuner optimizing a signal
that also promotes a cell can raise that signal to reduce the scrutiny applied to the tuner's own
output. The constraint binds whether or not the reviewer-burden term is ever activated, and it binds
the tuner's inputs, not merely its intent.
