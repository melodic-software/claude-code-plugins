# Review risky Dependabot updates in a model job and act in a scripted job

- Status: accepted; amended 2026-10-18 (a major or unreadable Dependabot update waits for a
  human under `merge.dependabot.majors: hold`, see the
  [ADR 0073 addendum](0073-merge-dependabot-pull-requests-in-the-pr-merge-lane.md#addendum-2026-10-18-a-major-update-waits-for-a-human));
  Decision 1 and the promote step superseded 2026-10-23 (see the
  [addendum](#addendum-2026-10-23-the-model-job-holds-no-write-token))
- Date: 2026-10-16
- Amends: [ADR 0049](0049-run-ci-lanes-on-github-hosted-runners-under-trigger-and-token-hardening.md),
  last consequence: relayed release notes reach a lane that holds no post, close or merge
  credential

## Context

The owner decided on 2026-10-16 that no Dependabot pull request waits on a human: the pr-merge
lane merges non-major updates ([ADR 0073](0073-merge-dependabot-pull-requests-in-the-pr-merge-lane.md)), and an AI decides the rest. The rest are the
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
   the record the pr-merge lane merges on at the current head; `close` files an ignore-entry issue and closes the pull
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
- **A schedule on the dispatcher.** Left out of this decision. ADR 0071 later added a half-hourly
  schedule, which the broker accepts
  ([`pr-run-activity.md`, "The lane token broker"](../conventions/pr-pipeline/pr-run-activity.md#the-lane-token-broker)).

## Consequences

- A review-tier Dependabot pull request is reviewed after the next push to `main`, the
  dispatcher's half-hourly tick (ADR 0071) or a hand run of the dispatcher.
- The pr-merge lane merges a review-tier pull request whose current head carries the lanes App's
  `verdict=merge` marker (owner decision, 2026-10-16; [ADR 0073](0073-merge-dependabot-pull-requests-in-the-pr-merge-lane.md)), so the decision and the merge stay
  in separate lanes.
- `[dependabot skip]` lets Dependabot force-push over the lane's fix on a rebase; the next round
  then reviews the new head, and the round cap bounds the loop.
- A fix commit on a pull request that changes a plugin may need a changelog fragment that a
  Dependabot-only pull request is exempt from; `ci-status` reports it and the next round sees it.

## Addendum (2026-10-22): a fix changes only manifests, and a workflow change waits for a person

The owner decided on 2026-10-22 that review-tier non-major Dependabot pull requests keep merging
unattended on the review's verdict, with two limits the runner enforces, not the prompt:

- **A fix changes only manifests and lock files.** Decision 2 narrows: the promote step moves the
  PR branch only when every path the lane's commits change, either side of a rename, is an npm
  (`package.json`, `package-lock.json`, `npm-shrinkwrap.json`) or pip (`requirements*.txt` or
  `.in`) manifest or lock file outside `.github/`, in a directory `.github/dependabot.yml` lists
  at the base for that ecosystem (`inFixScope` in the base's `dependency-classify.mjs`; the two
  ecosystems the config lists that have manifests, and no file a build runs, such as `setup.py`).
  Any other path leaves the fix off the branch, and the
  verdict job escalates `dependency-fix-not-landed`. The verdict job checks the same rule on what
  landed (`dependency-invalid`), and `patch-rules.json`'s `dependency-review` row allows only
  `dependency-manifests`, which refuses until a runner hands it the config's pairs. Basis:
  [`pr-run-activity-write.yml`](../../.github/workflows/pr-run-activity-write.yml), promote step.
- **A workflow or action file change is an owner merge.** A `merge` verdict on a pull request
  whose files change a workflow or action file (a `github-actions` bump outside the allowlisted
  publishers, say) posts no merge marker and escalates `dependency-workflow-held`. Basis:
  [`apply-dependency-verdict.mjs`](../../.github/scripts/pr-unblock/apply-dependency-verdict.mjs).

## Addendum (2026-10-23): the model job holds no write token

Decision 1 and the promote step of Decision 2 and the 2026-10-22 addendum are superseded: the
model job no longer holds `contents: write`.

- **The model job is a read skill.** `review-dependency` is an `effect: read` skill leaf with
  `applied-by` `{patch: apply-dependency-patch, dependency-verdict: apply-dependency-verdict}`, on
  the read runner, on `run-claude-cli` (the pr-unblock role's API key, then its subscription
  token after a credit stop or with an empty key). Its tools are Read, Grep, Glob, Skill, Edit,
  Write and Agent, with no Bash, and WebFetch on the five configured hosts. It leaves a fix
  uncommitted; the runner hands it on as a patch, and its verdict, the launcher's structured
  output under the same schema, goes through the scan job's leak scan before upload. Basis:
  [`pr-unblock.yml`](../../.github/workflows/pr-unblock.yml);
  [`pr-run-activity-read.yml`](../../.github/workflows/pr-run-activity-read.yml).
- **A base job selects, and every later input comes from it or a scan job.**
  `review-dependency-select` runs `review-dependency.mjs select` before any model turn and writes
  the context file and `context.json`, the run fields the verdict job reads. A select that does not
  proceed posts the `review-dependency` check neutral, so the dispatcher does not send that head
  again.
- **A script pushes the fix, on a fix verdict only.** `apply-dependency-patch` runs
  `apply-patch.mjs` under `patch-rules.json`'s `dependency-review` row: it needs the scanned
  verdict `fix`, admits only `dependency-manifests` paths, holds each file to the
  `dependency-version-change` content rule (`fixRefusal` on the local blobs, before any commit is
  built), skips a moved head, and pushes one commit marked `[dependabot skip]`. A refused patch
  leaves no fix commit, and the verdict job escalates `dependency-fix-not-landed`.
- **A round with no verdict.** The verdict job counts it. It skips `no-model-turn` only when the
  same call's scan handed on no patch, refused nothing, and the head is still the select job's;
  a scan that refused an oversize patch escalates `dependency-fix-not-landed`, and any other gap
  `dependency-invalid`.

The verdict job's checks (Decision 3) and the dispatcher (Decision 4) are unchanged.
