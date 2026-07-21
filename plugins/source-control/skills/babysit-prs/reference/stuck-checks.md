# Stuck Checks

Routing for checks that degrade `mergeStateStatus` to `UNSTABLE` without ever completing, blocking
a clean merge-readiness read even when every REQUIRED check is green. Use this only when the
snapshot reports a non-empty `checks.stuck` array for a PR — that field is the queue signal, and it
is a **report/escalation** signal, never an auto-fix trigger.

## The Queue Signal

The snapshot engine classifies stuck checks from data it already normalizes — no extra GitHub
fetch. Each PR carries `checks.stuck[]`, always present (empty when none), where each entry is
`{name, type, class, target_url, details_url, age_seconds}`. Detection fires only under
`mergeStateStatus == UNSTABLE`. That state's own contract — "mergeable, every REQUIRED gate
satisfied, a non-required commit status not passing" — is why a stuck non-required check is not a
required-check failure; the same fact is stated for the single-PR lifecycle in the pull-request
skill's [readiness reference](../../pull-request/reference/readiness.md) (the `codex-review`
duplicate-row gotcha). Because detection is gated on `UNSTABLE`, every check reaching a stuck class
is non-required by construction — the merge-state gate supplies the required/non-required split, so
no per-check required flag is needed.

The engine surfaces the same signal as a `material_findings` entry, **never a `blockers` string**.
That distinction is load-bearing: a blocker would pin `classification == active` and re-dispatch a
worker every cycle for a check no branch action can clear. A material finding reports and escalates
without re-firing the fan-out.

### The three classes

| `class` | Shape | Age-gated | Typical root cause |
| --- | --- | --- | --- |
| `orphaned_status` | `StatusContext`, pending, empty `target_url` — no backing run to cancel | no | An external app posted a pending commit status that never resolves and has no run to settle it |
| `stuck_queued` | `CheckRun` still `QUEUED` past the age threshold | yes | An Actions job on an unmatched self-hosted runner label — nothing will ever pick it up |
| `never_settling` | Any other pending check past the age threshold | yes | A non-required check that holds `UNSTABLE` without ever finishing |

The age threshold is `--stuck-check-age-seconds` (default 30 minutes), so normal in-flight CI and
freshly-started non-required checks are never reported. `orphaned_status` has no backing run — thus
no start time to age against — and so is detected structurally, not by age. A pending check whose
inception time is unknown (a QUEUED `CheckRun` gh reports without `startedAt`) is left unflagged for
the age-gated classes rather than reported on an unprovable age.

## Before Acting — Confirm Required-Green

`UNSTABLE` alone does not prove the required gates are green for THIS decision. Re-confirm against
the guarded merge wrapper's own read rather than inferring it: [`../scripts/babysit_merge.py`](../scripts/babysit_merge.py)
emits a `requiredChecks` field in its snapshot JSON. Only once required checks are green is a stuck
non-required check the sole thing holding `UNSTABLE` — and even then the merge gate correctly
refuses `UNSTABLE` and forbids any `--admin` / `gh pr merge` bypass. This auditor is the clean path
to escalate that state, not a route around the gate.

## Routing — Never Auto-Fix

Cancelling a stuck check makes it worse (`CANCELLED` is a failure state). Remediation is a
judgment call the orchestrator escalates; the categories map to different owners:

- **Branch-CI-config-fixable** (e.g. a wrong `runs-on:` label in the PR branch's own workflow YAML):
  this rides the normal `head_sha_changed` delta — a corrected workflow is a new commit, and the
  next snapshot re-reads checks for the new head. Route the fix to the branch's own workflow, or to
  the shared runner selection in the `ci-workflows` repo (`select-runner`) when the label policy is
  org-owned, not branch-owned.
- **Org/settings-class** (an unmatched self-hosted runner pool, an orphaned external status, branch
  protection): route to `github-iac` / the posting app's configuration. These stay
  `material_findings` and are escalated — never auto-fixed from a babysit worker.

Any of these that "belongs in an upstream source-of-truth repository" or touches runners, an
external app's settings, or branch protection is a Stop-and-Ask / Never-Do-Automatically condition:
[`safety.md`](safety.md) is the single home for those lists. Confirm role boundaries there before
escalating.
