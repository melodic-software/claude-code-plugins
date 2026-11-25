# Lifecycle map

Each automated task in this repository's delivery lifecycle, from a new issue to a merged pull
request and on into post-merge, release and maintenance work. A task is one workflow in
`.github/workflows/`, or one distinct job or activity inside one. The rules each lane follows live
in [the PR pipeline contract](../pr-pipeline/README.md) and `docs/conventions/pr-pipeline.yaml`;
this map only places the tasks.

This map is a point-in-time snapshot, written by hand. **As of**: 2026-11-25, every
`.github/workflows/*.yml` file has a row, named in its Task cell or its Shape cell. No check
compares the map with that directory, so a workflow added, renamed or removed since then may be
missing or out of date here. **Recheck trigger**: a pull request that adds, renames or removes a
file in `.github/workflows/`, or changes a workflow's triggers, jobs or outputs; update the rows
and the as-of date in the same pull request.

## Columns

- **Task**: what runs, and the workflow file that runs it.
- **Shape**: `own run` starts its own workflow run; `own run after X` starts one when workflow X
  completes (`workflow_run`); `step in X` runs only as a job or called workflow inside X's run.
- **Component**: the part of the delivery system whose work the task does:
  - `tracker`: issue state (filing, labels, fields, issue comments);
  - `git host`: branches, pull request content, merges and releases;
  - `runner`: checks and test or review runs on a commit;
  - `orchestrator`: decides which run starts next and starts it, doing none of its work;
  - `observability`: reads runs and state and writes only reports, digests or incident issues.
- **Model**: `yes` when the task runs a Claude model, `no` when it runs scripts only.
- **Trigger**, **Inputs** and **Outputs**: the events that start it, what it reads and what it
  writes.

## Intake

| Task | Shape | Component | Model | Trigger | Inputs | Outputs |
|---|---|---|---|---|---|---|
| Flag outside-actor activity (`intake-label-outside-actor-activity.yml`) | own run | tracker | no | `issues`, `issue_comment`, `pull_request_review`, `pull_request_review_comment` and `pull_request_target` events | event payload; trusted-actor list on main | `security: outside-actor` label; Work status `needs-human` or the PR's `needs-human` label; one comment per outside actor |
| Send an answered issue back to intake (`intake-reenter.yml`) | own run | tracker | no | `issue_comment` created; `issues` unlabeled, field added or removed | comment and issue read from the API; label and field history | status label removed; Work status `needs-triage`; a reply comment; an `intake-triage.yml` dispatch |
| Intake gate and floor label | step in `intake-triage.yml` | tracker | no | `issues` opened or reopened; `workflow_dispatch` with an issue number | issue labels; kill switch | skips an issue that has a routing label; `needs-triage` when no priority label is set |
| Triage verdict | step in `intake-triage.yml` | tracker | yes | the gate passes | issue; trusted comments | labels, triage comment, Size, Complexity and Uncertainty fields and a status label, written by the lanes App |
| Admission | step in `intake-triage.yml` | orchestrator | no | the verdict is applied | `admission-rules.json`; lane caps | `agent-ready`, which starts `work-resolve-issue.yml`, or `admission-deferred` |
| Refinement | step in `intake-triage.yml` | tracker | yes | a thin issue, or done-when items admission parked | issue body | refinement comment; a re-triage dispatch |
| Size split | step in `intake-triage.yml` | tracker | yes | an issue with Size Large | issue done-when items | sub-issues, each dispatched to triage, or a comment declining the split |
| Hourly triage sweep | step in `maintenance-audit-lane-runs.yml` | tracker | no | schedule, hourly | issues waiting for intake | `needs-triage` and a comment; `intake-triage.yml` dispatches |

## Work on an issue

| Task | Shape | Component | Model | Trigger | Inputs | Outputs |
|---|---|---|---|---|---|---|
| Resolve an issue (`work-resolve-issue.yml`) | own run | git host | yes | `issues` field added: Work status `agent-ready` | issue, field state, blockers, admission rules | patch committed to a new branch; a ready PR, or an issue comment routing the stop; `pipeline/<step>` statuses |
| Unblock issues and re-fire runs | step in `work-unblock.yml` | orchestrator | no | `issues` closed; schedule; after `work-resolve-issue.yml` completes; `workflow_dispatch` | blocked issues and their blockers; work-resolve-issue runs | Work status `agent-ready` on issues whose blockers all closed; a park at Work status `confirmed`; a `needs-triage` hand-back comment |
| Clear a closed issue's queue labels | step in `work-unblock.yml` | tracker | no | `issues` closed | the closed issue's labels | `agent-ready`, `status: ready` and `admission-deferred` removed |
| Sync status labels to Work status | step in `work-unblock.yml` | tracker | no | `issues` labeled or unlabeled | the status label a listed human added | Work status field set to match |
| Publish the issue lane's concurrency level | step in `work-unblock.yml` | orchestrator | no | schedule, hourly | the sweep's lanes App readings; runs in progress; the last decision | one repository variable, `<level>@<valid-until>` |

