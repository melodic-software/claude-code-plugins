# Lifecycle map

Each automated task in this repository's delivery lifecycle, from a new issue to a merged pull
request and on into post-merge, release and maintenance work. A task is one workflow in
`.github/workflows/`, or one distinct job or activity inside one. The rules each lane follows live
in [the PR pipeline contract](../pr-pipeline/README.md) and `docs/conventions/pr-pipeline.yaml`;
this map only places the tasks.

This map is a point-in-time snapshot, written by hand. **As of**: 2026-11-25, every
`.github/workflows/*.yml` file has a row, named in its Task cell or its Shape cell, and every
plugin in `.claude-plugin/marketplace.json` is listed under [Plugins](#plugins). No check
compares the map with that directory or that file, so a workflow or plugin added, renamed or
removed since then may be missing or out of date here. **Recheck trigger**: a pull request that
adds, renames or removes a file in `.github/workflows/` or a plugin, changes a workflow's
triggers, jobs or outputs, or changes which plugin skills or scripts a workflow runs; update the
rows and the as-of date in the same pull request.

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

## Plugins

A plugin is on the map when a task above uses it to do the task's work: the task loads one of
its skills into a model run, or runs or reads one of its scripts or data files. A plugin whose
own tests, lint, evals or checks of its own files run in Required CI, Windows and macOS tests or
Plugin evals is the subject of that task, not part of it, so that alone does not place it.

### On the map

Resolve an issue, Address review feedback and Fix failing CI also run `scripts/check-affected.sh`
on their own change, which runs the `bash-format`, `code-metrics`, `code-tidying` and
`guardrails` checks named for Required CI below.

| Plugin | Tasks that use it, and how |
|---|---|
| `ai-slop` | Fix docs loads `ai-slop:audit fix`; Resolve an issue loads it as a tidy pass; Required CI runs its `detect.sh` through the em-dash gate |
| `bash-format` | Required CI runs its `lint-full.sh` |
| `code-metrics` | Required CI runs its `audit-size.sh --check` |
| `code-tidying` | Tidy code by area loads `code-tidying:tidy` and runs its upkeep scripts; Resolve an issue loads `code-tidying:tidy-diff`; Required CI runs its `comment-lint.sh` |
| `context7` | File upstream drift runs its `lookup` skill's `update.sh` drift check |
| `discovery` | Resolve an issue loads it for web reads |
| `docs-hygiene` | Resolve an issue loads `write-for-agents` and `write-for-humans` as tidy passes |
| `dometrain` | File upstream drift runs its `update` skill's `update.sh --check` |
| `evals` | Plugin evals, One skill-edit eval pass and Measure a skill edit run its case validator and scoring scripts; Required CI runs its `validate-cases.py` |
| `firecrawl` | File upstream drift runs its `update` skill's `update.sh --check` |
| `formal-verification` | Required CI runs its `check.mjs` |
| `guardrails` | Required CI runs its `reference-verify.sh` |
| `harness-ops` | Apply a Claude Code release loads `harness-ops:changelog` and runs its changelog status and inventory scripts |
| `implementation` | Apply a Claude Code release loads it; the changelog skill's CI mode runs `/implementation:implement` |
| `instruction-placement` | Required CI runs its `render-index.sh check` on `AGENTS.md` |
| `knowledge` | Resolve an issue loads it for page digests |
| `multi-agent` | The model profiles of Resolve an issue, Resolve merge conflicts, Address review feedback, Fix failing CI, Fix docs, Tidy code by area, Measure a skill edit and Apply a Claude Code release resolve through its role map, `reference/defaults.yaml` |
| `mutation-testing` | Mutation test the change loads `mutation-testing:audit` |
| `performance` | Required CI runs its `ratchet.py check` |
| `planning` | Apply a Claude Code release loads it and runs `/planning:plan --unattended`; Resolve an issue and Fix failing CI may run its `repin-digests.sh` |
| `playbooks` | File upstream drift runs the `boris` and `skill-authoring` skills' `update.sh --check` |
| `playwright` | File upstream drift runs its `playwright` skill's `update.sh --check` |
| `rate-limits` | Required CI's loop-lane floor drift check reads its `reference/reader-contract.md` as the source the copies in other plugins must match |
| `review` | Code review and Security review load `review:code-review` and `review:security-review`; Review from main reads those skills' files as its criteria; Rate merge risk loads `review:merge-risk` |
| `session-flow` | Required CI's `check-next-graph.py` reads its `workflow` skill's `context/steps.md` as the stage ladder every plugin's `## Next` graph must follow |
| `skill-quality` | Required CI runs its `check-skill.sh`, `check-evals-quality.sh`, `measure-invocation.sh` and `check-listing-budget.sh`; Resolve an issue runs `check-skill.sh` through its changed-skills check and may run `check-evals-quality.sh` |
| `source-control` | Resolve merge conflicts, Address review feedback, Review a dependency update and Fix failing CI load `source-control:pull-request`; `pr-merge.yml`, `post-merge-file-demotion-issues.yml`, `pr-review-main.yml`, `pr-unblock-dispatch.yml`, `pr-dispatch-feedback.yml` and Required CI's `ci-status` job run its `babysit-prs` scripts; Run a lane read activity and Run a lane write activity run its `resolve-version-bump-conflict.sh` |
| `testing` | Required CI runs its `cant-fail-scan.sh`; Resolve an issue may run it |
| `user-interface` | File upstream drift runs its `check-good-css-drift.sh --check` |
| `verification` | Apply a Claude Code release loads it and runs `/verification:confirm --unattended` |
| `work-items` | Resolve an issue loads `work-items:work`; the admission checks in `intake-triage.yml` and `work-unblock.yml` read its `charge-words.json`; Run a lane read activity and Run a lane write activity run its tracker script |

### Not an automated task

No task above uses these plugins to do its work. CI may still run their own tests or checks;
otherwise they run only in a person's own Claude Code session:

`actionlint`, `adhd`, `ai-briefing`, `animation`, `app-control`, `architecture`, `attribution`,
`autonomy`, `bugs`, `codebase-health`, `computer-use`, `context-budget`, `context-usage`,
`corrections`, `coupling`, `debugging`, `desktop-notification`, `developer-experience`,
`discipline`, `disk-hygiene`, `display-redaction`, `docs-naming`, `domain-driven-design`,
`education`, `eol-normalizer`, `event-storming`, `explainer-video`, `external-agents`, `fleet`,
`gaming`, `github`, `go-format`, `harness-config`, `harness-memory`, `improvement`,
`javascript-format`, `kindle-dedrm`, `machine-health`, `markdown-format`, `mcp-tools`, `miro`,
`naming`, `overengineering`, `pixel-art`, `playgrounds`, `plugin-diagnostics`,
`plugin-profiles`, `plugin-quality`, `powershell-format`, `prototype`, `python-format`,
`repo-fleet-hygiene`, `repo-hygiene`, `retro-audio`, `session-telemetry`, `songwriting`,
`speech`, `spelling`, `sql-server`, `tdd`, `themes`, `toolchain`, `user-experience`,
`visualization`, `wizard`, `writing`, `x`.

## Simplify pass on every pull request

**Built separately**: this map records only where the pass runs. The in-run half below exists
already. The post-merge half does not exist yet and gets built under its own issue, not this map.
No row above covers the pass, because no workflow runs it for every pull request.

**Placement**: the pass runs in two places.

- **A pull request opened by a `work-resolve-issue.yml` run**: inside that run, before the pull
  request opens. This is the run's tidy step (`tidy` in `docs/conventions/pr-pipeline.yaml`).
  `code-tidying:tidy-diff` runs a simplify pass on the run's own lines. It runs only when the
  change is within the tidy cutoffs.
- **Every other pull request**, except the batch's own tidy pull requests: after the merge, as a
  step in the scheduled batch of
  `maintenance-tidy-code-upkeep.yml`. The step simplifies the lines each pull request changed if
  that pull request merged since the last batch and was not tidied in its own run. It opens its
  own pull request when it changes anything.

**Reason**: the pass must never slow the pull request. A pass inside an open pull request pushes a
commit, and that commit starts CI and both reviews again on the new head. The in-run tidy is the
one place inside a pull request that costs nothing: its edits are already in the first head, so
there is no extra push or review round. For the other pull requests, the upkeep batch is the
cheapest post-merge place:

- It already reads each area's churn from git history.
- It already caps its open pull requests (`upkeep_max_open` in
  `docs/conventions/code-tidying.yaml`) and honors the lanes kill switch.
- A schedule starts it, not a merge. So it starts no agent work on a merge before this map
  settles the brakes for the deferred item "A merge starts the next run"
  ([#17133](https://github.com/melodic-software/claude-code-plugins/issues/17133)).

`pr-refine.yml`'s fix-docs, which tidies markdown inside the pull request, stays as
`limits.fix-docs-per-run` in [`pr-pipeline.yaml`](../pr-pipeline.yaml) sets it.

## Is a lifecycle UI needed?

**Provisional answer**: no, not yet. The map and the existing reports are enough. Repository data
gives this answer, and it does not stand in for the owner's. The owner decides it in a
[`/planning:wayfind`](../../../plugins/planning/skills/wayfind/SKILL.md) interview.

**Evidence**:

- **The structure fits one page.** The tables above hold 65 tasks in eight stages, one row each.
- **Live state already has read-only views**:
  - `maintenance-audit-lane-runs.yml` rewrites a daily digest issue.
  - `maintenance-monitor-signals.yml` opens at most one incident issue per signal.
  - [`/work-items:morning-brief`](../../../plugins/work-items/skills/morning-brief/SKILL.md) shows
    queue counts, merge-ready pull requests, parked decisions, each lane's failures, turn headroom
    and model use.
  - [`/work-items:measure-delivery`](../../../plugins/work-items/skills/measure-delivery/SKILL.md)
    reports the delivery trend.
- **Most per-run facts are already recorded.** Most model tasks write a lane-outcome record for
  each run (see Follow-ups).
- **One gap**: no view follows one issue through every task that touched it, from intake to merge.
  A UI would serve that case. It would need the follow-ups below joined per issue and kept for
  longer than the 7 days `pr-run-activity-read.yml` keeps its transcripts. Ask the question again once they land.

## Follow-ups

These columns are pending. No task row carries them yet.

- **Skill use per task**: which skills and subagents each task's model runs invoke. Data source:
  the sealed `lane-transcript-*` run artifacts, sealed to the `LANE_TRANSCRIPT_PUBLIC_KEY`
  variable's key, so reading them needs the matching private key.
  - `pr-run-activity-read.yml`'s `upload-transcript` job uploads one for each lane activity and
    keeps it for 7 days.
  - Other model workflows, such as `intake-triage.yml` and `maintenance-tidy-code-upkeep.yml`,
    upload theirs through the ci-workflows `upload-lane-transcript` action.
  - For attended work, the source is the session transcripts.
- **Work per run**: turns, duration, cost, tokens, models and GitHub API calls for each task.
  Data source: the lane-outcome record. Its fields are `turns`, `maxTurns`, `durationMs`,
  `costUsd`, `usage`, `models` and `githubCalls`, read through
  `.github/scripts/lib/lane-outcome.mjs`.
  - Most model workflows write it as run annotations through the ci-workflows
    `report-lane-outcome` action.
  - Activities run through `pr-run-activity-read.yml` also carry it in their
    `<lane> / <activity>` check run's output.
  - `pr-review-hosted.yml`, `pr-review-security-hosted.yml` and the tasks with no model write no
    record. Their run and job timings come from the GitHub Actions runs and jobs API.
