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

This rule is the operator's. Anthropic does not document review on every pull request as a
requirement. Its launch post says it runs Code Review "on nearly every PR at Anthropic"
(<https://claude.com/blog/code-review>, fetched 2026-09-24); the product docs set no default
trigger, leaving an Owner to pick once, every push, or manual per repository
(<https://code.claude.com/docs/en/code-review>, fetched 2026-09-24); and Boris Cherny's Steps of
AI Adoption says "Automated code review and security review are on by default"
(<https://claude.ai/code/artifact/bfdfaef9-bc62-4dfe-ba9e-c58a26c9accf>, fetched 2026-09-24).
What Anthropic does document is that its reviews do not gate a merge:

- The managed Code Review check run "always completes with a neutral conclusion so it never
  blocks merging through branch protection rules" (code-review page above).
- `anthropics/claude-code-security-review` never fails its job on findings: its `action.yml`
  exits non-zero only when the API key is missing, downgrades a scanner failure to a warning,
  and reports findings as a count and PR comments
  (<https://github.com/anthropics/claude-code-security-review/blob/main/action.yml>, fetched
  2026-09-24).

Both lanes authenticate with the org-shared `CLAUDE_CODE_OAUTH_TOKEN`. Anthropic's GitHub Actions
doc recommends an API key from the Claude Console, or workload identity federation, for a secret
shared across repositories, because an OAuth token is tied to the subscription of the person who
minted it (<https://code.claude.com/docs/en/github-actions>, fetched 2026-09-24). The operator
keeps the shared OAuth secret on purpose. The account that holds it is tracked in
melodic-software/claude-code-account-rotation#145.

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
   the shared guard library, and the skip-actors reader and list. The security lane's path gate
   was restored too, then removed the same day (see the addendum).
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

- Review spend rises from one run per pull request to one per push for both lanes, drawn on the
  subscription window the interactive sessions share. Cancelling superseded runs bounds it.
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
- The autonomy security-review policy's floors change so that a class below C3 must not run the
  security lane → reintroduce `paths-file`, and record why.

## Addendum (2026-09-24): the security lane runs on every pull request

The operator decided that the security lane reviews every non-draft pull request, not only those
touching a path in `.github/claude-security-paths`. The caller now passes neither `paths` nor
`paths-file`, which the reusable treats as "every call is relevant". The lane stays advisory and is
never a required check.

The operator's rule is a code review and a security review on every pull request. The autonomy
plugin's security-review policy
([`plugins/autonomy/reference/guardrails/security-review.md`](../../plugins/autonomy/reference/guardrails/security-review.md))
sets per-class floors (C2 not required, C3 advisory, C4 and C5 blocking) and lets a binding
tighten any cell, never weaken one. An advisory security review on every pull request, C2
included, is a permitted tightening.

That tightening is advisory today. It lives in this ADR and in the callers, and neither is a
binding surface: the policy's knobs bind only on the org's security governance surface, the
settings-as-code home `melodic-software/github-iac`, and the security-binding schema resolves no
axis from a repo-local surface. The binding cell is
`verification_blocking.ai-review.C2: advisory`. No security binding exists in github-iac yet, and an absent binding falls back to the
shipped floors, so the tightening becomes binding only once that document is authored. The
trigger to author it is running the autonomy plugin's guided setup (`/autonomy:setup`) for the
org. Trigger frequency and path scope have no dimension in the binding and stay in this ADR and
the callers.

`.github/claude-security-paths` stays: the `security` class of the `pr_skill_evidence` map in
`.claude/source-control.md` reads it for the seat-run security review, and the `ci.yml` evidence
reporter checks it out from the base to serve that map. With no path list, the reusable's
incremental relevance skip (ci-workflows#259) no longer applies, so every push to a ready pull
request is security-reviewed.
