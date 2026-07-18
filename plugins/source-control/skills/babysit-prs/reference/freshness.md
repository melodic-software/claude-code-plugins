# Branch Freshness

Guarded refresh of behind-base PR branches. Use this only when the snapshot reports
`branch_freshness.state == "behind"` — that field is the queue signal; it already folds in the
one documented fallback below, so there is no separate BLOCKED-vs-BEHIND judgment call to make by
hand. Require `mutation_policy.branch_write_allowed`; an external-fork head is a stop-and-ask
condition only when its head repository is outside `<watched-owners>`, even when
`maintainerCanModify` is true — the mutation gate is authoritative for cross-repository heads
under the watched owners. Angle-bracket slots (`<watched-owners>`, `<state-dir>`) are filled from
the effective-configuration block in this skill's `SKILL.md`, which renders every key's resolved
value and its unset fallback; `<state-dir>` is the `state/babysit-prs` subdirectory of the plugin
data directory.

## Why `branch_freshness` Exists, Not Just `mergeStateStatus`

GitHub's `mergeStateStatus` is a single-valued field (GraphQL `MergeStateStatus` enum: `BEHIND` =
"The head ref is out of date."; `BLOCKED` = "The merge is blocked." —
https://docs.github.com/en/graphql/reference/enums#mergestatestatus). When a PR is simultaneously
behind its base AND blocked by another gate (a failing required check, a missing review, ...),
GitHub reports `BLOCKED` and the `BEHIND` signal is lost. This precedence is not documented by
GitHub anywhere this skill's authors could find — it was observed live: a PR sat eleven commits
behind its base (the compare API reported `status: diverged` with `behind_by: 11`) while its
required checks failed for exactly that staleness (content from a just-merged sibling PR was
missing from the branch), yet `mergeStateStatus` reported `BLOCKED`, never `BEHIND`. A gate that
only ever matched the literal string `BEHIND` could never open for that PR — a chicken-and-egg an
automated queue cannot break out of on its own.

The snapshot engine closes that gap with one narrow, evidence-based fallback: when
`mergeStateStatus` is `BLOCKED`, it compares the base ref against the head SHA via GitHub's own
`GET /repos/{owner}/{repo}/compare/{basehead}`. If the compare proves outstanding base commits
(`status` in `behind`/`diverged` and `behind_by > 0`), the PR is classified
`branch_freshness.state == "behind"` (`source: "compare_api"`) exactly as if `mergeStateStatus`
had reported `BEHIND` directly. Any other cause of `BLOCKED` — a real merge conflict, a pending
human review, anything else — is untouched: the fallback only ever flips `BLOCKED` to `behind`,
never invents eligibility the compare API did not prove, and every other invariant below
(conflict check, human-review stop, worker lease, unique head ref, the per-source-SHA refresh
ledger) is still enforced completely independently, on both the stored snapshot and a live
re-check right before the mutating call. This is a strictly evidence-based extension, not an
inferred "blocked *because* stale" judgment — the tool cannot and does not attempt to prove
causation between the two; refreshing a genuinely-behind branch is always safe regardless of why
it also happens to be `BLOCKED`.

The base compare **must** use the base ref's NAME, never the PR's cached `baseRefOid`: that field
lags once the base branch advances past the PR's last sync, and a compare against a stale OID
silently understates or hides real divergence (verified empirically — see the single-PR
diagnostic below).

## Orchestrator-Only Refresh Procedure

Only the orchestrator may refresh a branch:

1. Hold the PR's worker lease, require a unique head repository/branch across the open watched
   queue, require no human-review stop, and take the snapshot's head SHA as
   `<expected-head-sha>`.
2. Run the guarded helper, which uses GitHub's default merge update and `expected_head_sha`
   optimistic locking:

   ```text
   python "${CLAUDE_PLUGIN_ROOT}/skills/babysit-prs/scripts/refresh_pr_branch.py" --pr owner/repo#42 --expected-head-sha <expected-head-sha> --lease-token <worker-token> --state-dir <state-dir> --apply
   ```

3. Treat GitHub's `202 Accepted` response as asynchronous — and terminal for that PR's cycle.
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
NAME (`baseRefName`), not `baseRefOid` — the cached OID lags the base branch's live tip once the
base advances past the PR's last sync (empirically: a real PR's head compared as up to date
against its own stale `baseRefOid` while comparing the same head SHA against the live base tip
correctly reported `status: diverged` with a positive `behind_by`):

```text
gh pr view 42 -R owner/repo --json mergeStateStatus,baseRefName,headRefOid
gh api "repos/owner/repo/compare/<baseRefName>...<headRefOid>" --jq "{status,ahead_by,behind_by}"
```

## Genuine Merge Conflicts Are Out Of Scope Here

This file covers only the guarded refresh above (`branch_freshness.state == "behind"`, whether
reported as `BEHIND` directly or recovered from a `BLOCKED` status via the compare fallback) — a
`202`-async update request with no conflict yet realized. It does not cover resolving an actual
merge conflict once one appears on the branch (from a refresh, a base change, or a worker's own
fix attempt). For that, see `orchestration.md`'s Merge Conflict Resolution section: a dedicated,
fresh worker, `git merge` never `git rebase`, understand both sides' intent before touching
markers, verify with tests before pushing, and escalate genuine semantic ambiguity.

Official references:

- https://docs.github.com/en/rest/pulls/pulls#update-a-pull-request-branch
- https://cli.github.com/manual/gh_pr_update-branch
