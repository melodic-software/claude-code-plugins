# Let a pull_request_target dispatcher start pr-refine

- Status: accepted
- Date: 2026-11-06
- Amends: [ADR 0071](0071-start-pr-unblock-from-a-push-to-main-dispatcher-checked-at-the-gate-and-the-broker.md):
  the gate and the broker accept one more dispatcher event, for one dispatched workflow
- Related: [#13717](https://github.com/melodic-software/claude-code-plugins/issues/13717); owner
  decision Q12, [2026-11-06](https://github.com/melodic-software/claude-code-plugins/issues/13717#issuecomment-6694392754)

## Context

Refine starts only from the dispatcher's push and schedule runs, so a pull request waits for the
next tick. A `pull_request_target` run of the same dispatcher can start it on the pull request's
own event. The checks that vouch for a dispatcher run assume it ran on `main`: its `head_branch`
must be `main`, and its `head_sha` must be an ancestor of the tip and hold the tip's dispatcher
file. A `pull_request_target` run reports the PR's branch as `head_branch` and the PR head as
`head_sha` (run 42286186105), so it fails all three.

Since 2025-12-08, a `pull_request_target` run takes its workflow file and its checkout commit from
the default branch, whatever the PR's base
([GitHub changelog, 2025-11-07](https://github.blog/changelog/2025-11-07-actions-pull_request_target-and-environment-branch-protections-changes/)).
The dispatcher that runs is therefore `main`'s. This is a property of the event, which the checks
below rest on. It is not an accepted risk.

## Decision

A `pull_request_target` run of `pr-unblock-dispatch.yml` may start `pr-refine.yml`, under four
invariants: it runs `main`'s code only and never checks out the head; no head-controlled text
reaches a `run:` step; its permissions are `actions: write` and `contents: read` only; and it
holds no App token or secret beyond `GITHUB_TOKEN`.

The trusted-trigger gate
([`check-trusted-trigger`](../../.github/actions/check-trusted-trigger/README.md)) and the lanes
token broker check such a run as they check a push dispatcher run, except:

1. **One caller.** The dispatched run must be `pr-refine.yml`.
2. **The PR entry replaces the branch check.** The run's head repository is this one, and one
   `pull_requests` entry has this PR's number, base `main`, base and head repository ids of this
   repository, and a head ref equal to the run's `head_branch`. The entry's head SHA is live data
   and is not compared. An empty or missing list refuses.
3. **Actors.** The run's `actor` and `triggering_actor` are each the lanes bot or a listed human,
   and a re-run attempt still needs a listed human.
4. **The record names the commit.** The dispatcher records the `main` commit it ran, as
   `pr-unblock-target-dispatched-<commit>-<run id>`. The ancestry check, the dispatcher-file check
   and `dispatcher-current.sh` read that commit in place of `head_sha`. Each record name is
   accepted only on its own dispatcher event.

Every existing refusal stays, including a `pull_request` dispatcher run and a record of another
dispatcher's form.

The trigger ships on `pr-unblock-dispatch.yml`: its `refine` job holds the four invariants,
each pinned by a test in `workflow-gates.test.mjs`, and records each dispatch under a name built
from `github.workflow_sha` and the run id the dispatch API returned.

Amended 2026-11-07: the half-hourly tick no longer dispatches fix-docs, so this trigger is
fix-docs's only start (issue #13717's done-when, after an event-started Refine was seen reaching
review).

Amended 2026-11-12 (owner decision, configurable refine dispatch list): the same run may also
dispatch each `pr-refine.yml` activity the base config's `refine-dispatch.activities` lists, from
a closed allowlist in `refine-event-dispatch.mjs` (`fix-marker`), on a listed human's event only,
never the lanes bot's, whose patch push would start the activity again. Each dispatch gets its own
`pr-unblock-target-dispatched-<commit>-<run id>` record, so one run may hold two; the gate and the
broker each accept the record that names their own run. The invariants and the checks above are
unchanged. The list is empty by default, and in this repository.

## Alternatives considered

- **Start Refine from a `pull_request` run.** Its file and checkout come from the PR head, so a
  PR could rewrite the dispatcher that vouches for it.
- **Keep the tick only.** That costs the wait this change removes.

## Consequences

- The `pull_requests` list is live data, read when the gate runs. A pull request retargeted to
  `main` after its event run still matches the entry. Retargeting needs write access to this
  repository, and the dispatched Refine runs `main`'s code either way.
- `dispatcher-current.sh` runs before the record may exist, and leaves that run to the broker.
- The once-per-PR rule stays in `fix-docs-dispatch.mjs`, and the event dispatcher applies it
  before it dispatches (`refine-event-dispatch.mjs`); in `pr-refine.yml` it would also stop a
  person's dispatch, which that file allows. The event dispatcher also skips an event whose
  sender is not the lanes App or a listed human, since the gate would refuse that run.
