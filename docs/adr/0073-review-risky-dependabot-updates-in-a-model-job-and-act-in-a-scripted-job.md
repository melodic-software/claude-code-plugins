# Review risky Dependabot updates in a model job and act in a scripted job

- Status: accepted
- Date: 2026-10-16
- Amends: [ADR 0049](0049-run-ci-lanes-on-github-hosted-runners-under-trigger-and-token-hardening.md),
  last consequence: relayed release notes reach a lane that holds no post, close or merge
  credential

## Context

The owner decided on 2026-10-16 that no Dependabot pull request waits on a human: the pr-merge
lane merges non-major updates (a parallel change), and an AI decides the rest. The rest are the
updates `dependency-classify.mjs` sorts `review`: a major bump, a GitHub Actions publisher outside
the allowlist, a group holding a major, or a red `ci-status`. Basis:
[`dependency-classify.mjs`](../../.github/scripts/pr-unblock/dependency-classify.mjs).

A Dependabot pull request body quotes upstream release notes and changelogs. ADR 0049 keeps
`dependabot[bot]` on the trusted-actor list and accepts that a listed bot relays text someone else
wrote, in the same class as web pages. A model that reviews such a pull request reads that text,
and the release notes it fetches, on every run. A token with both `contents: write` and
`pull-requests: write` can enqueue a pull request
([`pr-run-activity.md`, "prepare: review-threads"](../conventions/pr-pipeline/pr-run-activity.md#prepare-review-threads)),
and `pr-unblock` never merges
([`lane-rules.json`](../../.github/actions/resolve-config/lane-rules.json)).

## Decision

1. **A model job that cannot post.** `review-dependency` is a `mutate-branch` skill leaf with
   `prepare: dependency-review`: `contents: write` for a fix push, `pull-requests: read` and
   `issues: read`, no `workflows`. Its verdict is the skill's structured output under a fixed JSON
   schema, which the runner, not the model, writes to an artifact beside the gated head. The skill
   frames the PR body, the release notes and every fetched page as data
   ([`untrusted-content`](../conventions/untrusted-content/README.md)). Basis:
   [`pr-pipeline.yaml`](../conventions/pr-pipeline.yaml) `review-dependency`;
   [`dependency-ci.md`](../../plugins/source-control/skills/pull-request/reference/dependency-ci.md).
2. **A fix stays outside `.github/` and lets Dependabot rebase.** The promote step moves the PR
   branch only when the lane's commits touch nothing under `.github/` and each message carries
   `[dependabot skip]`. A fix that needs a workflow change is an `escalate` verdict. Basis:
   [`pr-run-activity-write.yml`](../../.github/workflows/pr-run-activity-write.yml), promote step.
3. **A scripted job acts, and never merges.** `apply-dependency-verdict` is a `publish-artifact`
   script leaf with no model. It validates the artifact against the schema and its SHA-256, binds
   every action to the reviewed head, and posts a lanes App round marker. `merge` is that marker,
   the record a merge authority reads; `close` files an ignore-entry issue and closes the pull
   request, except a security update, which escalates; `escalate` and an invalid verdict hand the
   pull request to a person through `report-escalation`. Basis:
   [`apply-dependency-verdict.mjs`](../../.github/scripts/pr-unblock/apply-dependency-verdict.mjs);
   [`activity-rules.json`](../../.github/actions/resolve-config/activity-rules.json).
4. **The existing dispatcher starts it.** `pr-unblock-dispatch.yml` dispatches `review-dependency`
   from the run that dispatches conflict resolution, so the gate and the broker check it unchanged
   (ADR 0071). Basis: [`dependency-dispatch.mjs`](../../.github/scripts/pr-unblock/dependency-dispatch.mjs).
5. **Two rounds, then a person.** `loop.dependency-review-rounds` (2) review rounds on one pull
   request, counted from the round markers and the model job's check runs, then
   `dependency-round-cap`. The cap is judgment.

## Alternatives considered

- **One job holding `contents: write` and `pull-requests: write`.** Rejected: a model steered by a
  release note could enqueue, close or comment.
- **Enqueue from the verdict job.** Rejected for this change: `pr-unblock` forbids the `merge`
  effect and a repository has one merge authority (README, "Merge authority"). The pr-merge lane
  reads the `merge` marker instead.
- **A pull request that adds the `ignore` entry.** Rejected: the verdict job's grant holds
  `contents: read`, and `.github/dependabot.yml` is a trust-root path no lane merges, so the pull
  request would wait on a person anyway. An issue carries the proposal.
- **Run the repository's tests in the model job.** Rejected: a write-effect activity must not run
  head code (README, "Activities", `effect`), and the bumped dependency is head code. `ci-status`
  runs them on every pushed head.
- **A schedule on the dispatcher.** Not possible without a broker change: the broker accepts a
  dispatcher run started only by a push or a listed human
  ([`pr-run-activity.md`, "The lane token broker"](../conventions/pr-pipeline/pr-run-activity.md#the-lane-token-broker)).

## Consequences

- A review-tier Dependabot pull request is reviewed after the next push to `main` or a hand run
  of the dispatcher, not on a timer.
- Until the pr-merge lane reads the `merge` marker, a `merge` verdict records the decision but
  nothing enqueues it.
- `[dependabot skip]` lets Dependabot force-push over the lane's fix on a rebase; the next round
  then reviews the new head, and the round cap bounds the loop.
- A fix commit on a pull request that changes a plugin may need a changelog fragment that a
  Dependabot-only pull request is exempt from; `ci-status` reports it and the next round sees it.
