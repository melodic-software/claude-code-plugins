# Posting lanes and overlapping runs

Record for the loop-lane convention's [confirm-then-record pattern](README.md#confirm-then-record).
It lists each lane with an external side effect (a comment, label, issue, check, merge or release)
and says what stops two overlapping runs of it from both passing a check-then-act dedupe. Research
only: it changes no lane. As of 2026-10-19, read from `.github/workflows/*.yml` on the default
branch.

**Recheck trigger**: a workflow is added, or one gains or loses a `concurrency:` block or a write
permission. Re-read the rows for the workflows that changed.

Marks: **concurrency** (a workflow `concurrency:` group), **claim** (another atomic claim, named),
**uncovered** (neither; the row gives the reason overlap cannot happen or cannot do harm).

## Workflow lanes

| Lane (workflow) | External writes | Mark |
|---|---|---|
| `work-resolve-issue` | PR, issue comment | concurrency: `work-resolve-issue-<issue>-<is agent-ready label>`, `cancel-in-progress: false` |
| `intake-triage` | issue labels, comments | concurrency: `intake-triage-<issue>` |
| `pr-unblock` (write activities, through `pr-run-activity-write`) | PR comments, pushes, checks | concurrency: `pr-pipeline-write-<pr>`, `queue: max` |
| `pr-unblock` (the dispatching workflow itself) | none beyond the above | concurrency: `pr-unblock-<activity>-<pr>` |
| `pr-refine` (write activity `apply-patch`, through `pr-run-activity-write`) | pushes, checks | concurrency: `pr-pipeline-write-<pr>`, `queue: max` |
| `pr-refine` (the dispatching workflow itself) | none beyond the above | concurrency: `pr-refine-<activity>-<pr>` |
| `pr-unblock-dispatch`, `pr-feedback-dispatch` | start `pr-unblock` runs; `pr-unblock-dispatch` also starts `pr-refine` runs | concurrency: `pr-unblock-dispatch`; `pr-feedback-dispatch-<head sha>` |
| `pr-review-hosted`, `pr-review-security-hosted` | review comments, check | concurrency: `<workflow>-<pr>`, `cancel-in-progress: true` |
| `pr-check-managed-files-hosted`, `pr-verify` | read-only token at job level; no comment or label write found | concurrency (per PR or head sha); not verified to post |
| `pr-require-checks` | statuses; the advisory linkage comment and the `needs-issue-linkage` label (`check-contract`); re-runs of red contract-only sibling runs (`actions: write`) | uncovered. Label and body-edit events take a per-run group (`ci-contract-<pr>-<run_id>`), so those runs do not serialize. Each status write is a fresh set, not a check-then-act. The comment upsert is check-then-act: it looks up the newest bot comment carrying the `<!-- pr-contract:linkage -->` marker, so two overlapping runs that both find none each post one, and every later run edits only the newest. The duplicate is an advisory comment a person can ignore; the gate is the status, not the comment. A label add or remove is idempotent, and the next contract event re-derives it from the current body. A duplicate sibling re-run repeats the contract check, whose writes are covered above |
| `pr-run-activity-write` (reusable; called by `pr-unblock`, `pr-refine` and `work-resolve-issue`) | the caller's writes | covered by the caller's group: `pr-pipeline-write-<pr>` (`queue: max`) on the `pr-unblock` and `pr-refine` jobs; the `work-resolve-issue-<issue>-<is agent-ready label>` run group for `work-resolve-issue`, whose `resolve-issue` job also queues on `work-resolve-issue-slot-<slot>` |
| `pr-run-activity-read` (reusable; PR-mode callers the `pr-unblock` `fix-ci` and `fix-ci-subscription` jobs and the `pr-refine` `fix-docs` and `fix-docs-subscription` jobs) | a check run; a patch artifact that `apply-patch` pushes through `pr-run-activity-write`; a call that hands off to its `-subscription` job posts neither | concurrency: the caller's run group `pr-unblock-<activity>-<pr>` or `pr-refine-<activity>-<pr>`, `cancel-in-progress: false`, and each call's job group `pr-pipeline-write-<pr>` with `queue: max`, which differs from the run group, so neither waits on its own run |
| `pr-merge` | merge | concurrency: `pr-merge`, `queue: max` |
| `dependabot-fragments` | fragment commit | concurrency: `dependabot-fragments` |
| `maintenance-audit-lane-runs`, `maintenance-audit-test-selection` | audit report | concurrency: own named group (the second on one job only; its other job is read-only) |
| `maintenance-file-upstream-drift-issues` | files issues | concurrency: `maintenance-file-upstream-drift-issues` |
| `maintenance-monitor-signals` | files issues, comments on, edits, closes and reopens its own | concurrency: `maintenance-monitor-signals`, `cancel-in-progress: false` |
| `post-merge-demotion-alert` | alert issue or comment | concurrency: per workflow, event and head sha |
| `release-publish-plugins` | releases, tags | concurrency: `release-plugins` (`cancel-in-progress: true`, so a newer run can cancel one mid-publish) |
| `intake-reenter` | removes a parked status label and `needs-human`, adds `needs-triage`, starts an `intake-triage` run for an issue intake admits | concurrency: `intake-reenter-<issue>`, `queue: max`; claim: removing the status label, where a 404 means another run took it and nothing is dispatched |
| `intake-label-needs-triage` | adds the `needs-triage` label | uncovered. It runs once per `opened` or `reopened` event, and adding a label the issue already carries adds nothing, so two runs on one issue leave the same label set. It posts no comment and creates no record |
| `work-unblock` | adds `agent-ready`; on the schedule sweep also re-fires and posts a marker comment | uncovered. The close-event run only adds the label, and a label already present is left alone (the script header); a second add starts a `work-resolve-issue` run, which that lane's group serializes per issue. The re-fire and its record comment run only on the hourly schedule, which has a 10-minute job timeout and no `workflow_dispatch`, so two scheduled sweeps overlap only if GitHub delays a run past the next hour or someone re-runs one by hand. The re-fire record is then a duplicate comment and a second `agent-ready` re-add, which the `work-resolve-issue` group serializes. The sweep also adds `needs-human`, a label add that changes nothing when present |
| `eval-browser-dispatch`, `maintenance-check-links-online-claude-code-plugins` (sync-managed from standards), `maintenance-check-upstream-drift`, `post-merge-detect-silent-revert`, `pr-test-windows` | none (read-only token) | not a posting lane |

## Local loop lanes

| Lane | External writes | Mark |
|---|---|---|
| `work-loop` | claims, PRs, comments | claim: the tracker seam `claim` verb (assignee plus lease comment; a foreign earlier lease backs off, per the work-items tracker `CONTRACT.md` "Lease protocol") |
| `attend-queue` | comments, labels | claim: the marker partition and the lane-instance suffix (§4 "Lane-instance identity"), so a lane edits only its own comment |
| `babysit-loop` | PR comments, labels | claim: the PR's worker lease (§1) |
| Telemetry comment (every loop lane) | one comment per instance, edited in place | claim: the `<lane-marker>@<lane_instance>` marker names the writer; a racing instance never edits another's comment (§4) |
| Escalation record and marker (§2) | record file, marker comment | not atomic across runs by design: a stop between the two writes re-escalates the next cycle, a duplicate a person can discard |

No follow-up issue is filed: each uncovered row above states why overlap cannot do harm.
