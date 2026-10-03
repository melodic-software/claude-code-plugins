# Stuck Checks

Routing for checks that degrade `mergeStateStatus` to `UNSTABLE` without ever completing, blocking
a clean merge-readiness read even when every REQUIRED check is green, and for checks held for
approval (§Held For Approval). Use this only when the snapshot reports a non-empty `checks.stuck`
or `checks.approval_held` array for a PR. That field is the queue signal, and it
is a **report/escalation** signal, never an auto-fix trigger.

## The Queue Signal

The snapshot engine classifies stuck checks from data it already normalizes, with no extra GitHub
fetch. Each PR carries `checks.stuck[]`, always present (empty when none), where each entry is
`{name, type, class, target_url, details_url, age_seconds}`. `age_seconds` is the check's age at
snapshot time in seconds, or **`null`** when no inception timestamp is known, which is expected for
`orphaned_status` entries from apps that post a pending status without a `createdAt`, which is also
why that class is detected structurally rather than by age. Detection fires only under
`mergeStateStatus == UNSTABLE`. That state's own contract, "mergeable, every REQUIRED gate
satisfied, a non-required commit status not passing", is why a stuck non-required check is not a
required-check failure; the same fact is stated for the single-PR lifecycle in the pull-request
skill's [readiness reference](../../pull-request/reference/readiness.md) (the `codex-review`
duplicate-row gotcha). Because detection is gated on `UNSTABLE`, every check reaching a stuck class
is non-required by construction: the merge-state gate supplies the required/non-required split, so
no per-check required flag is needed.

The engine surfaces the same signal as a `material_findings` entry, **never a `blockers` string**.
That distinction matters: a blocker would pin `classification == active` and re-dispatch a
worker every cycle for a check no branch action can clear. A material finding reports and escalates
without re-firing the fan-out.

### The three classes

| `class` | Shape | Age-gated | Typical root cause |
| --- | --- | --- | --- |
| `orphaned_status` | `StatusContext`, pending, empty `target_url`, so no backing run to cancel | no | An external app posted a pending commit status that never resolves and has no run to settle it |
| `stuck_queued` | `CheckRun` still `QUEUED` past the age threshold | yes | An Actions job on an unmatched self-hosted runner label, so nothing will ever pick it up |
| `never_settling` | Any other pending check past the age threshold | yes | A non-required check that holds `UNSTABLE` without ever finishing |

Report a `stuck_queued` entry as **queued**, not as a slow-running job. Name the runner-pool
contention when the snapshot or a jobs-API read supplies it: the job's `runs-on` labels, how long
it has been queued, and occupancy (`N/M busy`) when the token can list runners. Queued-versus-running
calls for different operator action on a capacity-constrained pool: a running job is the change's
own time, a queued job behind a busy pool is fleet capacity, and a queued job with no online runner
for its label is the unmatched-label case this class already names. Never wait on it with
`gh pr checks --watch`; a long wait is a REST poll per the pull-request
[monitor reference](../../pull-request/reference/monitor.md) "Waiting on a pending check".

The age threshold is `--stuck-check-age-seconds` (default 30 minutes), so normal in-flight CI and
freshly-started non-required checks are never reported. `orphaned_status` has no backing run, thus
no start time to age against, and so is detected structurally, not by age. A pending check whose
inception time is unknown (a QUEUED `CheckRun` gh reports without `startedAt`) is left unflagged for
the age-gated classes rather than reported on an unprovable age.

## Held For Approval

A separate signal from `checks.stuck`: the snapshot's `checks.approval_held[]`, always present,
lists each rollup entry concluded `ACTION_REQUIRED` as `{name, type, workflow_name, class:
"awaiting_approval", details_url}`, in any merge state. That is the conclusion of a workflow run
waiting for a maintainer's approval, such as a fork PR from a first-time or outside contributor
under the repository's approval setting, and of a check asking for a manual action. GitHub Actions
also holds a run it judges potentially malicious in a public repository until a collaborator with
write access approves it in an authenticated web session; GitHub has not said which conclusion
that run carries, so when a run is missing or never starts, read the PR's checks page before
treating the PR as waiting on CI.

No push, re-run, or wait releases any of these, and an unattended agent cannot approve them:

- The engine reports them as a `material_findings` entry. They are not counted in the
  `failing check(s)` blocker or the new-failing-check worker arm, so no worker is sent to fix them.