## Pull request checks and reviews

| Task | Shape | Component | Model | Trigger | Inputs | Outputs |
|---|---|---|---|---|---|---|
| Required CI (`pr-require-checks.yml`) | own run | runner | no | `pull_request` events; `merge_group`; schedule; `workflow_dispatch` from `pr-merge.yml` | PR diff, labels, title and linkage; repository files | check runs, including the required `CI Status`; `ci-lanes` status; linkage comment and label |
| Windows and macOS tests (`pr-test-platforms.yml`) | own run | runner | no | `pull_request` events; schedule; `workflow_dispatch` | PR diff; Windows test plan | informational job checks |
| Managed-file check (`pr-check-managed-files-hosted.yml`) | own run | runner | no | `pull_request` opened, synchronize, reopened | PR file list; standards sync manifest | advisory check `PR Check Managed Files` |
| Code review (`pr-review-hosted.yml`) | own run | runner | yes | `pull_request` opened, synchronize, ready, reopened | PR diff; closing issues | review and inline comments; reviewed-head marker; `pr-review / claude-review-status` check |
| Security review (`pr-review-security-hosted.yml`) | own run | runner | yes | `pull_request` opened, synchronize, ready, reopened | PR diff | security review comments and check |
| Review from main for lane-source changes (`pr-review-main.yml`) | own run after `pr-require-checks.yml` | runner | yes | PR Require Checks completes off main | diff; trusted PR text and criteria | review verdict artifact the merge gate reads; a count check run |
| Verify a head against its issue (`pr-verify.yml`) | own run after `pr-require-checks.yml` | runner | yes | PR Require Checks completes off main | diff; trusted PR text; linked issues | `pass`, `pass-notes` or `fail` verdict artifact; a `pr-merge.yml` dispatch on a pass |
| Rate merge risk (`pr-rate-merge-risk.yml`) | own run after `pr-require-checks.yml` | observability | yes | PR Require Checks completes on a lane branch | PR data files | rating artifact |
| Plugin evals (`pr-run-plugin-evals.yml`) | own run, or after `pr-run-plugin-evals-label.yml` | runner | yes | `workflow_dispatch`; the `eval: run` label relay completes | plugin eval suites; PR head diff | job summary and results artifact; in compare mode an eval-pair record on the PR |
| Relay the `eval: run` label (`pr-run-plugin-evals-label.yml`) | own run | orchestrator | no | `pull_request` labeled | label event | a completion that starts `pr-run-plugin-evals.yml` |
| One skill-edit eval pass (`maintenance-measure-skill-edit-pass.yml`) | step in `maintenance-measure-skill-edit.yml` or `pr-run-plugin-evals.yml` | runner | yes | called by those workflows | main checkout; an edit patch artifact | pass artifact with scores and verdicts |
| Run a lane read activity (`pr-run-activity-read.yml`) | step in `pr-refine.yml`, `pr-unblock.yml` or `work-resolve-issue.yml` | runner | yes | called by those workflows | lane, activity, PR or issue, PR head | `<lane> / <activity>` check run; patch and transcript artifacts |
| Run a lane write activity (`pr-run-activity-write.yml`) | step in `pr-refine.yml`, `pr-unblock.yml` or `work-resolve-issue.yml` | git host | no | called by those workflows | lane, activity, patch artifacts | the activity's write (push, PR, comment or label); a check run |

## Unblocking pull requests

