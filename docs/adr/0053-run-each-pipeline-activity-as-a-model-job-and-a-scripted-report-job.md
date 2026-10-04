# Run each pipeline activity as a model job and a scripted report job

- Status: accepted
- Date: 2026-10-04

## Context

Every PR pipeline lane ([`docs/conventions/pr-pipeline/`](../conventions/pr-pipeline/README.md))
runs activities, and each activity must end in a check run a reviewer and the merge gate can read:
success, failure, or neutral with a skip reason. Silence is not a skip.

Three facts constrain who may write that check:

- [ADR 0049](0049-run-ci-lanes-on-github-hosted-runners-under-trigger-and-token-hardening.md)
  keeps `checks: write` out of every job that runs the model, so no lane can write `ci-status`.
- Branch protection pins `ci-status` to the GitHub Actions integration, which every
  `GITHUB_TOKEN` writer shares. A job holding `checks: write` can post a check under any name,
  `ci-status` included, unless its code refuses to.
- An activity runs code from the PR head: a script's working directory is the head checkout, and a
  skill reads and edits it. Any file the activity's job writes after that point, including a verdict
  file, can be forged by that code.

## Decision

One reusable workflow,
[`pr-run-activity-write.yml`](../../.github/workflows/pr-run-activity-write.yml), runs one activity of one
lane in two jobs. Its contract is
[`pr-run-activity.md`](../conventions/pr-pipeline/pr-run-activity.md).

1. **The `run` job** holds only `contents: read` and `pull-requests: read`. It gates the trigger,
   accepts only a PR into the default branch whose base SHA the default branch holds, reads that
   base SHA's config, runs the skill or script, and writes `verdict.json`. For an effect other than
   `read` it mints a short-lived App token with the grant the config sets; a `read` activity mints
   nothing and uses the job's `GITHUB_TOKEN`. It never holds `checks: write` or `workflows`.
2. **The `report` job** holds `checks: write` plus the two reads and has no model step. It posts one
   check run named `<lane> / <activity>` through the Checks API and refuses either name part
   `ci-status`
   ([`decide.mjs:47-56`](../../.github/actions/report-check-run/decide.mjs)).
3. **The report job trusts only what the runner computed.** Lane and activity come from its own
   `workflow_call` inputs. From the run job it trusts `needs.run.result` and the outputs `base-sha`,
   `head-sha`, `pr-number`, `gate-reason`, `can-commit` and `act-outcome`. Each is a step outcome or
   an output of a step that ran before any head code, except a gate skill's `act-outcome`: its
   verdict step runs after the skill, so a gate skill must not execute head code
   ([ADR 0055](0055-load-nothing-head-controlled-into-a-pipeline-skill-activity.md)). The report job
   checks out the default branch tip, then the run job's `base-sha` only when the default branch
   holds it, and runs `check-signed-commits` itself with its own `GITHUB_TOKEN` unless `can-commit`
   is `false`.
4. **The verdict is a cross-check, never a source.** A verdict whose lane, activity, gate stop
   reason or head SHA differs from the trusted values fails the check. Its `dirty-tree` counts only
   when `true` (failure). A missing verdict is a failure. A cancelled run job posts neutral
   `superseded-sha` only when the PR's current head differs from the gated head; any other cancel
   is a failure. Success requires `act-outcome` to be `success`.
5. **Lanes chain by `workflow_dispatch`.** A check run written with `GITHUB_TOKEN` starts no workflow
   run; only `workflow_dispatch` and `repository_dispatch` are exempt
   ([triggering a workflow from a workflow](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow#triggering-a-workflow-from-a-workflow),
   fetched 2026-10-04). No lane starts on a `check_run` event from another lane.

## Alternatives considered

- **The model job posts its own check.** Rejected: it needs `checks: write` beside the model, which
  ADR 0049 forbids, and that token could post `ci-status`.
- **The report job reads the verdict's gate reason and head SHA.** Rejected: head code runs before
  the verdict is written, so a forged `no-pr` gate stop would suppress the check and a forged head
  SHA would post it on another commit.
- **The run job checks commit signatures and reports the result in the verdict.** Rejected for the
  same reason; `check-signed-commits` runs in the report job, which needs only API reads.
- **The run job computes `act-outcome` in a step and writes it to `GITHUB_OUTPUT`.** Rejected: that
  step would run after head code, which could forge it. The job output and the verdict step's env
  use the same runner-evaluated expression instead.
- **Chain lanes on `check_run` events.** Rejected: the checks the report job writes start no run.

## Consequences

- Every activity that passes the trusted-trigger gate ends in exactly one `<lane> / <activity>`
  check per run attempt. In the `melodic-software/pr-pipeline-sandbox` runs (for example
  [37223500535](https://github.com/melodic-software/pr-pipeline-sandbox/actions/runs/37223500535)
  and [37223058695](https://github.com/melodic-software/pr-pipeline-sandbox/actions/runs/37223058695))
  every run job held `Contents: read`, `Metadata: read` and `PullRequests: read` only, and every
  report job added `Checks: write`.
- A cancel with no newer head is a failure, not a skip: sandbox run
  [37222056077](https://github.com/melodic-software/pr-pipeline-sandbox/actions/runs/37222056077),
  cancelled mid-run, posted `The run was cancelled and no newer head superseded it.` on every check.
- Each caller job also produces job checks `<caller job> / run` and `<caller job> / report`. When
  the run job's base SHA predates the runner's actions, both fail and no lane check is posted.
- The callers must sit in a per-PR concurrency group that queues and never cancels a pending run
  (`queue: max`); a dropped pending run leaves its activity with no check.
- A fork PR gets no check: its `GITHUB_TOKEN` cannot write checks, so the report job skips it.
- The report job's `GITHUB_TOKEN` cannot write issues or pull requests, so an unverified lane
  commit fails the check with no label or comment. Escalating it needs a separate App-token step.
- Accepted residual: the report job's token could still post any check name. Only the reporter's
  `ci-status` refusal and its test stand between a defect in that code and a spoofed required
  check.
- Accepted residual: on `pull_request`, the caller and `pr-run-activity.yml` load from the PR's
  merge commit, so a PR that edits `.github/workflows/` controls both jobs. The bound is who can push
  `.github/workflows/`, not the job split.
