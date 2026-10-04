# Keep commit signing on the default-branch rule and add no all-branch rule

- Status: accepted
- Date: 2026-10-04

## Context

PR pipeline lanes commit to PR head branches, signed through the API. The organization's signing
ruleset, managed in `melodic-software/github-iac`, applies `required_signatures` to
`~DEFAULT_BRANCH` in repositories that carry the `requires-signing` property. Nothing stops an
unsigned commit from landing on a PR head branch.

The first design answer was to extend `required_signatures` to `~ALL`, so no unsigned commit could
reach any branch. The evidence for and against:

- Every commit on the last 40 merged PRs across four repositories was verified (380 of 380).
- That scan covered merged PRs only. At least one writer pushes unsigned commits to a PR head today:
  medley's `.github/workflows/regen-lockfiles.yml` runs `git commit` then
  `git push origin "HEAD:${HEAD_REF}"`, which a `~ALL` rule would reject. Rolling the rule out
  safely would need a sweep of every governed repository's workflows and scripts, of open PRs and
  long-lived branches, and a medley change before deploy.
- The open question was whether an unsigned commit on a PR head can reach the default branch
  through a squash merge, which GitHub commits itself.

A probe on `melodic-software/pr-pipeline-sandbox` answered it. That repository's `main` carries
deletion, non-fast-forward, linear-history, pull-request (zero approvals) and `required_signatures`
rules, and no status-check rule. A PR whose head held one unsigned commit (sandbox PR #3, head
`213d404`, verification reason `unsigned`) read `mergeStateStatus: BLOCKED`; a PR whose commits
were all signed (sandbox PR #2) read `CLEAN`.
The signature rule alone blocked the squash merge.

## Decision

**Add no `required_signatures` rule on `~ALL`.** The `~DEFAULT_BRANCH` signature rule is the
control: an unsigned commit may sit on a PR branch, but the PR cannot merge while it is there.
No github-iac or medley change follows from this record.

Inside the pipeline, lane commits stay signed (`use_commit_signing`), the report job's
`check-signed-commits` fails an activity when a commit added after its gated head SHA is not
verified
([ADR 0053](0053-run-each-pipeline-activity-as-a-model-job-and-a-scripted-report-job.md)), and
`pr-fix-ci` acts only when every commit on the PR is verified
([ADR 0051](0051-start-pr-fix-ci-from-workflow-run-for-same-repository-trusted-prs.md)).

## Alternatives considered

- **`required_signatures` on `~ALL`.** Rejected: the probe showed it adds nothing to what reaches
  the default branch, and it would break medley's lockfile workflow and any unsigned writer the
  merged-PR scan could not see.
- **`~ALL` with bypass actors or exceptions for unsigned writers.** Rejected: the owner's rule for
  this rollout was that unsigned writers are fixed, not exempted, and with the rule itself
  unneeded there is nothing to exempt them from.

## Consequences

- No unsigned-writer sweep, medley change or github-iac deploy is needed for signing.
- Accepted residual: unsigned commits can exist on PR and other non-default branches. A PR carrying
  one stays blocked until the commit is replaced. While an activity's gated head SHA is still an
  ancestor of the current head, `check-signed-commits` checks only the commits added after it, so
  an unsigned commit already on the branch does not fail a later activity's check; the
  default-branch rule is what stops it. The check falls back to every PR commit, and an unsigned
  commit already on the branch fails it too, when there is no gated SHA, when it is no longer an
  ancestor (a force-push or rebase rewrote the head), or when GitHub's compare response truncates
  the commits between it and the head.
- Accepted residual: a repository without the `requires-signing` property has no signature rule on
  any branch. This record does not change which repositories carry it.
- Accepted residual: the evidence is one probe in one sandbox repository whose ruleset matches the
  governed shape. Re-derive this record if a PR with an unsigned head commit reads `CLEAN` in a
  repository under the default-branch signature rule, or if GitHub changes how `required_signatures`
  evaluates a squash merge.