| Task | Shape | Component | Model | Trigger | Inputs | Outputs |
|---|---|---|---|---|---|---|
| Dispatch unblock and refine activities (`pr-unblock-dispatch.yml`) | own run | orchestrator | no | push to main; schedule; `pull_request_target` events; `workflow_dispatch` | open PRs; check runs; dispatch record | `pr-unblock.yml` and `pr-refine.yml` dispatches |
| Dispatch feedback after reviews (`pr-dispatch-feedback.yml`) | own run after seven workflows | orchestrator | no | PR Review Hosted, PR Review Security Hosted, PR Verify, PR Unblock Dispatch, PR Merge, PR Review Approved or PR Review Comment Relay completes | upstream run facts; PR threads and verdict artifacts | `pr-unblock.yml` address-feedback dispatches; `ci-status` re-runs |
| Post verify notes | step in `pr-dispatch-feedback.yml` | git host | no | PR Verify completes | verify verdict artifact | verify-note review comments; `pr-verify-failed` label on a person's PR |
| Relay an approving review (`pr-review-approved.yml`) | own run | orchestrator | no | `pull_request_review` submitted | review event | a completion that starts `pr-dispatch-feedback.yml` |
| Relay a review comment (`pr-review-comment-relay.yml`) | own run | orchestrator | no | `pull_request_review_comment` created | comment event | a completion that starts `pr-dispatch-feedback.yml` |
| Resolve merge conflicts | step in `pr-unblock.yml` | git host | yes | `workflow_dispatch`, activity `resolve-conflicts` | PR head and base | merge pushed to the PR branch |
| Address review feedback | step in `pr-unblock.yml` | git host | yes | `workflow_dispatch`, activity `address-feedback` | review threads; verdict artifacts | fix pushes; thread replies and resolutions |
| Review a dependency update | step in `pr-unblock.yml` | git host | yes | `workflow_dispatch`, activity `review-dependency` | Dependabot PR | `verdict=merge` marker or an escalation |
| Fix failing CI | step in `pr-unblock.yml` | git host | yes | `workflow_dispatch`, activity `fix-ci` | CI logs; PR head | fix pushed to the PR branch |
| Sync shared copies | step in `pr-unblock.yml` | git host | no | `workflow_dispatch`, activity `sync-shared-copies` | PR head | shared-copy patch pushed to the PR branch |
| Declare test scope | step in `pr-unblock.yml` | git host | no | `workflow_dispatch`, activity `fix-test-scope` | PR head | test-scope patch pushed to the PR branch |
| Fix docs (`pr-refine.yml`) | own run | git host | yes | `workflow_dispatch` from `pr-unblock-dispatch.yml` | PR changed files and head | docs patch pushed to the PR branch; check runs |

## Merge

| Task | Shape | Component | Model | Trigger | Inputs | Outputs |
|---|---|---|---|---|---|---|
| Merge sweep (`pr-merge.yml`) | own run | git host | no | schedule, every 30 minutes; `pull_request_target` unlabeled; `workflow_dispatch` with no `pr` | open lanes App and Dependabot PRs; gate evidence; verify artifacts | merge-queue enqueues; `pr-merge/unarmed` status; `pr-merge / gate` check runs |
| Arm auto-merge | step in `pr-merge.yml` | git host | no | the sweep's triggers; `workflow_dispatch` with `pr`, which `pr-verify.yml` sends on a pass | each PR's gate evidence | native auto-merge armed |
| Start a full CI run of main | step in `pr-merge.yml` | orchestrator | no | push to main; a sweep that asks for one | main's head | a `pr-require-checks.yml` dispatch on main |
| Dispatch post-merge records | step in `pr-merge.yml` | orchestrator | no | schedule; `workflow_dispatch` with no `pr` | red full runs it started | `post-merge-file-demotion-issues.yml` dispatches; one re-run per red run |

## Post-merge

| Task | Shape | Component | Model | Trigger | Inputs | Outputs |
|---|---|---|---|---|---|---|
| Detect a silent revert (`post-merge-detect-silent-revert.yml`) | own run | runner | no | push to main; `workflow_dispatch` | git history of the pushed range | red or green run |
| File demotion and fix records | step in `post-merge-file-demotion-issues.yml` | tracker | no | PR Require Checks or the silent-revert canary completes on main; `workflow_dispatch` from `pr-merge.yml` | failed run, jobs and annotations; main history | demotion and fix issues; intake dispatches; quarantine issues |
| File a revert record | step in `post-merge-file-demotion-issues.yml` | tracker | no | the silent-revert canary completes on main | the commits the push brought | revert record issue for a reverted lanes App PR |
| Label merge paths | step in `post-merge-file-demotion-issues.yml` | git host | no | the silent-revert canary completes on main | the commits the push brought | merge-path labels on the merged and reverted PRs |
| Report a red main | step in `post-merge-file-demotion-issues.yml` | observability | no | a scheduled or dispatched PR Require Checks run fails on main | the failed run and its re-run | red-main log issue naming the culprit |
| Close cleared records | step in `post-merge-file-demotion-issues.yml` | tracker | no | a scheduled PR Require Checks run completes on main; `workflow_dispatch` with `close-cleared` | open records; main's run results | records main has cleared, closed |
| Select a mutation range (`post-merge-select-mutation-range.yml`) | own run | orchestrator | no | push to main that changes source | push SHAs | range artifact, whose completion starts the mutation lane |
| Mutation test the change (`post-merge-test-mutation.yml`) | own run after `post-merge-select-mutation-range.yml` | runner | yes | the range run completes on main | range artifact; pushed head | job summary; one comment on the merging PR |
| Audit test selection (`maintenance-audit-test-selection.yml`) | own run, or after `pr-require-checks.yml` | observability | no | schedule; `workflow_dispatch`; PR Require Checks completes on main | suite traces; selector replays | job summary and artifact |

