# Restore the Claude review lanes on every push, beside the seat layer

- Status: accepted
- Date: 2026-09-24
- Supersedes, for this repository: ADR 0037's decision 2 (both OAuth lanes retire) and the
  consequences that follow from it, and ADR 0002's once-per-PR trigger set. ADR 0037's seat layer
  (decisions 1 and 3 to 8) stands unchanged.

## Context

The operator requires a code review and a security review on every pull request, visible in CI.
"Mandatory" here means a review runs on every pull request and a failed review shows red. It does
not mean a review blocks a merge.

ADR 0037 measured the lanes' coverage (14 of the last 40 merged pull requests had no successful
code-review run; 1 was reviewed on the commit that merged) and retired them. The cause of that gap
was trigger timing, not the lanes existing: both callers ran on `opened`, `ready_for_review` and
`reopened` only, and "Workflows will not run on `pull_request` activity if the pull request has a
merge conflict" (GitHub, events that trigger workflows, fetched 2026-09-24). An agent branch opened
while main had moved lost its one trigger, and no later push re-triggered it.

The seat layer ADR 0037 put in place reaches only pull requests that pass through the
pull-request skill; ADR 0037 records that pull requests opened any other way receive no review.

## Decision

1. **Both lanes are restored** as they stood before #4210: the two callers, their evidence guards,
   the shared guard library, the skip-actors reader and list, and the security lane's path gate
   `.github/claude-security-paths` with its patterns unchanged.
2. **Every push is reviewed.** Both callers trigger on `opened`, `synchronize`,
   `ready_for_review` and `reopened`. Drafts are still skipped. The push that resolves a merge
   conflict is a `synchronize` event, so a pull request that conflicted when it opened is reviewed
   once it no longer does.
3. **Per-push runs do not stack.** Each caller has a workflow-level per-pull-request concurrency
   group with `cancel-in-progress: true`, so a newer push cancels the older run. The code-review
   lane keeps its repo-wide job queue, and sets `max-reviews-per-pr: 0` so a busy pull request is
   not silently capped.
4. **A failed review shows red.** Both callers set the ci-workflows `status-check` input
   (ci-workflows#619), which publishes `review / claude-review-status` and
   `security-review / claude-security-review-status`. Each goes red and names the failure class
   (`auth`, `rate-limit`, `overloaded`, `no-delivery`, `other`) when the review fails.
5. **No review check is required.** `ci-status` stays the only required check. The lanes, their
   evidence guards and the status checks are advisory per ADR 0002 and must never be added to
   required status checks.
6. **The seat layer stays as a second layer.** The `pr_skill_evidence` map, the ready step, and
   the three advisory readers from ADR 0037 keep running beside the lanes.

## Consequences

- Review spend rises from one run per pull request to one per push, drawn on the subscription
  window the interactive sessions share. Cancelling superseded runs and the security lane's
  incremental relevance check (ci-workflows#259) bound it.
- The security lane is still path-gated: a pull request touching no path in
  `.github/claude-security-paths` gets no security review in CI. Whether that gate should go is an
  open operator question.
- `REVIEW.md` keys the security split on the security workflow file existing. With the file
  restored, the code-review lane again leaves security findings to the security lane, which is the
  split the `review` plugin's skills state.
- The skill-degrade guard on the code-review lane will meet #4306 (the skill returns no content
  inside the lane) on every push until that is fixed.
- ADR 0037's revisit trigger "the review-count or last-reviewed-head comment appears on a pull
  request opened after this change" no longer applies: those comments are expected again.
- The fleet's managed callers come from `melodic-software/standards` `components/claude-lanes/`;
  their trigger set is changed there, not here.

## Revisit triggers

- A status check shows the same failure class repeatedly → fix the cause (credential, usage
  window) rather than muting the check.
- Per-push spend exceeds what the operator accepts → reintroduce `max-reviews-per-pr` or drop
  `synchronize` on one lane, and record which.
- The operator decides the security review must run regardless of paths → remove the path gate.
