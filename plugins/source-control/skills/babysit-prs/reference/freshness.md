# Branch Freshness

Guarded refresh of behind-base PR branches. Use this only when the snapshot reports
`branch_freshness.state == "behind"`. That field is the queue signal; it already folds in the
one documented fallback below, so there is no separate BLOCKED-vs-BEHIND judgment call to make by
hand. Require `mutation_policy.branch_write_allowed`; an external-fork head is a stop-and-ask
condition only when its head repository is outside `<watched-owners>`, even when
`maintainerCanModify` is true. The mutation gate is authoritative for cross-repository heads
under the watched owners. Angle-bracket slots (`<watched-owners>`, `<state-dir>`) are filled from
the effective-configuration block in this skill's `SKILL.md`, which renders every key's resolved
value and its unset fallback; `<state-dir>` is the `state/babysit-prs` subdirectory of the plugin
data directory.

## Why `branch_freshness` Exists, Not Just `mergeStateStatus`

GitHub's `mergeStateStatus` is a single-valued field (GraphQL `MergeStateStatus` enum: `BEHIND` =
"The head ref is out of date."; `BLOCKED` = "The merge is blocked.", per
https://docs.github.com/en/graphql/reference/pulls#enum-mergestatestatus). When a PR is simultaneously
behind its base AND blocked by another gate (a failing required check, a missing review, ...),
GitHub reports `BLOCKED` and the `BEHIND` signal is lost. This precedence is not documented by
GitHub anywhere this skill's authors could find. It was observed live: a PR sat eleven commits
behind its base (the compare API reported `status: diverged` with `behind_by: 11`) while its
required checks failed for exactly that staleness (content from a just-merged sibling PR was
missing from the branch), yet `mergeStateStatus` reported `BLOCKED`, never `BEHIND`. A gate that
only ever matched the literal string `BEHIND` could never open for that PR, a chicken-and-egg an
automated queue cannot break out of on its own.

`BEHIND` is also reported only where the base requires branches to be up to date. Under loose
required status checks GitHub merges a behind head, so a behind head with every other gate met
reads `CLEAN` (or `HAS_HOOKS`).

The snapshot engine closes both gaps with one narrow, evidence-based fallback: when
`mergeStateStatus` is `BLOCKED`, `CLEAN`, or `HAS_HOOKS`, it compares the base ref against the
head SHA via GitHub's own `GET /repos/{owner}/{repo}/compare/{basehead}`. If the compare proves
outstanding base commits (`status` in `behind`/`diverged` and `behind_by > 0`), the PR is
classified `branch_freshness.state == "behind"` (`source: "compare_api"`) exactly as if
`mergeStateStatus` had reported `BEHIND` directly. A behind `CLEAN`/`HAS_HOOKS` head is the one
exception: its base's rules are read too, and it is `behind` only when that read succeeds and
shows no merge queue. On a queue base it stays `not_reported_behind`, because the queue tests the
PR against the latest base itself and needs no branch update. On an unreadable rules answer it
also stays `not_reported_behind` for that cycle: the refresh disarms auto-merge and its push
reruns CI and the AI reviews, which a transient failure must not start on a queue base. The next
snapshot reads the rules again. Any other cause of `BLOCKED`, a real merge conflict, a pending
human review, anything else, is untouched: the fallback only ever flips these states to `behind`,
never invents eligibility the compare API did not prove, and every other invariant below
(conflict check, human-review stop, worker lease, unique head ref, the per-source-SHA refresh
ledger) is still enforced completely independently, on both the stored snapshot and a live
re-check right before the mutating call. This is a strictly evidence-based extension, not an
inferred "blocked *because* stale" judgment. The tool cannot and does not attempt to prove
causation between the two; refreshing a genuinely-behind branch is always safe regardless of why
it also happens to be `BLOCKED`.

The base compare **must** use the base ref's NAME, never the PR's cached `baseRefOid`: that field
lags once the base branch advances past the PR's last sync, and a compare against a stale OID
silently understates or hides real divergence (verified empirically, see the single-PR
diagnostic below).

### Verification record for the two GitHub claims

**Claims.** GitHub reports `BLOCKED` in preference to `BEHIND` when both apply, and a PR's
`baseRefOid` lags the base branch's live tip once the base advances past the PR's last sync.