## Release

| Task | Shape | Component | Model | Trigger | Inputs | Outputs |
|---|---|---|---|---|---|---|
| Build and queue the plugin release (`release-publish-plugins.yml`) | own run | git host | no | schedule; push to main that changes `.changes/`; `workflow_dispatch` | changelog fragments on main; release PR state | signed commit on `release/plugins`; release PR opened or updated; merge-queue enqueue |
| Changelog fragments for Dependabot merges (`release-generate-dependabot-changelog-fragments.yml`) | own run | git host | no | push to main that changes dependency manifests; schedule; `workflow_dispatch` | main history of Dependabot merges | commit on `release/dependabot-fragments`; PR with auto-merge armed |
| Apply a Claude Code release (`upstream-apply-changelog.yml`) | own run | git host | yes | schedule, hourly; `workflow_dispatch` | Claude Code release list | branches; PRs; handoff issues |

## Maintenance

| Task | Shape | Component | Model | Trigger | Inputs | Outputs |
|---|---|---|---|---|---|---|
| Audit lane runs (`maintenance-audit-lane-runs.yml`) | own run | observability | yes | schedule, daily; `workflow_dispatch` | the last 24 hours of lane runs, CI logs and open PRs | digest issue rewritten |
| Monitor signals (`maintenance-monitor-signals.yml`) | own run | observability | no | schedule, hourly; `workflow_dispatch` | runs, jobs, annotations, artifacts, PRs; thresholds in `pr-pipeline.yaml` | job summary; at most one incident issue per signal |
| Re-run lost runs (`maintenance-reconcile-lost-runs.yml`) | own run | orchestrator | no | schedule, every 15 minutes; `workflow_dispatch` | runs and jobs for PR heads; service status pages | one re-run of each lost CI, verify, review or intake run; record artifacts |
| File recurring issues (`maintenance-file-recurring-issues.yml`) | own run | tracker | no | schedule, daily; `workflow_dispatch` | `.github/recurring-schedule.json`; open recurring issues | one issue per due row |
| File upstream drift (`maintenance-file-upstream-drift-issues.yml`) | own run | tracker | no | schedule, daily; `workflow_dispatch` | `docs/upstream` pins; vendored skills | one `Upstream drift: <id>` issue per upstream, opened, updated or closed |
| Check links online (`maintenance-check-links-online.yml`) | own run | runner | no | schedule, weekly; `workflow_dispatch` | repository files; lychee settings | job summary; dead-links artifact |
| File dead links (`maintenance-file-dead-links.yml`) | own run after `maintenance-check-links-online.yml` | tracker | no | the link check completes on main | dead-links artifact | one rollup issue, opened, rewritten, closed or reopened |
| Delete stale branches (`maintenance-delete-stale-branches.yml`) | own run | git host | no | schedule, daily; `workflow_dispatch` | branches; PR and issue state; rulesets | branches deleted; ledger artifact |
| Report changed areas for tidying | step in `maintenance-tidy-code-upkeep.yml` | observability | no | push to main | the pushed range | job summary |
| Tidy code by area | step in `maintenance-tidy-code-upkeep.yml` | git host | yes | schedule, daily; `workflow_dispatch` | settings; open tidy PRs; sweep records | one tidy branch and PR per area |
| Measure a skill edit (`maintenance-measure-skill-edit.yml`) | own run | git host | yes | `workflow_dispatch` by a listed human | plugin and skill names; the skill's eval suite | draft PR when the edit scores better than the merged skill |
