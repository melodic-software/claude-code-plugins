# Relay a listed human's review comment to the feedback dispatcher

- Status: accepted
- Date: 2026-11-01
- Amends: [ADR 0071](0071-start-pr-unblock-from-a-push-to-main-dispatcher-checked-at-the-gate-and-the-broker.md):
  the gate and the broker accept one more upstream for the `workflow_run` dispatcher
- Related: [#7866](https://github.com/melodic-software/claude-code-plugins/issues/7866); owner
  decisions [2026-10-18](https://github.com/melodic-software/claude-code-plugins/issues/7866#issuecomment-6244807014)
  and 2026-11-01 (Q1 option (a) of the
  [probe result](https://github.com/melodic-software/claude-code-plugins/issues/7866#issuecomment-6553706657))

## Context

address-feedback applies a listed human's reply on a thread the lane escalated, but nothing
started the lane when that reply was posted. `pr-feedback-dispatch.yml` runs on the completion of a
review, pr-verify, tick, pr-merge, pr-unblock or approval-relay run, and the gate and the broker
accepted its dispatch only through a `pull_request` review run its record names. An owner's reply
waited for the next review round, the next tick's fix-request sweep, or a hand dispatch.

## Decision

1. **An unprivileged relay.** [`pr-review-comment-relay.yml`](../../.github/workflows/pr-review-comment-relay.yml)
   runs on `pull_request_review_comment` (`created` only) with `permissions: {}`, no checkout, no
   secret and no event field in a step. Its job's condition skips a bot's comment, a fork's PR and
   a branch the lanes App opens no PR from, only to save runners. `pr-feedback-dispatch.yml` lists
   it under `workflow_run.workflows`; no new dispatcher is added.
2. **The dispatcher admits it from GitHub-set run facts.** Its dispatch job runs for a successful
   relay run on a lane branch of this repository whose actor is a `User`.
   [`feedback-dispatch.mjs`](../../.github/scripts/pr-unblock/feedback-dispatch.mjs) reads the run
   back and requires a listed human as actor and re-runner (never the lanes App), the PR among its
   `pull_requests`, and an unresolved thread carrying a listed human's direction. As for a fix
   request, only address-feedback check runs started after the relay run count, so a head an
   earlier round handled is sent again. The kill switch, hold labels, the resolve-config slot and
   the select job's round cap still apply. The record names the relay run as the upstream.
3. **The gate and the broker accept that upstream by path, event and actor id.** The
   `run-dispatcher-relay` input of check-trusted-trigger, and the broker's matching constant,
   accept a relay run in place of a review run when its `event` is `pull_request_review_comment`,
   its `pull_requests` name the PR (an empty list refuses), and its `actor` and
   `triggering_actor` are both listed humans. The lanes App never vouches for a relay run, so its
   own replies start nothing. Every other upstream check (repository, head repository, PR head,
   record, window) is unchanged.

The relay's `GITHUB_REF` is the PR's merge ref (`refs/pull/<n>/merge`,
[Events that trigger workflows](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows)),
so the relay file is treated as PR-controlled. Nothing trusts its contents: only its path, event,
actors, head SHA, `pull_requests` and conclusion, which GitHub sets. Whether a relay run starts the
dispatcher is set by the dispatcher's `workflows:` list, which `workflow_run` reads from the
default branch.

## A conflicted PR

The pr-pipeline-sandbox probe confirmed three of the four facts the 2026-10-18 decision named: the
relay run's actor is the commenter, its `head_sha` is the PR head, and its `pull_requests` is
populated. The fourth failed: GitHub started no `pull_request_review_comment` run on a PR with a
merge conflict. The owner chose to build the relay anyway (2026-11-01). Such a reply is picked up
once the conflict is resolved:

- pr-unblock-dispatch sends each conflicting lanes App PR to resolve-conflicts, whose merge commit
  moves the PR branch with the lanes App token.
- That push raises `synchronize`, which starts both review lanes: resolve-conflicts run
  [41312127206](https://github.com/melodic-software/claude-code-plugins/actions/runs/41312127206)
  pushed `52777ee4`, and review runs 41312495673 and 41312495696 started on it 7 seconds later as
  `pull_request` runs whose actor is the lanes App.
- The review run's completion starts the dispatcher, and the listed human's reply keeps its thread
  workable on the new head (`address-feedback.mjs` `onReviewedHead`), so that pass dispatches.

## Alternatives considered

- **A `pull_request_review_comment` trigger on the dispatcher.** Not chosen: the owner's decision
  adds no new dispatcher event, and the dispatcher, which holds `actions: write`, would then run a
  PR's merge ref.
- **A `pull_request_target` relay**, which GitHub runs on a conflicted PR. Not chosen (2026-11-01):
  it is not a review-comment event, and a privileged trigger is a new security design.
- **A scheduled caller.** Declined for #7860 on 2026-10-18, and ADR 0071 excluded a schedule sweep.

## Consequences

- Every person's review comment on a lanes App PR costs one relay runner; the dispatcher then
  starts a runner only for a successful relay run, and reads one run before any PR read.
- A reply on a conflicted PR waits for resolve-conflicts and the review run that follows it.
- The REST run object lists no `pull_requests` once the PR merges, so a late relay run is refused
  there; a run whose head the PR has moved past still lists the PR, and the head check refuses it.