**Basis.** Two parts, split by what GitHub publishes and what it does not. The field shapes are
documented: [GraphQL Pulls reference](https://docs.github.com/en/graphql/reference/pulls) carries
the `MergeStateStatus` values quoted above, `BEHIND` as "The head ref is out of date." and
`BLOCKED` as "The merge is blocked.", and defines `baseRefOid` as "Identifies the oid of the base
ref associated with the pull request, even if the ref has been deleted." Neither the precedence
nor a refresh guarantee for `baseRefOid` appears anywhere on that page, so both remain live
observations, reproducible with the single-PR diagnostic below: read `mergeStateStatus` and
`baseRefName` with `gh pr view`, then compare the same head SHA against each of the two bases with
`gh api repos/{owner}/{repo}/compare/{basehead}` and read `behind_by`.

**Verified.** 2026-09-06, against the GraphQL Pulls reference as fetched that day.

**Recheck trigger.** The Pulls reference gaining a precedence rule for `mergeStateStatus` or a
refresh guarantee for `baseRefOid`, a GitHub changelog entry naming either, or a diagnostic run
where `BLOCKED` no longer co-occurs with a positive `behind_by`.

### Verification record for the loose-base and merge-queue claims

**Claims.** A base with loose required status checks lets a behind head merge, and a base that
requires a merge queue gives the same up-to-date guarantee without the branch being updated.

**Basis.** The strict and loose rows of
[require status checks before merging](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches#require-status-checks-before-merging),
and [about merge queues](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue#about-merge-queues).
The rulesets field read for the strict setting is `strict_required_status_checks_policy` on a
`required_status_checks` rule, as `GET /repos/{owner}/{repo}/rules/branches/{branch}` returns it.

**Verified.** 2026-10-04, against both pages and a live rules read as of that day.

**Recheck trigger.** Either page changing what the loose setting or a merge queue guarantees, or
the rules endpoint renaming the strict field.

## Orchestrator-Only Refresh Procedure

Only the orchestrator may refresh a branch:

1. Hold the PR's worker lease, require a unique head repository/branch across the open watched
   queue, require no human-review stop, and take the snapshot's head SHA as
   `<expected-head-sha>`.
2. Run the guarded helper, which uses GitHub's default merge update and `expected_head_sha`
   optimistic locking:

   ```text
   python "<skill-dir>/scripts/refresh_pr_branch.py" --pr owner/repo#42 --expected-head-sha <expected-head-sha> --lease-token <worker-token> --state-dir <state-dir> --apply
   ```

3. Treat GitHub's `202 Accepted` response as asynchronous, and terminal for that PR's cycle.
   Persist the source SHA and request time, classify the PR as `pending fresh CI`, and end work
   on that PR until a later snapshot observes a different head SHA. Do not edit, delegate, retry
   checks, or post a review trigger while the accepted source SHA is still current, even if merge
   state transiently changes.
4. On a later snapshot, require a new stable head SHA and reload checks and reviews for that SHA
   before assigning work.

The helper serializes state, writes a durable attempt before calling GitHub, and keeps a
per-source-SHA ledger across close/reopen cycles. Never rebase, force-update, clear that ledger,
or repeat a refresh request for the same source SHA. Stop and report `403`, `422`, conflicts,
missing permissions, an incomplete attempt, or a refresh that remains unchanged across later
snapshots.

## Single-PR Diagnostic

For an ambiguous single PR, inspect it without changing anything. Compare against the base ref's
NAME (`baseRefName`), not `baseRefOid`: the cached OID lags the base branch's live tip once the
base advances past the PR's last sync (empirically: a real PR's head compared as up to date
against its own stale `baseRefOid` while comparing the same head SHA against the live base tip
correctly reported `status: diverged` with a positive `behind_by`):

```text
gh pr view 42 -R owner/repo --json mergeStateStatus,baseRefName,headRefOid
gh api "repos/owner/repo/compare/<baseRefName>...<headRefOid>" --jq "{status,ahead_by,behind_by}"
```

## Genuine Merge Conflicts Are Out Of Scope Here

This file covers only the guarded refresh above (`branch_freshness.state == "behind"`, whether
reported as `BEHIND` directly or recovered from a `BLOCKED` status via the compare fallback), a
`202`-async update request with no conflict yet realized. It does not cover resolving an actual
merge conflict once one appears on the branch (from a refresh, a base change, or a worker's own
fix attempt). That contract, who resolves, who pushes, and every invariant either side must hold,
lives in one place: `orchestration.md`'s Merge Conflict Resolution section.

## Never squash-merge a behind-base PR

Squash-merging while the head is behind its base can silently drop commits that landed on the
base after the PR branched, including the tests that covered them, with CI green throughout.
Treat `branch_freshness.state == "behind"` as a hard stop on the merge path even when GitHub
reports `mergeStateStatus` `CLEAN`/`HAS_HOOKS`: under a non-strict ruleset, GitHub does not itself
refuse a behind-base merge, so CLEAN does **not** imply an up-to-date base. The merge gate enforces
this on its own: on a base whose rulesets require neither strict required checks (a strict rule
that lists at least one required check) nor a merge queue, it compares an otherwise-ready head
against the live base when it runs, and holds the head if it is behind or the compare cannot be
read (`baseFreshness` in its output). Only rulesets are read: classic branch protection is not,
so a base that is strict or queue-gated only through classic protection still gets the compare.

The check runs only when the gate runs. Once the gate has armed auto-merge (`--auto`), GitHub
merges the PR when its checks pass without the gate running again, so a base that moves after
arming is not re-checked; that race predates this check. A compare that keeps failing on a loose
base holds the PR until a human acts, because the snapshot does not report the head `behind`
without a compare that proves it, so no refresh clears the hold.

Cost: the gate makes one compare per otherwise-ready PR on a base with no ruleset strict or queue
rule, and none on one with either. The snapshot compares every `BLOCKED`, `CLEAN`, or `HAS_HOOKS`
PR on every cycle, whatever the base, and reads the base's rules once more for each `CLEAN` or
`HAS_HOOKS` head the compare shows behind.

Before any merge:

1. Require a successful refresh (this file's procedure) when the snapshot reports `behind`.
2. Re-check `branch_freshness` on the post-refresh head; do not merge while it is still
   `behind`.
3. Where the consuming repo runs an overlapping-path CI gate (the marketplace's own is
   `scripts/check-stale-base-overlap.sh --check`), prefer it as the tripwire. Such a gate covers
   the stale-**base** class only: a head current in history but stale in **content** passes it,
   and only a post-merge detector (a silent-revert check, itself a bounded heuristic) catches that
   class. A consuming repo may have neither.

Official references:

- https://docs.github.com/en/rest/pulls/pulls#update-a-pull-request-branch
- https://cli.github.com/manual/gh_pr_update-branch
