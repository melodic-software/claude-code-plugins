# Choose the pull request branch update method from shared criteria

- Status: accepted
- Date: 2026-11-08
- Supersedes: decision 4 of
  [ADR 0037](0037-seat-mandatory-reviews-on-the-operator-session-and-retire-the-oauth-lanes.md), on
  "once a pull request exists the ready step merges and never rebases", and its "What stands"
  entry on that point only. The rest of ADR 0037 and its addendum are unchanged.

## Context

ADR 0037 made every update of an open pull request a merge because a rebase rewrote the SHAs its
skill-evidence rows named. The addendum to that record removed the evidence system and kept the
merge-only rule, so the rule stayed in place after its reason had gone.

A fixed method fits some branches badly. A native stack member takes a rebase, a head a dependency
manager owns is updated by that manager, and some landings keep the branch's commits on the base.
Several steps also chose their own method: `create` rebased, `ready` merged, and `monitor` and
`merge` each had a rule of their own.

The owner asked for the choice to be "driven by facts and the latest consensus-based /research",
with one source of truth for every step that updates a pull request branch.

## Decision

1. **One decision.** `plugins/source-control/scripts/branch-update-signals.sh` reads the facts and
   `plugins/source-control/scripts/branch-update-method.sh` picks `none`, `merge`, `rebase`,
   `delegate` or `hold`. `plugins/source-control/reference/branch-update-criteria.md` holds each
   row's reasoning. The default is the table; `pr_update_method` forces a method only on the rows
   marked forceable.
2. **One way to carry it out.** The pull-request skill's "Decide and carry out the update" in
   `ready-for-review.md` owns the sequence, and every other pull-request step points at it and
   states only what differs.
3. **A rewrite is rarely available.** Only an attended `create`, an attended `ready` or
   `reassess --act` may ask for one. An unattended run keeps a pushed head unrewritten, so it
   merges or holds.
4. **`ready` reviews and verifies after any update, whatever the method.** Its reviews and its
   verify gate run on the head the update produced, so no earlier record of a review or verification
   survives a rebase or carries over to a new head.

## Consequences

- A rebase can now run on an open pull request, where the criteria and an attended caller allow
  it. It uses the pinned lease form, and a reviewed pull request gets a before-and-after comparison.
- The fallback, when a rebase's push is refused, is a merge, reported; a native stack member holds
  instead.
- `push-branch.sh`'s stale-base step, the babysit conflict worker and the babysit full-mode
  freshness merge are exempt: each carries out a merge already chosen or is an opt-in merge, so
  none reads the decision.

## Revisit triggers

- A run reports the `default-merge` or `safety-unknown` row for a case a named row should have
  decided.
- The verify gate or the reviews stop running on the head an update produced.
