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
   SHA, before any head checkout. Basis:
   [`check-trusted-base/action.yml:61-85`](../../.github/actions/check-trusted-base/action.yml).
2. That one SHA is the `base-sha` output, the source of config, actions and trusted actors, and
   the merge's second parent
   ([ADR 0068](0068-push-a-lane-merge-as-an-api-made-two-parent-commit-signed-by-the-app.md)).
   Basis: [`pr-run-activity-write.yml:118,222-233,448`](../../.github/workflows/pr-run-activity-write.yml).
3. Both pr-unblock jobs pass `trusted-base: default-tip`; no other caller passes the input, so
   every other lane keeps the `pr-base` default. Basis:
   [`pr-unblock.yml:57,81`](../../.github/workflows/pr-unblock.yml); `pr-run-activity.md:61`.

## Alternatives considered

- **Every lane resolves at the tip.** Rejected for now: it changes every lane's base-SHA contract
  for a problem only a conflicting PR has. Basis: judgment; the owner chose the per-caller input
  in the pr-unblock design review on 2026-10-11.
- **Refresh the PR's base before the lane runs.** Rejected: it is a write to the PR before any
  gate, and not a lane action. Basis: judgment.

## Consequences

- For pr-unblock, the config the job runs and the grant the broker computes come from the same
  revision unless the default branch moves during the run, which narrows ADR 0058's effect-skew
  residual for this lane only. Basis: judgment, from ADR 0058 "Consequences" and decision point 2
  above; not measured.
- If the default branch moves during a run, the merge uses the tip recorded at the start, and
  the newer commits can conflict with the lane's merge commit, so the PR can be in conflict again.
  The dispatcher run for that push lists the PR again if GitHub reports it `CONFLICTING`: the
  lane's check run is posted on the gated head, not on the merge commit, so the existing-check
  skip does not match the new head, and a dispatch sent while the lane is still running waits in
  the `pr-unblock-<n>` group and gates the PR's head as it is when it starts. A PR whose mergeable
  state stays `UNKNOWN`, or that falls past the per-run cap, waits for the next push to `main`,
  the dispatcher's half-hourly tick (ADR 0071) or a hand run of the dispatcher. Basis:
  [`dispatch.mjs:48-57,60-110`](../../.github/scripts/pr-unblock/dispatch.mjs);
  `pr-unblock.yml:31-33`;
  [`check-trusted-trigger.mjs:349-353`](../../.github/actions/check-trusted-trigger/check-trusted-trigger.mjs);
  the check run is posted only by the report job (`pr-run-activity-write.yml:1088-1089`,
  [`report-check-run.mjs:101`](../../.github/actions/report-check-run/report-check-run.mjs)).
- The caller file is lane-power, and the broker checks it against the tip (`workflow-modified`).
  Basis: ADR 0058 point 3.
