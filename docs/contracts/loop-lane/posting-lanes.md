# Posting lanes and overlapping runs

Record for the loop-lane convention's [confirm-then-record pattern](README.md#confirm-then-record).
It lists each lane with an external side effect (a comment, label, issue, check, merge or release)
and says what stops two overlapping runs of it from both passing a check-then-act dedupe. Research
only: it changes no lane. It is read from `.github/workflows/*.yml` on the default branch.

**Recheck trigger**: a workflow is added, or one gains or loses a `concurrency:` block or a write
permission. Re-read the rows for the workflows that changed.

Marks: **concurrency** (a workflow `concurrency:` group), **claim** (another atomic claim, named),
**uncovered** (neither; the row gives the reason overlap cannot happen or cannot do harm).

## Workflow lanes

| Lane (workflow) | External writes | Mark |
|---|---|---|
| `work-resolve-issue` | PR, issue comment | concurrency: `work-resolve-issue-<issue>-<is agent-ready label>`, `cancel-in-progress: false` |
| `intake-triage` | issue labels, comments; its `apply-verdict` job also writes the Work status, Size, Complexity and Uncertainty fields | concurrency: `intake-triage-<issue>`; `apply-verdict`: `intake-apply-verdict-<issue>` |
| `pr-unblock` (write activities, through `pr-run-activity-write`) | PR comments, pushes, checks | concurrency: `pr-pipeline-write-<pr>`, `queue: max` |
| `pr-unblock` (the dispatching workflow itself) | none beyond the above | concurrency: `pr-unblock-<activity>-<pr>` |
| `pr-refine` (write activity `apply-patch`, through `pr-run-activity-write`) | pushes, checks | concurrency: `pr-pipeline-write-<pr>`, `queue: max` |
| `pr-refine` (the dispatching workflow itself) | none beyond the above | concurrency: `pr-refine-<activity>-<pr>` |
| `pr-unblock-dispatch`, `pr-feedback-dispatch` | start `pr-unblock` runs; `pr-unblock-dispatch` also starts `pr-refine` runs | concurrency: `pr-unblock-dispatch`; `pr-feedback-dispatch-<head sha>` |
| `pr-review-hosted`, `pr-review-security-hosted` | review comments, check | concurrency: `<workflow>-<pr>`, `cancel-in-progress: true` |
| `pr-check-managed-files-hosted`, `pr-verify` | read-only token at job level; no comment or label write found | concurrency (per PR or head sha); not verified to post |
| `pr-require-checks` | statuses; the advisory linkage comment and the `needs-issue-linkage` label (`check-contract`); re-runs of red contract-only sibling runs (`actions: write`) | uncovered. Label and body-edit events take a per-run group (`ci-contract-<pr>-<run_id>`), so those runs do not serialize. Each status write is a fresh set, not a check-then-act. The comment upsert is check-then-act: it looks up the newest bot comment carrying the `<!-- check-contract:linkage -->` marker, so two overlapping runs that both find none each post one, and every later run edits only the newest. The duplicate is an advisory comment a person can ignore; the gate is the status, not the comment. A label add or remove is idempotent, and the next contract event re-derives it from the current body. A duplicate sibling re-run repeats the contract check, whose writes are covered above |
| `pr-run-activity-write` (reusable; called by `pr-unblock`, `pr-refine` and `work-resolve-issue`) | the caller's writes | covered by the caller's group: `pr-pipeline-write-<pr>` (`queue: max`) on the `pr-unblock` and `pr-refine` jobs; the `work-resolve-issue-<issue>-<is agent-ready label>` run group for `work-resolve-issue`, whose `resolve-issue` job also queues on `work-resolve-issue-slot-<slot>` |
| `pr-run-activity-read` (reusable; PR-mode callers the `pr-unblock` `fix-ci` and `fix-ci-subscription` jobs and the `pr-refine` `fix-docs` and `fix-docs-subscription` jobs) | a check run; a patch artifact that `apply-patch` pushes through `pr-run-activity-write`; a call that hands off to its `-subscription` job posts neither | concurrency: the caller's run group `pr-unblock-<activity>-<pr>` or `pr-refine-<activity>-<pr>`, `cancel-in-progress: false`, and each call's job group `pr-pipeline-write-<pr>` with `queue: max`, which differs from the run group, so neither waits on its own run |
| `pr-merge` | merge | concurrency: `pr-merge`, `queue: max` |
| `release-generate-dependabot-changelog-fragments` | fragment commit | concurrency: `dependabot-fragments` |
| `maintenance-audit-lane-runs`, `maintenance-audit-test-selection` | audit report | concurrency: own named group (the second on one job only; its other job is read-only) |
| `maintenance-file-upstream-drift-issues` | files issues | concurrency: `maintenance-file-upstream-drift-issues` |
| `maintenance-file-recurring-issues` | files issues | concurrency: `maintenance-file-recurring-issues`, `cancel-in-progress: false` |
| `maintenance-monitor-signals` | files issues, comments on, edits, closes and reopens its own | concurrency: `maintenance-monitor-signals`, `cancel-in-progress: false` |
| `post-merge-file-demotion-issues` | alert issue or comment | concurrency: per workflow, event and head sha |
| `post-merge-test-mutation` | one report comment on the pull request that merged the pushed head, only when the result has a surviving or uncovered mutant, from the model-free `report` job; any other outcome is in the job summary, and a refusal or an all-not-run result is a `::warning::` annotation | concurrency: `post-merge-test-mutation-<head sha>`, `cancel-in-progress: false`. The comment upsert is check-then-act on the `<!-- post-merge-test-mutation -->` marker from `github-actions[bot]`, edited in place on a re-run; the group serializes runs for one head, and a pull request merges one head |
| `release-publish-plugins` | release commit on `release/plugins` through a staging branch, opens and edits the release pull request, queues or merges it | concurrency: `release-plugins` (`cancel-in-progress` on scheduled and dispatched runs, so one can cancel a run between its head write and pull request edit; a push run waits) |
| `intake-reenter` | on an answer: removes the answered status label when the issue still carries it (never `needs-human`, which only a listed human removes), sets Work status to `needs-triage`, starts an `intake-triage` run for an issue intake admits; on a listed human's release of a Work status hold: posts a marked record comment, sets Work status to `needs-triage` when the release emptied it, starts the same run, and writes no label. On an answer, a failed later call sets Work status back and puts back the label it took; on a field release, it deletes the record it posted and leaves Work status as written | concurrency: `intake-reenter-<issue>`, `queue: max`; claim: removing the status label, where a 404 means another run took it and nothing is dispatched; with no label to take, Work status at `needs-triage`, which a second run reads and stops at; on a field release, the record comment `<!-- intake-reenter:release <actor id> <event time> -->`, keyed to the field event that left the hold, which a re-run of that release finds and dispatches nothing, while a later release starts a run again. An issue `work-unblock` hands back goes to intake through the hourly triage sweep, not this lane |
| `intake-triage` (its `intake-label-needs-triage` job) | adds the `needs-triage` label to an issue opened or reopened with no `priority:*` label, unless the born-triaged gate (which reads the labels with Work status) skips it; writes no Work status | uncovered. It runs once per `opened` or `reopened` event, and adding a label the issue already carries adds nothing, so two runs on one issue leave the same label set. It posts no comment and creates no record |
| `work-unblock` | `label-unblocked`: sets Work status (`agent-ready` before adding the `agent-ready` label, `deferred` past the queued cap, `confirmed` for a done-check park or a failed stop, `needs-triage` on a hand-back, the refused state on a refusal), adds `agent-ready` and `attended`, takes legacy status labels and its own refs-hold `needs-human` off, posts admission, hand-back and re-fire comments. `sync-status`: writes the state of a status label a listed human adds into Work status unless the field holds, and `confirmed` when one removes `agent-ready` while the field reads `agent-ready` | concurrency: `work-unblock-label-unblocked`, `cancel-in-progress: false`, one run across the repository; a newer waiting run replaces an older one, whose work the next sweep repeats. `sync-status`: `work-unblock-sync-status-<issue>`, `queue: max`. A non-hold Work status write keeps a hold a person set since the read. A second `agent-ready` add starts a `work-resolve-issue` run, which that lane's group serializes per issue |
| `pr-run-plugin-evals`, `maintenance-check-links-online` (sync-managed from standards), `maintenance-check-upstream-drift`, `post-merge-detect-silent-revert`, `post-merge-select-mutation-range`, `pr-test-platforms` | none (read-only token) | not a posting lane |

## Local loop lanes

| Lane | External writes | Mark |
|---|---|---|
| `work-loop` | claims, PRs, comments | claim: the tracker seam `claim` verb (assignee plus lease comment; a foreign earlier lease backs off, per the work-items tracker `CONTRACT.md` "Lease protocol") |
| `attend-queue` | comments, labels | claim: the marker partition and the lane-instance suffix (§4 "Lane-instance identity"), so a lane edits only its own comment |
| `babysit-loop` | PR comments, labels | claim: the PR's worker lease (§1) |
| Telemetry comment (every loop lane) | one comment per instance, edited in place | claim: the `<lane-marker>@<lane_instance>` marker names the writer; a racing instance never edits another's comment (§4) |
| Escalation record and marker (§2) | record file, marker comment | not atomic across runs by design: a stop between the two writes re-escalates the next cycle, a duplicate a person can discard |

No follow-up issue is filed, because each uncovered row above states why overlap cannot do harm.
