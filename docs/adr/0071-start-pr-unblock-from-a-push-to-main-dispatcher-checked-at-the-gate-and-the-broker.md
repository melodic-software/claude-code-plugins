# Start pr-unblock from a push-to-main dispatcher checked at the gate and the broker

- Status: accepted
- Date: 2026-10-12
- Amends: [ADR 0058](0058-mint-lane-app-tokens-through-an-oidc-broker.md), point 3: the broker's
  trusted-actor check gains the dispatcher path below

## Context

"Workflows will not run on `pull_request` activity if the pull request has a merge conflict"
([Events that trigger workflows](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows),
fetched 2026-10-12), so the PRs pr-unblock exists for never start a PR-event lane. A workflow must
start it from outside the PR. An event raised with `GITHUB_TOKEN` creates no run except
`workflow_dispatch`, `repository_dispatch` and `pull_request` runs that need approval (same
page), so the lane is started by `workflow_dispatch`. A sandbox probe showed that a run dispatched with
`GITHUB_TOKEN` names only `github-actions[bot]` (id 41898282) as sender, actor, triggering actor
and OIDC actor, and nothing in it names the dispatching run (pr-pipeline-sandbox runs 38155572048
and 38155580529). The trigger gate and the broker trust only listed actors
([ADR 0049](0049-run-ci-lanes-on-github-hosted-runners-under-trigger-and-token-hardening.md)
condition 1, ADR 0058 point 3), and on its own a `github-actions[bot]` sender cannot be told apart
from any workflow in the repository holding `actions: write`.

## Decision

1. **A scripted dispatcher.**
   [`pr-unblock-dispatch.yml`](../../.github/workflows/pr-unblock-dispatch.yml) runs on a push to
   `main` and on a listed human's `workflow_dispatch`, only on `refs/heads/main`, with no model and
   no App token: its `GITHUB_TOKEN` holds `actions: write` and three reads. It checks the kill
   switch, checks a hand run or any re-run with `check-trusted-trigger` (`require-pr: false`,
   `require-kind: human`), then runs
   [`dispatch.mjs`](../../.github/scripts/pr-unblock/dispatch.mjs): open, non-draft,
   same-repository PRs into `main` that GitHub reports `CONFLICTING`, re-querying `UNKNOWN` up to 5
   times 10 s apart, skipping a PR whose head already has a `pr-unblock / resolve-conflicts` check
   from the GitHub Actions app, and dispatching `pr-unblock.yml` for at most 3 per run with
   `pr-number` and `dispatcher-run-id`. It filters no labels or authors; the lane decides those
   once, from its own config and gate. Basis:
   [`pr-unblock-dispatch.yml:14-101`](../../.github/workflows/pr-unblock-dispatch.yml);
   [`dispatch.mjs:1-110`](../../.github/scripts/pr-unblock/dispatch.mjs). The retry count and
   delay and the cap of 3 are judgment, as `dispatch.mjs:23-28` says.
2. **The lane runs on `workflow_dispatch` only**, from the dispatcher or a listed human. Basis:
   [`pr-unblock.yml:14-25`](../../.github/workflows/pr-unblock.yml).
3. **The gate checks the dispatcher run.** A `workflow_dispatch` sent by `github-actions[bot]`
   proceeds only when the `dispatcher-run-id` it carries names a run of the dispatcher on the
   default branch, started by a push or a listed human, with a listed human on any re-run attempt,
   its head an ancestor of the tip and no tag named like the branch, and this run is
   `pr-unblock.yml` created inside the dispatcher run's window: from its `run_started_at` to the
   earlier of its `updated_at` and ten minutes later. The PR author check still applies. Basis:
   [`check-trusted-trigger.mjs:196-292,376-390`](../../.github/actions/check-trusted-trigger/check-trusted-trigger.mjs);
   [README](../../.github/actions/check-trusted-trigger/README.md). The ten-minute cap is
   judgment (`check-trusted-trigger.mjs:25-27`).
4. **The broker repeats the check.** The request carries `dispatcher_run_id`; when the OIDC actor
   is `github-actions[bot]`, the broker mints only after the same dispatcher checks and a
   byte-equal check of the dispatcher file against the tip (`workflow-modified`). Basis:
   [pr-run-activity.md, "The lane token broker"](../conventions/pr-pipeline/pr-run-activity.md#the-lane-token-broker)
   (lines 559-596); `melodic-software/azure-iac` `src/lanes-token-broker/src/dispatcher.mjs:7-51`.
5. **The skill step admits the bot only then.** claude-code-action gets
   `allowed_bots: github-actions` only when `dispatcher-run-id` is set. Basis:
   [`pr-run-activity-write.yml:546-549`](../../.github/workflows/pr-run-activity-write.yml).

## Alternatives considered

- **The broker trusts `github-actions[bot]` on the pr-unblock caller with no run check.**
  Rejected: the broker, the independent check, could not tell the dispatcher from any workflow
  holding `actions: write`, including one on a same-repository PR branch. Basis: the sandbox
  probe runs in Context; the owner confirmed the run-id check at the broker on 2026-10-11.
- **A separate dispatch App.** Rejected: a second App, key and trusted-list row for one call.
  Basis: judgment, under the same owner confirmation.
- **Require the dispatcher run to still be running.** Replaced by the window: a dispatched run
  that waited in the per-PR queue would fail it, while the window still binds the dispatched run
  to one dispatcher run. Basis: `pr-unblock.yml:48-50` (job-level queue); check-trusted-trigger
  README, window paragraph.
- **A schedule sweep** was left out of this scope; a hand run of the dispatcher recovers a missed
  push. Basis: judgment; `pr-unblock-dispatch.yml:17`.

## Consequences

- Accepted residual: any workflow on any branch of this repository can get a `GITHUB_TOKEN` with
  `actions: write`. With one, a forger can dispatch `pr-unblock.yml` on `main` naming a real
  dispatcher run, inside that run's window, with any `pr-number`. Since `allowed_bots` admits
  `github-actions` for such a run, the forged dispatch can reach the model. The PR author check
  and the lane's `applies-when` (a conflicting, non-draft PR without a hold label) still apply.
  A forged dispatch skips the dispatcher's existing-check skip and its cap of 3, so it can repeat
  runs on one head; the per-PR write queue and the `needs-human` label after an escalation limit
  that (judgment, untested). The owner has decided to build run-id membership: the dispatcher
  records the run ids it dispatched in an artifact, and the gate and the broker require
  membership. It is not built yet. Basis: check-trusted-trigger README, residual paragraph;
  `pr-run-activity-write.yml:546-549`; `dispatch.mjs:60-110`.
- One runner per conflicting PR per push, capped at 3 per dispatcher run. The cap is judgment
  until the lane's per-run cost is measured. Basis: `dispatch.mjs:23-24`.
- A merge-queue merge raises one push for a batch, so the dispatcher lists PRs against `main` as
  it is when it runs, not against the pushed commit. Basis: `pr-unblock-dispatch.yml:6-7,38-43`.
- The lane went live with the dispatcher. Basis: dispatcher run 38201493950 dispatched pr-unblock
  run 38201565861, which minted through the broker and escalated as expected.