- They stay `failing` in the rollup, so the merge gate keeps holding.
- Escalate to a maintainer with the PR and the run's link. Never approve a run, through the API or
  otherwise: approval runs the PR's code with the repository's secrets, and that is the decision
  the hold reserves for a person.

**Claim, basis, as of, recheck:** fork-run approval and the malicious-run hold, including who may
approve and where,
[approving workflow runs from forks](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/approve-runs-from-forks)
and [Actions holds potentially malicious workflows](https://github.blog/changelog/2026-07-28-github-actions-holds-potentially-malicious-workflows-for-approval);
2026-10-02. Recheck when GitHub names the status a held run carries, adds an API route for the
malicious-run hold, or changes either page.

## Not Stuck: Never Scheduled

A different failure with the same surface complaint ("CI is not finishing"), and the two are
distinguished by the merge state, not by the check list. Everything above concerns checks that are
PRESENT and never settle, detected only under `UNSTABLE`. This section is the opposite: checks that
never appear at all, under `DIRTY`.

**Its queue signal is therefore not `checks.stuck`, which is empty here by construction.** A
conflicted PR surfaces as `branch_freshness.state == "conflicting"` (`DIRTY` or `CONFLICTING`, per
`compute_branch_freshness` in [`../scripts/babysit_delta.py`](../scripts/babysit_delta.py)), and
that state is this section's entry condition. [`runbook-cycle.md`](runbook-cycle.md) names it
alongside the non-empty-`checks.stuck` trigger for loading this file.

A `pull_request` workflow runs against a merge ref GitHub computes by merging the head into the
base. When the PR is conflicted there is no such ref to compute, so those workflows are never
scheduled. They are **absent**, not queued, not pending, not failing. Nothing in `checks.stuck`
reports them, because a check that was never created has no record to classify.

What makes this actively misleading is that `pull_request_target` workflows run against the base
commit and are therefore unaffected, as are external apps posting commit statuses and any
`schedule` or `push` lane. A conflicted PR in a repository that splits its lanes that way still
runs the base-anchored ones while the `pull_request` workflow carrying the great majority of the
gates does not schedule at all. The result is a short all-green check list with no failures
anywhere: a PR that reads as "passing" or "not started yet" while nearly every gate is simply
missing. Resolving the conflict makes the absent lanes appear and the count jumps.

So read `mergeStateStatus` BEFORE reasoning about a check list that looks too short. `DIRTY`
explains the absence completely, and the remedy is to merge the base branch or rebase, not to
investigate CI. Diagnosing the missing lanes as a trigger, permissions, or App-token problem is
time spent on a mechanism that is not involved.

The event split is a repo fact, not a constant: derive it by reading the `on:` blocks under
`.github/workflows/` rather than trusting any count written down, since a lane added tomorrow
changes which side it lands on.

## Before Acting: Confirm Required-Green

`UNSTABLE` alone does not prove the required gates are green for THIS decision. Re-confirm against
the guarded merge wrapper's own read rather than inferring it: [`../scripts/babysit_merge.py`](../scripts/babysit_merge.py)
emits a `requiredChecks` field in its snapshot JSON. Only once required checks are green is a stuck
non-required check the sole thing holding `UNSTABLE`, and even then the merge gate correctly
refuses `UNSTABLE` and forbids any `--admin` / `gh pr merge` bypass. This auditor is the clean path
to escalate that state, not a route around the gate.

## Routing: Never Auto-Fix

Cancelling a stuck check makes it worse (`CANCELLED` is a failure state). Remediation is a
judgment call the orchestrator escalates; the categories map to different owners:

- **Branch-CI-config-fixable** (e.g. a wrong `runs-on:` label in the PR branch's own workflow YAML):
  this rides the normal `head_sha_changed` delta: a corrected workflow is a new commit, and the
  next snapshot re-reads checks for the new head. Route the fix to that workflow. When the
  label is organization-owned, read the standards `runner-policy` component vendored at
  `.github/standards/runner-policy/policy.json` and `docs/ci-runner-routing.md`, and edit the
  approved-label list those record rather than guessing a workflow name.
- **Org/settings-class** (an unmatched self-hosted runner pool, an orphaned external status, branch
  protection): route to `github-iac` / the posting app's configuration. These stay
  `material_findings` and are escalated, never auto-fixed from a babysit worker.

Any of these that "belongs in an upstream source-of-truth repository" or touches runners, an
external app's settings, or branch protection is a Stop-and-Ask / Never-Do-Automatically condition:
[`safety.md`](safety.md) is the single home for those lists. Confirm role boundaries there before
escalating.
