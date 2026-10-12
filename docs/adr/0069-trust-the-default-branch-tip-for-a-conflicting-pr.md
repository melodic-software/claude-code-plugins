# Trust the default branch tip for a conflicting PR

- Status: accepted
- Date: 2026-10-12
- Amends: [ADR 0053](0053-run-each-pipeline-activity-as-a-model-job-and-a-scripted-report-job.md),
  point 1, for callers that pass `trusted-base: default-tip`

## Context

A write activity reads its config, actions and trusted-actor list from the PR's base SHA, which
must be on the default branch (ADR 0053 point 1; `check-trusted-base`). A PR in merge conflict
keeps a stale base SHA: on pr-pipeline-sandbox, a dispatch for a conflicting PR whose `base.sha`
was still an old main commit failed with `lane pr-refine has 0 slots for activity
test-workflow-push`, because that commit's config lacked the probe's activity (run
38148621946). The token broker
already decides the grant from the default-branch tip
([ADR 0058](0058-mint-lane-app-tokens-through-an-oidc-broker.md)), and the merge the lane makes
has to bring in the tip, not the stale base.

## Decision

The write runner takes a caller input `trusted-base`, `pr-base` by default or `default-tip`
([pr-run-activity.md, step 4](../conventions/pr-pipeline/pr-run-activity.md#the-run-job)):

1. With `default-tip`, `check-trusted-base` runs the same checks (the PR targets the default
   branch, the gated base SHA is on it), then checks out the default branch tip instead of the base
   SHA, before any head checkout
   ([`check-trusted-base/action.yml:61-85`](../../.github/actions/check-trusted-base/action.yml)).
2. That one SHA is the `base-sha` output, the source of config, actions and trusted actors, and
   the merge's second parent
   ([ADR 0068](0068-push-a-lane-merge-as-an-api-made-two-parent-commit-signed-by-the-app.md)).
3. Both pr-unblock jobs pass `trusted-base: default-tip`
   ([`pr-unblock.yml:57,81`](../../.github/workflows/pr-unblock.yml)); every other lane keeps
   `pr-base`.

## Alternatives considered

- **Every lane resolves at the tip.** Rejected for now: it changes every lane's base-SHA contract
  for a problem only a conflicting PR has.
- **Refresh the PR's base before the lane runs.** Rejected: it is a write to the PR before any
  gate, and not a lane action.

## Consequences

- For pr-unblock, the config the job runs and the grant the broker computes come from the same
  revision unless the default branch moves during the run, which narrows ADR 0058's effect-skew
  residual for this lane only.
- If the default branch moves during a run, the merge uses the tip recorded at the start; the PR
  may then be behind only, which the merge queue handles.
- The caller file is lane-power, and the broker checks it against the tip (`workflow-modified`).
