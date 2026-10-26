# Changelog for the PR pipeline convention

## [5.13.6] - 2026-10-26

### Fixed

- A head whose CI job ran past its `timeout-minutes` is no longer left red with no lane acting on it. GitHub ends such a job `cancelled`, and only its check run's annotation ("The job has exceeded the maximum execution time") says why; fix-ci-context and the fix-ci dispatcher now read that annotation and count the job as failing, so fix-ci works on the slow or hanging test, with the time-limit note in its context. A check cancelled with no such note stays skipped (`.github/scripts/pr-unblock/fix-ci-context.mjs`, `.github/scripts/pr-unblock/fix-ci-dispatch.mjs`).
- The fix-ci dispatcher waits for the lost-run reconciler's one re-run of a cancelled, timed-out or start-failed first attempt, as it already does for an infra-only failure, so the two do not act on the same head at once (`.github/scripts/maintenance-reconcile-lost-runs/infra-failure.mjs`).
- The lost-run reconciler names each CI run lost again after its one re-run in its run summary, with who takes it (`.github/scripts/maintenance-reconcile-lost-runs/reconcile.mjs`).

## [5.13.5] - 2026-10-26

### Fixed

- Intake apply-verdict now writes a native blocked-by edge for each blocker the issue body names, not only those the triage model's `Blocked by:` line lists, so admission, which reads only native edges, no longer admits an issue whose blocker is named only in its text and the issue lane no longer hands it back to a person. A line that starts with `Blocked by` or `Depends on`, and each list item under a `Blocked by` or `Depends on` heading, names its `#<n>` references and this repository's issue URLs; fenced and inline code, HTML comments, `>` quotes, other repositories' references and pull request URLs name nothing, and a Markdown link, inline or by reference, counts as its target alone, so `[#12](<another repository's issue URL>)` names nothing. Each number is only a candidate: it gets an edge when GitHub answers it is an open issue of this repository, not a pull request, with no edge yet, at most 10 per issue, with the existing missed-edge handling. Edges are written on an escalated verdict too, so an `agent-ready` label a person adds later still finds them; an edge missed on a verdict that is not ready only warns, since no `status: ready` waits on it (`.github/scripts/intake-triage/edges.mjs`, `.github/scripts/intake-triage/apply-verdict.mjs`).

## [5.13.4] - 2026-10-26

### Fixed

- The fix-ci dispatcher no longer dispatches a head whose tested run ended `cancelled` when no check on the head failed, timed out or failed to start. fix-ci-context fixes only those, so each such run posted `Skipped: not-applicable` and spent the head's per-head cap on nothing. The dispatcher decides from the head's REST check runs through fix-ci-context's own `failingChecks`, so a failed job that a later contract-only run skipped still gets fix-ci (`.github/scripts/pr-unblock/fix-ci-dispatch.mjs`, `.github/scripts/pr-unblock/fix-ci-context.mjs`, `.github/scripts/pr-unblock/dispatch.mjs`).

## [5.13.3] - 2026-10-26

### Fixed

- pr-merge.yml's full-run dispatch no longer waits out a rate limit and sends again: any 429, or a 403 with a retry-after, remaining 0 or a message naming a rate limit, fails the step red, naming the pool and the reset (with no header time, a minute on for a secondary limit and an hour on for any other, as the lanes' rate guard decides), and the candidate listing fails red on a rate limit instead of retrying it. enable-auto-merge's resend is pinned by a test never to resend an arm GitHub answered with 403 or 429. When a gate reader it starts (the per-pull-request verifier read or the lane-room read) exits 75 on a rate limit, enable-auto-merge holds that pull request and every later one as an unread room: it sends no further read, arm or note that run, disarms each armed lanes App pull request unless the GraphQL pool is the one stopped (then it names each one still armed), and fails red with the guard's error naming the pool and the reset. Either post-merge check (the post-merge-dispatch job's and the merge job's) that exits 75 on a rate limit now fails its job red once its outputs are written, with needs-dispatch false, and no dispatch, re-run or gate follows it. The re-run step's calls and the candidate listing go through the shared shell rate guard (`api-budget.bash`), so a rate-limited read or re-run POST ends it red instead of green. Those steps and the full-run wait also stop on gh's bare `Too Many Requests (HTTP 429)` message, where they used to retry. A rate limit that stops post-merge-dispatch (its check, its dispatch or its re-run) goes to the merge and enable-auto-merge jobs as its `rate-limited` output, naming the pool and the reset; each then ends red at its first step and sends nothing to GitHub.

## [5.13.2] - 2026-10-26

### Fixed

- work-unblock counts a run whose broker-check `Check the kill switch` step saw a kill switch on, and so skipped the broker ask, as a breaker trip. That run ends green with no failed step, so it was handed to a person as stranded with no report instead of being re-fired. The jobs listing alone shows it; no log is read (`.github/scripts/work-unblock/label-unblocked.mjs`).

- The issue lane's WIP cap counts a lane pull request as held when it carries `needs-human` or `do-not-merge` in any case (for example `Needs-Human`), as pr-merge's `enable-auto-merge.mjs` (`holdReason`) matches them, so a hold label with other casing no longer leaves the pull request in the countable total ([#8476](https://github.com/melodic-software/claude-code-plugins/issues/8476)). A label with a missing or non-string name is no hold, and the `Hold: a human merges this` body line still matches exactly.

## [5.13.1] - 2026-10-26

### Changed

- `pr-merge.yml` no longer wakes when `work-resolve-issue` finishes. That run could only disarm an armed pull request on a hold: an event run never arms (`enable-auto-merge.mjs` `READER_EVENTS`), and a pull request the issue lane just opened is not armed yet. The 15-minute schedule arms new lane pull requests as before, and `ci-status` still enforces every hold, on the pull request and in the merge queue. This removes about 1,000 run records and about 140 runner jobs a day.

### Fixed

- A pr-unblock run whose credential was refused (`class=auth`, a 401) now counts as a limit stop: its head waits `limits.fallback-reset` hours before the next dispatch instead of spending all `limits.limit-stops-per-head` runs at once, and the dispatcher logs a notice naming the class and the reset time (`.github/scripts/pr-unblock/limit-stop.mjs`, `dispatch.mjs`).
- `pr-run-activity-read.yml` now puts the lane record's class and reset on the check run it posts, so `limit-stop.mjs` can tell a usage limit or a refused credential from any other failure on resolve-conflicts, address-feedback and review-dependency checks; before, every such check read as a plain failure.

## [5.13.0] - 2026-10-26

### Added

- `limits.api.<pool>.limit-cap` sets the requests per window a GitHub API pool plans to: planned = min(header limit, `limit-cap`), used = header limit - header remaining, left = planned - used. `github-token` defaults it to 1000, GitHub's documented GITHUB_TOKEN limit of 1,000 requests per hour per repository, so an observed 5,000 header limit is headroom, never a target; the other pools have no cap. The rate guard's read floor is now a share of the planned budget, in the Node guard (`planOf` in `.github/actions/log-api-budget/rate-guard.mjs`) and in the shell guard (`API_BUDGET_LIMIT_CAP`, which ci-status sets to 1000). The stop still reads only the header's remaining and GitHub's 403 and 429 refusals, and `writer-pause` and `breaker` stay shares of the header's limit.

### Changed

- Each read-runner lane (pr-unblock's fix-ci, its rung-up, address-feedback, review-dependency and resolve-conflicts; pr-refine's fix-docs; work-resolve-issue's resolve-issue) runs its activity once more, on the central fallback subscription token `FALLBACK_CLAUDE_CODE_OAUTH_TOKEN`, when the role's OAuth token also stops (a limit stop, a credit stop, or a 401 or 402). Each handoff job reads whether the secret is set and passes it as the second call's `fallback-ready`; a `<subscription>-handoff` job reads this run's jobs and `<first>-fallback` runs on the fallback token alone. With the secret empty, the second call stays the last and the lanes run as before.

## [5.12.0] - 2026-10-26

### Changed

- pr-verify judges once more, on the central fallback subscription token `FALLBACK_CLAUDE_CODE_OAUTH_TOKEN`, when the pr-verify role's subscription token also stops (a limit stop, a credit stop, or a 401 or 402) with no permission denial: `check-intent-subscription` passes `fallback-ready` to run-claude-cli, and the new `check-intent-fallback` job runs on a third VM and records `fallback-reason` `limit-stop`, `credit-stop` or `auth`. With the secret empty, the subscription leg stays the last and the lane runs as before.

- No path is held for being trusted alone (owner direction 2026-10-24) except a narrow floor (owner decision Q-FLOOR (B)): ci-status's `merge-holds.mjs` `HOLD_PATH_FLOOR` keeps only `.github/actions/resolve-config/**`, `.github/actions/request-lane-token/**`, `.github/actions/check-trusted-trigger/**`, `.github/actions/check-kill-switch/**`, `.github/actions/log-api-budget/rate-guard.mjs`, `**/CODEOWNERS`, `**/.gitmodules` and the files that enforce it (owner decision [Q-ENFORCE (A)](https://github.com/melodic-software/claude-code-plugins/pull/9826#issuecomment-6401599691)): `.github/scripts/pr-merge/merge-holds.mjs`, `.github/scripts/pr-merge/enable-auto-merge.mjs`, `.github/scripts/pr-merge/superseded.mjs`, `.github/scripts/pr-merge/clear-escalations.mjs`, `plugins/source-control/skills/babysit-prs/scripts/babysit_risk.py`, `.github/workflows/pr-require-checks.yml`, `.github/workflows/pr-merge.yml` (which runs those scripts and sets their environment), `docs/conventions/pr-pipeline.yaml`, and every module those scripts import (`.github/scripts/pr-unblock/address-feedback.mjs`, `.github/scripts/pr-unblock/gate-source.mjs`, `.github/scripts/pr-unblock/thread-scope.mjs`, `.github/scripts/work-resolve-issue/report-outcome.mjs`, `.github/scripts/work-resolve-issue/limits.mjs`), and the Python that decides the holds (`babysit_risk.py` and `babysit_verify_evidence.py`, which `enable-auto-merge.mjs` runs, with the 16 `plugins/source-control/skills/babysit-prs/scripts/` modules they import, `babysit_merge.py` and `babysit_merge_policy.py` among them), which `test_merge_holds_sync.py` derives from their imports and requires on the floor, equal to `babysit_risk.HIGH_FLOOR` and read from the base commit's module; a trusted person's approval of the head lifts it. The forced denied paths (the pipeline config and the trusted-actor list) are gone, and resolve-config no longer adds them to `merge.diff-check.denied-paths`: the floor holds the pipeline config, and the widening hold the trusted-actor list. This repository sets `high-path-floor: false`, which no longer turns off the floor. The trusted-actor widening hold and the review lanes still judge the rest.
- ci-status no longer holds a plugin or marketplace manifest change; the security lane flags it.
- `plugins/multi-agent/reference/defaults.yaml` is no longer a cost path; the infrastructure-as-code cost paths stay.
- A body hold (`Hold:` or "do not merge") counts only when a person wrote or edited the body; in a lanes App body only report-outcome's own `Hold: a human merges this` line holds, so untrusted-provenance work still waits.
- The verifier pass binds a link of several issues that still names the judged one, linked the way it judged it; a link that drops the judged issue, a removed link included, holds it.
- `enable-auto-merge.mjs` comments on every refusal and adds the human-gated label only for a cause a person must clear: an untrusted spec, the repeated-FAIL round cap, a security finding (CRITICAL, or a path that could alias another, a symlink or a mode change), a trusted-actor widening, a cost hold, a hold path (a configured `merge.diff-check.denied-paths` match or a floor path, which only a trusted approval lifts) or report-outcome's own `Hold: a human merges this` line (owner decision Q-HOLDLINE; a reader run reads the discussion first so it comments once, and disarms an armed one at once). An issue link the lane does not take, a FAIL, a changed spec and any other risk reason get the comment alone.
- `clear-escalations.mjs` takes that label off once the head moves under `merge.lane-prs: native` too, including a label put back under a standing escalation comment; the next run labels the new head again only if its cause still holds.
- `enable-auto-merge.mjs` reads a pull request's labels and its comments, reviews and review threads whole instead of refusing past 100, arms nothing and labels nothing when the resolved config does not read, and starts each run at an offset that moves with the run number, so the pull requests past the verify budget change from run to run.
- ci-status's `merge-holds.mjs` holds a trusted-actor list change that adds or widens an entry (`actorsHold`, the rule of `babysit_risk._actors_widened`, base and head read at `BASE_SHA` and the head), so one pushed after auto-merge is armed waits for the owner; a trusted person's approval of the head lifts it, as it lifts a hold path, and a change that only removes entries passes.
- The review callers' `hold-paths` name every path-floor entry (`test_merge_holds_sync.py` checks both callers and ci-status's exempt-author `hold_patterns` each match all of them), adding `.github/actions/resolve-config/**`, `.github/actions/request-lane-token/**`, `.github/actions/check-kill-switch/**`, the rate guard (`.github/actions/log-api-budget/rate-guard.mjs`, which the trusted-trigger check imports), the merge-hold code (`merge-holds.mjs`, `enable-auto-merge.mjs`, `superseded.mjs`, `clear-escalations.mjs`, the `pr-unblock/` and `work-resolve-issue/` modules they import, `pr-require-checks.yml`, `pr-merge.yml`, and the babysit-prs Python that decides the holds) and the pipeline config (`docs/conventions/pr-pipeline.yaml`, whose lane slots the token broker reads), so the security lane reads those changes as trusted paths, and ci-status's exempt-author check fails a Dependabot, release App or standards-sync pull request that changes them.
- The review callers' `hold-paths` also name the security review's own files, `plugins/review/skills/security-review/**` and `plugins/review/evals/security-review-*/**`, so a change that weakens the review that judges trust controls gets the same scrutiny. They are scrutiny only: ci-status's exempt-author check does not fail on them, and nothing holds a pull request for them.

## [5.11.3] - 2026-10-26

### Fixed

- The pr-unblock dispatcher no longer fails its run when GitHub answers one pull request's read with a 5xx. A GraphQL query answered 5xx is now sent again with the same bounded backoff and per-attempt timeout as a GET (`retryServerErrors`). A mutation is still sent once: a document that names a mutation or subscription anywhere, or a request that names an operation, is never resent. A per-PR read that still answers 5xx after those retries logs a warning naming the PR and skips that PR until a later run, in fix-docs, resolve-conflicts, review-dependency and fix-ci (its hold read and its required-run read). A rate limit or any other read error still fails the run.

## [5.11.2] - 2026-10-26

### Changed

- `enable-auto-merge` no longer spends most of its lane-room time limit on a full post-merge check when the run's report was refused only because an issue the lanes App opened was edited since (`demotion-changed`). The room reads the demotion records alone and keeps the report when they are unchanged, so a slow API window no longer risks running past the time limit and disarming every armed lanes App pull request.

## [5.11.1] - 2026-10-26

### Changed

- The rate guard keeps a rate-limit reading of every guarded call under `API_BUDGET_TOKEN`, so every Node script's calls reach the job-end api-budget notice, not only `budgetedFetch`'s. The log-api-budget action adds an `api-calls <token>=N not-modified=M` line: this job's own calls, which the notice's `cost` (a counter every concurrent job shares) is not. The jobs that posted no notice now post one: intake-triage's born-triaged and refine-select, pr-verify's two judge jobs, pr-unblock's four select and context jobs, post-merge-demotion-alert's report-red-main, and the audit-lane-runs, delete-stale-branches, monitor-signals and reconcile-lost-runs jobs. No call is added.
- pr-feedback-dispatch's rerun-ci-status sends each repeat poll of the pr-require-checks run as a conditional GET on the last answer's ETag; a 304 stands for that answer, so the poll keeps its 60 s pace, its 10-minute cap and its decisions. Each 304's reading reaches the job's notice, which shows whether GitHub counts a 304 against `GITHUB_TOKEN`.
- pr-merge's dispatch-full-run sends each read of the full run after the first as a conditional GET on the last ETag; a 304 means the run is still going, so the wait keeps its three-minute reads, its 39-minute ceiling and its red-run dispatch.
- pr-unblock's report-escalation reads a pull request's comments 100 to a page, not GitHub's default 30.

### Fixed

- `enable-auto-merge` no longer leaves every lanes App pull request unarmed, and disarms the armed ones, when the run's post-merge report is one the gate would not reuse (for example `demotion-changed`, which any issue the lanes App files and triage then labels sets). The lane's room now checks the report again as the gate does and arms from that answer.

## [5.11.0] - 2026-10-26

### Added

- Adoption: a person's pull request skips the `idle-hours` wait when a trusted person's merge-queue enqueue was removed for failed checks (owner decision Q-REQ (a)). GitHub must have seen that head on the branch by the enqueue and not since, and no person may have commented or reviewed since the enqueue. The pr-merge gate records `eligibility.adoption` as `requeue-after-ejection` and then applies every gate rule unchanged, the `merge.max-queue-ejections` cap included.

## [5.10.7] - 2026-10-25

### Fixed

- The pr-merge lane's escalation to a person (risk, verifier, held-major and shared-copy) is posted as a new comment beside the human-gated label instead of an edit of its earlier comment, so the escalation notifies and the head-moved clear pairs the label with the newest escalation comment. An unchanged escalation is not posted again.

## [5.10.6] - 2026-10-25

### Fixed

- `enable-auto-merge` no longer re-arms a lanes App pull request whose head the merge queue has removed for failed checks `merge.max-queue-ejections` times (default 2) since it last changed. GitHub does not re-arm a pull request the queue removes, and each scheduled run armed it again, so a head that kept failing its merge group was re-queued without end. The count and the limit are the gate's own, read through `babysit_verify_evidence.py evidence --lane-queue`. At the cap the pull request is left unarmed with the gate's `<!-- babysit-merge-queue-ejections -->` comment and no label, since a push resets the count; a count that cannot be read leaves it unarmed.

## [5.10.5] - 2026-10-25

### Fixed

- The shell rate guard ends the step when it cannot record a stop (no space or no permission for `$RUNNER_TEMP/api-budget`), with an error naming the pool, and refuses every later call in that shell, so no call reaches an exhausted pool unrecorded. Its errors go to a copy of the step's stderr taken when the wrapper is set up, so they reach the log when a caller such as ci-status's `gh_read` holds the call's stderr in a file, and from a subshell every shell up to the step's is ended, so no retry loop around the call sends again. The Node guard names a stop it could not record in its error line.
- The shell and Node stop-file readers fail closed: a stop file that exists but cannot be read (no permission, a directory, a path part that is a file) holds every pool, with an error naming the file; a missing one holds nothing.
- The shell and Node stop-file readers take only lines shaped `<pool> <1-12 digits>` and ended by a newline, alike, so a fragment a short write left spoils only the line it runs into; `rate-guard.vectors.json` pins the reader cases for every port. Both guards cap a stop at the largest 12-digit second, so a huge `retry-after` still writes a stop the readers take.

## [5.10.4] - 2026-10-25

### Fixed

- `enable-auto-merge` posts a new refusal comment when it escalates a lanes App pull request to a person (the comment carrying the attended queue's escalation marker, written with the human-gated label), instead of editing its earlier lane comment. An edit sent no notification and kept the comment's old date, so the timeline showed only a bare label event with no visible reason. A refusal that stays a lane's still edits the one comment in place, and an unchanged person's refusal is not posted again.

## [5.10.3] - 2026-10-25

### Fixed

- The fix-ci dispatcher counts a head's earlier `pr-unblock / fix-ci` runs from the REST check-runs listing before it dispatches, instead of from the GraphQL check rollup, which lists only the newest run per check name. The per-head cap (`limits.limit-stops-per-head`) now stops a head that fix-ci-context skips each time, which was dispatched again after every base move. A head whose runs cannot be read is not dispatched (`.github/scripts/pr-unblock/fix-ci-dispatch.mjs`).
- A head that reaches the per-head cap in fix-ci or resolve-conflicts now gets one `::warning::` annotation on the dispatcher run that finds the cap, naming the PR, the head and the run count. The head then goes into the dispatch record, so later dispatcher runs skip it without reading its hold, check runs or required run (`.github/scripts/pr-unblock/fix-ci-dispatch.mjs`, `.github/scripts/pr-unblock/dispatch.mjs`, `.github/scripts/pr-unblock/limit-stop.mjs`).

- `enable-auto-merge` no longer arms, and disarms, a lanes App pull request whose linked issue carries a label naming untrusted work, in any spelling, or had one removed by a non-human. report-outcome already writes a `Hold:` line when the issue carries the exact label at PR open, so this covers a label added after the pull request opened, or any other spelling. The refusal is one a person clears: the pull request gets the refusal comment and the human-gated label.

- In the merge queue, `ci-status` now applies the trust hold to a queued pull request an automation opened. The step `Fail a queued pull request carrying a hold label` reads its linked issue: its closing issues here, or with none, the one plain `Refs:` issue. The step fails when that issue carries a label containing `untrusted` in any ASCII case, or had one removed by anyone other than a person on the base's trusted-actor list, or through an App. A lanes App pull request that does not link exactly one issue here fails too, so dropping the link after arming does not skip the check; another automation's that links none passes. A removal by a non-human stays in the issue's timeline, so no later label change lifts it; a new issue and a new pull request linking it do. report-outcome's `Hold:` line covers the exact label at PR open, and `enable-auto-merge` covers arm time, so the remaining gap was a label added after the pull request opened. A pull request armed before the label landed no longer merges on it. An unreadable link, label list, timeline or trusted-actor list, a bot author with no numeric id, or a jq error matching them, fails closed. This costs one GraphQL read per queued pull request, plus one timeline read per linked issue and a labels read for a `Refs:` issue when an automation opened it. A person's own pull request is not read.

## [5.10.2] - 2026-10-25

### Changed

- The pr-merge merge job now needs post-merge-dispatch, so it reads this run's kept post-merge report instead of racing its upload and running the same check again; on 2026-10-25, 20 of 43 scheduled runs read before the report was kept. `!cancelled()` keeps the job running on pull_request_target, where post-merge-dispatch is skipped, and when that job fails. The reuse rule (same main commit, under REUSE_MINUTES old) and the fallback to the job's own check are unchanged (`.github/workflows/pr-merge.yml`).

## [5.10.1] - 2026-10-25

### Changed

- A changed trust-gate path no longer holds a pull request by itself: the review callers' `hold-paths` only sends those files to extra security scrutiny, and the security lane judges them. An exempt author's pull request (Dependabot, the release App, the standards-sync App), which no review lane reads, still fails on a trust-gate path.
- The verifier fails a change to the takeover set only when it lets someone outside the organization gain trust or weakens a check beyond the spec, treats only a hold on a real charge (not model, effort, turn, timeout or schedule spend) as a hold the owner keeps, and passes a diff too large to judge whole with notes naming the parts it could not judge when those parts are prose or data; an unjudged workflow, action, script, hook, binary or takeover-set file still fails.
- ci-status's cost-only clear is no longer blocked by every lanes App comment in the window, only by a lanes App escalation comment.
- The lost-run reconciler re-runs, once, a pr-verify run whose first attempt failed or was lost before or during its judge step. A run whose verdict write started, which happens only when the judgment succeeded, is held, with the reason in the run summary, even when writing or uploading the verdict then failed, so a head is never judged twice. pr-verify fails a run the lanes kill switch stopped, so the reconciler re-runs it once the switch is off instead of leaving the head with no verdict.

## [5.10.0] - 2026-10-25

### Added

- Intake's size split also copies, as written, the task-list lines of intake's refinement comment on an issue a listed human filed, where admission already counts that comment as spec. A Size Large issue whose done-when lives only in that refinement no longer stays parked with no one asked. Each sub-issue that copies a refinement line names that comment's id and update time in its header.
- Admission and pr-verify trust such a sub-issue only while the named comment is still intake's newest refinement on the parent, never edited, with its update time equal to its creation time or to the recorded one, and only on a parent body a listed human wrote. Every line must be one of the listed human's task-list lines or one of that comment's task-list lines, never its prose; after a listed human's edit, either kind may also have its box ticked, and nothing else. A deleted, edited or superseded refinement makes the sub-issue untrusted, even when a listed human has edited it since.

### Changed

- `merge.rung` is a pacing cap: no work class is read, and no class, missing class or diff shape caps it. The only check that names a class is the local babysit lane's untrusted-provenance hold. That lane also needs a human to vouch for the linked issue: a write-access human wrote it, or one applied the admission label in person with no body edit after. The risk score's `class-contradicted`, `blast-radius-missing` and rung reasons are gone (#9668).
- `merge.diff-check.c2-contradictions` is deprecated and has no effect. The schema still accepts it so existing configs validate, and a config that sets it true gets a `configNotes` entry in the gate's `unattended` report saying it has no effect.

- `resolve-issue` reads any web page and runs the research skills; it was limited to six official docs hosts. It runs on the run-claude-cli launcher, which stages no curl-based docs script, from a job with no write token, and admission no longer refuses a done-when item for naming a page outside those hosts ([pr-pipeline.yaml](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline.yaml)).

### Fixed

- fix-ci no longer hands a pull request to a person (`ci-fix-escalated`) in the same run that pushed its fix: a written patch now pushes with no escalation, whatever the model escalated beside it, and the new head's own CI decides. A red new head gets its own fix-ci run, which escalates what it cannot fix, and `loop.fix-ci-rounds` still ends the rounds with `ci-fix-round-cap` ([pr-run-activity.md](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/pr-run-activity.md#prepare-apply-patch)).

- The issue lane's blocker gate counts the same closes admission does: a size-split parent the lanes App closed once a listed human or a merge closed every sub-issue no longer blocks a run admission already let through (`.github/scripts/work-resolve-issue/check-blockers.mjs`, now on `admit.mjs` `closedByTrusted`).

- The pr-pipeline convention names the repository's default branch, not the pull request's base, as where the merge gate reads admission's `task-list` for a size-split sub-issue.

## [5.9.5] - 2026-10-25

### Fixed

- pr-unblock's publish-feedback step loads again. It runs from a copy of `.github/scripts/pr-unblock/` alone, and the adjudicator module it imports had started loading `request-budget.mjs`, whose `.github/actions` imports do not resolve from that copy, so every address-feedback run failed at publish with `ERR_MODULE_NOT_FOUND`. `adjudicate-feedback.mjs` now loads `request-budget.mjs` only in its `prepare` command, which runs from the full base checkout.

## [5.9.4] - 2026-10-25

### Fixed

- The adjudicator of a disputed review finding now reads the whole review comment and the files and lines it cites, beside the locations the fixing lane cited, instead of only the comment's first paragraph and the lane's locations (`.github/scripts/pr-unblock/adjudicate-feedback.mjs`).
- A disputed code-review finding carrying `severity: CRITICAL`, and a disputed pr-verify verifier note, go to a person again instead of to the adjudicator: resolving a verifier note's thread left its FAIL holding the merge with nothing to say so.
- pr-unblock's `adjudicate-feedback` job runs only when the answering leg's replies hold an `INCORRECT` reply; a round with none no longer checks out, sets up and stages for nothing. Its contents reads are logged in the job's api-budget notice.
- The monitoring lane's rolling issues render each finding's summary inside a text fence, in the body and the change comment, so a mention, link or tag in run or job text no longer works.

## [5.9.3] - 2026-10-25

### Changed

- The pr-pipeline README describes how pr-merge's gate counts a size-split sub-issue the lanes App filed as trusted spec. It does so on the same rule pr-verify applies: every line after the header must be a trusted task-list line of its native parent, or on the edited path that line with its box ticked. A failed read is `verify:unreadable`, and a cut comment page counts nothing.

### Fixed

- work-unblock tells a run the token broker refused for the lanes kill switch, at broker-check or at a lane token request, from other failures by reading the refused job's log (one per run, at most 1 MiB, only the failed step's last line). Such a breaker trip is re-fired an hour after it ended with a record of its own, and past `limits.limit-stops-per-issue` trips on the stranded backoff; it no longer spends the once-per-version re-fire, counts toward the failed-mint bound, or posts the "fault in the lanes" backoff comment. A refusal for another reason, or a log it cannot read, is classed as before (`.github/scripts/work-unblock/label-unblocked.mjs`).

## [5.9.2] - 2026-10-25

### Fixed

- Intake apply-verdict no longer stops the whole verdict when GitHub answers a blocked-by edge read or write with 403, 429 or 5xx: that edge is missed and named in the step summary and a run annotation, and the verdict's other labels still land. Admission and work-unblock read blockers only from the native edges, so the edges that run wrote are deleted again, and a ready verdict with a missed edge lands without `status: ready` and is not admitted; the hourly triage sweep runs intake again on it, and after two runs that leave it so hands it to a maintainer. A 403 fails the job after every write, since no re-run fixes a missing permission (`.github/scripts/intake-triage/edges.mjs`, `.github/scripts/intake-triage/apply-verdict.mjs`).
- Intake refinement no longer lifts the lanes App's `status: needs-decision`, on an exact refinement or a split, while the App's verdict comment lists a security or cost flag or records that whether an earlier verdict flagged is unknown, so an earlier flag a later triage omitted can no longer clear through a refinement and the re-triage after it (`.github/scripts/intake-triage/refine.mjs`).

### Security

- A size-split sub-issue a listed human last edited counts as that human's text only when every line after its header is one of its parent's trusted task-list lines or that line with its box ticked. GitHub names only the last editor, so a listed human ticking a box after another account's edit no longer makes that account's text trusted.
- pr-verify stops, writing no verdict, when a split sub-issue's native parent cannot be read or has more comments than the page it reads, instead of judging the pull request without the sub-issue's criteria. Before, an outsider could pad the parent past the page during a run and delete the padding before the merge gate counted the sub-issue.

## [5.9.1] - 2026-10-25

### Changed

- The hourly work-unblock sweep reads closes from 15 minutes before the last scheduled run whose labeling step succeeded (at most 3 hours back; the full 3 hours when that run cannot be read or did not sweep, as under the kill switch or a lane the config turns off) instead of always the last 3 hours. Metric: sweep passes per closed issue. Baseline: about 3 (hub measurement). Expected: about 1.

- enable-auto-merge logs each verifier read's cost, `enable-auto-merge: #<n> calls=<total> github-token=<n> paginated=<n> ms=<elapsed>`, read from the reader's `babysit-gh-calls` stderr line, and adds the same rows to the step summary even on a run that raised nothing. `calls` counts gh invocations; a paginated one (the artifact listing) made one request per page. A reader that exits non-zero is now reported by its last error line, not by the calls line (`.github/scripts/pr-merge/enable-auto-merge.mjs`).
- pr-merge's merge job records each gate candidate's gh invocations as `calls` in its summary row (`.github/workflows/pr-merge.yml`).

## [5.9.0] - 2026-10-25

### Added

- Intake splits an issue admission parked as Size Large into native sub-issues before any run takes it (owner Q93). The refine model returns only item numbers: the parts over the issue's task-list lines and the order between them. Each part becomes a sub-issue holding those lines as written and taking the issue's Issue Type, the order becomes native blocked-by edges (a refused edge leaves the split unfinished for the next triage to retry), and intake triages each sub-issue. An invalid split leaves the issue parked, with the reason in the step summary.
- Admission and pr-verify count the body of such a sub-issue as the text of the listed human who filed its parent when every line after its header is one of the parent's trusted task-list lines and nobody edited it, or when a listed human last edited it (ticking a task box is an edit). An edit by any other account makes it untrusted. Admission does not park or refuse such a sub-issue for Size Large, since it never splits again.
- Admission waits on an issue while any of its sub-issues is open, and work-unblock closes a split issue as completed once every sub-issue is closed by a listed human or a merge.

### Security

- collect-base-activity makes the base marketplace copy read-only (`chmod -R a-w`) once it is staged, and a write skill's `--disallowedTools` carries `Edit(/$RUNNER_TEMP/base-marketplace/**)`, so neither the skill's file tools nor a process it starts can rewrite the plugin hooks and scripts that load in place from that copy ([pr-run-activity.md](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/pr-run-activity.md)).

## [5.8.1] - 2026-10-25

### Fixed

- An issue's closing pull requests count only the open ones: GitHub lists a merged pull request in `closedByPullRequestsReferences` despite `includeClosedPrs: false`, so admission and the work-unblock sweep waited on a merged closer forever and find-prior stopped the issue lane for one (`.github/scripts/work-resolve-issue/report-outcome.mjs`).

## [5.8.0] - 2026-10-25

### Added

- `limits.api` sets GitHub API margins per pool (`github-token`, `lanes-app`, `graphql`, `owner-token`, `content-creation`), each a share of the limit the pool's `x-ratelimit-limit` header reports: `plan` (0.7), `writer-pause` (0.4), `breaker` (0.2) and `read-floor` (0.1); `content-creation` adds `per-minute` (80) and `per-hour` (500). The defaults live only in the schema. The rate guard reads only `read-floor`; the other fields are thresholds meant for the hub's limits sampler, not enforced here. resolve-config passes the block through as set.

### Changed

- Every lane GitHub call made through createGitHub, the dispatchers' budgetedFetch or the ci-status gh wrapper goes through one rate guard (`.github/actions/log-api-budget/rate-guard.mjs` and its shell port in `api-budget.bash`). A response that shows a pool exhausted (remaining 0, any 429, a 403 naming a rate limit or abuse detection, retry-after, or a GraphQL answer of any status with a `RATE_LIMITED` error or an error naming a rate limit) stops that pool, or every pool for a secondary limit or a 429, until its reset for the rest of the job: later calls are refused without a request, a call GitHub refused fails (one it answered with a 2xx keeps its answer and status, so no write is resent), and a Node step fails red with an error naming the reset. With no usable reset header, a secondary limit stops for a minute and any other limit for an hour; a paginated `gh api` call, whose headers the wrapper cannot see, gets the same from its error text. Under `read-floor` left it warns once and calls continue; ci-status sets the gh wrapper's floor to the schema default. ci-status's gh_read no longer sends a probe request while limited, and waits only for a reset a header gave, never a guessed one. A rate limit on check-born-triaged's read sets its new `rate-limited` output, which stops intake-triage and the needs-triage label. The check-born-triaged read, post-statuses and the maintenance, branch-cleanup and post-merge-demotion-alert scripts' raw API calls go through it too.
- intake-label-needs-triage reads the org and repository kill switches, as intake-triage does; either one stops its API reads and its label.

### Fixed

- The issue lane no longer runs an agent-ready issue that a `blocked_by` issue or pull request still blocks (owner decision Q95). A blocker stops blocking only as admission judges it: a pull request merged in this repository, or an issue closed, for any reason, by a listed human or, in this repository only, a merge; another repository's issue is read there. Admission, work-unblock, the lane's gate and the queued count now share that one rule (`admit.mjs` `blockerDone` and `stillBlocking`).
  - The admit job checks the blockers after the trusted-trigger check. A blocker that still blocks, or blockers it cannot read, skip the run with a notice or warning. The skip takes no model turn, adds no `needs-human`, and leaves `agent-ready` on.
  - work-unblock's sweep never re-fires, strands or hands to a person an agent-ready issue that a blocker still blocks. Once no blocker blocks, it re-fires a run the gate skipped.
  - The same admit step applies admission's provenance rule (`admit.mjs` `untrustedHold`) to a label added by hand. An issue carrying `work-class: untrusted-provenance`, or whose newest removal of it was by neither a listed human nor the lanes App, stops for good with a notice. The sweep never re-fires it and adds no `needs-human`. Labels or events it cannot read skip with a warning, and the sweep retries.
  - Admission no longer keeps an issue out of `admission-deferred` because work-unblock's sweep would not count its blockers: the sweep now counts them by the same rule, so the issue defers and waits its turn oldest first like any other.
  - The WIP cap's queued count leaves out agent-ready issues that a blocker still blocks. It makes at most 30 blocker reads per check.
  - Files: `.github/workflows/work-resolve-issue.yml`, `.github/scripts/work-resolve-issue/check-blockers.mjs`, `.github/scripts/work-unblock/label-unblocked.mjs`, `.github/actions/check-wip-cap/check-wip-cap.mjs`.

## [5.7.0] - 2026-10-25

### Changed

- Past the address-feedback round bound (`loop.review-rounds` plus the one fresh fixer round), a pull request whose open findings all come from the code review lane no longer skips `cost-gated` and waits with no label. It escalates `feedback-not-converging` with the human-gated label and a comment that names each open review thread and gives its own resume steps: resolve the open threads, or reply on one with a write-access fix request and dispatch the lane, since removing the label alone would stop again on the same head. No sweep, schedule or dispatch starts another automatic round; a write-access fix request still gets its own round, and a security or intent finding or a pull request a person gated still escalates `feedback-round-cap` (`.github/scripts/pr-unblock/address-feedback.mjs`, `.github/scripts/pr-unblock/report-escalation.sh`).
- The address-feedback round marker reads `round <N> of max <M>`, M being the cap plus the fresh fixer's round, and a round-cap escalation's neutral `address-feedback` and `publish-feedback` checks add the same line to their summary through `report-check-run`'s new `not-run-detail` input, which shows only that line.

- `work-resolve-issue`'s `resolve-issue` runs on ci-workflows' `run-claude-cli` instead of claude-code-action, on `ISSUE_LANE_CLAUDE_API_KEY` first, in `dontAsk` with an explicit allow list. When that call hands off (an empty key, a credit stop, or a 401 or 402), a new `resolve-issue-handoff` job reads so from the run's job conclusions through the shared `handoff-evidence.sh` and `resolve-issue-subscription` runs the activity again on `ISSUE_LANE_CLAUDE_CODE_OAUTH_TOKEN`; every later job takes the call that ran. See [Issue mode](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/pr-run-activity.md#issue-mode).
- On the launcher, an issue lane's check and verify-script wrappers are staged under `.lane/` (read-only, denied to the file tools), `issue.json` goes to the writable `.lane/scratch`, and its skill reads git only through a staged `git-read` wrapper that runs `git status`, `diff`, `log` and `show` and refuses options that write a file or read one outside the checkout. See [Two calls on one credential each](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/pr-run-activity.md#two-calls-on-one-credential-each).
- The read runner's launcher step and leg timeouts now derive from the run job's `timeout-minutes` (10 and 15 minutes under it); the issue sizes' timeouts grow by 15 minutes (small 65, medium 115, 40 without dimensions) so each leg keeps the time its turn budget was set for, and a first call hands off on `run-claude-cli`'s `handoff` output, which adds a 401 or 402 to the credit stop, in PR mode too.
- `resolve-issue` routes to the `code-fix` model profile, since the launcher needs a model alias; the reuse summary pass also runs on the launcher.
- A run the launcher stopped at its leg timeout (class `timeout`) with no outcome of its own is now a turn-cap stop: it keeps `agent-ready`, work-unblock restarts it within `limits.turn-cap-restarts`, and the next run resumes its branch, instead of handing back as `stopped`.

- An issue run of the read runner (`work-resolve-issue`'s `resolve-issue`) now hands its reply, run fields, patch and outcome files to the scan job only sealed to the scan-carrier key, as a PR-mode run does. The scan job opens them, scans them for credentials, and is the only job that uploads them; the run job uploads nothing and shows no model text in its step summary. See [The scan job](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/pr-run-activity.md#the-scan-job).
- The read runner's patch outputs now come from the scan job alone. Its issue outputs (`scan-issue-run-started`, `scan-reuse-branch`, `scan-resume-branch`, `scan-resume-tip`, `scan-base-sha`) come from a new `issue-fields` job, which runs whatever the run job's result, holds each run job field to its closed set and combinations, and re-derives any branch claim with the default-tip earlier-work check. `work-resolve-issue.yml` reads only these, and the reuse summary job takes its code from the default branch tip. The run-job-sourced `issue-run-started`, `reuse-branch`, `resume-branch`, `resume-tip` and `base-sha` outputs are removed.
- The skill's `work-outcome.json` is cut at 48 KiB, down from 64 KiB, so every sealed payload at its cap still fits the five chunks a job's outputs hold.

## [5.6.0] - 2026-10-25

### Changed

- work-unblock and the hourly triage sweep no longer stop an item for a person outside an intent or security question (owner intent, 2026-10-24):
  - A stranded issue already re-fired on its lane workflow files, or a lane token request that keeps failing, is re-fired again on a backoff (three hours, doubling, at most 24) with one comment edited in place, never `needs-human`.
  - A lanes App PR merged with `Refs:` or closed unmerged takes `status: ready` and `agent-ready` off and adds no `needs-triage`, so the triage sweep sends the issue back to intake, whose fresh `status: ready` re-admits it.
  - A blocker closed by a listed human or a merge in this repository counts whatever its close reason, and another repository's blocker counts once a listed human closed it there (a merge there, or another repository's pull request blocker, never counts).
  - A listed human's open pull request for an issue counts as work running on it, so work-unblock does not re-fire or relabel it.
  - The triage sweep re-dispatches intake for any issue with no `status:` label and no `agent-ready` or person's hold, whatever comments intake left (an issue the lanes App opened included), and for a born-triaged issue in `status: ready` that nothing admitted. After two dispatches in one triage cycle (a work-unblock hand-back starts a new one) it labels the issue `needs-triage` and says so in its own comment on the issue, instead of filing a new issue, and later passes skip that issue unread while it carries `needs-triage`.
  - Admission on a blocker's close takes the issues it would label oldest opened first (owner Q95) (`.github/scripts/work-unblock/label-unblocked.mjs`, `.github/scripts/maintenance-audit-lane-runs/triage-sweep.mjs`).

## [5.5.1] - 2026-10-24

### Fixed

- A handoff job's log now shows the decision: `handoff-evidence.sh` prints one line naming each settled fact and the read count, such as `handoff evidence: posted=false allowed=true (1 read)`, before it exits successfully (`.github/scripts/lib/handoff-evidence.sh`).

## [5.5.0] - 2026-10-24

### Added

- Intake writes a native blocked-by edge for each open issue in the repository the triage names on a new `Blocked by: none|#N[, #M]` verdict line, before admission reads the blockers; only `#<number>` tokens count, the issue itself, pull requests, closed and other-repository issues and existing edges are skipped, and at most 50 are written (`.github/scripts/intake-triage/edges.mjs`, `.github/workflows/intake-triage.yml`).

### Changed

- Intake admission now treats a blocker closed as not planned or a duplicate as no longer blocking, and reads another repository's blocker there instead of waiting on it for good. A blocker here still needs a close by a listed human or a merge; another repository's blocker counts only on a listed human's close.
- Intake admission takes the unblocked issues oldest first: an issue that passes the rules while an older open issue waits in `admission-deferred` is deferred behind it, and the hourly sweep admits them in order. While the sweep still counts only completed or merged blockers in this repository, an issue that rests on any other blocker never gets `admission-deferred`, which the sweep would drop without admitting it: with room it is admitted without that wait, and with the lane full it waits with a comment.
- The admission refusal comment no longer asks a person to add `agent-ready` by hand; it names what admission needs.
- An issue admission would refuse only for Size Large (split at intake pending, owner Q93) is parked instead: it keeps `status: ready`, gets no `status: needs-decision`, loses `admission-deferred` and gets a comment naming what it waits on. Any other refusal reason still refuses and names both.

- Intake triage stops an issue for a person only on intent or security. A `status: needs-decision` or `status: needs-info` the lanes App set on an earlier run gives way to a clean verdict and is taken off only when the App's earlier verdict comment lists no `flagged:` reason; a listed flag, or no App verdict comment at all (an issue held before these comments), keeps the hold, and the new comment carries it forward; `needs-human` is never lifted, whoever set it, and a hold from the triage run's own escalation, a listed human or an unread setter still holds. A `needs-triage` the triage left no longer keeps a clean verdict from `status: ready` and is taken off after the verdict. An issue field a listed human set to another value is kept and is the value admission reads, without a hold; one from any other setter still holds. GitHub keeping other field options than `models.issue-dimensions` maps fails the run without adding `status: needs-decision`. Whenever the verdict sets `status: needs-decision`, the reasons go on the issue in one lanes App comment edited in place, not only in the step summary; a held verdict writes that comment before its labels and, when the write fails, adds no label and removes none but `status: ready`, names the failure in the step summary and fails the job, so no hold lands without its record; a ready verdict that admission refused or did not finish leaves that comment too, and a failed write there still rewords the lane comment and fails the job (`.github/scripts/intake-triage/apply-verdict.mjs`).

### Fixed

- ci-status fails a ready pull request whose review lane the kill switch stopped (`CLAUDE_LANES_DISABLED`, `CLAUDE_LANES_REPO_DISABLED`, or a lane's own `CLAUDE_REVIEW_DISABLED` or `CLAUDE_SECURITY_REVIEW_DISABLED`), naming the lane: "did not run on <head> (<run>): a kill switch was on when it started. Once it is off, re-run all jobs of <run>; ci-status re-runs when it finishes." Before, a stopped lane passed, so a head pushed while the switch was on could merge with no review. The kill switch pauses review and never waives it; the admin bypass stays the break-glass.
- ci-status reads only review runs from this repository's head. A fork's run on the same commit, even the newest, no longer decides a lane, and a pull request whose head is a fork fails as a fork before any run is read.

## [5.4.0] - 2026-10-24

### Changed

- Intake refinement no longer stops an issue for a person on its own: a split of done-when items an unattended lane run cannot perform files no `needs-human` child issue, and lists those items in the refinement comment as checks a person runs, leaving the rest of the done-when in the body for admission; the lanes App refines each version of an issue body once instead of each issue once; an exact refinement that finds a duplicate or fixing change asks whether to close the issue instead of failing the run; and an issue edited while the model ran is triaged again instead of left waiting (`.github/scripts/intake-triage/refine.mjs`, `.github/workflows/intake-triage.yml`).
- work-unblock lifts the `needs-human` hold report-outcome put on an issue for a lanes App `Refs:` pull request when that pull request closes unmerged, not only when it merges, and hands the issue to triage (`.github/scripts/work-unblock/label-unblocked.mjs`).

### Fixed

- The lane sweep's file step drops a finding whose slice is not its unit's, whose workflow is not its slice A or D unit's, or whose job is not among the jobs its unit's data lists, so a judge steered by CI log text cannot put a finding in the digest against a workflow or job its unit does not show. A unit that lists no jobs leaves the job unbound; the free-text signature still lets a steered judge mint fresh fingerprints, which land only as digest entries, at most 3 per unit.

## [5.3.0] - 2026-10-24

### Changed

- The monitoring lane keeps one rolling issue per signal, `Monitoring: <signal>`, in place of one issue per signal and key. It rewrites the body and adds a comment only when the signal's state changes, closes the issue when the signal clears, and reopens the same issue when it fires again; it never files a second. GitHub incidents are listed in the run summary and no longer filed. Open issues from the per-key form are closed as not planned, pointing at the signal's rolling issue (`.github/scripts/maintenance-monitor-signals/`).
- The lane sweep writes its findings into one rolling digest issue, `Lane sweep: open findings`, in place of filing an issue per finding. A sweep whose findings or their tracking issues changed replaces the body, so a fixed finding drops off; when the collector or a judge leg read only part of the day, earlier entries carry over (`.github/scripts/maintenance-audit-lane-runs/file-findings.mjs`, `findings.mjs`).
- Neither lane labels its issues `needs-triage` any more; each keeps its `source:` label. Each rewrite takes `agent-ready` off the rewritten issue, since a person vetted the earlier text. The [pr-pipeline README](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md#the-monitoring-lane) has the rules.

- A review finding `address-feedback` answers `INCORRECT` no longer hands the pull request to a person. pr-unblock.yml's new `adjudicate-feedback` job gives a fresh-context model, once per disputed thread (up to three a round), the finding's claim without its rationale, the locations the lane cited without its note, and those files at the head. It runs on `run-claude-cli` under `dontAsk` with Read alone, confined to its own slot by Read denials on the base checkout and the runner's temp directory (where the lane's replies, with its reasoning, sit), with each staged file under a `.txt` suffix so a cited `CLAUDE.md` is never loaded as instructions, and returns `lane`, `reviewer` or `human` as structured output. The model route is the new run route `adjudicate-feedback`, on the `review` profile (Opus), above the review lanes' `pr-review` (Sonnet at effort high). `publish-feedback` applies the verdict with fixed text: `lane` replies and resolves the thread; `reviewer` replies that the finding stands and leaves it open, and the next round works it again (`threadAuthors` keeps it); `human` escalates `feedback-question-intent`, `feedback-question-design` or `feedback-question-security`. A thread a trusted person directed (a fix request, or a reply after an escalation) is not adjudicated: an `INCORRECT` reply on it escalates `feedback-disputed`. Only a code-review lane finding (a github-actions[bot] comment ending in the `claude-lane: claude-review` footer; the same footer in a claude[bot] comment, whose body the model writes, names no lane) or a verifier note is adjudicated: a disputed security-review finding, or one whose lane its comment does not name, always goes to a person as `feedback-disputed`, and no verdict resolves it. A thread whose finding stood is not adjudicated again: the next round's `INCORRECT`, `UNCERTAIN` or `VALID-defer` on it escalates `feedback-disputed`. No verdict escalates `feedback-unadjudicated`. A stands verdict in a round that left the head unmoved, so no review run follows, skips the reply check as the new `finding-stands`, and `pr-feedback-dispatch.yml`'s half-hourly sweep dispatches that head again, as it does after `no-model-turn`; the select job's round cap and the sweep's three skips per head bound it. Verdicts are checked against the head the select job read, so a round that pushes a fix for one thread still applies the verdict on another. The write file takes `review-adjudication-attempt` and `review-adjudication-sha256`. No label is added; `fix-ci`, `resolve-conflicts`, `fix-docs` and `apply-patch` keep running while a thread is disputed, and the open thread still holds the merge.

### Fixed

- A handoff no longer depends on step data GitHub's jobs listing can return late or empty. Every handoff read (pr-unblock's five handoff jobs and `fix-ci-unreported`, and pr-refine's `fix-docs-handoff`) now runs one script, `.github/scripts/lib/handoff-evidence.sh`, which decides from job-level conclusions first: a skipped report job means no check was posted, and a new read-runner job, `broker-allowed`, succeeds only on broker-check's allow. Only a report that ran is read through its step, and that read is retried with backoff for about five minutes, then fails the job with one error line naming what stayed missing. Before, an empty step list read as "not allowed", so an empty or credit-stopped key ended the item stopped instead of starting the subscription leg, and as "not posted", which started a second leg after a call that had posted.

## [5.2.1] - 2026-10-24

### Changed

- Intake triage no longer holds an issue for cost when the work only spends from a flat or prepaid source: model runs, lane runs and `claude plugin eval` passes bill the prepaid API keys, which do not auto-refill (owner Q37). Only a new or renewing charge (Actions billing, Azure, a key or plan that renews or auto-recharges) is cost (`.github/workflows/intake-triage.yml`).

## [5.2.0] - 2026-10-24

### Added

- intake-reenter sends an issue back to intake triage when a listed human removes `needs-human` and leaves no `status:` label, no `agent-ready` and an author intake admits.

## [5.1.0] - 2026-10-24

### Changed

- On an issue whose body a listed human wrote, and last edited if ever, intake triage's newest refinement comment (opening `<!-- intake-triage refinement -->`) by the lanes App now counts as spec while it is unedited: pr-verify's `resolve-pr.mjs` gives it to the verifier as spec text when it was posted before the pull request opened, and admission (`admit.mjs`) counts its task list for criterion 7. The lanes App is the trusted-actor list's id for `merge.agent-identity` in pr-verify and the list's id for the App's login in admission. An edited newest refinement counts nothing and no older one stands in for it; an App-filed issue, a body someone else last edited, a comment whose first text is not exactly the marker, and any other Bot's or App's comment stay out. A lane pull request still never supplies its own spec. The refinement stays out of the recorded spec comments the merge gate compares, whose filter stays human-only, so the gate does not see a refinement edited, hidden or added after a pass; an edit only removes it from spec. Intake's refinement banner and `refine.mjs`'s criteria check follow the rule.

## [5.0.0] - 2026-10-24

### Changed

- At the address-feedback round cap (`loop.review-rounds`), a pull request whose open findings all come from the code review lane no longer goes to a person. One more round runs on every kept thread, a fresh fixer in a new session like every round, and the round marker names it as past the cap. After that round the select job skips `cost-gated`, adds no label, and waits for the next write-access fix request. A security lane finding, a pr-verify note (an intent mismatch), a `claude[bot]` finding, whose lane no footer proves, or a pull request a person gated with the human-gated label (its hold lifts only on a fix request newer than the last round) still escalates `feedback-round-cap`, before and after the fresh fixer's round.

- pr-merge's `enable-auto-merge` job skips its work, green with a notice, when another run's `enable-auto-merge` job still waits and does the same work, so a backlog of events costs one pass instead of one serial pass each. On a pull request event it runs only for a lanes App pull request (`AUTOMATION_LANES_APP_SENDER_ID`), so any other pull request's check reads skipped instead of pending behind the queue.
- pr-merge's merge job reuses its run's `post-merge-dispatch` check when that check judged main at the merge job's commit under six minutes ago, instead of running the same check again.
- The merge and `enable-auto-merge` jobs read main's pr-merge run listing, each run's artifact list and each compare once between their kept-file readers (the gate cursor, the head-ref map and the lane records).

### Removed

- **Breaking:** the `admission` and `work-classes` keys of `applies-when` are gone from the schema, so a `pr-pipeline.yaml` that still sets either fails validation; delete the key. No pipeline predicate reads a work class (owner decision Q85, [#9668](https://github.com/melodic-software/claude-code-plugins/issues/9668)): an issue with no class or any class, `work-class: structural` included, is decided by its labels, events and holds alone. resolve-issue's PR still carries `Hold: a human merges this` for an issue labeled `work-class: untrusted-provenance`, a trust hold that reads no other class.

### Fixed

- pr-merge's refire step now reads the annotations of a failed pr-unblock write-runner job (`<caller> / run`) when the jobs API lists its steps empty or cut short without the token step, so a refused run still gets its empty commit. A job that lists the token step as passed, and any job that is not a write-runner job, are still skipped.
- The red-main report counts a failed job that lists no failed step as a failing check of its own, matching the post-merge check.
- The demotion alert judges failing checks with red-main's rule (`failing-checks.mjs`) instead of its own shell copy. A failed job that lists no failed step now files, and, as a baseline entry, such a job excuses nothing.

- A merge job no longer skips its gate citing a pending run whose merge job already ran: a run reads pending while any one of its jobs waits, so the skip now reads the pending run's jobs and counts it only while its merge job still waits.

## [4.21.0] - 2026-10-24

### Changed

- A review-dependency `merge` verdict on a Dependabot pull request that changes a workflow or action file no longer waits for a person, and the `dependency-workflow-held` escalation reason is retired. The verdict job instead posts the merge marker only when that change is a full-SHA pin swap: every changed line in those files a `uses:` line that keeps its indent and action path, with both refs full 40-hex SHAs, so only the SHA and the trailing comment differ. Anything else (a tag ref, a path change, a new step, a `run:` change, an added or removed line, an added or deleted file) escalates the new `dependency-workflow-unpinned`. A lane fix still never lands under `.github/`.

- An issue run of the read runner (`work-resolve-issue`'s `resolve-issue`) now hands its reply, run fields, patch and outcome files to the scan job only sealed to the scan-carrier key, as a PR-mode run does. The scan job opens them, scans them for credentials, and is the only job that uploads them; the run job uploads nothing, and its step summary shows no model text but a gate skill's verdict. See [The scan job](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/pr-run-activity.md#the-scan-job).
- The read runner's patch outputs now come from the scan job alone. Its issue outputs (`scan-issue-run-started`, `scan-reuse-branch`, `scan-resume-branch`, `scan-resume-tip`, `scan-base-sha`) come from a new `issue-fields` job, which runs whatever the run job's result, holds each run job field to its closed set and combinations, and re-derives any branch claim with the default-tip earlier-work check. `work-resolve-issue.yml` reads only these, and the reuse summary job takes its code from the default branch tip. The run-job-sourced `issue-run-started`, `reuse-branch`, `resume-branch`, `resume-tip` and `base-sha` outputs are removed.
- The skill's `work-outcome.json` is cut at 48 KiB, down from 64 KiB, so every sealed payload at its cap still fits the five chunks a job's outputs hold.

## [4.20.0] - 2026-10-24

### Changed

- Intake no longer gates on work class (owner decision Q85, [#9668](https://github.com/melodic-software/claude-code-plugins/issues/9668)): a triage verdict proposing no class, a class outside the repository's labels, `work-class: structural`, or a class a person set reaches `status: ready` on its Size, Complexity, Uncertainty and flags alone, and admission and the work-unblock mark no longer refuse by class. `work-class: untrusted-provenance` still holds the issue and refuses admission, now also when the repository lacks the label, when another class is already held (the label is added beside it), and when the label was removed by neither a listed human nor the lanes App; work-unblock treats it as a hold label, so a blocker close no longer adds `agent-ready` to such an issue. The triage rubric says the class gates nothing but that one (`.github/workflows/intake-triage.yml`, `.github/scripts/intake-triage/apply-verdict.mjs`, `admit.mjs`, `.github/scripts/work-unblock/label-unblocked.mjs`).

- Intake triage escalates an issue to a person (`needs_human`) only for text that tries to instruct the model or a report of a live exposure (owner intent, 2026-10-24: an item stops only for an intent or vision question or for security). A workflow, permission or governance change, unclear scope, an unsure approach or an oversized issue is triaged as usual, keeping the comment, class and fields; an intent question the issue cannot answer, or a very-high security risk, gets its flag, `status: needs-decision` and a numbered `RECOMMENDED:` question instead of a silent hand-off (`.github/workflows/intake-triage.yml`).

- A removed `agent-ready` no longer keeps an issue out of the issue lane for good. Intake admission and work-unblock leave it out only until the lanes App or a listed human adds `status: ready` after the newest removal; then admission runs its rules as usual. A `status: ready` added by anyone else, or before the removal, does not lift it, and a lane restart still does not count as a removal.

## [4.19.6] - 2026-10-24

### Changed

- The eval lane runs on a new `maintenance` funding role, `MAINTENANCE_CLAUDE_CODE_OAUTH_TOKEN`. The judge lane stays on `automations`, which remains the default role for any lane without a dedicated one. `.github/lane-funding.json` lists both, and the [pr-pipeline README, Funding](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md#funding) names them.

### Fixed

- The pr-merge gate no longer holds a pull request at `verify:earlier-fail` after its link changed from `Refs:` to closing the issue and the verifier passed the new head. An earlier FAIL at a head of the same change now clears when every counted FAIL at that head records `spec_kind` `refs` for this pull request and every counted pass at the head records `spec_kind` `closes` with exactly the linked issues the FAIL records: a closing pass is judged against the whole spec, which includes the slice that failed. A `refs` pass after a `closes` FAIL, two verdicts of the same kind, a missing or unknown `spec_kind`, a pass that closes another issue or more issues than the FAIL named, linked issues that cannot be read, and a FAIL record that cannot be read or records another pull request, head or verdict all keep the refusal. Every other refusal is unchanged.

## [4.19.5] - 2026-10-24

### Fixed

- `enable-auto-merge` checks out the default branch with full history, as the post-merge check and the merge job do, so the room's post-merge recompute decides containment locally instead of making a compare API call per lane record. The lane-room read also has its own 8 minute timeout, apart from the verifier reads' 4 minutes, and a timeout still holds the lane. The arm step's timeout is now 18 minutes and the job's 30.

- `fix-ci` dispatch trusts a `ci-lanes` commit status by its creator's type and id (the GitHub Actions bot, `Bot` 41898282) instead of the login `github-actions[bot]`, which GraphQL never returns (it reports `github-actions`); no pull request was dispatched while the login check stood. A status set by any other actor, or with no creator, is still ignored.
- The dispatcher logs why it skips a listed pull request whose `ci-lanes` status failed or errored, so a skip of that kind is no longer silent; a failed status the GitHub Actions bot did not set is named as such.

## [4.19.4] - 2026-10-24

### Fixed

- The work-resolve-issue lane no longer opens a `Refs:` PR for an issue its run delivered whole. `report-outcome` derives the link line from the outcome's `remaining` list and ignores the run's `link` field: a non-empty list opens a `Refs:` PR with a `## Remaining work` section naming each part, which is the remaining work pr-verify's Refs rule asks the body to name. A `remaining` that is not 1 to 20 strings, each with text in the bullet it renders as, counts as empty, so the PR closes the issue. The run text the lane quotes in a PR body or comment also drops C1 control characters now.

## [4.19.3] - 2026-10-24

### Fixed

- A pending lane merge no longer makes `enable-auto-merge` disarm every armed lanes App pull request. The post-merge step takes about as long as the gate's two-minute reuse age, so the lane's room read the report as too old. It now keeps the report while nothing it was read from has moved, and otherwise checks again as the gate does, with the lane records the last run kept, so that check reads them without an artifact or run read each. When the room is held, by a refusal or because it cannot be read, the run raises one warning annotation and step-summary line naming the reason and each lanes App pull request it left unarmed or, in report-only mode, that a disarm would have turned off. A pull request still armed because its disarm failed gets an error annotation and summary line instead. It posts no comment on the pull requests.

## [4.19.2] - 2026-10-24

### Fixed

- The pr-unblock dispatcher no longer sends resolve-conflicts to a Dependabot head (a `dependabot/` branch Dependabot opened): its merge commit stopped Dependabot's own rebases, which resolve the conflict.

## [4.19.1] - 2026-10-24

### Fixed

- The pr-unblock `review-dependency` round cap counts only round markers at the pull request's current commits, so a `@dependabot recreate` or force push no longer carries the replaced head's rounds into the new one. A marker that names no head still counts.

## [4.19.0] - 2026-10-24

### Added

- A listed human adding `admission-deferred` to a decided issue with `status: ready` now has the hourly work-unblock sweep run intake's admission rules on its own work-class label and Size, Complexity and Uncertainty fields, each counting only when a listed human or the lanes App added or set it, admitting it when there is room and refusing it to `status: needs-decision` with a comment otherwise.
- The sweep now re-fires an `agent-ready` issue left with no run and no report for 3 hours, once per version of the lane workflow files, and then hands it to a person with `needs-human` and a comment.

### Changed

- Intake admission now reads the `- [ ]` acceptance criteria only from text a listed human wrote, in the body or a comment of their own, since pr-verify judges a lane pull request only against that text (owner decision Q9). The lanes App's refinement comment no longer satisfies the criteria check; a person who confirms it posts the criteria as their own comment.
- Intake admission now refuses an issue with more than 100 comments, since pr-verify reads only the first 100 and stops on such an issue.

## [4.18.0] - 2026-10-24

### Changed

- This repository sets `merge.dependabot.majors: review`: a Dependabot major, unreadable or disagreeing update merges on the pr-unblock review's `verdict=merge`, as any tier `review` update does, instead of waiting for a person (owner direction 2026-10-24; ADR 0073 addendum).
- `dependency-classify.mjs` reads a security update's version jump from its verified commit subject when the metadata has no `update-type`, matching the pr-merge classifier.
- `clear-escalations.mjs` clears a pr-merge Dependabot-major escalation when the head moves, like pr-merge's other escalations.

## [4.17.1] - 2026-10-24

### Changed

- A lane escalation's `needs-human` no longer stops the other fixers that could clear its cause. `resolve-conflicts`, `apply-conflict-patch`, `fix-ci`, `apply-patch` and `fix-docs` drop `needs-human` from their `labels-absent` (they keep `do-not-merge`); their dispatchers and base-code jobs (`resolve-conflicts-select` and `fix-docs-head` through the new `lane-hold.mjs`, and `fix-ci-context`) hold the human-gated label unless `gate-source.mjs` reads it as a lane escalation whose reasons, from report-escalation's `- Reason:` line, are another activity's. A person's label, a person's comment or review since the label went on (read from the REST issue timeline the way `clear-escalations.mjs` reads one, now one shared `spoken`), an escalation reason report-escalation.sh does not list, a review-lane hold or anything ambiguous still holds as `awaiting-human`. The dispatchers read a held PR's timeline once per run between them, and fix-docs reads it only for a PR not yet refined. When they work past the label, the write runner's `patch-fix-requested` lifts only the human-gated hold for that push, under any patch row. The label stays on, so `pr-merge` still refuses the PR. The verdict is read before the model turn, so a hold that lands during a run stops the next dispatch, not that run's push; `do-not-merge` still stops it.
- `report-escalation.sh` is idempotent per resume key and reason: a second activity escalating on the same head while the label is on posts its own comment, so that activity's own escalation holds it.

### Fixed

- A failed `pr-unblock / resolve-conflicts` run no longer marks its head handled for good: the dispatcher retries it until `limits.limit-stops-per-head` failures (limit stops included) stand on the head.
- A resolve-conflicts run skipped while the pull request was held (`Skipped: awaiting-human`) no longer marks its head handled: the dispatcher skips a held pull request itself, without recording it, and the next sweep after the hold comes off dispatches it. Held skips count toward `limits.limit-stops-per-head` with failures, for resolve-conflicts and fix-ci alike, so a hold the run reads and the dispatcher does not stops there. The dispatch record's version is now 4, so heads recorded under the old rule are read again.
- fix-ci no longer leaves a head for good after a run that found no failing check (`not-applicable`) or `fix-ci-restarts` failed runs: once the base tip moves past those runs the dispatcher dispatches the head again, until `limits.limit-stops-per-head` such runs stand on it. A new head starts with none.

- `enable-auto-merge` posts the gate's `<!-- babysit-merge-pin sha=<head> -->` comment before it arms a lanes App pull request, unless the App's newest pin already names that head unedited. When the pin fails to post, the pull request stays unarmed and the run fails. Arming a pull request that is already mergeable enqueues it at once with no auto-merge event, so the post-merge check now reads that head back against the pin.

## [4.17.0] - 2026-10-24

### Changed

- A trusted spec edit after a pass no longer strands the head at `verify:spec-changed`. `resolve-pr.mjs` judges a head again, with reason `spec-changed`, when every counted pass there started before the spec's last change (an issue body edit, a spec comment added or edited, or a body edit of a pull request that is its own spec), and the lost-run reconciler re-runs, once and with a record, the passed `pr-require-checks` run of such a head so pr-verify starts. The gate decides on the passes of the pr-verify run that started last, so the new verdict replaces the stale one. Each passed checks run is re-run once; a changed closing set and a removed spec comment still wait for a person.
- The verifier prompt no longer fails a pull request for touching workflows, CI, hooks, scripts, agent instructions, package manifests, lockfiles, path or file-type refusals, a `merge: human` setting, deploys, cloud, releases or other repositories; those are judged as ordinary code. It fails a change to the takeover set (the trusted-actor list, the `check-trusted-trigger`, `check-kill-switch`, `request-lane-token` and `resolve-config` actions, `CODEOWNERS`, submodules) whatever the spec says, unrequested work that loosens a hold the owner keeps (outside-organization work, cost and billing, rate, capacity, work-in-progress and round caps), and unrequested work on secret values or organization or repository settings.
- Spec trust is unchanged: text the lanes App wrote, an issue it filed or intake triage's refinement comment included, is still not spec. Trusting it is held for an owner decision.

## [4.16.0] - 2026-10-24

### Added

- Intake refinement now files the split admission recommends. When admission holds an issue at the lanes App's `status: needs-decision` only because some, not all, of its done-when items ask for what an unattended lane run cannot perform, and the triage raised no flag, the `refine-issue` run judges the split. When the model returns exactly the held item numbers, `apply-refinement` files one child issue as the lanes App, labeled `needs-human` and born triaged, that holds those items as written, with their indented sub-lines, and links back. It then replaces them in the issue body with one line linking the child, lifts `status: needs-decision`, and triages the issue once more so admission reads the rest. The refinement marker keeps it to once per issue, and a retry reuses the child it filed. A proposal that names any other items, drafts criteria or asks questions alongside a split is refused before anything is written.

### Fixed

- An address-feedback round whose reply job skipped `no-model-turn` no longer waits for a review or `pr-verify` run that may never come. `pr-feedback-dispatch.yml` also runs when a scheduled `pr-unblock-dispatch.yml` run completes (its half-hourly tick), and sweeps the open lanes App pull requests into `main`. The first head whose newest `pr-unblock / publish-feedback` check skipped `no-model-turn`, fewer than three times at that head, is decided and dispatched as for its newest completed review run, which the dispatched-run record names. A tick dispatches at most one head, keeps no dispatch record, and moves past a pull request it cannot read. The dispatcher stays a `workflow_run` run, so the trusted-trigger gate and the broker check it unchanged.

- Admission waits only on an open pull request in this repository that is for the issue: one GitHub lists as closing it (`closedByPullRequestsReferences`), or one whose body has the issue lane's `Refs: #<issue>` line. A pull request that only mentions the issue no longer defers admission, in `admit.mjs` or in work-unblock's sweep of `admission-deferred` issues.
- `publish-feedback` accepts an earlier fix on a retry. When the compare range holds no lane fix commit and the round wrote no patch, each `VALID` thread's fix may be the newest earlier commit on the pull request that the lanes App made through the API with the push job's `Lane-Activity` trailer, committed after the thread's newest comment by the reviewer, the verifier or the lane, that changed the thread's path and a line the reply's evidence cites (in a file no later commit on the pull request changed), and that no lane reply already names as a fix. A commit the lane already answered on that thread, or one the reviewer raised the finding again after, does not count. Before, a round whose fix had landed but whose replies did not post left every thread open, and every retry ended `feedback-not-landed`.

## [4.15.1] - 2026-10-24

### Fixed

- pr-merge's enable-auto-merge job no longer fails its arm with `fetch failed` after a long verifier read. Every request now sends `Connection: close`, so none goes out on a pooled keep-alive connection that sat idle while the verifier ran and that GitHub had closed. A GraphQL request that still fails on the network (Node's "fetch failed", or a cause code of `ECONNRESET`, `ETIMEDOUT`, `UND_ERR_SOCKET` or `UND_ERR_CONNECT_TIMEOUT`, or "other side closed") is sent up to twice more (a REST write, such as the refusal comment, never is), after full-jitter waits capped at 4 s and then 8 s. An HTTP error answer or a GraphQL error is not sent again. A resent arm passes the same `expectedHeadOid`, so it arms only the head the run read. A pull request whose arm or disarm still fails is left as it was and named with the error's cause code and message, with any token scrubbed. The run then goes on to the other pull requests and exits 1.
- A lanes App pull request that native auto-merge leaves unarmed no longer sits with only an Actions log line to say why. On a scheduled or hand-started run, a refusal on a hold path, a cost path, the gate's verifier verdict or its risk score is written on the pull request in one `<!-- babysit-merge-risk -->` comment that names the head and the reason. The comment is edited in place when the reason changes, and left alone while it does not. A refusal a person must clear also gets the human-gated label: a hold or cost path, an issue link the lane does not take, a verdict the gate marks `needsHuman`, or a risk hold that has stood unchanged for `merge.risk-escalation-minutes`. That comment carries the attended queue's escalation marker. A refusal the lanes clear on their own, such as a missing verdict, gets the comment only. A label a person removes stays off until the reason or the head changes.

- report-outcome's hand-backs (pushback, stopped, a refused patch, a dimension skip and a turn cap with no restart left) open with `<!-- work-items:escalation lane=work-resolve-issue kind=escalated -->`, then the outcome marker, so `/work-items:attend-queue` lists the issue as escalated. The outcome-marker parser that `issue-prior`, work-unblock and the monitor signals share reads the outcome marker after that one line.

## [4.15.0] - 2026-10-24

### Changed

- resolve-config no longer adds `.github/**` to `merge.diff-check.denied-paths`; it still adds the config file's own path and the trusted-actor list. A lanes App pull request touching `.github/scripts`, `.github/actions` or another `.github` path off the merge gate's HIGH floor is no longer held by report-outcome's `Hold:` line, `enable-auto-merge` or `ci-status`, and merges on the two review lanes (owner direction 2026-10-23). The lanes App's token never carries the `workflows` permission, so no lanes App push changes a workflow file; another identity with write access can still push one after auto-merge is armed. Hold paths now match case-insensitively, as the merge gate's `glob_match` does, so `.github/codeowners` or `.github/actions/Resolve-Config/` holds. The floor also holds `.github/actions/check-kill-switch/**`, whose output writer check-trusted-trigger and resolve-config load; a test walks both actions' imports and fails on any file the floor does not hold.
- `merge-holds.mjs` no longer holds every `plugin.json` and `marketplace.json` path-wide. Its hold-path floor is the forced paths plus the merge gate's HIGH floor (`babysit_risk.HIGH_FLOOR`), and `ci-status` compares a changed manifest base against head as the gate's manifest review does (`manifestChanges`, the rule of `babysit_risk._manifest_changes`): an executable `plugin.json` key or `experimental.monitors`, a marketplace plugin added, removed, renamed or re-sourced or a marketplace `name` change, a removed, renamed or copied manifest, and a side that does not read or parse or repeats a key hold; a `userConfig` default or version change merges. `enable-auto-merge` arms such a change once the gate's risk score (`evidence --lane-reviews`) allows it. ci-status now hands the module each file's status and the base commit.

- Intake admission also takes issues whose Uncertainty is Knowable (`admission-rules.json`), which the run lane already runs research-first (owner decision 2026-10-24, amending Q51 criterion 3).

- The intake, pr-unblock and pr-verify lanes run on their own funding roles' secrets instead of the `automations` pair. `intake-triage.yml` passes `role: intake` with `INTAKE_CLAUDE_API_KEY` and `INTAKE_CLAUDE_CODE_OAUTH_TOKEN`, and its intake reusable pins ci-workflows [`b0ecc27`](https://github.com/melodic-software/ci-workflows/commit/b0ecc273abe492d12f2efa98ee4741a84c219ed2), whose runner-policy contract names that role ([standards#863](https://github.com/melodic-software/standards/pull/863)). Every Claude job in `pr-unblock.yml` and the fix-docs jobs in `pr-refine.yml` pass `role: pr-unblock` with `PR_UNBLOCK_*`, and both `pr-verify.yml` jobs pass `role: pr-verify` with `PR_VERIFY_*`. Each run's `credential=` now names its own role's secret. `.github/lane-funding.json` lists the new secrets, the read-run secret allowlist in `scripts/check-read-caller-keys.mjs` admits `PR_UNBLOCK_*` in place of `AUTOMATIONS_*`, and `callers.test.mjs` fails when a catalog lane reads another role's secret or passes a `role:` other than its own ([pr-pipeline README, Funding](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md#funding)).

### Fixed

- An issue-lane run that waited in its slot while a change to `work-resolve-issue.yml` or `pr-run-activity-write.yml` merged no longer fails red as `workflow-stale`. The read runner's `workflow-current` step sets `stale=true` and ends green with a warning, the `Stop on stale workflow files` step runs, and `go` is `false`, so no model turn, earlier-work check, outcome marker or caller job follows, and lane telemetry counts no failure. work-unblock's hourly sweep finds that step in the run's job listing and re-fires the issue on main's files, once per version of the two lane workflow files, as it does a failed run. The sweep reads each run's job listing once, shared by its checks.

- The address-feedback scope rule (`thread-scope.mjs`) no longer lets a fix edit a plugin's control or instruction files through the plugin-wide arm; it excludes the same control paths the pull-request-files arm does.

## [4.14.1] - 2026-10-24

### Changed

- pr-merge's head-ref map (`.github/scripts/pr-merge/head-ref-map.mjs`) is carried on a run that saves no artifact listing, such as a run with no candidates: the map read before the gate is uploaded as it is, with one log line and no warning, and the next run that saves a listing prunes it. Before, that run warned and uploaded no map, so once the trusted-run window passed the next run downloaded every untied FAIL again. A listing file that exists but cannot be read still uploads nothing, and with no map read before the gate nothing is uploaded. The map is still read only from the newest scheduled or hand-started `pr-merge.yml` run on main and never passes through `actions/cache`.

## [4.14.0] - 2026-10-24

### Changed

- The `enable-auto-merge` activity arms a lanes App pull request whose issue link the merge gate takes, a plain `Refs: #<n>` issue included, instead of only one whose body opens with `Closes #<issue>`. The link is read with the verdict, through the gate's own rule (`babysit_verify_evidence.py evidence --lane-link`, which runs `babysit_merge_policy._linked_issue`), on the scheduled and hand-started runs only: two or more `Refs:` issues, a `Refs:` line in any other form, a number that is no issue, two closing issues, a closing issue in another repository, and a failed read all leave the pull request unarmed, or disarm it. An event run reads no link, so it never disarms on one.
- The `enable-auto-merge` activity applies the merge gate's run-level refusals, which native auto-merge would otherwise skip. Each scheduled or hand-started run waits for the same run's `post-merge-dispatch` job, which keeps its post-merge report as a one-day artifact, and reads the lane's room from that report (`babysit_verify_evidence.py lane-room`, `babysit_merge_policy.lane_room`). While a demotion record, `merge.rung`, the loop setting or the rung cap holds the lane off, or a lane merge failed its post-merge check, nothing is armed and every armed lanes App pull request is disarmed. At `merge.max-in-flight`, counting the queue's lane entries, the lane's unverified merges and armed pull requests not yet queued, nothing more is armed. A missing report, one the gate would not reuse (`shared_refusal`: older than 30 minutes, as a re-run job reads the run's first report, a demotion record filed or changed since, or a lane merge landed since that it does not count), or a room that cannot be read, holds as a refusal does: nothing is armed and every armed lanes App pull request is disarmed. The report is read whenever `post-merge-dispatch` ran, so a later step of that job failing does not disarm anything. The job now holds `pull-requests: read` for the merge-queue and merge reads.
- In the merge queue, `ci-status` holds a lanes App pull request whose verifier pass no longer binds its live issue link. It reads the counted pass's `verdict.json` (one artifact download) and the closing issues (one GraphQL read), and `merge-holds.mjs` `linkHold` holds unless the body still closes, or with no closing issue still names by a plain `Refs:` line, the one issue the pass judged, linked the same way. This is pr-merge's reader rule (`verify:spec-changed`), so a body edited after arming, such as `Refs: #A` to `Closes #B`, no longer merges on a pass for the old issue. A trusted approval of the head lifts it, as it lifts the verifier hold. `refsIssue` moves to `merge-holds.mjs`, which `resolve-pr.mjs` re-exports.
- `enable-auto-merge` holds a lanes App pull request on the merge gate's risk score: `evidence --lane-reviews` runs `babysit_risk.score` and `holding` over the inputs the gate builds, at the lane room's effective rung. Each of these leaves it unarmed or disarms it: an open CRITICAL security-lane finding or a review not bound to the head (whether or not the lane applied its hold label), a symlink, submodule or other non-regular mode, a high path, the manifest review, the trust gate, and the cost review unless the owner's decision lifts it. The job now also holds `checks: read` for the lanes' annotations.
- `ci-status` fails a lanes App pull request while the lanes kill switch (`CLAUDE_LANES_DISABLED` or `CLAUDE_LANES_REPO_DISABLED`) reads anything but `false`, so one armed before the switch was turned on stops in the merge queue. It reads the vars context and makes no API call. Owner and Dependabot pull requests are not affected.

## [4.13.3] - 2026-10-23

### Changed

- `pr-unblock-dispatch.yml` also runs half-hourly, at minutes 9 and 39, five minutes after each `maintenance-reconcile-lost-runs` tick. A lanes App pull request whose reconciler re-run failed now gets `fix-ci` at the first tick after that failure instead of waiting for the next push to `main`, and a conflicting or Markdown-changing pull request is picked up the same way. A tick runs the same listings as a push run, and heads the dispatch record holds are not read again. The gate and the token broker already accept a dispatcher run started by a schedule. A re-run of a scheduled run fails at the trigger check, which handles no `schedule` event; the next tick replaces it. Only a push cancels a dispatcher run in progress; a tick or a hand run waits behind it, so a tick never cuts short a push run's dispatches.

## [4.13.2] - 2026-10-23

### Fixed

- The pr-merge lane no longer adds `needs-human` back to a pull request after a person removed it (a User of kind `human` on the trusted-actor list at the default branch, with write access), while the escalation it explains is unchanged (same head and reasons). A removal by a bot, by an account off that list, or through a GitHub App lifts nothing, and a new head or new reasons escalate again ([README.md, The pr-merge lane](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md#the-pr-merge-lane)).

## [4.13.1] - 2026-10-23

### Fixed

- `ci-status` and `enable-auto-merge` hold a lanes App pull request that changes the marketplace manifest (until a trusted approval of the head) or a merge-gate cost path (until the owner's linked cost decision).

## [4.13.0] - 2026-10-23

### Added

- pr-verify's resolver gives the verifier the one issue a plain `Refs: #<n>` line names as the spec of a pull request that closes no issue, by the same rule the pr-merge gate reads (`refsIssue`, kept equal to `babysit_merge_policy.refs_issue` by `test_verify_rules_sync.py`), and marks each spec entry's `spec_kind` (`closes`, `refs` or `pull-request`), which the verdict records as `spec_kind`. The verifier judges a `Refs:` issue as a partial slice (owner decision 2026-10-23): only the part the pull request body says it delivers, in the issue's scope, correct and coherent, with the body naming what remains; a body naming no delivered part or no remaining work, or claiming the whole issue, fails. Closing issues are still judged whole, and the spec trust rules are unchanged.
- A `Refs: #<n>` whose number names no issue or pull request (GitHub's NOT_FOUND) gives the resolver no linked issue instead of failing the run; the resolver reads the `Refs:` issue with a GitHub helper that keeps GraphQL errors, so the default helper's throw on any `errors` never reaches it, and an answer with no repository, or a null issue without that NOT_FOUND, fails the read. work-resolve-issue's report-outcome no longer puts the human-gated label and a refs-hold comment on the issue of a `Refs:` pull request it opens, since the merge lane now merges a plain `Refs:` pull request; work-unblock still lifts a hold set before.

## [4.12.3] - 2026-10-23

### Changed

- API budget logging reads the rate limit from each job's own responses. It no longer reads `GET /rate_limit`, which reports a different bucket from the one the job spends. `.github/actions/log-api-budget` holds three parts:
  - `api-budget.bash`: a `gh` wrapper and the notice
  - `api-budget.mjs`: the fetch side
  - an end-of-job emitter
- Each named token gets one notice for its last reading and one for each refused (403/429) reading: `token=<name> workflow=<path> job=<id> run=<id> attempt=<n> limit= remaining= used= reset=<epoch> resource= cost=<N or na>`. `cost` is how much `used` rose since the first reading with the same reset.
- Where the notices come from:
  - `ci-status` wraps its own `gh api` reads and writes its notice before the aggregate step.
  - pr-merge's merge job reads through the babysit gh seam.
  - The pr-feedback-dispatch and pr-unblock-dispatch jobs read through `request-budget.mjs`.
  - Those three jobs write their notices from their existing end steps.
- The start-of-job `/rate_limit` steps are gone, including those in work-unblock, intake-triage and pr-run-activity-write.
- The lanes App token is now named `lanes-app` (it was `lane`). The monitor-signals ceiling reads both names and both notice shapes.

- `pr-feedback-dispatch.yml`'s `rerun-ci-status` re-runs a head's ci-status once, after the last review lane finishes, instead of once per lane: while the other lane's newest run on the head is still going it stops after one read, since ci-status would still be red and that lane's completion starts the job again. A head with no run of the other lane re-runs on one lane. A ci-status that started after both lanes finished, or a re-run already queued, is left alone. The job list is read once, and each 60-second poll reads only the run. A read refused by the token's primary rate limit (403 or 429) waits `retry-after` seconds, else, with `x-ratelimit-remaining: 0`, until one second past `x-ratelimit-reset` inside the same 10-minute cap instead of failing; a reset past the cap fails the job with an error naming the reset, since nothing else re-runs a ci-status left stale.

## [4.12.2] - 2026-10-23

### Fixed

- Native auto-merge of a lanes App pull request now needs the verifier verdict pr-merge's gate needs. `enable-auto-merge.mjs` arms, and keeps armed, only when pr-merge's gate reader refuses nothing at the head it read (a pr-verify pass, no FAIL at the head, FAILs under `merge.max-verify-fails`, an unchanged trusted spec), and only on its scheduled or hand-started run; event runs never arm. `ci-status` turns an armed lanes App pull request's auto-merge off on each push to its head. In the merge queue, `ci-status` requires a pass or pass-notes artifact at the queued head from a successful pr-verify run on main; a trusted approval of the head lifts it. Pull request events read no verdict, since pr-verify runs only after a green pull request run.

## [4.12.1] - 2026-10-23

### Changed

- pr-verify names a FAIL verdict's artifact with `-i` and the issues its verdict records, ascending and joined by dots (`write-verdict.mjs` `artifactName`), so the pr-merge gate counts it toward each issue's repeated-fail cap from the artifact listing alone. PASS and PASS-NOTES names are unchanged. The writer checks every name against the readers' pattern (`NAME`, now kept in `write-verdict.mjs` and re-exported by `resolve-pr.mjs`) and fails the job before upload on one no reader takes. The resolver checks the names without issues first and skips a head judged under one without reading the linked issues; only then does it read them, which the spec needs anyway, and look up its own FAIL under the `-i` name; a FAIL another pull request left at the same head is still missed and that head judged again, at the cost of a run, and so is this pull request's own FAIL once a body edit changes its linked issues at the same head, one run per change of the issue set; neither changes the gate's decision, since the earlier FAIL stays tied and refuses the head. A FAIL whose issues no name carries (more than 10, or a number over 10 digits) keeps the plain name with a warning, and the resolver never looks such a name up, so that pull request is still judged.

- pr-merge carries the `pr-merge-dispatched-<id>` and `pr-merge-rerun-<id>-attempt-2` records the post-merge check proved from one run to the next as the `pr-merge-lane-records` artifact (`.github/scripts/pr-merge/lane-records.mjs`), so the check stops listing each record and reading the run that uploaded it on every run. Before each post-merge check, in the `merge` job and in `post-merge-dispatch`, a step reads the file from the newest scheduled or hand-started `pr-merge.yml` run on main other than itself whose head commit is on main, found the way the gate cursor and the head-ref map are; the check steps, the `--remediate` step and the gate step name it in `BABYSIT_POSTMERGE_LANE_RECORDS`. After the gate a scheduled or hand-started `merge` job uploads the records the checks read in and proved, while unexpired and still listed by the run's artifact listing under the record's name and sender run; the read step removes any file already at its path first; with no listing file (no candidates, or a listing the run could not read), unexpired records are carried as they are and pruned on the next run that saves a listing; a listing file that exists but cannot be parsed uploads nothing, and the next run reads an older file. Only a run's own steps can upload its artifacts, and the file never passes through `actions/cache`. Any failure leaves no file, and the check reads each record as before. Permissions are unchanged.

## [4.12.0] - 2026-10-23

### Changed

- `merge.lane-prs` (default `native`) leaves the lanes App's pull requests to GitHub's native auto-merge: pr-merge's `merge` job no longer lists them, so its gate never scores, escalates or enqueues one. Adopted owner pull requests and Dependabot's are gated as before. `gate` restores the earlier listing, and this repository sets it until `ci-status` or `enable-auto-merge` enforces the pr-verify verdict and the post-merge check judges native merges ([README.md, Native auto-merge](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md#native-auto-merge)).

### Removed

- `merge.read-token-floor` and the pr-merge gate's switch to the lane App token. The gate's review-evidence reads (timeline, comments, review-lane runs with their attempts, jobs and annotations) stay on `GITHUB_TOKEN` whatever its budget, since GitHub's [Terms of Service](https://docs.github.com/en/site-policy/github-terms/github-terms-of-service) section H bars sharing tokens to exceed its rate limits ([owner decision](https://github.com/melodic-software/claude-code-plugins/issues/9297#issuecomment-6368281689)). A read refused for a rate limit is made once and not retried: the candidate's lanes read `evidence-missing` and it holds until a later run reads again. **Breaking:** `merge.read-token-floor` is gone from the schema, so a `pr-pipeline.yaml` that still sets it fails validation; delete the key.

### Fixed

- `work-resolve-issue` no longer resumes an earlier run's lane branch that is behind the default branch. Such a branch carried its stale base into the runner's whole-branch checks, which failed and handed the issue to a person with no pull request. The run now starts fresh from the default branch under a new lane branch and leaves the old one in place. `issue-prior` reads `behind_by` from the compare call it already makes, and fails the step when that value is not a whole number. The outcome comments say a restart continues from the branch only while it is not behind.

## [4.11.1] - 2026-10-23

### Changed

- The verifier-notes poster (`verify-notes.mjs`) and `pr-feedback-dispatch.yml`'s FAIL filter accept a FAIL artifact name that ends with `-i` and the issues the verdict records, ascending, each once, joined by dots, so `write-verdict.mjs` can start writing them later. `pr-feedback-dispatch.yml` fails its run on a FAIL-shaped name no reader takes rather than skipping it, and anchors its filter at the true end of the name; the notes poster refuses a name whose issues are not the ones its verdict JSON records. The resolver's name pattern (`resolve-pr.mjs` `NAME`, checked by `isVerdictName`) follows the same grammar, though its already-judged lookup still builds exact names and finds an issue-named FAIL only once the writer change teaches it to. `test_verify_rules_sync.py` checks that the gate, the resolver's pattern (`isVerdictName`; it does not exercise `judged()`), the notes poster and the workflow filter accept the same names, with the same 10-digit pull request bound and 194-character limit.

## [4.11.0] - 2026-10-23

### Changed

- `address-feedback` may fix a finding in any file the pull request already changes that the gated head holds, not only in the thread's own scope. The select job writes the PR's files, rename sources included, as `pr_paths` in the thread file and `run.json`, less `.github/workflows/`, `.gitmodules`, `CODEOWNERS`, `settings*.json`, package manifests, `requirements*.txt`, anything under `.github/`, `CLAUDE.md`, `AGENTS.md`, `.mcp.json`, `.lsp.json`, a `.claude` or `.claude-plugin` directory and a plugin's `hooks/`, `monitors/` and `bin/`. `apply-patch.mjs`'s `kept-threads` rule and the reply job admit them, and only as changes to an existing file: a file the fix creates keeps the old scope. A `VALID` fix commit lands when it changes the thread's path or a `pr_paths` file at a line the reply's evidence cites inside one of its hunks. Every apply-patch refusal still applies.

## [4.10.2] - 2026-10-23

### Fixed

- A `resolve-conflicts` round whose scan refused the model's output (a leak-scan block or an oversize patch) now escalates `unresolved-conflict` instead of ending with a failed leg and no escalation. The new `conflict-scan-refusal` job in [`pr-unblock.yml`](https://github.com/melodic-software/claude-code-plugins/blob/main/.github/workflows/pr-unblock.yml) runs when the answering leg handed on no patch state, downloads the read runner's scan-refusal markers by name, never a job output, and reads them with `scanRefusal` through [`conflict-scan-refusal.mjs`](https://github.com/melodic-software/claude-code-plugins/blob/main/.github/scripts/pr-unblock/conflict-scan-refusal.mjs); `report-escalation` and `report-conflict-status` take its reason. No marker escalates nothing ([#9391](https://github.com/melodic-software/claude-code-plugins/issues/9391)).

## [4.10.1] - 2026-10-23

### Changed

- `pr-review-hosted.yml` and `pr-review-security-hosted.yml` call ci-workflows' [`pr-review-cli.yml`](https://github.com/melodic-software/ci-workflows/blob/6d6cb798e7cb7560a0f9327d8a22398961c23b31/.github/workflows/pr-review-cli.yml) v0.64.2, which spends fewer job-token API requests per run ([ci-workflows#869](https://github.com/melodic-software/ci-workflows/pull/869)). It reads the pull request's file list once instead of three times and pulls.get twice instead of three times, and the publish gate now comes through git. A whole review with an inline comment drops from 15 requests to 8. Check names, the marker comment, the review-complete notice and holds are unchanged.

- The pr-merge lane token carries no Actions permission: `merge-pr`'s `activity-grants` row is gone, and a test pins that no live slot resolves an actions permission. The verdict downloads, the artifact listing, the run records and the compares stay on `GITHUB_TOKEN`, and nothing is built to fall back from them to the lane token.

## [4.10.0] - 2026-10-23

### Added

- The pr-merge lane's `enable-auto-merge` activity (effect `merge`) turns on GitHub's native auto-merge, squash at the head it read, for each open lanes App pull request into main that opens with `Closes #<issue>` and carries no hold (a `Hold:` line or "do not merge" in its body, `do-not-merge`, the human-gated label, a member's newest comment saying "do not merge", a head that now changes a denied path), and turns it off on an armed one that now carries a hold. Auto-merge a person turned off stays off. `pr-merge.yml` runs it in its own job, with its own lanes App token, when the issue lane finishes (a new `workflow_run` trigger the merge job ignores), on a listed human's edit, unlabel or ready, and on the schedule. While `merge.report-only` is true it writes nothing ([README.md, Native auto-merge](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md#native-auto-merge)). `ci-status` fails a lanes App pull request on a body hold, a member's veto comment or a changed or renamed-from denied path (lifted by a trusted person's approval of the head), on each pull request event and in the merge queue, so a hold added after arming stops the merge.

### Changed

- `resolve-conflicts` runs on the read runner, [`pr-run-activity-read.yml`](https://github.com/melodic-software/claude-code-plugins/blob/main/.github/workflows/pr-run-activity-read.yml), on `run-claude-cli` with a subscription fallback, and no model job holds a write token or runs git. [`pr-unblock.yml`](https://github.com/melodic-software/claude-code-plugins/blob/main/.github/workflows/pr-unblock.yml) runs it as five jobs: `resolve-conflicts-select`, a base job with a read-only token, pins the default branch tip, merges it into the head with the base's `prepare.sh` and decides clean, conflicted or escalate; `resolve-conflicts-not-run` posts the check neutral (`clean-merge` for a clean merge) when no model is needed; the model job and its subscription call (started by `resolve-conflicts-handoff`'s read of the run's jobs, `fallback: handoff`) merge the pinned base again, must reach the same conflict tree, and hand the skill's resolutions on as a patch; and `apply-conflict-patch` merges once more and commits the merge with the head and the pinned base as parents. Every gate, head, base and conflict tree comes from the select job, and every model-call input from one leg's scan job.
- `resolve-conflicts` has effect `read` and `applied-by` `patch: apply-conflict-patch`, and routes to the `code-fix` profile (the read runner refuses `default`). Its skill gets Read, Grep, Glob, Skill, Edit, Write and Agent with no Bash, and `.lane/merge/`, which the new [`context.sh`](https://github.com/melodic-software/claude-code-plugins/blob/main/.github/scripts/merge-base/context.sh) writes before any model turn (each conflicted path's three stages and both sides' history, capped), read-only and denied to the file tools. The new script activity `apply-conflict-patch` runs `apply-patch.mjs` under the `merge-base` row.
- `prepare.sh` prints `conflict-tree`, the merge's stage-0 entries plus each conflicted path's marker file, and runs the version-bump script under `LC_ALL=C`. The new [`run-prepare.sh`](https://github.com/melodic-software/claude-code-plugins/blob/main/.github/scripts/merge-base/run-prepare.sh) is the step around it in all three jobs, and fails red unless a later job's merge reaches the select job's state and tree. `collect-patch.sh` takes an optional tree to measure the patch from.
- `apply-patch.mjs` commits a merge: under a row with parents `[head, base]` it applies the patch to the conflict tree in a scratch index, holds only the patch's own changes to the refusals, `max-files`, the `merge-result` predicate (a conflicted path, else `unexpected-path-staged`), the credential scan and the blob caps, escalates `unresolved-conflict` for a conflicted path left with markers and `workflow-staged` for a workflow change that is not exactly the base's, uploads only the blobs the base's `tree-entries.sh` flags, refusing before any write past the new row key `max-blobs`, and commits `[head, base]`. A clean merge commits with no patch. The `merge-base` row sets `max-files` 300, `max-blobs` 300, `skip-moved-head`, `empty-at-push: conflict`, and the escalations `conflict-patch-invalid`, `conflict-patch-not-applied` and `conflict-patch-protected-path`, which `report-escalation.sh` explains.
- The read runner's scan job reads a merge-base patch as text and never applies it to the head; a binary hunk blocks it. `report-conflict-status` posts on an `unresolved-conflict` from the select or the push job. The schema requires `applied-by.patch` of a read `merge-base` skill and adds the `clean-merge` skip reason.

### Removed

- The write runner's `merge-base` skill mode: its post and commit steps, the promote step's merge branch, and its `merge-state` output. A `merge-base` skill on the write runner, or on `claude-code-action`, now fails red. `post.sh` and its tests are gone, and `prepare.sh` no longer copies `.git/config` or prints the config, attributes and snapshot hashes only `post.sh` read. `collect-base-activity` drops the merge-base git deny list: every write skill on `claude-code-action` is denied all of git.

## [4.9.0] - 2026-10-23

### Added

- Intake refines a thin issue: one whose triage flags `intent` or whose body has no task list line. A read-only model run in `intake-triage.yml` (`refine-issue`, contents read only, no project settings, `dontAsk`) explores the default branch, checks the open and closed issues and merged pull requests a title search found for duplicates and finished work, and reads the docs hosts resolve-issue reads. The `apply-refinement` activity posts its output as the lanes App in a separate comment opening with `<!-- intake-triage refinement -->`, once per issue.
- An exact refinement lists its acceptance criteria as a task list, lifts the lanes App's `status: needs-decision`, and triages the issue once more; one that is not exact asks numbered questions with `RECOMMENDED:` answers and leaves the issue at `status: needs-decision`. It never adds `agent-ready` or `needs-human`.
- Admission's criterion 7 also counts the task list in that comment when the lanes App's account posted it after the body's last edit, and the work lane's `issue.json` keeps that comment as `author_kind: refinement`.
- Only issues and pull requests a listed human or the lanes App opened reach the refinement model as duplicate candidates, and refinement text cannot add a link, an autolink or a `GH-N` reference.
- A refinement is dropped when the issue's title or body changed while the model ran. Labels change before the marker comment is posted, so a failed label update leaves no marker and the next triage refines the issue again.

### Changed

- `fix-docs` moves from `pr-unblock` back into its own `pr-refine` lane (stage `refine`): `pr-refine.yml` holds the `fix-docs`, `fix-docs-subscription` and `apply-docs-patch` jobs, and `pr-unblock.yml` no longer takes `fix-docs`. `pr-unblock-dispatch.yml` dispatches `pr-refine.yml`, still once per PR and at most `limits.fix-docs-per-run` per run; a PR that already has a `pr-unblock / fix-docs` run counts as done.
- `fix-docs` now tidies every ready PR that changes Markdown, lanes App PRs included, except Dependabot's, the release App's and the standards-sync App's, matched by account id.
- Both activity runners name `pr-refine.yml` as the dispatched workflow for the `pr-refine` lane. pr-merge's refire of a broker `workflow-modified` refusal leaves `pr-refine` runs out: a `pr-refine` run is dispatched on main, so an empty commit on the PR cannot make it pass, and a listed person re-dispatches it.

- The pr-merge lane token now carries Actions read (owner decision Q8), for its verdict and run reads to fall back on; the verdict downloads, listing and run records still read with `GITHUB_TOKEN`.

- pr-merge's `merge` job carries the head ref each untied pr-verify FAIL's verdict.json records, by artifact id, from one run to the next as the `pr-merge-head-refs` artifact (`.github/scripts/pr-merge/head-ref-map.mjs`), so the gate stops downloading every old-format untied FAIL on every sweep. Before the gate it reads the map from the newest scheduled or hand-started `pr-merge.yml` run on main other than itself, found the way the gate cursor is; after the gate a scheduled or hand-started run uploads that map plus its own downloads, for ids the artifact listing still lists. Only a run's own steps can upload its artifacts, and the map never passes through `actions/cache`. Any failure leaves no map, and the gate downloads as before. Permissions are unchanged.

### Security

- `fix-docs-subscription` no longer starts on `fix-docs` outputs, which its head-code run job could forge. A `fix-docs-handoff` job reads this run's jobs through the Actions API, as `fix-ci-handoff` does for fix-ci. The fallback runs only when the broker allowed `fix-docs` and its report job posted no check (#8890).
- `apply-docs-patch` no longer takes its patch inputs or head from `fix-docs` run-job outputs. It takes them from the answering leg's scan job and the head from `fix-docs-head`, as fix-ci's `apply-patch` does (#8890).

## [4.8.1] - 2026-10-23

### Changed

- The pr-merge HIGH path floor holds only the takeover set: the trusted-actor list, the trusted-trigger check, `CODEOWNERS`, `.gitmodules` and `resolve-config`. Agent permission config, package manifests and lockfiles, and the release and `id-token: write` workflows merge on the review lanes. The `high-path-floor` schema description and the README say so.

## [4.8.0] - 2026-10-23

### Changed

- `address-feedback` works a pull request carrying the human-gated label when a lane escalation (pr-unblock or fix-ci) put the label on and no review-lane hold names the current head or is open; a review-lane hold, or anything ambiguous, still limits it to threads a trusted person with write access asked it to fix. The label stays on: `clear-escalations` removes it only while no address-feedback round has been recorded since it went on, so once a round runs a person removes it. To stop the lane working such a PR, add `do-not-merge`.

## [4.7.5] - 2026-10-23

### Added

- `ci-status` now gates tests that cannot fail. On a pull request or merge group, the `check-plugins` gate `cant-fail-scan` runs `/testing:audit`'s scan on each changed test file, and reports not applicable when the diff changes none. When there is no diff base (the schedule, a dispatch, or a pull request or merge group that resolves to the whole tree), a new `check-tests` job scans the whole tree; with a diff base it returns at once ([#9184](https://github.com/melodic-software/claude-code-plugins/issues/9184)).

## [4.7.4] - 2026-10-23

### Changed

- The pr-merge HIGH path floor also holds `.github/actions/resolve-config/**`, so a change there waits for a human merge: the token broker runs that directory's code from main in its signer process.

- Every reader of a pr-verify verdict name (the pr-merge gate, the resolver, the FAIL-notes poster `verify-notes.mjs` and pr-feedback-dispatch) also accepts the name followed by `-<ref-digest>`, the first 16 hex digits of the SHA-256 of the head branch the verdict records (`headRefDigest` in `write-verdict.mjs`). The gate ties an untied FAIL from such a name without downloading it, so a digest-named FAIL whose verdict.json cannot be read no longer refuses `verify:unreadable`. `verify-notes.mjs` checks the digest against the verdict. pr-verify still uploads the old name until a follow-up switches the writer.

## [4.7.3] - 2026-10-23

### Changed

- The pr-merge gate fetches each verifier verdict by its artifact id, one request where `gh run download` spends two, and an untied FAIL record that could not be read refuses the run's later candidates without another download. Both stay on `GITHUB_TOKEN`, since the lane App token holds no Actions permission.

## [4.7.2] - 2026-10-23

### Fixed

- `pr-unblock-dispatch.yml` releases a `review-dependency` head the usage limit stopped once that limit resets, as it does for `resolve-conflicts`, and stops re-dispatching the head after `limits.limit-stops-per-head` limit stops. Before, a limit stop held the head until the next push, and the dispatch record could store it as reviewed. The dispatcher now reads the base's resolved limits and its clock for `review-dependency` too ([#9382](https://github.com/melodic-software/claude-code-plugins/issues/9382), [#9379](https://github.com/melodic-software/claude-code-plugins/pull/9379)).
- The dispatch record's version is now 3, so `pr-unblock-dispatch.yml` and `pr-feedback-dispatch.yml` read a record cached under the old rule as empty. Such a record could hold a limit-stopped `review-dependency` head as reviewed, past its reset. The cost is one pass of re-reads, never an extra dispatch ([#9382](https://github.com/melodic-software/claude-code-plugins/issues/9382)).
- The lane catalog's trigger gate check covers `issue_comment`: a job that holds a Claude credential under it must show an author or same-repo gate, and `lane-funding.schema.json` requires a `gate` for a lane with that trigger ([#9382](https://github.com/melodic-software/claude-code-plugins/issues/9382), [#9380](https://github.com/melodic-software/claude-code-plugins/pull/9380)).

## [4.7.1] - 2026-10-23

### Fixed

- address-feedback's and review-dependency's fallback calls no longer start on the read runner's run-job outputs, which head code can forge. As for fix-ci, `address-feedback-handoff` and `review-dependency-handoff`, base jobs with only `actions: read`, read this run's jobs through the Actions API once, and the fallback call runs when the first call's report job posted no check ([#9365](https://github.com/melodic-software/claude-code-plugins/issues/9365)).
- Every fallback call with a handoff job, fix-ci's among them, passes `fallback: handoff`, which the read runner now accepts, instead of a label taken from the first call's `lane-class`. Its lane record reads "posted no check" in place of "hit a credit stop" or "is empty" ([#9365](https://github.com/melodic-software/claude-code-plugins/issues/9365)).

- An issue held before admission (an escalated or flagged intake verdict, or a hold label) whose done-when asks for what an unattended lane run cannot do now gets the admission comment that names those items and recommends the split, which a `needs_human` escalation used to drop. The intake rubric no longer sends such items through the `intent` flag: the model triages the lane-checkable items with their work class and leaves the hold to admission.

- `pr-unblock-dispatch.yml` dispatches `review-dependency` again at a head whose newest `pr-unblock / apply-dependency-verdict` check skipped `no-model-turn`. The `pr-unblock / review-dependency` check runs that started before that verdict no longer hold the head, a limit stop aside. Each such round still posts its round marker, so the round cap bounds the retries. The dispatcher records a head as reviewed only once a verdict check started after its newest `review-dependency` check, or once that check is a select job skip (`awaiting-human`, `not-applicable`, `superseded-sha`) that no verdict follows ([#9362](https://github.com/melodic-software/claude-code-plugins/issues/9362)).
- The dispatch record's version is now 2, so `pr-unblock-dispatch.yml` and `pr-feedback-dispatch.yml` read a record cached under the old rule as empty. Such a record could still hold a `no-model-turn` head as handled and skip the release ([#9362](https://github.com/melodic-software/claude-code-plugins/issues/9362), [#9360](https://github.com/melodic-software/claude-code-plugins/pull/9360)).

## [4.7.0] - 2026-10-23

### Added

- Both review lanes hold a pull request for a person: `pr-review-hosted.yml` and `pr-review-security-hosted.yml` call ci-workflows' [`pr-review-cli.yml`](https://github.com/melodic-software/ci-workflows/blob/9aca743c4ed9aaf7870288a36586c3994e9321e4/.github/workflows/pr-review-cli.yml) v0.64.1 with `hold-label: needs-human`, and a changed file under `.github/standards/trusted-actors/**`, `.github/actions/check-trusted-trigger/**`, `**/CODEOWNERS` or `**/.gitmodules` holds as `trust-gate` whatever the review says ([Review-lane holds](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md#review-lane-holds)).
- ci-status requires both review lanes on the head of a ready pull request: the newest `pull_request` run of each caller must have a successful status job whose `Apply the hold` step ran. A pending, failed, skipped or summary-mode review fails with the cause named; a lane the kill switch stopped passes; Dependabot, the release App and the standards-sync App are exempt by author id unless their PR changes a hold path.
- ci-status fails when a review-lane hold was lifted by anyone but a person on the base's trusted-actor list: the first removal of the human-gated label after the newest hold comment or lane-added label event decides.
- `pr-feedback-dispatch.yml`'s `rerun-ci-status` job re-runs the head's ci-status job when either review lane completes on an open same-repository pull request, after polling at most 10 minutes for a ci-status already in progress.

### Changed

- `fix-ci` dispatch keys on the head's `ci-lanes` commit status instead of ci-status, so a hold, a pending review or a contract failure no longer summons it.

## [4.6.4] - 2026-10-23

### Fixed

- Intake admission refuses `agent-ready` for an issue whose done-when asks for what an unattended lane run cannot do: a run on a named host or OS (such as a Windows 11 host), a paid eval, a run repeated N times, a measurement over time, or a page on a host outside resolve-issue's web-access domains. The issue gets `status: needs-decision` and the admission comment names each such item and recommends splitting it into a needs-human child issue. The intake rubric raises the `intent` flag for the same items.

## [4.6.3] - 2026-10-23

### Fixed

- A read runner scan that refused or failed on a model call's output (an oversize patch, a leak-scan block, a refused decode) now hands the round to a person instead of ending it as `no-model-turn`. When the scan job fails or is cancelled, the new `scan-refusal` job in `pr-run-activity-read.yml` uploads a `scan-refused-<lane>-<activity>-<attempt>` marker artifact. The write runner's reply and verdict jobs download it by name, so no decision depends on a failed job's outputs reaching a `workflow_call` caller. `address-feedback` escalates `feedback-invalid`, and `review-dependency` escalates `dependency-fix-not-landed` for an oversize patch or `dependency-invalid` otherwise. The read runner's `scan-refused` output and the write runner's `dependency-scan-refused` input are removed ([#9340](https://github.com/melodic-software/claude-code-plugins/issues/9340)).
- `address-feedback`'s reply job escalates `feedback-invalid` when the scan named replies it uploaded (a replies attempt or SHA-256) but none arrived, for example after a failed download, instead of skipping `no-model-turn` ([#9225](https://github.com/melodic-software/claude-code-plugins/issues/9225)).
- `pr-feedback-dispatch.yml` dispatches `address-feedback` again at a head whose newest `pr-unblock / publish-feedback` check skipped `no-model-turn`, on that head's next review or `pr-verify` completion. The `pr-unblock / address-feedback` check runs that started before that reply no longer hold the head. Each such round still posts its round marker, so the round cap bounds the retries ([#9218](https://github.com/melodic-software/claude-code-plugins/issues/9218)).

## [4.6.2] - 2026-10-23

### Fixed

- fix-ci's fallback calls no longer start on the read runner's run-job outputs, which head code can forge. `fix-ci-handoff` and `fix-ci-rung-up-handoff`, base jobs with only `actions: read`, read this run's jobs through the Actions API, and the fallback call runs when the first call's report job posted no check ([#8890](https://github.com/melodic-software/claude-code-plugins/issues/8890)).
- A fix-ci round in which no call posted a check now posts `pr-unblock / fix-ci` failure on `fix-ci-context`'s head from the new `fix-ci-unreported` job when a call's broker-check job allowed the lane; as in the report job, a kill switch or a broker refusal posts nothing. fix-ci-dispatch counts that check toward `fix-ci-restarts`, so the loop stays capped whatever the run reports ([#8890](https://github.com/melodic-software/claude-code-plugins/issues/8890)).
- The read runner's report job no longer counts the PR head it reads at report time as a gated head. With no caller or event head, any run head is forged, and failure is posted on the head it read ([#8945](https://github.com/melodic-software/claude-code-plugins/issues/8945)).
- The read runner's run job fails before the head checkout when its trigger gate read a head other than the caller's non-empty `head-sha`. This is fix-ci's part of [#8954](https://github.com/melodic-software/claude-code-plugins/issues/8954).
- A fix-ci patch collection the collector refused (`collect-patch.sh` exit 3) now reaches a person. The collect step sets `state` `refused`, the scan job hands it on as the new `scan-collect-refused` output, and `apply-patch` runs on it and escalates `ci-fix-invalid` through `report-escalation`. `apply-patch` and `apply-patch-rung-up` now take every patch input from one leg's scan job, never from a run job ([#8912](https://github.com/melodic-software/claude-code-plugins/issues/8912)).

## [4.6.1] - 2026-10-23

### Added

- `merge.read-token-floor` (default 0.3): the pr-merge gate reads its review evidence (timeline, comments, review-lane runs with their attempts, jobs and annotations) with `GITHUB_TOKEN` only while that token has at least this share of its hourly core limit left. Below it, or when the limit cannot be read, those reads use the lane App token, as they did before. The floor is only an early switch: when one of those reads is refused for a rate limit (a 429, or a 403 naming one), the gate reads that candidate's evidence again with the lane App token and marks `GITHUB_TOKEN` spent in the run cache for later candidates. Either token reads the same data, so no gate decision changes. The value is read at the default branch head. The repository's `GITHUB_TOKEN` pool, 1,000 requests an hour shared by every job, ran out on 2026-10-23 once these reads moved onto it.

### Fixed

- pr-merge.yml's `post-merge-dispatch` job caps its dispatch waits at 180 s instead of 300 s. Its whole run took 97-127 s on recent scheduled runs, and the re-run step after the dispatch sleeps up to 170 s while it reads back attempt 2. The lower cap leaves about 6.5 of the job's 15 minutes free, so a timeout no longer lands after the re-run POST and leaves attempt 2 unrecorded.
- Both dispatch steps send the dispatch again after no response only when gh's error shows the connection failed before the request was sent (a `dial tcp` error or a failed TLS handshake). A reset or timeout on an open connection may follow GitHub creating the run, so the step now warns and stops, as it does on exhaustion.

## [4.6.0] - 2026-10-23

### Changed

- The code review lane (`pr-review-hosted.yml`) runs on ci-workflows' [`pr-review-cli.yml`](https://github.com/melodic-software/ci-workflows/blob/83b739f625b501ad40c65dee7168d836883195e1/.github/workflows/pr-review-cli.yml) (v0.63.1), lane `code`: the reviews role's API key first, and its subscription token only after the key hands off or when the repository variable `REVIEWS_KEY_EXHAUSTED` is `true`. The check stays `pr-review / claude-review-status`; the review now posts as `github-actions[bot]`, each comment ending in its `claude-lane: claude-review` footer. A newer push no longer cancels a running review: it waits for it.
- Both review lanes now run on `pr-review-cli.yml`, funded by the `reviews` role's `REVIEWS_CLAUDE_API_KEY` and `REVIEWS_CLAUDE_CODE_OAUTH_TOKEN`; the code lane no longer reads the bare `CLAUDE_CODE_OAUTH_TOKEN`.

### Fixed

- pr-merge.yml's `dispatch-full-run` and `post-merge-dispatch` jobs send the full-run dispatch at most three times: a rate-limited 403 or 429 waits retry-after seconds, else until one second past `x-ratelimit-reset` while none remain, else 60 s, and a request that got no response waits a full-jitter backoff, all within a per-job cap (180 s and 300 s) that keeps each job inside its timeout. Any other answer, a 5xx included, is not sent again, since the run may exist. A dispatch that still fails ends the job green with a warning naming the merge commit, uploads no `pr-merge-dispatched-<id>` record and skips the wait, so the next push or scheduled run starts the run instead of a red job.
- The wait for the dispatched run reads its status every three minutes instead of every minute, 13 reads over 39 minutes.

## [4.5.0] - 2026-10-23

### Changed

- The security review lane (`pr-review-security-hosted.yml`) runs on ci-workflows' `pr-review-cli.yml` (v0.63.1), lane `security`: the reviews role's API key first, and its subscription token only after the key hands off or when the repository variable `REVIEWS_KEY_EXHAUSTED` is `true`. The check stays `pr-review-security / security-review`; the review now posts as `github-actions[bot]`, each comment ending in its `claude-lane: claude-security-review` footer. A newer push no longer cancels a running review: it waits for it.
- `address-feedback` and `pr-feedback-dispatch.yml` treat a `github-actions[bot]` comment as the reviewer's when its last non-blank line is a review lane's footer and its review is `github-actions[bot]`'s; `claude[bot]` findings are unchanged.
- One funding role, `reviews`, backs both review lanes and is keyed; the `reviews-security` role is gone.

## [4.4.0] - 2026-10-23

### Changed

- `review-dependency` runs on the read runner, [`pr-run-activity-read.yml`](https://github.com/melodic-software/claude-code-plugins/blob/main/.github/workflows/pr-run-activity-read.yml), on `run-claude-cli` with a subscription fallback, and no model job holds a write token. `pr-unblock.yml` runs it as six jobs: `review-dependency-select`, a base job with a read-only token, selects the pull request and uploads the context file and `context.json`, the run fields the verdict job reads; `review-dependency-not-run` posts the check neutral when the select job does not proceed, so the dispatcher does not send that head again; the model job and its subscription call return the verdict as structured output and leave a fix as a patch; `apply-dependency-patch` pushes the patch only beside a scanned `fix` verdict; and `apply-dependency-verdict` acts on the verdict whenever the select job proceeded. Every gate and head comes from the select job, and every model-call input from one leg's scan job.
- `review-dependency` has effect `read`, `applied-by` `patch: apply-dependency-patch` and `dependency-verdict: apply-dependency-verdict`, and routes to the `review` profile (Opus, 60 turns). Its skill gets Read, Grep, Glob, Skill, Edit, Write and Agent with no Bash, the context file read-only under `.lane/dependency/`, and one `WebFetch(domain:)` rule per configured host. A launcher activity with a `web-access` host list now gets those per-host rules instead of failing red. The new script activity `apply-dependency-patch` runs `apply-patch.mjs` under the `dependency-review` row, which now skips a moved head and holds each file to the new `dependency-version-change` content rule (`fixRefusal` on the local blobs, before any commit is built). The row's `dependency-manifests` rule reads the base `.github/dependabot.yml`, which the write runner copies out of the base, and its `dependency-verdict: fix` requirement reads the scanned verdict, which the write runner checks against the scan job's SHA-256 before the mint.
- `apply-dependency-verdict.mjs` reads the select job's `context.json` and the scanned `dependency-verdict.json`, each against the SHA-256 its own job recorded. A round with no verdict counts and skips `no-model-turn` only when the same call's scan handed on no patch, refused nothing, and the head is unmoved; a scan that refused an oversize patch escalates `dependency-fix-not-landed`, and any other gap `dependency-invalid`. A round with no model run named always posts its marker.
- The read runner carries, seals, scans and uploads a `dependency-review` skill's verdict at 49152 bytes, never beside a `review-threads` skill's replies, so the sealed payloads still fit five chunks. Its new `dependency-attempt`, `dependency-sha256`, `dependency-verdict` and `scan-refused` outputs come from the scan job alone.
- The schema requires `applied-by.patch` and `applied-by.dependency-verdict` of a `read` `dependency-review` skill.

- work-unblock's restart sweep reads a reopened fix issue's comments and events once: the recurrence check and the restart check share that read instead of listing both again, so each alert-filed issue costs one or two fewer lanes App calls per sweep, with the same verdicts.

- The work-unblock and intake-triage apply-verdict jobs log the lane token's and the job token's REST budget at mint and at job end (`.github/actions/log-api-budget`), as pr-merge does, so each run's lanes App spend is on record. pr-run-activity-write logs it at mint, before the head checkout replaces the base checkout the step runs from.

### Removed

- The write runner's `dependency-review` mode: its select step, the promote step's dependency branch, the verdict collect and upload steps, and its `dependency-round`, `dependency-run-sha256` and `dependency-run-attempt` outputs. A `dependency-review` activity on the write runner now fails red.

### Fixed

- The hourly triage sweep re-dispatches intake for an issue whose intake run failed: the `needs-triage` floor label, which lands on open whether or not intake runs, no longer counts as triaged, so the missing intake comment decides. A filing records an in-progress state before it files, so a failed write cannot file twice (`.github/scripts/maintenance-audit-lane-runs/triage-sweep.mjs`, [#9216](https://github.com/melodic-software/claude-code-plugins/issues/9216)).
- `status: needs-info` holds an issue like `status: needs-decision`: resolve-issue and apply-issue-patch start nothing on it, work-unblock neither adds `agent-ready` to it nor restarts it, and the WIP cap leaves it out of queued work. Pull request hold labels are unchanged ([#9216](https://github.com/melodic-software/claude-code-plugins/issues/9216)).

- The pr-merge lane holds a pull request before it enqueues when an owner, member or collaborator's newest comment on it says "do not merge". A later comment from that person lifts the hold ([README.md, The pr-merge lane](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md#the-pr-merge-lane), [#9216](https://github.com/melodic-software/claude-code-plugins/issues/9216)).

- The lane sweep's collect job reads every run of its 24-hour window. It made one capped run listing, which returns at most 1,000 runs and so covered about the last 4 hours. It now reads each workflow's run count with one `per_page=1` call and halves any range at the cap until each part fits, inside its 350-call budget with 170 calls kept for the units. A workflow it reads only part of is named in a warning, and its unit carries `window_complete: false`, which the judge is told to report as partial.

## [4.3.0] - 2026-10-23

### Changed

- Merge authority: a review flag holds only for a cost increase, a trusted-actor widening or a CRITICAL security finding; other open findings are reported. New **Trusted-actor widening** rule: a change that adds or widens an entry in `trusted-actors.json` waits for the owner whatever `high-path-floor` says; a pure removal merges.

## [4.2.0] - 2026-10-23

### Added

- `merge.gate-candidate-minutes` (a whole number of minutes; absent is no limit): how long one candidate's gate in `pr-merge.yml` may spend reading. Past it the gate starts no further read and the candidate is reported `unknown:candidate-deadline` (exit 11), never ready; a write already started finishes, and the loop goes on to the next candidate within `merge.gate-budget-minutes`. The first candidate a run stops is recorded in the gate cursor as deferred and gated first in the next run under `merge.gate-deferred-minutes` (20 here; absent is no limit), so a pull request whose gate always runs past the limit still gets a longer gate. One stopped at that ceiling gets a warning annotation and goes back to the capped rotation, never deferred again. Set to 4 here, so one slow candidate no longer holds the serialized merge queue for 20 minutes or more.

## [4.1.1] - 2026-10-23

### Changed

- pr-merge.yml's merge job runs its read-only post-merge check under the job's own `GITHUB_TOKEN` (the job gains `issues: read` for the demotion records) instead of the lane App token; only the `--remediate` run keeps the lane token. The gate's review-evidence reads run under `BABYSIT_VERIFY_GH_TOKEN` too, so the lane token is spent on writes and the reads that need the App's identity.

## [4.1.0] - 2026-10-23

### Changed

- An issue whose Size, Complexity or Uncertainty field is empty, or was last set by an account that is neither a listed human nor the lanes App, is no longer refused with `not-assessed`: the field reads as Size `small`, Complexity `medium` or Uncertainty `known`, and the run goes ahead at that budget. The config check rejects an `issue-dimensions` table that lacks one of those keys, or whose `small` size is `split`.
- `report-outcome`'s resume pick still passes over a `not-assessed` marker an earlier run left, so a turn-capped issue resumes.

### Removed

- `not-assessed` as an issue-dimension skip: `report-skip` and the write file's `dimension-skip` input no longer accept it. fix-ci's neutral `not-assessed` check is unchanged.
- The `labeled-after` predicate key from `predicate.mjs`.
- The unused copy of `checkPatchRules` and its old refusal list in `resolve.mjs`; the live check is in `patch-rules.mjs`.

## [4.0.0] - 2026-10-23

### Changed

- **Breaking:** `merge.diff-check.floor-paths` and `merge.diff-check.floor-script-scopes` are gone from the schema, so a `pr-pipeline.yaml` that still sets either fails validation; delete both keys.
- `merge.diff-check.floor-paths` and `floor-script-scopes` are gone, and `high-path-floor` holds only the external-effect path set and the manifest review that `babysit_risk.py` defines; a MED score of class and size reasons alone merges (#9270); the security lane holds only on a CRITICAL finding.

## [3.11.0] - 2026-10-23

### Added

- Intake admits clear issues with no person in the loop (owner decision Q51): after apply-verdict sets `status: ready`, `.github/scripts/intake-triage/admit.mjs` adds `agent-ready` as the lanes App when the issue meets the rules in `.github/actions/resolve-config/admission-rules.json` (type Bug or Task, or Feature under an open parent a listed human filed; class read-only, mechanical or scoped; Size Small or Medium; Uncertainty Known; a `- [ ]` task list; no open blocker (a blocking issue counts as done only when a listed human or a merge closed it), open pull request or refusing label; a listed author) and the issue lane's caps have room. Over a cap, or while an open pull request in the repository names the issue, it adds `admission-deferred`, which work-unblock's sweep admits once there is room and no such pull request is open; a refusal swaps `status: ready` for `status: needs-decision` and says why in one App comment ([#9214](https://github.com/melodic-software/claude-code-plugins/issues/9214)).

### Changed

- Lane patches reach review outside workflows and settings. Every [`patch-rules.json`](https://github.com/melodic-software/claude-code-plugins/blob/main/.github/actions/resolve-config/patch-rules.json) row now refuses `github-workflows` (`.github/workflows/**`, which the lane token cannot push), `codeowners` (a `CODEOWNERS` file at the root, in `.github/` or in `docs/`), `gitmodules`, `settings`, `symlink`, `gitlink` and `rename-into-refused`, plus `backslash` on every row. The rest of `.github/`, `.claude/`, the root `.mcp.json`, agent instruction files, plugin hooks, monitors and bin, and an executable bit the patch sets now reach the branch and its review.
- `address-feedback` hands a pull request to a person as `feedback-protected-path` only when it changes `.github/workflows/**`, and a kept thread's scope may now hold a path elsewhere under `.github/`. `pr-merge` clears that reason once the pull request changes nothing under `.github/workflows/`.
- `resolve-conflicts` escalates `protected-path-conflict` only for a conflicted workflow, `.gitmodules` or `settings*.json`; a conflicted `CLAUDE.md`, `.claude/` or `.mcp.json` goes to the model, and `post.sh` keeps the resolution it staged. It escalates `unexpected-path-staged` only for a symlink, gitlink, backslash path, `.gitmodules`, settings file or `CODEOWNERS` change outside the conflicts; any other change the model stages is committed and reaches review.

- A pr-verify `fail` goes to an `address-feedback` round instead of a person. `pr-feedback-dispatch.yml` also runs when `pr-verify` completes: its new `post-verify-notes` job posts a fail verdict's summary and notes on the pull request, still at the judged head, as file-level review comments by `github-actions[bot]` whose first line is `<!-- pr-verify:fail-note -->` (`.github/scripts/pr-unblock/verify-notes.mjs`), posting only the comments the head does not hold yet, by file, so a retry after a partial post finishes it. An adopted pull request the lanes App did not open gets the notes but no round, so its author sees why the pr-merge lane refuses it. The dispatch job then decides as for a review run, with the newest completed review run at that head as its recorded upstream, so the gate and the broker check the same run as before. Only `pr-unblock / address-feedback` check runs started after the `pr-verify` run was created hold it, so a round an earlier review started at the same head does not swallow the notes.
- `address-feedback` keeps such a thread as the `verifier`'s finding, beside the reviewer bot's, when its review is `github-actions[bot]`'s on a marker-confirmed head. The round cap, the scope rule and the reply job are unchanged.
- The verifier prompt passes work the spec does not ask for with a note (`pass-notes`). It fails only a spec not delivered, a correctness or safety problem, a change of intent, or a change to a hold the owner keeps, and asks each note to start with its file path so the note lands on that file.

- `wip.pause-from` is set (2026-10-22), so over the WIP or held cap the issue lane pauses its runs, and over the queued cap admissions pause, instead of only alerting.
- Intake holds an issue on security only for a very-high risk, the security review's CRITICAL tier: the triage prompt sets the `security` flag only when the work would expose a credential, bypass a trust boundary or open an external attack surface, and apply-verdict no longer keeps an issue from `status: ready` for the `area: security` label alone.
- work-unblock admits nothing, newly unblocked or deferred, while the issue lane is paused over its WIP or held cap, so its sweep no longer undoes intake's deferral during a pause.

### Removed

- The `github`, `claude`, `mcp-config`, `new-executable` and `instruction-path` refusals, and the rule that a `script-exec-bit` row must refuse `instruction-path`.

## [3.10.0] - 2026-10-23

### Added

- The lost-run reconciler re-runs the failed jobs of a PR CI run once when its first attempt failed on anything but infra, so a flaky test the diff did not cause costs no model run ([#9271](https://github.com/melodic-software/claude-code-plugins/issues/9271)). Its attempt number caps it at one re-run per run and head; a run where only ci-status failed gets none.
- fix-ci waits for that re-run before it takes a head, and also takes a head whose ci-status passed but whose advisory pr-test-windows run failed again, since the merge gate holds a pull request on any failing check.

### Changed

- This repository's Uncertainty `knowable` maps to `run`, so a Knowable issue runs instead of skipping with `research-first`. Unknown still skips with `probe-first` and Large with `split-required`.
- `work-resolve-issue` no longer adds `Hold: a human merges this` for `work-class: structural`; untrusted-provenance work, `merge: human` and the denied-path diff still carry it.
- intake-triage holds an issue for cost only when the charge is one no diff shows: a new paid service or subscription, a plan upgrade, or an account, organization or repository billing setting. A charge a diff shows (IaC, runner labels or cron, model, effort or turn flags, new secrets) gets no `cost` flag; the merge-time cost hold catches it.

### Removed

- The `labeled-after` key from the live config and its schema property, and the issue update-time read that served it. The `work-resolve-issue` lane's go-live cutoff is gone, so an issue labeled `agent-ready` at any time starts a run.

## [3.9.0] - 2026-10-23

### Added

- [`.github/lane-funding.json`](https://github.com/melodic-software/claude-code-plugins/blob/main/.github/lane-funding.json),
  the catalog of the seven lane funding roles (`reviews`, `reviews-security`, `issue-lane`,
  `intake`, `pr-unblock`, `pr-verify`, `automations`): each role's target secrets, whether it is
  keyed, and each lane's workflow, job, launcher and the secrets its job reads today, with a JSON
  schema beside it. No workflow's secrets change. `callers.test.mjs` fails when a job that reads a
  Claude secret is missing from the catalog or reads other secrets than it lists, when a job reads
  an API key off `run-claude-cli`, or when a role's secret names do not follow its prefix.

### Changed

- `address-feedback` runs on the read runner, [`pr-run-activity-read.yml`](https://github.com/melodic-software/claude-code-plugins/blob/main/.github/workflows/pr-run-activity-read.yml), on `run-claude-cli` with a subscription fallback, and no model job holds a write token. `pr-unblock.yml` runs it as five jobs: `address-feedback-select`, a base job with a read-only token, keeps the threads and uploads the thread file and `run.json`; the model job and its subscription call answer them and hand on a patch and their replies; `apply-feedback-patch` pushes the patch; and `publish-feedback` posts the replies. Every later job takes its gate, head and reply inputs from the select job, never from a model call's run job, and `publish-feedback` runs whenever the select job proceeded. A skip or an escalation posts both checks neutral.
- `address-feedback` has effect `read`, `applied-by` `patch: apply-feedback-patch` and `feedback-replies: publish-feedback`, and the `code-fix` route. The new script activity `apply-feedback-patch` runs `apply-patch.mjs` under the `review-threads` row, which now skips a moved head. The row's `kept-threads` rule reads the select job's thread file, `named_paths` included. A needs-human PR's push still takes a fix that a trusted person with write access asked for.
- `publish-feedback.mjs` requires an empty `fix_sha` and names the fix itself: the one lanes App commit in the range, committed by `web-flow` with a valid signature, that carries the `Lane-Activity: pr-unblock/address-feedback` trailer. A push that was superseded, refused, escalated or held leaves none, and a `VALID` round ends `feedback-not-landed`. `replies.jsonl` is capped at 49152 bytes and `run.json` at 1 MiB. A round with no `replies.jsonl` still counts. It posts a `no-model-turn` skip rather than escalating only when the same call handed on no patch and the head has not moved; otherwise it escalates. `replies.jsonl` must match the SHA-256 the scan job recorded. The push and reply jobs take every model-call input from one call, the subscription call when it ran, and push a patch only beside that call's replies. The read runner passes the `pr-feedback-dispatch.yml` trust to its gate only for a `review-threads` call. The round marker names the model attempt that produced the replies, so a re-run of the model job counts a new round. The read runner carries, seals, scans and uploads it at that cap; all four sealed payloads at their caps still fit five chunks.
- The read runner accepts a `pr-feedback-dispatch.yml` dispatch and supports `prepare: review-threads` in PR patch mode. It checks the select job's thread file against its SHA-256, PR and head. It stages the review-thread tool read-only under `.lane/feedback/`, except `state/`, which only the tool writes (all of `.lane/feedback/` is denied to the file tools), and names the tool's path and subcommands in the preamble. Its `feedback-attempt` output comes from the scan job alone.
- The schema requires `applied-by.patch` of a `read` skill with `prepare: ci-context` or `review-threads`, and `applied-by.feedback-replies` of a `read` `review-threads` skill.

- The Funding section of the PR pipeline convention names the seven roles and points to the
  catalog instead of listing lanes in prose.

### Removed

- The write runner's `review-threads` mode: its select, promote-scope, collect and upload steps and its `feedback-round`, `feedback-run-sha256` and `feedback-run-attempt` outputs. A `review-threads` activity on the write runner now fails red.

## [3.8.0] - 2026-10-23

### Added

- intake-triage.yml writes the triage verdict as the lanes App after each triage run that applied: the proposed `work-class:` label, the Size, Complexity and Uncertainty issue fields, and `status: ready` or `status: needs-decision`, from the lane comment's class line and four verdict lines, each checked against a closed set (`.github/scripts/intake-triage/apply-verdict.mjs`, lane `intake-triage`, activity `apply-verdict`, effect `mutate-tracker`). It never adds `agent-ready`, keeps a class or field a listed human set, and drops the comment's "a maintainer confirms" wording once it applied the class ([#9213](https://github.com/melodic-software/claude-code-plugins/issues/9213)).

### Changed

- Intake triage follows a written priority, type and dimension rubric, and may no longer apply `good first issue` or `help wanted`.

## [3.7.0] - 2026-10-22

### Added

- pr-merge holds a pull request that could add or raise a charge (IaC files, new workflow
  schedules, billed runner labels, new secrets references, new model legs, raised model-leg
  timeouts, pipeline config changes) for a human unless its body links an owner
  `**Decision recorded.** Cost:` comment on its closing issue or the pull request itself.

## [3.6.1] - 2026-10-22

### Fixed

- work-resolve-issue's report-outcome names apply-issue-patch's escalation reason when it refused a done run's patch, instead of saying the run committed nothing.

- pr-unblock's `fix-docs` reports its check on the head it ran on when the PR head moves while it
  runs, instead of posting failure on the new head and blocking the merge. A new `fix-docs-head`
  job, which runs no head code, reads the head both `fix-docs` calls pass as `head-sha`; a run head
  that matches no gated head still posts failure. The read runner's new `post-decline` input
  (default `true`) is `false` for fix-docs, so a run that stops before its trigger gate posts
  nothing and the once-per-PR dispatcher tries the PR again.

## [3.6.0] - 2026-10-22

### Added

- `adoption.spec-from-body-apps`: the App ids whose PR bodies a script writes (the release App
  and the standards-sync App here). An adopted PR that closes no issue is judged against its own
  title and body when a person or one of these Apps opened it; resolve-pr hands the verifier that
  text as the spec, and the verdict records `intent: pull-request`. Any other App, the lanes App
  included, still needs a closing issue, since a model that wrote the diff would also have
  written its spec. A body last edited by anyone but its author or a trusted person is not the
  spec, and the verdict records the body's sha256 (`intent_sha256`).

### Changed

- Adoption covers every account on `.github/standards/trusted-actors/trusted-actors.json`, people
  and Apps alike, matched by id (owner decision 2026-10-22): fix-ci fixes a red PR the release
  App, the owner or anyone later added to the list opened, and `merge.verify-authors:
  lane-or-owner` judges it. An App's PR is adopted at once; a person's still waits
  `adoption.idle-hours`. Dependabot's red PRs stay with review-dependency.
- The verifier fails a change that alters behavior or intent the spec does not ask for, a lane's
  CI fix included, which escalates the PR to a person.

### Removed

- `adoption.owner-ids`: the trusted-actor list is the one source. Without `adoption.idle-hours`
  nothing is adopted.

## [3.5.1] - 2026-10-22

### Fixed

- pr-merge's `post-merge-dispatch` job re-runs a red full run it dispatched once before the
  demotion alert judges it, when the run was created within `red-main.confirm-wait-minutes` plus
  50 minutes (90 by default) and demotes by the affected-set rule, not only inside a lane merge's
  attribution window. The alert demotes only when that re-run fails too.

## [3.5.0] - 2026-10-22

### Changed

- resolve-config accepts `merge-base`, `review-threads` and `dependency-review` on a `read` skill
  that hands its change on as a patch (`applied-by.patch`), as the Activities section already
  describes, so those activities can move to the read runner. Without `applied-by.patch` the
  shape is still refused
  ([README.md](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md)).

## [3.4.2] - 2026-10-22

### Fixed

- work-unblock's sweep re-fires an `agent-ready` issue whose work-resolve-issue run was cancelled
  in `pick-slot` (its timeout while it waited in the WIP cap step) after `admit` passed and before
  `resolve-issue` ran, like a failed run and under the same once-per-workflow-version re-fire
  record ([run 39711139895](https://github.com/melodic-software/claude-code-plugins/actions/runs/39711139895)).
  A run a newer `agent-ready` run replaced while it waited ran no job and is still not re-fired.

## [3.4.1] - 2026-10-22

### Fixed

- Lane scripts send a GitHub REST GET again when it is answered 5xx, answered 200 with an empty or unparsable body, or fails on the network, after about 2, 4 and 8 seconds with jitter, instead of failing the step on the first bad answer. Each attempt is aborted after 20 seconds, and the time failed attempts take plus the waits is capped at 60 seconds per API client. POSTs, 4xx answers, rate limits and other thrown errors are not retried here, and a retry line never prints an error's message.
- pr-verify, the feedback dispatcher and the workflow_run trigger gate read a commit's pull requests through GraphQL's `associatedPullRequests` when `GET /commits/{sha}/pulls` still fails after those retries, and apply the same open, same-repository and base filters to the result.

## [3.4.0] - 2026-10-22

### Added

- `merge.verify-authors: lane-or-owner` judges the lanes App's pull requests and the owner
  account's, matched by account id, so an idle owner pull request the pr-merge lane adopts has a
  verdict. This repository sets it.

### Changed

- The verifier's spec now counts text a trusted human wrote even when that human opened the
  pull request, so an owner pull request whose closing issue the owner wrote is judged against
  that issue. Text by the lanes App, any other Bot or App, or an untrusted account is still left
  out.

### Fixed

- The issue lane's new or changed scripts land executable. apply-patch now makes each file that
  ends in `.sh` or starts with `#!` mode 100755 after every refusal passes, under the new
  `script-exec-bit` row key that the `issue` row sets. The model still sets no mode:
  `new-executable` refuses any executable bit the patch itself carries. Before this, the patch
  committed such files as 100644 and check-affected's exec-bit check failed
  ([run 39729937593](https://github.com/melodic-software/claude-code-plugins/actions/runs/39729937593)).
  A resumed run keeps the executable scripts an earlier lane commit landed.
- Inside an issue lane's patch run, `check-affected.sh --uncommitted` gives its snapshot the same
  bits: the checks wrapper sets `CHECK_AFFECTED_SCRIPT_EXEC_BIT=1`, so exec-bit passes on a new
  script. A run that commits gets no such flag and still has to chmod its own scripts.
- The `issue` row now refuses `instruction-path`, so the issue lane pushes no plugin hooks,
  monitors or bin, and no agent instruction file. A row that sets `script-exec-bit` must refuse it.

## [3.3.3] - 2026-10-22

### Fixed

- Write lanes deny git commands: they reach git only through the base wrappers. In `merge-base`
  mode, whose skill resolves the merge with git, the lane denies git's global options, the
  subcommands that read config or reach a remote, absolute and parent paths, quotes, and the flags
  or paths that read a file outside the index (including `blame` and `grep`) or run a diff or
  text-conversion program
  ([pr-run-activity.md](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/pr-run-activity.md)).

- check-wip-cap treats a GitHub search answer with `incomplete_results: true` as unknown, not as a failed read: new admissions pause whether or not `pause-from` is set or reached, with `admission_basis` and `admission_reason` `search-incomplete` and a `check-wip-cap` warning, so work-unblock defers newly unblocked issues instead of admitting without limit on a false empty. A read that fails without that answer still fails open, the queued cap still pauses only past `pause-from`, and no run pause changes.
- check-wip-cap's over-cap warning names why the lane keeps running (the base config could not be read, `pause-from` is not set, or `pause-from` not reached), and work-unblock's deferral log names its reason instead of always citing the queued cap.

## [3.3.2] - 2026-10-22

### Fixed

- The verifier verdict rules say a failed read of a verify record, run time or diff refuses `verify:unreadable` rather than keeping `verify:earlier-fail`, except a diff GitHub answers with 404, which still keeps it (#9063).

- fix-docs runs again, now in the read runner's default `dontAsk` mode instead of `auto`, which
  run-claude-cli's subprocess env scrub forced back to the default mode
  ([run 39723040443](https://github.com/melodic-software/claude-code-plugins/actions/runs/39723040443)).
  Its Bash runs only explicit allow rules: each `ai-slop:audit` script by absolute path under
  `.lane/plugins`, bare and double-quoted, plus `sha256sum` and `mkdir -p` in `.lane/scratch`
  for the fix flow's digests, and `Edit(./.lane/scratch/**)` so a redirect into the scratch
  directory is approved. It denies `git`, the `user-scope.sh` script, `NotebookEdit` on the
  staged plugin and the write lanes' shell deny set. The staging step also makes `.lane/prompt.md`
  and `.lane/` read-only, so a script's `--out` lands only in `.lane/scratch`.
- Write lanes also deny `wc`, a read-only command that runs with no allow rule and can print
  file contents in its errors.

## [3.3.1] - 2026-10-22

### Fixed

- The read runner's permission-mode check accepts a leg whose CLI reports `default` when `dontAsk` was asked for, so read-runner skills such as fix-ci no longer fail after their model leg ([#8964](https://github.com/melodic-software/claude-code-plugins/pull/8964)). The launcher's `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB` forces the CLI into `default`, and the launcher always passes `--permission-prompts none`, under which Claude Code denies every call no rule allows ([CLI reference](https://code.claude.com/docs/en/cli-reference)). Every other mismatch still fails, and a test fails any launcher pin not yet checked to pass that flag.

- The pr-unblock and feedback dispatchers wait out a rate limit on the repository's job token instead of failing at once: retry-after when GitHub sends it, else until one second past the reset when no requests remain, else one minute, then the call is sent once more. Waits are capped at six minutes per run, summed; a reset further away fails at once and names the reset time.
- The lost-run reconciler re-runs, once, the failed jobs of an intake-label-needs-triage run whose first attempt failed within its lookback, so an issue the floor label missed (a rate limit, most often) gets it on the next tick.

## [3.3.0] - 2026-10-22

### Added

- `models.issue-dimensions.complexity-profiles` maps an issue's Complexity to the profile its run starts on. This repository sends high Complexity to the new `code-xhigh` profile (Opus at effort xhigh); low, medium and unset keep the activity's default.
- A profile's `escalate-to` names the profile one model rung up, which a run resolved at resolve-config's new `model-rung` input 1 takes instead. `code-fix` escalates to `code-xhigh`; nothing escalates past it.
- fix-ci retries once one rung up: a run that changed nothing and escalated only `unfixed` or `not-reproducible` checks skips apply-patch with the new `rung-up` reason, and the same pr-unblock run runs fix-ci and apply-patch again at `model-rung` 1. Unless that retry's patch applies cleanly, the pull request goes to a person, as do `protected-path`, `weaken-required` and `flaky` escalations.

- A top-level `adoption` section (`idle-hours`, default 24; `owner-ids`, default empty) names
  owner accounts whose pull requests the lanes adopt. pr-unblock-dispatch starts `fix-ci` for a
  non-draft owner PR whose `ci-status` failed once its last update and its head commit are both
  `idle-hours` old, with no `do-not-merge`, `needs-human` or tracker human-gated label and no
  body line starting `Hold:` (babysit's reading: any case, after any whitespace, a bare CR ends
  a line). This repository adopts kyle-sexton's PRs after 24 hours (owner decision Q22).

### Changed

- The Fable rung above `code-xhigh` stays off: no profile names `fable` or `best`, pending an owner decision on a per-week Fable allowance for the lanes.

- While `adoption.owner-ids` lists anyone, the tracker's human-gated label also holds lanes App
  PRs from `fix-ci`. A base `.work-item-tracker.json` that is not JSON holds only the adopted
  owner PRs, and fails the dispatcher run; lanes App PRs still get `fix-ci`.

- The pr-pipeline README's WIP cap section names each `agent-ready` writer and whether the queued cap paces it: only work-unblock's new labels are paced.

### Fixed

- fix-docs is paused: its pr-unblock slot is `enabled: false`, so a dispatched run skips at
  resolve-config before any model turn, and the broker grants it nothing. Under run-claude-cli's
  subprocess env scrub the CLI forces the default permission mode instead of `auto`, so every
  fix-docs run failed its permission-mode check after spending a model leg
  ([run 39723040443](https://github.com/melodic-software/claude-code-plugins/actions/runs/39723040443)).

- The queued count no longer counts an issue twice when a person edits its lane PR's first body line: an open lane PR whose first line names no issue is matched by its `work-resolve-issue/issue-<n>-...` head branch, at one pull request read each.
- work-unblock's `label-unblocked` job runs one at a time across the repository, so a burst of closes or a close run beside the hourly sweep can no longer each admit the queued cap's whole room.

## [3.2.0] - 2026-10-22

### Added

- The lost-run reconciler re-runs the failed jobs of a PR CI run that failed only from an outside outage: each failed job hit its time limit, had an install step cancelled or timed out, or lost its runner. An install step that exits with a failure, such as `npm ci` on a stale lockfile, counts as a real failure. It re-runs at most twice per run, 15 then 30 minutes after the attempt ended, only while status.npmjs.org and githubstatus.com both show no incident, and never a run with any other failure.
- fix-ci starts no model run on a head whose required-run failures are all infra while the reconciler will still re-run it; once both re-runs are used, or the run is older than the reconciler's 24-hour lookback, fix-ci takes the head.

### Fixed

- The red-main report names every red full run since the last green one that has no report on the log, so a report the repository-wide concurrency group cancelled while pending is seen in the next report, whose range re-decides over its merges.
- The red-main report takes the oldest `github-actions[bot]` issue carrying the log marker as its log, and counts only that account's comments on it (matched by user id) toward the daily cap and the dedupe, so a newer issue carrying the marker can neither take the reports nor reset the cap.

## [3.1.1] - 2026-10-22

### Fixed

- The skill-run diagnostics in both run-activity files (`act-turns.json` and the step summary) now fit the 32768-byte carry cap after JSON escaping: each `denied` entry's `tool_name` is cut to 100 characters, the write file keeps at most 4 `local_command_stderr` messages as the read file does, `subtype` and up to 10 model names are cut to 100 characters, and `local_command_stderr_total` counts every stderr message. When the file would still exceed the cap, the oldest stderr messages drop first, then denials from the end, so a PR-mode read run's scan job no longer refuses an oversized file.

- `check-trusted-trigger` stops a pull request whose `base.ref` is not the payload's `repository.default_branch` with the new reason `untrusted-base`, on `pull_request`, `workflow_dispatch` and `workflow_run` alike, as it does a payload without the default branch. Before, a listed author's PR stacked on another branch passed. `report-check-run` maps `untrusted-base` to no skip reason, so the check posts failure, not neutral.

## [3.1.0] - 2026-10-22

### Added

- A skill activity's `permission-mode` (`dontAsk`, the default, or `auto`) sets the read
  runner's launcher mode, through `resolve-config`'s new `permission-mode` output. A step after
  each launcher leg fails the run unless the CLI's init message reports that mode. fix-docs sets
  `auto`
  ([ADR 0049](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/adr/0049-run-ci-lanes-on-github-hosted-runners-under-trigger-and-token-hardening.md)).

### Changed

- fix-docs moves into the `pr-unblock` lane, so its check is `pr-unblock / fix-docs`.
  `pr-unblock-dispatch.yml` dispatches it on each push to main, once per open, ready pull request
  a person opened that changes a Markdown file, carries no `do-not-merge` or `needs-human` label
  and never had a fix-docs run, at most `limits.fix-docs-per-run` (default 2) per run
  ([README, fix-docs](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md)).
- fix-docs runs on the read runner with no write token, on ci-workflows' run-claude-cli and the
  automations role's API key first. pr-unblock.yml calls the read runner twice, each call with one
  Claude secret: `fix-docs` passes only `AUTOMATIONS_CLAUDE_API_KEY`, and `fix-docs-subscription`
  passes only `AUTOMATIONS_CLAUDE_CODE_OAUTH_TOKEN` and runs only after a credit stop or with the
  key empty. Every fix-docs job trusts the default branch tip
  ([pr-run-activity.md, Two calls on one credential each](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/pr-run-activity.md#two-calls-on-one-credential-each)).
- fix-docs's change leaves as a patch that the `apply-docs-patch` job pushes as one commit, only
  when a patch was written. A refused patch posts the `pr-unblock / apply-patch` check neutral and
  labels nothing
  ([pr-run-activity.md, prepare: apply-patch](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/pr-run-activity.md#prepare-apply-patch)).
- The `default` row of
  [`patch-rules.json`](https://github.com/melodic-software/claude-code-plugins/blob/main/.github/actions/resolve-config/patch-rules.json)
  refuses every agent instruction path, caps a patch at 300 files and takes a moved head with
  `--3way` (`skip-moved-head: false`).
- The read runner's launcher takes a skill with no prepare mode that hands on a patch: Bash,
  Edit, Write and Agent as tools, no Bash allow rule, and `Read(./.git/**)` denied. It fails red
  on `checks`, `self-checks` and `verify-scripts`.
- fix-docs routes to the new `docs-fix` profile, a mechanical worker from the multi-agent role
  map, which resolves to sonnet.
- The launcher accepts `web-access` (`domains: any` only), staging the research skills and their
  plugins under `.lane/`. fix-docs leaves it off.

### Removed

- The `pr-refine` lane and `pr-refine.yml`, whose `pull_request` trigger ran the read runner's
  scan job off main, where the `pr-pipeline-scan-carrier` environment refuses it.

## [3.0.0] - 2026-10-22

### Added

- The optional `red-main` block (`dry-run`, `daily-cap`, `max-culprit-age-hours`, `confirm-wait-minutes`) and the Red main rule: after a full run on `main` fails, `post-merge-demotion-alert.yml`'s report job confirms the red on its one re-run, pins the culprit merge, and reports whether the bot would revert it, in dry-run only ([README.md, Red main](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md#red-main)).

- `apply-issue-patch`: a script activity that runs
  [`apply-patch.mjs`](https://github.com/melodic-software/claude-code-plugins/blob/main/.github/scripts/apply-patch/apply-patch.mjs)
  with the `issue` row of
  [`patch-rules.json`](https://github.com/melodic-software/claude-code-plugins/blob/main/.github/actions/resolve-config/patch-rules.json)
  (now capped at 300 files, and at 5 MiB per patched blob and 20 MiB in all). It makes a new `work-resolve-issue/issue-<n>-<run id>-<attempt>`
  branch at the commit the model worked on, with one commit, after re-reading the issue's hold
  labels and `agent-ready`, and names that branch in the run's `lane.json`. On a resumed run its
  refusals cover everything the new branch adds since the default branch, not only the patch. resolve-issue sets
  `applied-by` (`patch: apply-issue-patch`, `work-outcome: report-outcome`), and
  `activity-rules.json` refuses it any write effect.

- Monitoring lane signal 9, lane stop: a lanes App comment in the window that starts with a work-resolve-issue `outcome=funding`, `outcome=limited` or `outcome=turn-cap` marker files or updates one issue per outcome (`lane-stop:<outcome>`), listing each stopped issue ([README.md, The monitoring lane](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md#the-monitoring-lane)).

- `limits.admission-min-per-hour` (default 1, 0 to 100): the issue lane's queued cap never falls
  below this rate times `wip.merge-rate-window-hours`, so a day with no lane merges cannot hold
  admissions shut. 0 removes the floor.

- post-merge-demotion-alert.yml files one fix issue per newly failing check of a red scheduled or
  dispatched full run on main, at most 5, beside the new demotion or failure record, and dispatches
  intake triage for each. The issue holds fixed text only (the failing job's name in a checked
  charset, never an annotation title, hex SHAs, the run link and the record number), carries no
  label, is locked before intake reads it, and is reopened when its check fails again, keeping
  `agent-ready` and with no second intake dispatch, so a repeat goes straight back to agents. A fix
  issue that could not be filed, locked, reopened or sent to intake is named in a comment on the
  record.
  The record keeps `needs-human`; closing a fix issue changes nothing on it.

- `merge.max-verify-fails` (default 3): counted fails at that many distinct heads refuse `verify:repeated-fail`, which needs a human, whatever a later pass says. Fails of other open or closed pull requests in the repository that close the same issue count too, so a new pull request does not reset the count. A value that is not a count of 1 or more, empty or non-scalar included, is 1. The escalation comment names the refusal, and skip-unchanged carries it forward like the other verifier refusals.

- **Role profiles in `models`.** A profile may name a multi-agent role (`role`, optional `workload` and `effort-role`) in place of a model. resolve-config takes its model and effort from the base checkout's [multi-agent role map](https://github.com/melodic-software/claude-code-plugins/blob/main/plugins/multi-agent/reference/defaults.yaml). The model is `opus` when the role map gives `inherit`, `default`, a model ID or nothing. The schema refuses a `model` or `effort` key on a role profile, so it can name neither `default` nor a model ID.
- **fix-ci routes to a role profile:** a worker on code at the verifier's effort, with 75 turns as before.
- **New `applied-by-patch` output** from resolve-config: the activity that applies the selected activity's patch.

- The optional `red-main.remedy` key, `rollback` (default) or `fail-forward`. Under `fail-forward` the red-main report plans no revert: its decision is `human`, naming the remedy, and a person or a fix pull request repairs `main` ([README.md, Red main](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md#red-main)).

- A `branch-cleanup` leaf (`max-deletes-per-run`, default 25) and the daily
  maintenance-delete-stale-branches.yml that applies it: a branch lives as long as its issue is
  open, and one whose pull request closed or merged and whose linked issue closed is deleted, at
  most `max-deletes-per-run` a run with the calls those deletes need reserved first, after a re-read of its tip and open pull requests and a
  ledger line in the step summary and an artifact. A lane run's stop marker does not keep a
  branch once its issue closed. A branch with an open issue or pull request, and a protected or
  ruleset branch, are never deleted; a branch that never had a pull request, or whose tip moved
  after its pull request closed with commits ahead, is listed for a person. A manual run is a
  dry-run by default.

- `merge.quarantine-days` (default 7, at most 30): days a quarantine issue excuses its suite's out-of-set
  failures from post-merge demotion. post-merge-demotion-alert.yml now checks out main's tip and,
  when every newly failing suite is outside the merges' affected set, files no demotion record and
  runs no red-main report; it files or comments each suite's quarantine issue instead.

### Changed

- resolve-issue runs on the read runner. Its model job holds no write token: only the read-only
  job `GITHUB_TOKEN`
  [claude-code-action](https://github.com/anthropics/claude-code-action) needs, and no App token
  or `id-token`. Its uncommitted change leaves as a patch, collected also after a turn cap or a
  usage limit so a resumed run continues it. The earlier-work check, the issue file, the reuse
  path and the reuse summary pass move to the read runner with it
  ([pr-run-activity.md, Issue mode](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/pr-run-activity.md#issue-mode)).
- work-resolve-issue.yml checks the labeler in an `admit` job, with a read-only token and no
  secret, before any job that gets the lane's Claude credential: an unlisted account's
  `agent-ready` starts no credentialed job.
- The write runner refuses an issue skill, and its apply-patch select step runs the activity's
  own script from the base.

- The monitoring lane and the lane sweep reopen the closed issue they hold for a key or fingerprint, with a comment carrying the new evidence, instead of filing a new one; a close as not planned or duplicate mutes it, and the lane sweep no longer limits this to a 14-day window ([README.md, The monitoring lane](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md#the-monitoring-lane)).

- The Models and Limits sections point at `pr-pipeline.yaml` (`models.profiles`, `models.routes`, `limits` and `wip`) for this repository's values instead of restating them; the built-in defaults stay.

- The held cap pauses the issue lane like the WIP cap: on or after `wip.pause-from`, at or over
  `wip.held-cap` held lane PRs, work-resolve-issue starts no run and work-unblock re-fires none.
  It used to alert only. This repository sets `held-cap: 10` (was 60).
- check-wip-cap publishes `pause_reason` (`wip`, `held-cap` or `wip,held-cap`) and, on every
  pause, logs `admission paused: reason=... countable=... wip_cap=... held=... held_cap=...` as a
  `::notice` and in the step summary, so pauses can be counted.
- `docs/adr/**` joins this repository's `floor-paths`: a lane PR that changes an ADR scores HIGH
  and waits for a human.

- pr-verify hands the judgment to the subscription job on run-claude-cli's `handoff` output instead of the `credit-stop` class, so a key the API refuses with status 401 or 402 (class `auth`) also falls back; a 403 still fails the key job. The key-leg warning says whether to replace the key or rotate one in. The subscription job's lane record is plain `pr-verify`, with the reason in `fallback-reason` (`credit-stop`, `auth` or `no-key`). Every ci-workflows action pr-verify uses is pinned to v0.58.0, whose run-claude-cli installs the latest Claude Code release by default.

- The unattended merge reads the `merge:` block and `babysit_loop_merge` at the default branch head as well as at the pull request's base SHA and takes the stricter value of each setting, so a tightening on the default branch reaches pull requests opened before it; the two must name the same agent identity and enable the same authority ([README.md, Unattended merge](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md)).

- Merge authority no longer promises a later C4 rung: `merge.rung` stops at `C3`, and the pr-merge lane merges on the verifier verdict.

- **BREAKING:** `models.profiles`, the `models.issue-dimensions` option maps and `models.issue-dimensions.sizes` are written in block style, one key per line, in `docs/conventions/pr-pipeline.yaml` and in `examples/claude-code-plugins.yaml`. Values and key types are unchanged. The shared YAML-subset reader that `set-dimensions.sh` and `scripts/check-convention-yaml.sh` use now refuses flow mappings, so a consumer's `pr-pipeline.yaml` that writes these maps as `{ ... }` must rewrite them in block style.

- This repository sets `limits.turn-cap-restarts` to 1: one run that reaches its turn cap resumes from its pushed branch per `agent-ready` a listed human adds, then goes to a person. The built-in default stays 0.

- The pr-merge lane no longer holds a pull request for an earlier head's `verify:earlier-fail` once its current head has counted pass or pass-notes verdicts whose runs were all created after every such fail's run (each `created_at` read fresh from GitHub, which a re-attempt keeps), and the pull request's own change at the head differs from its change at every failed head. That change is a digest of the changed lines in the compare diff from the merge base with the base branch, so a head that only merges the base, an empty commit, or an edit that only changes whitespace or adds blank lines keeps the hold, as does a diff that cannot be read. Those passes then decide, so a changed or untrusted spec still refuses. Skip-unchanged no longer carries a `verify:earlier-fail` forward while a pass artifact names the head.

- The HIGH path floor rule and the `floor-paths` and `floor-script-scopes` descriptions say that a test file (a `*.test.mjs`, `*.test.sh`, `*.test.js` or `test_*.py` name; a `tests/` or `fixtures/` directory alone is not one) under a plugin `scripts/` directory, a `floor-paths` glob ending in a `scripts` directory or a script scope, safe, under no declared path and named by no other changed file, no longer holds a pull request for that reason; every other floor entry and `floor-paths` glob, and `denied-paths`, still do.

- fix-ci runs on ci-workflows' run-claude-cli v0.54.0, on the automations role's API key first.
  pr-unblock.yml calls the read runner twice, each call with one Claude secret: `fix-ci` passes
  only `AUTOMATIONS_CLAUDE_API_KEY`, and `fix-ci-subscription` passes only
  `AUTOMATIONS_CLAUDE_CODE_OAUTH_TOKEN` and runs only when the first call's key leg hit a credit
  stop or its key is empty. A call that hands off uploads nothing, records no lane outcome and
  posts no check; the fallback call's lane record names why it ran. Both calls queue in the
  per-PR write group
  ([pr-run-activity.md, Two calls on one credential each](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/pr-run-activity.md#two-calls-on-one-credential-each)).
- The read runner stages a PR-mode skill's plugin, CI context, scratch directory and prompt
  under `.lane/` in the checkout, which `--restricted` can read, and leaves `.lane/` out of the
  patch. A head that already holds `.lane` fails red. A staged plugin with no `.mcp.json` gets
  an empty server list, and the patch leaves out the CLI's empty scrub stubs; a stub name the
  head does not track that holds anything else fails the collector, so nothing is collected.
- fix-ci's patch goes through
  [`apply-patch.mjs`](https://github.com/melodic-software/claude-code-plugins/blob/main/.github/scripts/apply-patch/apply-patch.mjs)
  as the `apply-patch` activity, named in fix-ci's `applied-by`. The `ci-context` row of
  [`patch-rules.json`](https://github.com/melodic-software/claude-code-plugins/blob/main/.github/actions/resolve-config/patch-rules.json)
  caps a patch at 300 files and gains the optional `instruction-path` refusal, so fix-ci still
  pushes no agent instruction path. apply-patch refuses a row with no `requires` list.
- `collect-patch.sh` runs git against a fresh scratch repository that borrows only the checkout's
  objects, so no filter, hook, fsmonitor or include the activity planted in `.git` runs. The PR-mode
  leak scan applies the patch onto the gated head, as apply-patch does, and scans every file it
  makes; it scans copies of the reply and patch that the uploads then read, and the run's
  `patch-sha256` is the scanned copy's.
- The read runner's PR-mode model job uploads nothing and writes no step summary. It hands the
  reply, the run fields and the patch to a new scan job as job outputs sealed with
  `seal-lane-output` to the committed `.github/lane-keys/scan-carrier.pub`, each with its byte
  count, with the patch capped at 256 KiB. The scan job runs with `contents: read`, no `id-token`,
  and in the `pr-pipeline-scan-carrier` environment, whose `SCAN_CARRIER_PRIVATE_KEY` its
  `open-lane-output` step alone reads; each caller passes it by name as `scan-carrier-private-key`,
  and `scripts/check-scan-carrier-secret-shadow.sh` fails when a repository or organization
  secret shares the name. It fails closed on a withheld, oversize, mismatched or
  unopenable output, scans against a fresh checkout of the gated head, and is the only job that
  uploads the reply, patch and verdict
  ([pr-run-activity.md, The scan job](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/pr-run-activity.md#the-scan-job)).
- The read runner's dirty-tree check runs through `collect-patch.sh` and prints no path, and a
  PR-mode run removes the workspace's `.git` and `.base/.git` after the collector, so no git
  config the model planted runs after its legs.

- The HIGH path floor rule says that adding only `disable-model-invocation: true` to a plugin skill's frontmatter that no agent could preload, and a non-script file under `plugins/<plugin>/evals/`, are exempt from the floor entries `babysit_risk.py` names; manifests, named files, declared paths and `denied-paths` still hold them.

- The HIGH path floor rule says a plugin or marketplace manifest leaves the floor and clears only when every key that differs is on its allow-lists (metadata such as `version` and `description`, or a title or description edit on an existing `userConfig` key); any other difference, including an added `userConfig` key, a `defaultEnabled` change and a removed `version`, a new `plugin.json`, an added, removed or renamed marketplace entry, or a side that cannot be read or parsed scores HIGH as `manifest-review-required`.

- The HIGH path floor rule says a changed file in an eval case whose `case.yaml` could name a `scaffold_script`, or could not be read, and any script or mode 100755 file under `plugins/*/evals/**`, scores HIGH as `eval-scaffold-review-required`; a manifest key on the allow-list clears only with its expected type, compared as JSON.

- `publish-feedback` counts a fix commit as touching a review thread on a skill's `SKILL.md` when it changes any file in that skill's directory (its `evals/` and `reference/` included), so a fix to a skill's evals no longer escalates `feedback-not-landed` (#8832). Every other thread still needs its exact path, and the range check is unchanged.

- The skill-run diagnostics in both run-activity files (`act-turns.json` and the step summary) record `denied` as one `{tool_name, input}` for each of the first 20 denied calls, where `input` is the call's command, `file_path`, `path` or `pattern` cut to 300 characters, dropping entries from the end until `denied` serializes to at most 8192 bytes, and `denied_total` as the count of all of them, so a PR-mode read run's sealed `act-turns.json` stays under its 32768-byte carry cap; the read file gains `denied`, and a denied Read, Grep or Glob call now keeps its path or pattern. The step summary shows each as `tool: input`, then `(+N more)` when some were cut. In a PR-mode read run, `denied` travels in the sealed `act-turns.json` and reaches the step summary only after the scan job's leak scan.
- The `skill-reply-*` artifact is kept 7 days instead of 3 in both run-activity files, matching the patch and dependency-verdict artifacts.

- check-wip-cap is the one admission pacing gate. It counts queued work (open `agent-ready`
  issues with no hold label that no open lane PR names on its first body line, plus held lane
  PRs) against the queued cap, `max(limits.admission-factor × lane merges per hour,
  limits.admission-min-per-hour) × wip.merge-rate-window-hours`. At or over it, on or after
  `wip.pause-from`, new admissions pause: the action's new `admission-open` output is `false` and
  it logs `admission paused: reason=queued queued=... held=... cap=...`. Runs never pause on it.
- work-unblock admits at most the queued cap's room per run. A ready issue past it gets
  `admission-deferred`, and each hourly sweep revisits those issues oldest first, re-admitting only
  one whose newest `admission-deferred` the lanes App or a listed human added.
- The status JSON gains `queued_issues`, `queued_truncated`, `queued_total`, `queued_cap`, `admission_factor`,
  `admission_min_per_hour`, `queued_over`, `admission_open`, `admission_reason`,
  `admission_room` and `admission_basis`.

- `wip.pause-from` is empty: over the WIP cap or the held cap the issue lane alerts and keeps starting runs.

### Removed

- The read runner's `output-mode` input: patch mode follows the activity's `applied-by.patch`,
  and issue mode refuses an activity that names no patch.
- `apply-ci-fix` and `.github/scripts/pr-unblock/apply-ci-fix.mjs`.

- **Breaking:** `limits.admission-window-hours` is gone from the schema, so a `pr-pipeline.yaml`
  that still sets it fails validation; delete the key. `admission-window.mjs` is removed with it.

### Fixed

- pr-verify's verdict upload checks the summary and notes against every shared credential pattern (`findSecret` in `lib/publish-gate.mjs`: GitHub, AWS, private keys and the rest), not only Anthropic key shapes, and the error names the matched kind.

- The issue lane's `run-checks` job keeps the base's check scripts but restores the lane branch's own `scripts/` data files (`.txt`, `.json`, `.jsonl`), so a check reads the lists the branch changed, such as a new plugin in `scripts/fragment-plugins.txt`, the same as the pull request's CI.

- `check-signed-commits` reports a pull request it could not check (its head never matched its branch, or its commits could not all be listed) as "could not verify the lane's commits" in its log and escalation comment, instead of "unverified commits" with no commit named. It still fails closed.

- work-unblock's hourly sweep relabels a red-main fix issue that post-merge-demotion-alert.yml
  reopened on a repeat failure, so work-resolve-issue starts on it. The reopen keeps `agent-ready`
  but runs on that workflow's `GITHUB_TOKEN`, which starts no run. The sweep matches the issue's
  `<!-- post-merge-fix check=... -->` first line and the workflow's recurrence comment, both
  `github-actions[bot]`'s, logs how many match, and has the lanes App post a record naming that
  comment, then remove and re-add `agent-ready`: once per recurrence comment, inside the
  five-a-run cap, and only when a listed human or the App added its newest `agent-ready`; never on
  an issue that is held, has an open lane PR or a lane run in flight,
  or had `agent-ready` added since the reopen.

- An `agent-ready` issue the issue lane skips on its dimensions (`split-required`, `research-first`, `probe-first`, `not-assessed`) no longer ends the run green and silent: work-resolve-issue.yml's `report-skip` job runs `report-outcome` with the new `dimension-skip` input, which labels the issue `needs-human`, removes `agent-ready`, and comments the next step (`/work-items:decompose`, research, a probe, or setting the fields) with no model run. A later run still resumes the branch an earlier turn-cap or stopped run left ([pr-run-activity.md, Issue mode](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/pr-run-activity.md#issue-mode)).

- A red full run pr-merge.yml starts after a merge now reaches post-merge-demotion-alert.yml, so its
  record, fix issues and red-main report follow the merge instead of waiting for the next scheduled
  run. The run uses `GITHUB_TOKEN` and raises no `workflow_run` event, so pr-merge's
  `dispatch-full-run` job sends its run id through `workflow_dispatch`. Red is every conclusion
  `babysit_postmerge.py` counts as failed (`failure`, `timed_out`, `cancelled`, `startup_failure`,
  `action_required`), so a run cancelled on a time-budget overrun files its record and fix issues
  too; the red-main report still takes only `failure`. The alert takes the id only from
  `github-actions[bot]` or a listed human, never the lanes App, and only for attempt 1 of a red
  `pr-require-checks.yml` run on this repository's `main` that `github-actions[bot]` dispatched.
  pr-merge re-runs such a run only inside a lane merge's attribution window, so the alert waits up
  to `red-main.confirm-wait-minutes` for a re-run and starts none of its own. A dispatched red,
  whether its re-run failed or never finished, files nothing once a newer `pr-require-checks` run on
  this repository's `main` has succeeded: `main` already recovered, and the alert logs so and files
  no record, fix issue or report. The dispatch also sends the run's head SHA, which the alert
  checks against the run and keys its concurrency group on, so every sighting of one signal and
  SHA runs one at a time.

- `check-signed-commits` waits up to 60 s, backing off 5, 10, 20 and 25 s, for the pull request's head to match its branch before it gives up, instead of 8 s, since GitHub's pulls API can lag a push by minutes.
- `report-check-run` posts "The lane's commits could not be verified." when the signed-commit check failed without naming an unverified commit, and keeps "not GitHub-verified" for a named one. It takes the check's `unverified` output as a new input.

- A run record whose id is a boolean no longer stands for run 1.

- check-wip-cap keeps the last known WIP and held-cap pause when the open listing or the base
  config cannot be read, instead of failing open. work-unblock's hourly sweep saves the
  status to the Actions cache; work-resolve-issue's pick-slot only restores it
  (`cache-mode: read`). With no saved state the check still fails open. A kept pause logs
  `admission paused: reason=<reason> (read-error, kept last state)`, and the status gains
  `pause_basis` (`read`, `last-state` or `fail-open`).

- `check-trusted-trigger` re-reads a `workflow_dispatch` PR until `GET /pulls` shows the head its branch ref points at, waiting 5, 10, 20 and 25 s (60 s in all), so a job after pr-unblock's model job gates the head that job just pushed instead of the one `/pulls` still reports. When the two never agree, or the branch ref is missing, the lane stops with the new reason `head-lag` instead of gating a stale head, and `report-check-run` posts it as a `superseded-sha` skip, since the push that moved the branch is gated by its own run; a fork is not waited on. `check-signed-commits` now uses the same read from `check-trusted-trigger`.

- review-dependency dispatches again. dependency-dispatch matched Dependabot by the login
  `dependabot[bot]`, but the GraphQL listing names the Bot `dependabot`, so every Dependabot pull
  request was dropped and no dependency review ever ran. It now matches the Bot account id
  (49699333).
- A review-dependency `fix` lands only when its commits change npm (`package.json`,
  `package-lock.json`, `npm-shrinkwrap.json`) or pip (`requirements*.txt`/`.in`) manifest and lock
  files outside `.github/`, in a directory `.github/dependabot.yml` lists for that ecosystem. The
  promote step checks every changed path against the base's `dependency-classify.mjs` (copied
  with its SHA-256 before any model turn) and leaves any other fix
  off the branch, which the verdict job escalates as `dependency-fix-not-landed`; the verdict
  job checks the same rule on what landed, and the `dependency-review` patch row allows only the
  new `dependency-manifests` predicate.
- A `merge` verdict on a Dependabot pull request that changes a workflow or action file posts no
  merge marker and escalates the new `dependency-workflow-held`, so a person merges it.
- A lanes App commit on a Dependabot pull request must be a version change. The promote step,
  the verdict job's `fix` and `merge` paths, and the pr-merge lane refuse a fix file that is not
  modified in place, not a regular `100644` file (a symbolic link, submodule or executable), or
  whose content changes more than a version: in `package.json` only existing dependency entries'
  plain, bounded semver ranges may change; a lock keeps the Dependabot commit's package keys, and
  each entry resolves to exactly its own `https://registry.npmjs.org/<name>/-/<name>-<version>.tgz`
  with a `sha512-` integrity, the same alias `name` as before, and no install-script change; and requirements lines may add only
  `name==version` pins of projects the fix also unpins, with `--hash=sha256:` continuations. The
  repository's version-bump commit is admitted only when its `plugin.json` changes nothing but
  `version`. The verdict job's `merge` path now checks every commit that
  is not Dependabot's own (matched by account id, web-flow and a valid signature), reads the
  `[ecosystem, directory]` pairs from the base's `.github/dependabot.yml` itself, and requires
  run.json to name the head the model job's gate passed. A refusal escalates the new
  `dependency-fix-refused`.

## [2.20.4] - 2026-10-20

### Fixed

- The lost-run reconciler lists pr-verify runs once per lost conclusion and per not-yet-completed status instead of all runs of the day, so a day with more than 500 runs no longer fails the page cap.

## [2.20.3] - 2026-10-20

### Fixed

- `check-trusted-trigger` matches the re-runner by account id on every path instead of by login: it reads this run's own record (`GET /actions/runs/{run_id}`) and checks `triggering_actor.id` against the trusted-actor list, so a released login re-registered by someone else no longer passes. A failed or malformed read, or a record for another run or attempt, stops with `untrusted-rerunner`. The App-label re-runner must still be the listed lanes App or a listed human. `pr-unblock-dispatch.yml` now passes the job token to the gate so it can read its run.

## [2.20.2] - 2026-10-20

### Fixed

- The lost-run reconciler pages through a day of pr-verify runs instead of failing when there are more than 100, says how many listings failed instead of "nothing lost", and explains an exit 1 in the act step.

## [2.20.1] - 2026-10-20

### Fixed

- The finding-closure paragraph states that a finding any review of a head reported, whole or incremental, clears only by a new head (a fix) or a human resolution: each head on the covering chain counts the summary and thread-less inline findings any review of it reported, and a later clean review of the same head never clears one ([README.md, Unattended merge](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md)).

- The code review, security review and intake triage callers now honor the lane kill switches. A `kill-switch` job ahead of each reusable call runs `check-kill-switch` on `CLAUDE_LANES_DISABLED` and `CLAUDE_LANES_REPO_DISABLED`, which fail closed, and the call runs only when it says proceed. The code review lane also stops when `CLAUDE_REVIEW_DISABLED` is `true`, and the security review lane when `CLAUDE_SECURITY_REVIEW_DISABLED` is `true`. Intake has no switch of its own. The pinned ci-workflows reusables still read none of these variables.

## [2.20.0] - 2026-10-20

### Added

- address-feedback: a fix request by a trusted person with write access may name files to add to
  its thread's scope. The select step reads each file-shaped word of the request outside fenced
  code and quoted lines, from the repository root when it holds a `/` and from the thread path's
  directory when it does not, and records it in the thread's `named_paths` when it is in the same
  `plugins/<p>/` directory as the thread's path, in normal form, not under `.github/`, not an
  instruction path, and a regular file at the gated head (ten per thread at most). The promote
  step and the reply job accept changes to those files.

### Fixed

- A plugin's `.mcp.json`, `.gitmodules` or `CODEOWNERS` is no longer in the plugin-wide part of a
  kept thread's scope.
- The instruction paths `apply-ci-fix` and address-feedback refuse now also cover a `hooks`,
  `.claude` or `.claude-plugin` segment with nothing after it, a plugin's `monitors/` and `bin/`,
  and `.lsp.json`; a thread's plugin-wide scope also refuses `.bash`, `.zsh`, `.ps1`, `.cjs`,
  `.mts` and `.cts` files and any path with a character outside ASCII letters, digits and `_@+.-`.
- The address-feedback promote step moves the PR branch only when every path the lane branch
  adds or changes is a regular file at its tip, not a symbolic link or gitlink.

## [2.19.5] - 2026-10-20

### Fixed

- work-resolve-issue's `post-statuses.mjs` posts a resumed branch's `pipeline/*` statuses only while the branch ref still points at the tip run-checks checked; a branch that moved, or whose ref cannot be read, gets no status, as report-outcome already treats those check results.

## [2.19.4] - 2026-10-20

### Fixed

- The Unattended merge section documents that pr-merge refuses, as `shared-copy-sources-changed:`, a pull request carrying a shared-library canonical that main changed since its merge base, escalates it with the human-gated role label and a `babysit-merge-shared-copy-escalation` comment, and that the fix is merging main and running `scripts/sync-shared-copies.sh`. The head-moved clear removes that label once the head moves ([README.md, Unattended merge](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md)).

## [2.19.3] - 2026-10-20

### Fixed

- The review-threads round records the SHA-256 of the thread file before the model runs, and the branch move and the reply collection read the file only when it still matches; otherwise the PR branch is not moved and no replies are collected ([pr-run-activity.md](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/pr-run-activity.md)).

- pr-merge's `gate-check` job writes a `pr-merge / gate` check only at a candidate's current pull request head: its read also fetches each pull request's head, and a row whose head differs, or whose pull request the read reports `NOT_FOUND`, is skipped with a logged reason instead of taking its commit from the summary artifact alone. A missing pull request skips only its own row; any other GraphQL error still leaves the read's candidates unwritten. The job gains `pull-requests: read` for that read.

- pr-merge counts the cap of two whole reviews per lane pull request from the lane identity's conversions to draft on the pull request timeline as well as from the reasons comment's record lines, so editing that comment, which the lane token can do, no longer resets the cap. An unread timeline requests no whole review.

## [2.19.2] - 2026-10-20

### Changed

- Write lanes deny the shell commands that can print a file or the environment (`echo`, `printf`, `cat`, `head`, `tail`, `grep`, `find`, `env`, `printenv`, `strings`, `od`, `xxd`, `diff`, `sed`, `awk`, `sort`, `cut`, `tr`, `base64`, `nl`, `tac`, `rev`, `uniq`, `fold`, `column`, `jq`, `xargs`, `more`, `less`) and `Read` of `/proc`; the skill reads files with `Read`, `Grep` and `Glob`. `resolve-issue` fetches only the Claude Code, Claude platform, GitHub, Node.js and Python docs hosts, and no longer runs `scripts/run-test-file.sh` or `check-skill.sh`; the pull request's CI runs the tests ([pr-run-activity.md](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/pr-run-activity.md)).

## [2.19.1] - 2026-10-20

### Fixed

- pr-merge holds a stale-input pull request at its old head when the `update-branch` call gets no answer (a timeout, no HTTP status, or a server error), since the update may have landed; only a 4xx refusal enqueues as before. `merge.check-inputs` reads only a clone that is neither shallow nor partial ([README.md, Unattended merge](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md)).

## [2.19.0] - 2026-10-20

### Added

- pr-merge requests a whole review of a lane pull request held only by findings an incremental review cannot clear: it records the request in the reasons comment, then converts the pull request to a draft and marks it ready, once per head, at most twice per pull request and once per run, only while fewer than 35 jobs run or wait and both tokens have 30% of each rate-limit bucket left ([README.md, Unattended merge](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md)).

## [2.18.0] - 2026-10-20

### Changed

- pr-verify runs its model on the automations API key first and on the subscription token only after a key credit stop or when no key is set, as two jobs on run-claude-cli v0.54.0. A permission denial in either job yields no verdict. A key credit stop warns that the automations key needs rotating and leaves one lane record: the subscription job's, named for the stop, or the key job's as rate-limit when a denial on the key leg ends the run. Every ci-workflows action is pinned to v0.54.0.

## [2.17.1] - 2026-10-20

### Fixed

- A resumed `work-resolve-issue` run that reports done with no commit of its own now opens its PR from the branch it resumed instead of stopping for a person. `run-checks` runs the activity's checks over that whole branch, and `report-outcome` opens the PR only when at least one check ran and none failed, the branch is still at the tip checked (the compare and the new PR use that SHA), `lane.json`'s `resume` equals the branch the run resumed, and every commit on it ahead of the default branch is the lanes App's. The PR body's Verification section records this, and the run's `pipeline/*` statuses go on that checked tip; otherwise the run still hands back.

## [2.17.0] - 2026-10-20

### Added

- `intake-reenter.yml` sends an answered issue back to intake: a listed human's `**Decision recorded.**` comment on a `status: needs-decision` issue, or the author's or a listed human's reply on a `status: needs-info` issue, removes the status label, adds `needs-triage` and, for an issue from a listed human or the lanes App, dispatches `intake-triage.yml` once. It never adds `agent-ready`. A dispatched intake run no longer skips a born-triaged issue ([README.md, Stages](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md#stages)).

- The monitoring lane (`maintenance-monitor-signals.yml`, "The monitoring lane"): an hourly scripted job on the job token that reads eight factory signals and keeps one deduplicated issue per signal and key.

### Changed

- The finding-closure paragraph states the rule pr-merge applies: a clean whole review of the current head in the thread's own lane closes a resolved thread whoever resolved it, so a HIGH security finding needs the security lane's own clean whole review, and an incremental review never closes an unchanged thread.

## [2.16.0] - 2026-10-20

### Added

- `merge.dependabot.majors` (`hold` or `review`, default `hold`) decides a Dependabot pull request
  with a major update, or with an update whose version cannot be read (a SHA pin), marked
  `<name>(unreadable)`, or whose title and commit metadata disagree, marked `<name>(disagree)`.
  Under `hold` the pr-merge lane refuses it with the reason `dependabot-major-held:<names>`
  whatever the review verdict says, and escalates it once: a marked comment whose first line is the
  `<!-- work-items:escalation lane=pr-merge kind=escalated -->` marker, so
  `/work-items:attend-queue` lists it, then the tracker's human-gated role label. `review` keeps the
  earlier behavior, where the lanes App's `verdict=merge` marker merges it. This repository sets
  `hold`. Non-major tiers and the publisher rule are unchanged. `version` stays 2.

- A skill leaf's optional `self-checks`: repository check scripts with fixed flags, the same shape as
  `checks`, that the skill runs and fixes before it commits through the same wrapper. They are
  advisory: unlike `checks`, the issue lane's run-checks job never reruns them, so a failure the
  skill cannot fix still opens the PR and is named in its report. `work-resolve-issue`
  `resolve-issue` lists `scripts/check-affected.sh --uncommitted`, which checks the work tree as
  the commit the API would make, with untracked files and file modes included, and leaves the
  checkout's HEAD and index as they were. `version` stays 2.

- New config: `merge.max-queue-ejections` (default 2, 1 to 20). The unattended merge gate refuses to
  enqueue a head the merge queue has removed that many times for failed checks since the head last
  changed (a pushed commit or a force push), and posts one marked comment naming the failing
  `merge_group` runs; an unreadable timeline, or 20 items with no head change, also refuses.
  `version` stays 2.

- `funding`, a map from Claude lane id to its funding role (`reviews`, `automations` or
  `issue-lane`), whose `<ROLE>_CLAUDE_API_KEY` and `<ROLE>_CLAUDE_CODE_OAUTH_TOKEN` secrets a lane
  on ci-workflows' run-claude-cli action passes; intake is the first, and the other entries name
  the role each lane takes when it moves ([README.md, Funding](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md#funding)).
  `version` stays 2.

- `limits.admission-window-hours` (default 24): the hours of issue-lane admissions the admitted
  backlog (open issues labeled `agent-ready`) may hold before new `agent-ready` labels pause. This
  repository sets 24.
- `limits.admission-factor` (default 0.8, greater than 0 and at most 1): the share of the lane's
  hourly merge rate admitted per hour.
- `.github/scripts/work-resolve-issue/admission-window.mjs` reports whether admissions are open
  from live counts and exits 0 open, 1 held, 2 on error.

- `merge.diff-check.floor-paths` (a list of globs) adds paths to the risk scorer's HIGH path floor
  while `high-path-floor` applies; a pull request touching one waits for a human, where a denied
  path makes it ineligible. With the floor, a changed SKILL.md, agents/**/*.md or commands/**/*.md
  file is compared by its base and head text, each read once: it scores HIGH when its frontmatter
  gains or changes `hooks`, `allowed-tools`, `tools`, `permissionMode`, `mcpServers`, `memory` or
  another capability key `babysit_risk.py` lists, when it adds or changes a `!` backtick command or
  gains a ```` ```! ```` block, when a changed line falls inside a ```` ```! ```` block, or when
  either side or changed frontmatter cannot be read. `merge.diff-check.floor-script-scopes` (a list
  of globs) holds a `.ps1` or `.cjs` file, or one with git mode 100755, inside one of them or at the
  top level the same way. This repository lists `bin/`, `.lsp.json`, `settings*.json` and the
  scripts of the plugins the CI lanes load as floor paths, with the directories of the scripts a
  SessionStart or PreToolUse hook runs by path outside its plugin's `hooks/` (`pydeps.py`,
  `arm_observer.py`, `destructive_guard.py`), held whole so a sibling module cannot shadow an import, and those plugins as script scopes
  (Q646), and sets `high-path-floor: true` (owner decision 2026-10-18, reversing Q661), so its
  pr-merge lane holds such a pull request for a human, and the scorer's fixed HIGH floor
  (`.github/**`, `docs/conventions/**`, agent instructions, hooks, `lib/`, `scripts/`, package
  manifests and more) now applies there too. The switch governs both lanes: in the local babysit
  lane, false leaves out `floor-paths`, `floor-script-scopes`, the capability check and the new
  fixed floor entries (`plugins/*/monitors/**`, `plugins/*/workflows/**`), so a local-lane pull
  request scores as it did before this release. `version` stays 2.

- A new optional `wip` block derives the issue lane's WIP cap from the lane merge rate: merged
  lanes-App pull requests per hour over `merge-rate-window-hours` (24) times
  `target-lead-time-hours` (2), rounded up, at least `min-cap` (default 1; this repository sets
  12, the earlier fixed cap); `limits.wip-cap` applies only when the merged count cannot be read.
  Held lane pull requests (`needs-human`, `do-not-merge`, or a body line exactly `Hold: a human
  merges this`) no longer count against it and form their own buffer, `held-cap` (60), with an
  alarm past `held-alarm-hours` (24). Lane PRs opened in the window may be at most
  `opened-to-merged-ratio` (0.8) of those merged. Over a cap the check alerts, and pauses the lane
  only on or after `pause-from` (empty: never). The check publishes its status as the `wip` step
  output, the step summary and its log line (README, WIP cap). `version` stays 2.

- New config: `merge.gate-budget-minutes` (a whole number of minutes; absent is no budget). The
  pr-merge workflow's gate loop starts no further candidate once it has run that long, and the
  candidate in progress finishes first, so the budget never stops a gate between its check and its
  merge-queue write. Each run starts after the last candidate the previous loop reached, read from
  the `pr-merge-gate-cursor` artifact of a scheduled or hand-started `pr-merge.yml` run on the
  default branch, and wraps
  round to the lowest PR number, so every candidate is reached across runs. This repository sets
  10, and the merge job's timeout returns from 55 to 30 minutes as a ceiling above it. `version`
  stays 2.

- `models.issue-dimensions` budgets a run on an issue from its Size, Complexity and Uncertainty
  org issue fields, read by field and option id: turn cap = the size's `base-turns` times the
  complexity factor, rounded up, and the size's `timeout-minutes`. A field with no value, or whose
  latest setter is neither a listed human nor the lanes App, is not assessed, and an unmapped
  option fails the resolve (`unmapped-dimension`). New skip reasons, before any model turn:
  `not-assessed`, `research-first` and `probe-first` (Uncertainty Knowable and Unknown) and
  `split-required` (Size Large). This repository sets `small` (75 base turns, 50 minutes),
  `medium` (150, 100), `large` (`split`), and complexity factors 1, 1.5 and 2.
  work-resolve-issue.yml reads the fields (`issues: read`) and the timeout before its run job
  starts and passes the new `issue-dimensions` input on, so a field set while the run waits
  cannot outgrow the timeout, which is 25 minutes without `issue-dimensions`. No lane reads a
  `size:` label. A run that reaches its turn cap with no outcome of its own now leaves a
  `turn-cap` marker naming the cap and the branch, and the `pipeline/resolve-issue` status says so.
  `limits.turn-cap-restarts` (0 to 5, default 0) is how many times work-unblock restarts such an
  issue since a listed human last added `agent-ready`; past it the issue goes to a person, and this
  repository sets 0. The next run after a `turn-cap`, `stopped` or `limited` marker resumes from
  that run's lane branch when every commit on it ahead of the default branch is the lanes App's
  verified commit, and `issue.json` gains `resume`; a resumed run that reports `done` with no commit
  of its own opens no PR: the runner checks only the run's own branch, so it goes to a person naming
  the resumed branch. A run that exits non-zero on a funding stop
  (`api_error_status` 400 with "regain access on <date>", or 401) leaves a `funding` marker, keeps
  `agent-ready`, counts toward `limits.limit-stops-per-issue` (not `turn-cap-restarts`), and work-unblock restarts it after
  the date; `lane.json` gains `failed`, `api-error-status` and `error-text`
  ([README, Models](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md#models); [pr-run-activity.md, Issue mode](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/pr-run-activity.md#issue-mode)).
  `version` stays 2.

- `resolve-config` outputs `model` and `effort` for run-claude-cli callers: `model` is empty for a
  `default` model, which the launcher cannot pass, and `effort` is empty when the profile sets
  none.

- On its schedule, `pr-merge` takes off a `needs-human` label the lanes App set for a pr-unblock
  escalation once every reason it recorded since adding the label no longer holds at the head: `workflow-staged` when main
  changes nothing under `.github/workflows/` since its merge base with the head, `unresolved-conflict`
  and `protected-path-conflict` when GitHub reports the PR mergeable, `feedback-protected-path` when
  the PR changes nothing under `.github/`. It posts one comment naming the reason and the head first,
  never touches a label a person added, and keeps the label once any account but the lanes App
  commented or reviewed since it went on. At most five a run. `version` stays 2.

- The pr-merge workflow's merge job uploads each sweep's verdicts as the `pr-merge-summary` artifact
  (30-day retention): the run, the candidate, enqueued, merged and held counts, refusal counts by
  reason with PR numbers and run lists stripped so they aggregate, any gate-budget stop, and the
  per-candidate results. It also logs one `refusal-counts=` line built from that data, so a log
  search finds it once.

- `merge.skip-unchanged` (`max-minutes`, default 60; `max-skips`, default 3): the pr-merge workflow
  reports a candidate the last gating run refused on unchanged inputs with that refusal, marked
  `carried`, instead of gating it again, until the refusal is `max-minutes` old or has been skipped
  `max-skips` runs in a row. `0` in either turns it off. The `sweep-cost=` line gains `skipped=`, and the
  `pr-merge-summary` artifact gains `skipped`: its `candidates` stays the listed count and
  `budget_stop` counts only gated candidates as reached.

- A skill leaf's `applied-by` names what it hands on, keyed by artifact (`patch`,
  `feedback-replies`, `dependency-verdict`, `work-outcome`), and the script activity that applies
  each. Only a skill with effect `read` and gating `advisory` sets it. The config reader rejects
  (`invalid-applied-by`) a target that is not a script activity, a `patch` target without
  `prepare: apply-patch`, and a lane that holds the producer without the target in a slot that
  needs it. `resolve-config` emits the map in the resolved activity and takes an
  `applied-by-supported` input, which `pr-run-activity-read.yml` passes as `patch`. A `read` skill
  whose `applied-by` sets `patch` gets the edit tools of a write skill, commits nothing, and is not
  asked to fix instruction surfaces or CODEOWNERS paths. No activity in this repository sets it
  yet ([README](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md#activities)).
- `.github/actions/resolve-config/patch-rules.json`, with its schema, registers what an apply-patch
  script is to admit from each producer's patch: one row per prepare mode, plus `default` and `issue`.
  Every row refuses `.github/**`, `.claude/**`, the root `.mcp.json`, `.gitmodules`,
  `**/settings*.json`, symbolic links, gitlinks, a new executable bit and a rename into any of
  those; a row without that set, or a two-parent commit whose `allow` is not exactly `[merge-result]`, is rejected.
  `resolve-config` checks the registry before every lane resolve and fails closed without it; the
  lanes token broker does not read it
  ([README](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md#patch-rules)).

- `.github/scripts/apply-patch/apply-patch.mjs`, the one script that applies a read model job's
  patch to a pull request branch, driven by the
  [`patch-rules.json`](https://github.com/melodic-software/claude-code-plugins/blob/main/.github/actions/resolve-config/patch-rules.json)
  row of the producer's prepare mode (`default` when it has none), read from the trusted base
  checkout. It refuses the whole patch on any change under `.github/` (any case, any `..` segment)
  or `.claude/`, to the root `.mcp.json`, `.gitmodules` or a `settings*.json`, on a symbolic link,
  gitlink or new executable bit, on a rename into any of those, on a path holding a backslash, on more paths than the row's
  `max-files`, on a path its allow predicates refuse, and on an Anthropic API key, OAuth token or
  GitHub token shape in the patch or a patched blob. A row without the universal refusals, or with
  an unknown predicate, throws before any write. A head that moved since the model job takes the
  patch with `git apply --3way` only when the moved commits touch no patched path, else it skips
  `superseded-sha`. The commit goes through the Git Data API with one blob per changed file plus a
  tree, a commit and a ref update. No workflow runs it yet
  ([README](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md#patch-rules)).

- The pr-merge workflow shows each candidate's verdict on its head as one `pr-merge / gate` check
  run: neutral and titled with the top refusal, with the blockers in the summary, or success once
  enqueued or merged over a refusal already on show. One GraphQL read per 50 candidates, and a write
  only where the title or conclusion changed. A new `gate-check` job writes it with its own
  `GITHUB_TOKEN` and is the only job holding `checks: write`; the merge job keeps `checks: read`.
  The check is never required and is not part of `ci-status`.

- `merge.check-inputs`: git pathspecs the pull request checks read. When main changed one since a
  pull request's merge base, the pr-merge lane updates the pull request from main instead of
  enqueuing it. The default lists the shared-copy registry (`scripts/shared-copies.txt`) and the
  docs-only allowlist (`scripts/docs-only-paths.txt`); the registry counts only for a pull request
  that touches a path it registers.

- `pr-merge` also takes off a `needs-human` label the lanes App set for one of its own escalations
  once the head has moved: when the marked App comment written last before the label is pr-merge's
  and came within a minute of it, and the newest App comment carrying each of
  `<!-- babysit-merge-verify-escalation -->` and `<!-- babysit-merge-risk -->` names, in its
  ``at head `<sha>` ``, a head other than the current one, it posts one comment naming
  `head-moved`, the old head and the new one, then removes the label so pr-merge judges the new head
  and escalates again if its refusal still holds. A head that does not parse as 40-hex, any other
  marker (another lane's escalation just before the label included), a label a person added, or a
  person speaking since the label keeps it.

### Changed

- A pull request that changes this convention adds a changelog fragment under `.changes/pr-pipeline/`
  (`scripts/new-changelog-fragment.sh pr-pipeline <bump>`) instead of a `CHANGELOG.md` entry, and the
  release pull request writes the fragments into one entry, so concurrent lane pull requests stop
  conflicting on this file. `version` stays 2.

- The checks copy also carries the base's `.shellcheckrc`, `.markdownlint-cli2.jsonc` and
  `.github/requirements-ci.txt`, which `check-affected.sh` and `run-ruff.sh` read. A check's
  wrapper unsets `GH_TOKEN` and `GITHUB_TOKEN` and pins git config the way a verify-script's wrapper
  does. A skill with checks is told to fix what a check reports in the working tree and to name
  anything it could not fix in its report; a skill that commits is told to run the checks, fix,
  and run them again before it commits.

- The pr-merge workflow's merge job logs its API budget through the shared `log-api-budget` action,
  for the lane token and the job's own token, at mint and at job end, so the reading also lands on a
  run that times out. A `sweep-cost=` line (both tokens' spend since mint, candidates listed,
  candidates reached) goes to the log and the step summary. The action gains a `costs` output.
- The merge job keeps the verdict reads that never change (FAIL run records of pr-verify origin,
  FAIL head refs by artifact id, run heads found on main) across runs with `actions/cache`, under a
  new key per run, restored by prefix. The restored entry is untrusted: each kept read lands in a
  `carried-*` section the reader uses only to count a FAIL; everything else is dropped
  (`.github/scripts/pr-merge/carry-run-cache.mjs`).

- The PR pipeline convention says that after main changes a lane workflow, a lane run is
  re-triggered with a fresh event, not `gh run rerun`, which the token broker denies as
  `workflow-modified`.

- `pr-verify.yml` judges on ci-workflows' run-claude-cli action as the `automations` role, so its
  runs spend `AUTOMATIONS_CLAUDE_API_KEY` credits first and fall back to
  `AUTOMATIONS_CLAUDE_CODE_OAUTH_TOKEN` after a credit stop
  ([README.md, Funding](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md#funding)).
  The model reads its data files from `pr-verify-data` in the working directory with Read alone,
  every other path and tool denied. No verdict is written when any leg hit a permission denial,
  or when the summary or notes hold text shaped like an Anthropic key or OAuth token, and a run
  that leaves no verdict fails. The
  artifact name and verdict JSON are unchanged. `version` stays 2.

- `address-feedback` now also works a review thread the lanes App never commented on when a
  trusted person with write or admin permission replies to the reviewer bot's finding with a fix
  request (`PR-fix lane: please fix this finding`); every other comment must still be the reviewer
  bot's or a trusted person's. The select step, the reply job's re-read and
  `pr-feedback-dispatch.yml` judge threads the same way
  ([README.md](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md)).
  A fix request posted after the head's review starts the round when an account on the trusted-actor list runs
  `gh workflow run pr-unblock.yml -R melodic-software/claude-code-plugins -f pr-number=<n> -f activity=address-feedback`.
  `version` stays 2.

- `pr-run-activity-write.yml` takes a required `role` input, the funding role whose OAuth token the
  caller passes, and the lane record names that role's token (`<ROLE>_CLAUDE_CODE_OAUTH_TOKEN`) as
  the run's credential instead of always `AUTOMATIONS_CLAUDE_CODE_OAUTH_TOKEN`.
  `work-resolve-issue` passes `issue-lane` and its own `ISSUE_LANE_CLAUDE_CODE_OAUTH_TOKEN`;
  `pr-refine` and `pr-unblock` pass `automations`.

- `verify:fail` joins the verifier refusals that need a human: while `merge.report-only` is false the pr-merge lane escalates it with the `<!-- babysit-merge-verify-escalation -->` comment, which for `verify:fail` quotes the head `fail` verdict's `summary` as data, and the human-gated role label, so a refused pull request leaves the lane WIP count.

- At the address-feedback round cap (`loop.review-rounds`), a kept thread with a fix request
  from a write-access trusted person created after the newest counted round (its latest round
  marker or model check-run completion) runs one more round, on the requested threads only; other
  kept threads wait, and without such a request the PR still escalates `feedback-round-cap`. A
  round with no readable time grants none
  ([pr-run-activity.md](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/pr-run-activity.md)).

- `pr-merge` now keeps a lanes-App `needs-human` label only when a person commented, reviewed, or
  left a review or commit comment since it went on. A comment or review by a bot account (an AI
  review, another lane) no longer blocks the clear. An App comment carrying any marker other than
  pr-unblock's escalation still keeps the label.

- `checks`, `self-checks`, `verify-scripts` and `web-access` turned on need a skill whose runner
  stages edit tools: an effect other than `read`, or `applied-by.patch` without
  `prepare: ci-context`. Before, they needed an effect other than `read` and `checks` had no
  rule. `web-access` still requires `reads-untrusted: true`. `version` stays 2.

- A `verify:fail` escalation whose verdict record cannot be read, or a `verify:earlier-fail`, quotes
  the last fail summary the lane's comment carried, under the head it was given at.

- The work-resolve-issue lane's `report-outcome` no longer writes `Hold: a human merges this` on a `Refs:` pull request, and it holds a diff at the compare-listing cap only while `merge.diff-check.denied-paths` lists a path. A trusted `merge: human` label, structural or untrusted-provenance work, a denied-path match and an unreadable denied-path list still hold the pull request.

- A pr-merge `risk:MED` or `risk:HIGH` refusal whose reasons comment has stood unchanged at the head for `merge.risk-escalation-minutes` (new setting, 60) now gets its comment rewritten once to say the refusal persisted and needs a person, then the human-gated role label (the rewrite dates the comment beside the label, so the head-moved clear pairs them), while `merge.report-only` is false, so the pull request leaves the lane WIP count. A LOW score at that head first marks the comment cleared, so the time restarts with the next refusal. The README no longer says only a human removes that label: the `head-moved` clear does once the head moves. The README records the owner's finding-closure decision for #8450 and that the gate does not apply it yet (#8478).

### Removed

- The `funding` map. No workflow read it: each lane's workflow names its funding role as a literal
  ([README](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md#funding)).

### Fixed

- A write lane `pull_request` run on a PR that changes a workflow file the token broker compares no
  longer fails red. When the broker refuses the mint as `workflow-modified` and GitHub's compare of
  the default branch with the gated head lists the named file, the run job ends green with no token,
  its summary names the reason and file, and the check is neutral with the new skip reason
  `workflow-modified`
  ([pr-run-activity.md](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/pr-run-activity.md#a-workflow-file-the-pr-changes)).
  Every other denial, and a refusal of a file the PR does not change, stays red. `version` stays 2.

- `pr-run-activity-read.yml` takes the write file's `trusted-base` input and passes it to
  `check-trusted-base`, and pr-unblock's `fix-ci` job passes `trusted-base: default-tip`, as every
  other pr-unblock job does. A lane PR opened before `fix-ci` joined the config kept a base SHA
  whose config had no `fix-ci` slot, so every dispatched `fix-ci` run on it failed at "Resolve the
  config". `version` stays 2.

- pr-merge.yml's merge job now files the demotion record when its read-only post-merge check
  exits 1 (a failed lane merge: a canary or read-back failure, a missed dispatch deadline, or a red
  full run whose attempt 2 the agent identity did not start). It runs the check again with
  `--remediate` under the lanes App token, which files (or comments on, reopening) the record and
  dequeues the lane's merge-queue entries, so a human closing that record re-arms the lane. A full
  run this workflow dispatched with `GITHUB_TOKEN` raises no `workflow_run` event, so
  post-merge-demotion-alert.yml never files for it; when a human re-runs such a red run (run
  39200031682, red attempt 1, human attempt 2), the check reads it red and this step files the record.
  A red dispatched run that nobody re-runs still waits for its one re-run (exit 5) and files nothing;
  the lanes App cannot start that re-run.
- That step judges the remediation by its report, not its exit code: a missing report or a failed
  record filing or dequeue raises an error annotation, and only the expected refused re-run and
  dispatch attempts warn.
- post-merge-demotion-alert.yml also reads records the lanes App filed and treats a record of either
  filer that names the same failing run as this run's record, so one red run no longer gets two. Its
  record says the lane stays at rung off while any demotion record is open: fix main first, then close
  every open record.

- A red full run that pr-merge.yml dispatched now gets its one re-run without a person. The
  `post-merge-dispatch` job, which already holds `actions: write` under `GITHUB_TOKEN`, starts
  `rerun-failed-jobs` on attempt 1 of a red lane-dispatched run the post-merge check reports
  (`laneDispatched` in its `reruns`), one run per job. Once attempt 2 exists it uploads
  `pr-merge-rerun-<run id>-attempt-2`, which the post-merge check needs before it counts that
  attempt. Before this, such a run waited for a re-run the lanes App cannot start, every candidate
  was refused with exit 5, and no demotion record existed for a human to close until a person
  re-ran it. The lanes App gets no new permission. The re-run step runs only when the check
  could judge (exit 0, 1 or 5), after the full-run dispatch, and a failure in either leaves the
  other to run. Once the re-run starts, the step retries reading its attempt for about three
  minutes, and fails with an error rather than finishing quietly when it cannot confirm attempt 2.

- The held buffer only alerts: over `wip.held-cap` the WIP cap check writes its warning
  annotation and sets `held_over` and `alert`, but no longer pauses the lane. Only the WIP cap
  pauses it, on or after `pause-from` (README, WIP cap). Its warning over the held cap alone
  says only the WIP cap pauses the lane, instead of "pause-from not reached".

- `address-feedback` now works a thread a trusted person's fix request started even when the
  reviewer bot left the finding in a review of an earlier head than the one the reviewed-head
  markers name. Threads left by the reviewer bot alone, and threads the lane escalated, still need
  a review on a marker-confirmed head
  ([README.md](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md)).

- The `log-api-budget` action no longer reports a token's cost as `window-rolled` when the reset
  time moved earlier within one window; it counts `used` at end minus `used` at start, and calls
  the window rolled only when `used` fell or the reset moved more than 10 minutes later.

- `address-feedback` now works a thread a trusted person answered after the lane escalated it even
  when the reviewer bot left the finding in a review of an earlier head than the one the
  reviewed-head markers name, as it already did for a fix request with no escalation. Threads left
  by the reviewer bot alone still need a review on a marker-confirmed head
  ([README.md](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md)).

- `pr-unblock.yml` posts `pr-unblock / fix-ci` neutral `not-applicable` on the head when
  `fix-ci-context` skips (a closed pull request or no failing check). The skip posted no check,
  so `fix-ci-dispatch.mjs` sent the same lowest-numbered pull requests again on every run and
  starved every other red one.

- fix-ci now sees a failed check that a later skipped or neutral run of the same check hides, such as a contract-only run on a head whose `ci-status` stays red on the earlier failure; a later success still clears it.

- The merge-base lane (`pr-unblock` update-branch and resolve-conflicts) no longer escalates
  `workflow-staged` when the merge only brings in the default branch's own `.github/workflows/`
  files: `post.sh` lets the merge through when every staged workflow entry is the trusted base's
  (mode and blob), no head workflow is dropped, and the PR's own diff against every merge base
  touches no workflow. Every other case still escalates.

## 2.15.1 - 2026-10-18

`work-resolve-issue` no longer takes the model's word that its checks passed. A new `run-checks`
job, on a fresh runner after `resolve-issue`, runs each of the activity's `checks` from the default
branch tip's copy against a checkout of the lane branch whose `scripts/` is the base's, so
`scripts/fragment-plugins.txt` comes from the base and only the branch's own files, such as
`.changes/`, are checked. It hands the results (branch, tip, each check's exit status) to
`report-outcome` as a job output, never through the outcome artifact that code the model started
can rewrite, and only when `run-checks` succeeded. `report-outcome` lists those results under
Verification and stops a done run whose checks failed, are missing, or ran on a tip the branch has
since left, even when the outcome file's `not_done` is empty ([#7497](https://github.com/melodic-software/claude-code-plugins/issues/7497)).
`version` stays 2.

## 2.15.0 - 2026-10-18

`pr-unblock-dispatch.yml` starts pr-unblock's `fix-ci` for open lanes App pull requests whose
head's `ci-status` failed, from one GraphQL query per page with its `rateLimit.cost` logged, at
most `limits.fix-ci-per-run` per run and, on a head whose earlier runs all failed, at most
`limits.fix-ci-restarts` more times ([README](README.md#lanes)). Its job's concurrency group
now cancels a run in progress. `version` stays 2.

## 2.14.0 - 2026-10-18

`prepare` gains `ci-context`, the one mode for a `read` skill, and `apply-patch`, the one mode for
a script, a `mutate-branch` one. `pr-run-activity-read.yml` performs `ci-context`: it downloads a
base job's `ci-context-<attempt>` artifact, checks its SHA-256 and head, and gives the skill that
file plus Bash, Edit and Write; it takes `ci-context-attempt` and `ci-context-sha256` and gains a
`reply-attempt` output. `pr-run-activity-write.yml` performs `apply-patch` with the new
`patch-state`, `patch-sha256`, `patch-attempt`, `patch-head-sha`, `patch-activity` and
`reply-attempt` inputs ([pr-run-activity.md](pr-run-activity.md#prepare-apply-patch)). The
pr-unblock lane adds `fix-ci` and `apply-ci-fix`, which refuses the whole patch on a change to
`.github/**` or an agent instruction path (`CLAUDE.md`, `AGENTS.md`, `.claude/` or `.claude-plugin/`, a
plugin's `hooks/`, `.mcp.json`, `.gitmodules`, `CODEOWNERS`), and `report-escalation` takes six `ci-fix-*`
reasons. New config: `loop.fix-ci-rounds` (3), `limits.fix-ci-per-run` (2) and
`limits.fix-ci-restarts` (1). `version` stays 2.

## 2.13.0 - 2026-10-18

`pr-run-activity-read.yml` gains an `output-mode` input. The default, `clean-tree`, keeps failing a
run that leaves the tree changed. `patch` instead uploads what the activity changed against the
gated head as the artifact `patch-<lane>-<activity>-<run attempt>` (one `patch.diff`) and sets the
new `patch-state`, `patch-sha256` and `patch-attempt` outputs, beside a new `head-sha` output. An
empty change is `patch-state` `empty` and a success check titled `Passed: no changes`
([pr-run-activity.md](pr-run-activity.md#patch-output-mode)). `version` stays 2.

## 2.12.5 - 2026-10-18

The unattended merge gate reads `merge.max-in-flight` at the default branch head instead of at each
pull request's base, once per cache window; when the head's config cannot be read, the base's value
applies, and the post-enqueue room check keeps the lower of that and the cap the assessment applied. Every other `merge.` key is still read at the base.
`version` stays 2.

## 2.12.4 - 2026-10-18

`pr-run-activity-read.yml` takes a `dispatcher-run-id` input and passes it to its trigger gate with
`dispatcher-workflow: .github/workflows/pr-unblock-dispatch.yml` and
`dispatched-workflow: .github/workflows/pr-unblock.yml`, so a read activity that
`pr-unblock-dispatch.yml` sent to `pr-unblock.yml` runs; any other `github-actions[bot]` dispatch
still stops with `untrusted-actor`. With the id set, the skill step also admits `github-actions` in
`allowed_bots`. No caller passes it yet. `version` stays 2.

## 2.12.3 - 2026-10-18

`pr-unblock` `address-feedback` widens a kept thread's scope from its path alone to also a file in
the `plugins/<p>/` directory that path sits in, and a test file (`test_*.py`, `*_test.py`,
`*.test.*`, `*.spec.*`) in that path's directory
([#8109](https://github.com/melodic-software/claude-code-plugins/issues/8109)). The plugin-wide
part leaves out files the harness or a shell runs or loads as instructions: anything under
`hooks/`, `.claude-plugin/` or a `.claude/` directory, a `CLAUDE.md` or `AGENTS.md`, and any
`.sh`, `.py`, `.mjs`, `.js` or `.ts` file. The review-thread tool, the promote step and the reply
job apply the same rule; the promote step imports the base's `thread-scope.mjs` from a copy taken
before the head checkout, checked against its SHA-256. `.github/` stays refused. `version` stays 2.

## 2.12.2 - 2026-10-18

On a pull request labeled `needs-human` (the human-gated role label), `pr-unblock`
`address-feedback` works a thread when a person on the trusted-actor list with write or admin
permission asks for the fix: a line of their reply after the lane's escalation starts with
`PR-fix lane: please fix this finding`, in any case, outside a fenced block. Without one the
dispatcher starts nothing and the select step skips `awaiting-human`, so the pull request stays
held; with one the write runner lifts only the human-gated hold for that run
([pr-run-activity.md](pr-run-activity.md#prepare-review-threads)). Its `labels-absent` is
`[do-not-merge]`, `do-not-merge` still stops it, every other activity still waits on
`needs-human`, and `pr-merge` still refuses a `needs-human` pull request. `version` stays 2.

## 2.12.1 - 2026-10-18

A write-runner skill run that claude-code-action fails only because its `success` result went over
`--max-turns` now counts as a success: `act-outcome`, the verdict, the lane record and the job
result report success, so `pipeline/resolve-issue` posts `success` and report-outcome proceeds as on
any finished run. The run job reads this from the execution file's last result message (subtype
`success`, `is_error` false, `num_turns` over the cap); any other failure, or a missing or
unreadable execution file, still fails
([pr-run-activity.md](pr-run-activity.md#the-run-job)). `version` stays 2.

## 2.12.0 - 2026-10-18

`merge.max-in-flight` (an integer of at least 1, default 1) caps the lane merges in flight: the
agent identity's merge-queue entries plus its merged pull requests the post-merge check has not
verified. This repository sets 5. A red full run or canary run still charges every unverified
merge whose commit it contains. `version` stays 2.

## 2.11.10 - 2026-10-18

This repository's `limits.wip-cap` drops from 60 to 12, so `work-resolve-issue` starts no run, and
work-unblock re-fires none, while 12 or more lanes-App pull requests are open. The value is the
measured lane merge rate (about 1.5 per hour) times an 8-hour open-to-merge target. The schema
default (60) and its range (1 to 500) are unchanged. `version` stays 2.

## 2.11.8 - 2026-10-18

`pr-refine` no longer starts on `synchronize`: it runs when a PR opens, reopens or turns ready, or
on a `workflow_dispatch`, so an author push no longer draws a fix-docs commit and a fresh review
round. A docs change pushed after its first run waits for a reopen or a dispatch. When
`resolve-conflicts` escalates with `unresolved-conflict`, `pr-unblock.yml`'s scripted
`report-conflict-status` job posts a `failure` commit status with context `pr-unblock/conflict` on
that head, since GitHub runs no `pull_request` workflow on a conflicted PR. `version` stays 2.

## 2.11.7 - 2026-10-18

A `resolve-issue` run that waited in its slot while a change to `work-resolve-issue.yml` or
`pr-run-activity-write.yml` merged fails red `workflow-stale` before the token request, by the
broker's own blob comparison against main, instead of spending a mint the broker refuses as
`workflow-modified`. It leaves no outcome marker, so work-unblock's hourly sweep re-fires the issue
on main's files ([pr-run-activity.md](pr-run-activity.md#issue-mode)). `version` stays 2.

## 2.11.6 - 2026-10-18

An issue-lane run never dies on GitHub's rate limit or a pile of open lane pull requests.

- New `limits.wip-cap` (default 60, set in this repository's config). `work-resolve-issue`'s
  `pick-slot` job counts the lanes App's open pull requests with one search, through the new
  `check-wip-cap` action. At or over the cap, `resolve-issue` is skipped and takes no slot and no
  lane token. A failed count starts the run.
- work-unblock's hourly sweep re-fires a run that did no work: either its `Request the lane token`
  step failed (GitHub's rate limit past the 8-minute retry budget, among other causes) or the WIP
  cap skipped it. It waits `reset-clamp-min` hours after the run ended. The broker's `Retry-After`
  is at most an hour, so any rate-limit reset has passed by then. It acts only while fewer than
  `wip-cap` lane PRs are open, and stays within `restarts-per-run`.
- Such a re-fire is not limited to once per workflow version and is not a limit stop, so it never
  adds `needs-human`.

`version` stays 2.

## 2.11.4 - 2026-10-18

A write skill that commits through `commit_files` also gets `Bash(chmod +x *)`, and its commit
instruction says to run `chmod +x` on every new or changed file that starts with `#!` or ends in
`.sh` first: `commit_files` takes each file's mode from disk, and `Write` creates a file without
the executable bit, so lane PRs landed new scripts as `100644`
([pr-run-activity.md](pr-run-activity.md#skill-activities)). `prepare: merge-base` is unchanged:
the runner commits the staged index, whose modes the merge set. `version` stays 2.

## 2.11.3 - 2026-10-18

The verify-script wrapper for skill-quality's `check-skill.sh` runs it with `HOME` set to a fresh
`mktemp -d` directory and `CLAUDE_CONFIG_DIR` to that directory's `.claude`, so a skill test that
writes under `~/.claude` no longer fails on the runner's read-only one
([#8027](https://github.com/melodic-software/claude-code-plugins/issues/8027)). Other
verify-scripts keep the runner's `HOME`. `version` stays 2.

## 2.11.2 - 2026-10-18

The broker's `workflow-modified` refusal has one exception, for a lane's post-run report job
(`work-resolve-issue` `report-outcome`, `pr-unblock` `report-escalation`): it still mints when
every main commit that changed the workflow is signed, GitHub-made, on a linear range and landed
after run start, at most 50 minutes ago ([azure-iac#39](https://github.com/melodic-software/azure-iac/pull/39)).
The model step stays strict. `version` stays 2.

## 2.11.1 - 2026-10-18

The `resolve-issue` job passes `timeout-minutes: 25` to the write runner, down from 50, so a stuck
run frees its concurrency slot sooner. Of the 40 most recent successful runs the job took 3.5
minutes at the median, 10 at the 90th percentile and 15.4 at the maximum. `version` stays 2.

## 2.11.0 - 2026-10-18

[Changing this config](README.md#changing-this-config): a pull request that changes a lane and
lists a not-verified item that could stop the lane checks that item live before it merges. An item
only a merged run can exercise merges only once a tracked issue names the check and its owner; a
line in the pull request body does not count. `version` stays 2.

## 2.10.0 - 2026-10-18

`resolve-issue` lists `scripts/new-changelog-fragment.sh` as a `verify-script`, so the issue lane
can write a changelog fragment. The script now writes into the git work tree its caller stands
in (exit 2 outside one), not its own parent, refuses a plugin name with a path in it and a linked
`.changes` directory, and runs its own copy's `sync-shared-copies.sh` for `--carriers-of`, which
reads the checkout's registry. The verify-script prompt now says Bash runs only the named wrappers, each as its own command, that the
run inspects and changes files with Read, Grep, Glob, Edit and Write instead of `cd`, `;`, `&&`,
pipes or interpreter one-liners, and names the `git-mv-rm` wrapper for a rename or removal when
it is listed ([pr-run-activity.md](pr-run-activity.md#skill-activities)). `version` stays 2.

## 2.9.1 - 2026-10-18

`request-lane-token` also retries a broker 503 `github-rate-limited`, waiting exactly its
`Retry-After` plus up to 20 seconds of jitter, and fails red at once, naming the limit kind and its
reset time, when that wait would pass the 8-minute budget. A 503 `mint-unavailable` is never
retried, and its failure says it is final
([pr-run-activity.md](pr-run-activity.md#the-lane-token-broker)). `version` stays 2.

## 2.9.0 - 2026-10-17

`work-resolve-issue.yml` runs at most three `resolve-issue` jobs at once. A `pick-slot` job takes
the issue number modulo `SLOTS` (3, set in that job), and `resolve-issue` waits in the
`work-resolve-issue-slot-<n>` concurrency group with `queue: max`, so a burst of `agent-ready`
admissions queues instead of exhausting the lanes App's hourly API quota
([pr-run-activity.md, Issue mode](pr-run-activity.md#issue-mode)). The per-issue run group is
unchanged. `version` stays 2.

## 2.8.1 - 2026-10-17

`request-lane-token` retries a broker 503 whose reason is `github-unavailable`, with a fresh OIDC
token, after 60, 120 and 240 seconds plus up to 20 seconds of jitter, honoring a longer
`Retry-After` header and starting no retry more than 8 minutes after the first request. Every
other answer stays final ([pr-run-activity.md](pr-run-activity.md#the-lane-token-broker)).
`version` stays 2.

## 2.8.0 - 2026-10-17

An optional `limits` block sets the limit-stop restart values: `fallback-reset`,
`reset-clamp-min` and `reset-clamp-max` (hours), `restarts-per-run`, `limit-stops-per-head` and
`limit-stops-per-issue` ([README.md, Limits](README.md#limits)). Each defaults to the value the
lanes used before, and resolve-config emits all six. `version` stays 2.

## 2.7.0 - 2026-10-17

`resolve-issue` lists skill-quality's `check-skill.sh` and `check-evals-quality.sh` as
`verify-scripts`, so the issue lane can run the skill checks an issue's done-when names
([#7840](https://github.com/melodic-software/claude-code-plugins/issues/7840)). Every
verify-script wrapper now unsets `GH_TOKEN` and `GITHUB_TOKEN` before it runs the script, as
`scripts/run-test-file.sh` does for its test; code the script runs can still read the token from
an ancestor process's `/proc/<pid>/environ`. `check-skill.sh` runs each checked skill's
`scripts/*.test.sh` and the checkout's markdownlint: checkout code with the network open, the
power `run-test-file.sh` already gives the run ([pr-run-activity.md](pr-run-activity.md#skill-activities)).
`version` stays 2.

## 2.6.1 - 2026-10-17

`address-feedback.mjs select` now also keeps a thread the lane escalated (the lanes App's last
comment is an `INCORRECT`, `UNCERTAIN` or `VALID-defer` reply) when every comment after it is by a
human on the base's trusted-actor list, created after the escalation and edited by no one else.
Those replies are marked `direction: true` in the thread file. Before, every comment had to be the
reviewer bot's, so the lane never read a person's answer to its own escalation
([pr-run-activity.md](pr-run-activity.md)). `pr-feedback-dispatch.yml` judges a thread with the
same rule, so a review round that ends on a PR with such a thread dispatches address-feedback
([README.md](README.md)). `version` stays 2.

## 2.6.0 - 2026-10-17

A daily `maintenance` producer, the lane sweep ([README.md, The lane sweep](README.md#the-lane-sweep)):
a collect script, one read-only model leg per unit, and a file script that checks every quoted line
against main, de-duplicates by fingerprint, and files at most 5 `needs-triage` issues with the job's
own token. It labels nothing `agent-ready`. `version` stays 2.

## 2.5.0 - 2026-10-17

`scripts/run-test-file.sh` runs a `*.test.js` or `*.test.ts` file that imports `vitest` with the
package's locked vitest (`npx --no-install vitest run`, from the nearest `package.json` inside the
checkout), under the same checkout-path guard, after `npm ci --ignore-scripts` there when the
package has a `package-lock.json` and no `node_modules`. When it is a verify-script, the system prompt names
its wrapper as the test entry and says a compound `cd <dir>; <command>` is refused
([`pr-run-activity.md`](pr-run-activity.md#skill-activities)). `version` stays 2.

## 2.4.0 - 2026-10-17

`models.routes` and `resolve-config`'s `model-route` take a fifth run route, `summarize-reuse`
([README.md, Models](README.md#models)); this repository maps it to a new `summary` profile
(`sonnet`, effort `medium`, 10 turns). When work-resolve-issue reuses a lane branch, the write
file's new summary job, which holds only `contents: read`, runs a read-only summary pass
([pr-run-activity.md, The summary job](pr-run-activity.md#the-summary-job)), and `report-outcome`
writes its summary and changes into the PR body when the summary names the issue, the branch and
its current tip. Every reuse PR lists the files the branch changes, denied paths marked, and
still carries the hold line. `version` stays 2.

## 2.3.0 - 2026-10-17

`pr-run-activity.md` run job steps 11 and 12 now copy the base's `scripts/setup-env.sh` before the
head checkout, then set up Python and run it before a skill activity, so the skill can run the
repository's Python and Node tests. `version` stays 2.

## 2.2.0 - 2026-10-17

`models.routes` and `resolve-config`'s `model-route` take three more run routes: `review-code` and
`review-security` for the code and security review lanes, and `triage-issue` for intake triage
([README.md, Models](README.md#models)). This repository adds two profiles, `pr-review` (`sonnet`,
effort `high`, 75 turns) for both review routes and `triage` (`sonnet`, effort `medium`, 30 turns)
for triage. No caller resolves these routes yet, so no run changes.

## 2.1.0 - 2026-10-17

The issue lane admits on the `agent-ready` label alone (owner decision, 2026-10-17), whoever added
it: a listed human, or the lanes App through work-unblock. The owner's ratification marker comment
is retired everywhere. `admission` loses `ratified` and now requires `classes`; resolve-issue sets
no `admission` and holds an issue labeled `needs-human`, `needs-owner-decision` or
`status: needs-decision` through `labels-absent`. The write runner's and check-trusted-trigger's
`ratified-app-label` input is renamed `app-label`, and the gate reads no comment or edit history
for the App's label. `write-issue.mjs` freezes the issue for every run when the account that
applied the label added it in the event that started the run (its newest `labeled` event no
later than the payload's issue `updated_at`; a limit-stop restart anchors at the label it
restarted), leaving out later comments and failing on a later title or body change.
resolve-issue also requires `agent-ready` on the issue when the run starts (`labels`), so removing
it stops a waiting run. label-unblocked no longer reads the marker or
resolve-issue's admission, and the pr-merge lane no longer refuses `not-ratified`. `version`
stays 2.

## 2.0.0 - 2026-10-17

A `models` block sets each model run's model, effort and turn budget as named profiles, with
`routes` from a skill activity or `verify-pr` to a profile and a `default-profile` for the rest
([README.md, Models](README.md#models)). It replaces an activity's `model` and `max-turns` and
`merge.verifier-model`, which the schema now rejects; a config with no `models` block gets the
built-in `standard` profile (model `default`, 75 turns). Model values are aliases only.
`resolve-config` outputs `profile`, `claude-args` and `settings-json` in place of `model`, takes a
`model-route` input for a run that is no lane activity, and rejects an undefined profile
(`undefined-profile`) or route (`undefined-route`). The runners pass `claude-args` and
`settings-json` to claude-code-action and drop their `default-model` and `default-max-turns`
inputs; `collect-base-activity` drops its `model` and `max-turns` inputs; `pr-verify.yml` resolves
`verify-pr`. The write runner's lane record gains `models` and `profile`, after `max-turns`. This
repository's block keeps every run as it was: `standard` for each skill activity, `review` (`opus`,
60 turns) for the verifier. `version` is now 2: the schema rejects a version 1 config.

Migration from version 1:

1. Set `version: 2`.
2. For each distinct `model` and `max-turns` pair an activity sets, add a profile under
   `models.profiles` (`{ model: <alias>, max-turns: <n> }`; `model: default` for no `--model`, an
   alias for a full model ID) and a `models.routes` entry from the activity to it; delete the
   activity's `model` and `max-turns`.
3. Replace `merge.verifier-model: <alias>` with a profile (`max-turns: 60` keeps pr-verify's
   former budget) and `models.routes.verify-pr`.
4. Set `models.default-profile`; `{ model: default, max-turns: 75 }` keeps the runners' former
   defaults. With no `models` block every run gets that profile.

The pr-pipeline-sandbox keeps its own schema copy at version 1 and migrates when it takes this one.

## 1.27.0 - 2026-10-17

`merge.diff-check` gains three optional pr-merge lane switches, each off when absent:
`high-path-floor`, `c2-contradictions` and `max-changed-files`. In the pr-merge lane an absent
`max-changed-lines` is now no cap, and an empty `denied-paths` denies no path instead of refusing
`denied-paths-unset`. The schema asks for `denied-paths` and `max-changed-lines` only under
authority `local-babysit`, which keeps every check whatever the switches say. This repository
empties `denied-paths` and drops `max-changed-lines: 400` (owner decision, 2026-10-17), so a lane
pull request may touch any path at any size; the residual risk is in "The pr-merge lane", "Risk
switches". `version` stays 1.

## 1.26.0 - 2026-10-17

The pr-merge lane reads no `work-class:` label. A pull request the lanes App opened, not a fork or
a dependency manager's, with exactly one closing issue in this repository and no denied path, is
class C2, and the diff-derived C2 checks of the risk score still apply. The pr-verify verdict is
the merge criterion: with a rung above off the gate refuses `verifier-verdict-not-required` unless
`merge.require-verifier-verdict` is true, and the schema rejects an enabled pr-merge lane
(`agent-identity` set, authority absent or `pr-merge`) at C2 or C3 without it. Right before the
enqueue the closing issue is read again, and a different one refuses
(`closing-issue-changed:<was>><now>`); a class label removed meanwhile no longer refuses. The
closing issue must carry the owner's ratification marker under resolve-issue's rule, read fresh
at eligibility and before the enqueue (`not-ratified`).
`admission.classes` is now optional: without it only the owner's ratification marker admits and no
`work-class:` label is read, and an `admission` must set `classes` or `ratified`. This repository's
resolve-issue now admits on `{ratified: true}` alone, so an issue labeled read-only or mechanical
with no marker no longer starts the lane, and a ratified issue carrying another class now does
("Merge authority", "Activities"). `version` stays 1.

## 1.25.1 - 2026-10-17

The review-dependency activity checks commit provenance
([`pr-run-activity.md`](pr-run-activity.md#prepare-dependency-review)). Its classifier applies the
pr-merge lane's commit check as review reasons, so an unverified commit, one GitHub did not
commit, or one that is neither Dependabot's nor the version-bump commit sorts `review`, never
`auto`, and so does a commits listing short of the pull request's commit count
(`commits-listed:<listed>-of:<total>`). The select step skips `superseded-sha` when the head
moved since the gate, and records its start time before any model turn. The verdict job accepts
a `fix` only from commits GitHub signed for the lanes App during the run (author, committer
`web-flow`, a valid signature, a commit date no earlier than that start time) in a comparison
listed whole, else `dependency-invalid` or `superseded-sha`; it reads no Actions API. `run.json`
gains `files_truncated` and `started_at`, and a `merge` verdict on a truncated files listing
escalates the new reason `dependency-files-truncated`. `version` stays 1.

## 1.25.0 - 2026-10-17

Both Dependabot classifiers read the standards Dependabot policy at the base and make every update
to a dependency its `autoMerge.reviewOnly` lists tier `review` (`review-only:<dependency>`),
whatever the version change, and every Dependabot pull request tier `review`
(`dependabot-policy-unreadable`) when the policy does not read or a caller passes none. An entry's
`directory` covers a changed path in it, and a `github-actions` entry also covers the workflow and
action files the content rule gives its directory (README, "Review-only dependencies"). The
review-dependency activity gets the matched entries. Both classifiers also make an otherwise tier
`auto` npm or pip update tier `review` when its
registry provenance changed or cannot be read (`provenance-changed:<name>`,
`provenance-missing:<name>`, `provenance-unreadable:<name>`; README, "Registry provenance"). The
review-dependency select step outputs `controls`, `run.json` gains `controls`, and the write
runner gains a seventh dependency escalation reason, `dependency-control-uncited`: a `merge`
verdict on a review-only dependency that does not quote each matched entry's `control` in
`evidence`. The select step warns `classifier gap` when only a read failure sent a pull request
to review (README, "Classifier gaps"). `version` stays 1.

## 1.24.0 - 2026-10-17

`resolve-issue` lists two more `verify-scripts`, each wrapped by the same generator as the
can't-fail scan: `scripts/run-test-file.sh` runs one test file inside the checkout by name
(`test_*.py` under pytest, `*.test.sh` under bash, `*.test.mjs` under `node --test`, without
`GH_TOKEN` or `GITHUB_TOKEN`), and `scripts/git-mv-rm.sh` runs `git mv` or `git rm` inside the
checkout, recording an untracked path as intent-to-add first. Both refuse an absolute path, a `..`
segment, a leading `-` or `:` and a path that resolves outside the checkout (`scripts/lib/checkout-path.sh`).
`git-mv-rm.sh` sets `GIT_LITERAL_PATHSPECS=1`, so git reads no glob or pathspec magic, and
`run-test-file.sh` takes only `[A-Za-z0-9._/-]` names after `--`, so pytest reads no node id.
A write skill that commits also gets `mcp__github_file_ops__delete_files`, and the system prompt
tells it to delete each committed path it renamed or removed. When the stage grants the test-file
runner, the write runner sets up Python and installs the base's hash-pinned CI requirements before
the head checkout. `verify-scripts` may now list a script that changes files or runs checkout code
when the script limits itself. `version` stays 1.

## 1.23.0 - 2026-10-17

`merge.verify-authors` (`lane`, `any`; absent is `lane`) is a new optional key. Under `lane`
`.github/workflows/pr-verify.yml` judges only pull requests the lanes App opened (a `Bot` account
whose login is `merge.agent-identity`, compared as the pr-merge lane compares it) and skips any
other author's before the model runs, with the reason `author-not-lane`; `any` judges every
author's, and any other value judges none ("Verifier verdict"). `version` stays 1.

## 1.22.0 - 2026-10-17

`pr-unblock` gains `review-dependency` and `apply-dependency-verdict`, and `prepare` gains
`dependency-review` ([`pr-run-activity.md`](pr-run-activity.md#prepare-dependency-review);
[ADR 0074](../../adr/0074-review-risky-dependabot-updates-in-a-model-job-and-act-in-a-scripted-job.md)).
`pr-unblock-dispatch.yml` also dispatches `review-dependency` for at most 2 review-tier Dependabot
pull requests per run whose head has no `pr-unblock / review-dependency` check run. The model job
(`mutate-branch`) reads a read-only context file, the checkout and the upstream release notes as
data, may push a fix outside `.github/` whose every commit carries `[dependabot skip]`, and returns
a `merge`, `fix`, `close` or `escalate` verdict as structured output. The verdict job
(`publish-artifact`, no model) validates it and posts the round marker, closes the pull request
with an ignore-entry issue (never a security update), or escalates. Neither merges: the pr-merge
lane merges a review-tier pull request on the `verdict=merge` marker at the current head (1.20.0,
[ADR 0073](../../adr/0073-merge-dependabot-pull-requests-in-the-pr-merge-lane.md)). The
dispatcher sorts with the same tier and content rules as the pr-merge lane, and a base
`dependabot.yml` it cannot read is the reason `dependabot-config-unreadable`. `loop` gains
`dependency-review-rounds` (default 2; this repository sets 2), and the write runner gains the
`dependency-verdict`, `dependency-run-sha256` and `dependency-run-attempt` inputs and six
escalation reasons: `dependency-round-cap`, `dependency-invalid`, `dependency-fix-not-landed`,
`dependency-security-close`, `dependency-escalate` and `dependency-config-unreadable`. `version`
stays 1.

## 1.21.0 - 2026-10-17

`merge.require-verifier-verdict` and `merge.verifier-model` are new optional keys.
`.github/workflows/pr-verify.yml` judges each pull request head that passes `pr-require-checks`
and uploads a `pr-verify-<pr>-<head-sha>-<verdict>` artifact; with the first key true the pr-merge
lane refuses a merge, and dequeues a queued entry, without an allowing verdict at the head: a
counted `fail` under any pull request number or at an earlier head blocks, a pass needs every
linked issue written and last edited by a trusted human other than the author and unchanged since
the judgment, and a pull request older than 80 days goes to a human ("Verifier verdict" under
"Merge authority"). pr-merge.yml grants its job `actions: read` for the verdict reads. `version`
stays 1.

## 1.20.0 - 2026-10-16

`merge.dependabot.mode` (`off`, `report`, `enforce`; absent is `off`) adds the pr-merge lane's
Dependabot class (ADR 0073), and the pr-merge lane becomes the one merge authority for every
Dependabot pull request. The lane lists them unless the mode is `off`. Tier `auto` (every update
non-major, where major is a first-component change or, below 1.0, a second-component change;
Actions publishers `actions`, `github` or `anthropics` only; `ci-status` not red; read from the
verified commit metadata, else the title or body `Updates` lines, which must agree when both read)
merges on a green `ci-status`. Tier `review` merges only when the newest pr-unblock round marker
the lanes App authored names the current head with `verdict=merge`, and then also on a green
`ci-status`. Every commit must be a verified Dependabot commit, the `[dependabot skip]`
version-bump commit, or, after a review, the lanes App's `[dependabot skip]` fix; every push to
the head branch must be Dependabot's (or that commit's own pusher's), per the repository activity
API; and every changed path a manifest or lock file `.github/dependabot.yml` covers or a
`uses:`-only workflow or action repin; any other path makes the tier `review` with the reason
`dependabot-content:<path>`, while a failed push check always refuses. Both go through
the lane's gate as C2 with no closing issue, denied-path rule or diff risk score. The mode, not
`merge.report-only`, decides whether a Dependabot pull request writes, and the workflow starts the
post-merge full run when either can merge. `.github/workflows/pr-automerge-dependabot.yml` is
removed, and "Merge authority" no longer names it as an exception to the single authority.
`version` stays 1.

## 1.19.3 - 2026-10-16

"Outputs and skips" no longer says a leaf's verdict carries over to a commit with unchanged
content. A verdict and its findings belong to the commit the leaf judged, as "Activities" already
states, and a new commit gets a new verdict. `version` stays 1.

## 1.19.2 - 2026-10-16

`work-unblock.yml` also runs hourly (`schedule`, minute 47, from main only). A scheduled run lists
the issues closed in the last three hours (`LOOKBACK_HOURS` in `label-unblocked.mjs`; pull
requests and issues updated but closed earlier are left out), keeps those with a trusted close,
and applies the close path's rules to each issue they blocked, each once per run. It catches an
issue closed by a bot sender, such as a pull request merge, which the close-triggered run skips. A
scheduled run has no closer or re-runner to check; the kill switch and the `applies` gate still
run first, and the token request names no issue. On both paths, every blocking issue now counts as
done only when it was closed as completed with a trusted close, read fresh per blocker: its
`closed_by` is a listed human (by id), or a merge in this repository closed it: the `closer` of
the issue's last `ClosedEvent`, read with one GraphQL query, is a merged pull request or a commit
in this repository. The REST close event carries no link to the pull request, so GraphQL is the
read. Any other close, such as a workflow's `GITHUB_TOKEN`, does not count. A blocking pull
request counts only once merged, and a blocker in another repository never counts. An outside
author closing their own blocking issue therefore unblocks nothing. Both paths also refuse an
issue whose `agent-ready` label was ever removed, so removing it by hand stops the lane and
overlapping windows never put it back; a person adds it again to restart. The broker contract in
`pr-run-activity.md` lists `work-unblock.yml` as a `schedule` caller. `version` stays 1.

## 1.19.1 - 2026-10-16

The `verify-scripts` wrapper prints `exit status: <n>` to stderr and exits with the script's
status, and the system prompt tells the skill to run each wrapper as its own command: a chained
`; echo "$?"` needs approval the `dontAsk` lane denies. The write file's skill-run diagnostics
(`act-turns.json` and the step summary) gain `denied`, each command the permission mode denied,
redacted and cut to 300 characters. `version` stays 1.

## 1.19.0 - 2026-10-16

A skill leaf gains `verify-scripts`: exact paths of read-only checker scripts under `scripts/`,
`plugins/<plugin>/scripts/` or `plugins/<plugin>/skills/<skill>/scripts/`, no globs. For a skill
with an effect other than `read`, `collect-base-activity` copies each script's base plugin (or the
base `scripts/`) to a read-only `$RUNNER_TEMP/lane-verify`, denies `Edit` and `Write` on it, and
allows `Bash(<copy>/bin/<name> *)`, a wrapper that runs the script from the checkout with any
arguments except a path outside the checkout, with system, global, hook and fsmonitor git config
switched off. A leaf with effect `read` cannot set it. This repository's `resolve-issue` lists the
testing plugin's `cant-fail-scan.sh`. `version` stays 1.

## 1.18.5 - 2026-10-16

The write file gains the `ratified-app-label` input, issue mode only. `work-resolve-issue.yml`
sets it to `agent-ready` and no longer skips the lanes App's `agent-ready` label: the trigger gate
lets that one label from the App through only while the issue carries the owner's ratification
marker, read from the API when the run starts by the rule resolve-issue's admission uses
(`resolve-config/ratification.mjs`). Because the run reads the issue's title and body, a body
edit or title change after the newest marker also stops it. Any other App label or event, a
failed read, or no marker stops the run. The lanes token broker accepts the same labeler for an
`issues` mint, re-checking the marker. `version` stays 1.

## 1.18.4 - 2026-10-16

This repository's `pr-pipeline.yaml` adds the `work-unblock` lane (stage `work`) with one
activity, `label-unblocked` (a script, `mutate-tracker`). `work-unblock.yml` runs it when a
listed human closes an issue: each issue the closed one blocked gets `agent-ready` when it is
open, every blocker is closed as completed (not as not planned or duplicate), it carries none of
`needs-owner-decision`, `status: needs-decision` or `needs-human` in any casing, it holds the
owner's admission marker as resolve-issue reads it (the check now lives in
`resolve-config/ratification.mjs`, shared by both), and resolve-issue's `admission` admits it
(no `work-class:` label outside its classes; read from the config by
`resolve-config`'s `readAdmission`). The workflow stops before the token request when the
resolved activity does not apply (`enabled: false`). The label starts `work-resolve-issue` once
resolve-issue accepts App-added labels (follow-up by Automation Lanes). Everything is re-read
from the API when the run starts. A close whose sender is a bot (`sender.type` `Bot`), or whose
closer or re-runner is not a listed human (each is checked on its own; a re-runner may be
another listed human), is a clean skip. `version` stays 1.

## 1.18.3 - 2026-10-16

A verdict is bound to the commit it judged: the README no longer promises reuse by patch id or
content fingerprint. A `pr-merge` merge needs a verdict on the commit being merged, a precondition of
the lane's own merge rather than a required check, and a lane merge commit needs a fresh one. The
address-feedback round cap is `loop.review-rounds` (default 2) instead of a fixed 2. This
repository's `pr-pipeline.yaml` sets it to 3. `version` stays 1.

## 1.18.1 - 2026-10-16

`pr-merge.yml` no longer wakes on `workflow_run` completions of `pr-require-checks`,
`pr-review-hosted` and `pr-review-security-hosted`, and its schedule runs every 15 minutes
instead of hourly. Those completions arrived faster than the serialized runs finished, so the
`pr-merge` concurrency group's queue reached GitHub's 100-run cap and further runs were rejected.
Every run already reads every open PR, so the schedule finds what those wake-ups found.
`version` stays 1.

## 1.18.0 - 2026-10-16

`applies-when` gains `admission` (`classes`, optional `ratified`), an issues lane's admission
rule. An issue carrying a `work-class:` label outside `classes`, in any casing or spacing, is
refused with `not-applicable`, even beside a listed class. Otherwise an exact listed class label
admits it, or, with `ratified: true`, the owner's batch-ratification marker
`<!-- admission: admitted when unblocked, owner batch ratification YYYY-MM-DD -->` does: a line
in a never-edited comment by a human on the trusted-actor list, posted through no GitHub App. No
bot ratifies, the lanes App included. An `admission` predicate reads the issue's labels when the
run starts, and with `ratified: true` reads its comments; off an issues event, or when that read
is refused, the run fails. resolve-config logs the id, author and creation time of the ratifying
comment, never its text. This repository's `resolve-issue` replaces its `labels` allowlist with
`admission: { classes: [read-only, mechanical], ratified: true }`. `version` stays 1.

## 1.17.3 - 2026-10-16

This repository's `pr-pipeline.yaml` enables the address-feedback round: the `pr-unblock` lane now
runs `resolve-conflicts`, `address-feedback` (`source-control:pull-request comments --ci`,
`prepare: review-threads`, `mutate-branch`, held by `do-not-merge` or `needs-human`, skipping
drafts), `publish-feedback` (the reply script, `publish-artifact`) and `report-escalation`, which
now follows all three. `pr-feedback-dispatch.yml` starts dispatching on lanes App PRs from here
on. `version` stays 1.

## 1.17.2 - 2026-10-16

The write runner's promote step re-reads the PR's labels and draft flag with the job's
`GITHUB_TOKEN` right before it moves the PR branch: `do-not-merge`, the base's human-gated role
label, a label in the activity's `labels-absent` list, or a draft set while the activity ran drops
the lane's commits and skips `awaiting-human`, for every `mutate-branch` activity that promotes.
The hold labels are now read from the base by their own step for every PR-mode skill, not only
merge-base, and the merge commit step holds on the same list. `fix-docs` gains `draft: [false]`,
so it skips a draft before any model turn. `publish-feedback.mjs` re-reads the
PR branch before each post and each resolve and posts nothing more once it moved past the head the
job gated (`feedback-not-landed` before any reply, `feedback-partial` after one), and its round
marker names the model run, so a re-run of the reply job alone posts no second marker (a model run
that uploaded no replies names none and always posts). The
script needs `HEAD_REF`, `GITHUB_RUN_ID` and `MODEL_RUN_ATTEMPT`. `version` stays 1.

## 1.17.1 - 2026-10-16

`pr-feedback-dispatch.yml` no longer resolves the whole `pr-unblock` lane, which decided every
slot's `applies-when` and failed on `resolve-conflicts`' `mergeable` predicate with no head SHA.
`feedback-dispatch.mjs` finds the PR and its head first, then resolves only the `address-feedback`
slot for them, and dispatches only when the lane, `address-feedback` and `publish-feedback` are
enabled and `address-feedback` applies. A disabled slot no longer counts as present, and a lane with
no `address-feedback` slot still skips; a config the resolver refuses fails the run. resolve-config's
`resolve-config.mjs` exports `resolveFromBase`, which returns the resolved config or throws the
resolver's refusal (with `absentAsNull`, null for a valid config whose lane lacks the activity);
`main` wraps it. `resolve.mjs` exports `laneHasActivity`.

## 1.17.0 - 2026-10-15

`pr-unblock.yml` takes an `activity` input (`resolve-conflicts`, the default, or
`address-feedback`), and its dispatch concurrency group names the activity. `address-feedback`
runs as two jobs: the model job (`mutate-branch`), then, when its `feedback-round` output is
`true`, the `publish-feedback` script job (`publish-artifact`, `review-replies: true`, and the
model job's `feedback-run-sha256` as `review-run-sha256`), which posts the replies;
`report-escalation` takes any job's reason and its resume command names the activity. The
activity rules forbid `address-feedback` every effect that posts and `publish-feedback` every
effect that pushes. `pr-feedback-dispatch.yml`
dispatches `address-feedback` from `workflow_run` when both review lanes have reviewed a lanes App
PR's current head and a reviewer-bot thread is open; the trigger gate and the broker accept its
runs through the review run their record names, which a lanes App push or a listed human must have
started. The jobs after the model job pass its gated head as `expected-upstream-head`, so the gate
and the broker accept the review of that head when only commits GitHub signed for the lanes App
during the run (committer `web-flow`, signature `valid`) follow it. The dispatcher skips while a `pr-unblock address-feedback #<n>` run (the new
`run-name`) is queued or going, and dispatches nothing until the lane config holds both slots. The
write file gains the `expected-upstream-head` input and `head-sha` output. No effect grants both `contents: write` and
`pull-requests: write` but `merge`. No live activity sets either leaf yet. `version` stays 1.

## 1.16.0 - 2026-10-15

Schema: `prepare` takes `review-threads`. `pr-run-activity.md` "prepare: review-threads" says what
the write runner then does in two jobs. The model job keeps the reviewer bot's unresolved threads
on a marker-confirmed head before the mint, escalates `feedback-protected-path` or
`feedback-round-cap` before any model turn, stages the review-thread tool, pushes the fixes, and
uploads the replies the tool recorded; it posts nothing. A script job with the new
`review-replies` input and no model validates those replies, posts them and resolves only the
fixed `VALID` threads, posts the round marker, and escalates `feedback-uncertain`,
`feedback-not-landed`, `feedback-invalid`, `feedback-partial` (posting stopped partway),
`feedback-incomplete` (a kept thread has no disposition) or `feedback-disputed` (an INCORRECT
reply, left open for a person). The write file gains the `feedback-round` output. No
live activity sets it yet. `version` stays 1.

## 1.15.0 - 2026-10-14

Issue mode: `report-outcome` opens the PR ready, not draft, since the skill's CI mode now runs the
same prep the local pull-request prep does. A `report-statuses` job posts
`pipeline/<activity>` commit statuses for the lane's steps. Nothing is skipped on a success; a
failing one holds the pr-merge gate like any failing check.
`version` stays 1.

## 1.14.0 - 2026-10-14

Schema: a skill leaf's optional `web-access` (`enabled`, `domains`: `any` or host names), off when
absent; turning it on requires `reads-untrusted: true` and an effect other than `read`. `pr-run-activity.md` "Skill activities" says
what the write runner then allows: `WebSearch`, `WebFetch` to those domains (which also opens them
to sandboxed shell commands) and the research skills, with their plugins installed. The live config
turns it on for `resolve-issue` with `domains: any`; the token residual now says the model can send
its token to any allowed domain. `collect-base-activity`'s `plugin` output is now `plugins`, one per line. `version` stays 1.

## 1.13.2 - 2026-10-14

"The pr-merge lane" considers only pull requests the lanes App opened, and reads the work class from the pull request's single closing issue, never from a
label on the pull request, and counts a class label the lanes App or a human in person applied.
`report-outcome` no longer copies `work-class:` labels onto the PR, and `pr-merge.yml` shortlists
the lanes App's open PRs instead of PRs carrying the label. The live config's comment on
`merge` says so, and each `denied-paths` entry carries a one-line reason. `version` stays 1.

## 1.13.1 - 2026-10-14

The pr-merge workflow queues extra runs (`concurrency.queue: max`) instead of letting GitHub cancel
all but one waiting run, which left CANCELLED `merge` checks on PRs. No rule or schema change.
`version` stays 1.

## 1.13.0 - 2026-10-14

Schema: a skill leaf's optional `checks`, repository check scripts with fixed flags that a write
skill may run. `pr-run-activity.md` "Skill activities" says how the write runner runs them from the
base copy against the checkout. The live config gives `resolve-issue` the changelog fragment format check.
`version` stays 1.

## 1.12.4 - 2026-10-14

"The pr-merge lane" names three more reads it changes: the kill switch comes from the workflow's
own check (`--lane-kill-switch proceed`; missing or any other value stops), the rung cap from the
workflow's `vars` (`--lane-rung-cap`; empty is no cap), and the post-merge check
and in-flight rule count only merges the agent identity enqueued. In report-only mode the workflow
starts no full CI run. `version` stays 1.

## 1.12.3 - 2026-10-14

The `work-resolve-issue` lane's allowlist gains `work-class: mechanical` beside `work-class: read-only`,
and the comment above it names both. `labeled-after` is unchanged. `version` stays 1.

## 1.12.2 - 2026-10-14

The `work-resolve-issue` lane goes live: its `labeled-after` is now 2026-10-14T19:21:59Z, so issues
labeled `agent-ready` after that time start a run. The allowlist stays `work-class: read-only`
only. `version` stays 1.

## 1.12.1 - 2026-10-14

The live config gains the `pr-merge` lane with one `merge-pr` activity (effect `merge`, the babysit
wrapper under `--authority pr-merge`), run by `.github/workflows/pr-merge.yml`. `version` stays 1.

## 1.12.0 - 2026-10-14

Issue mode. Schema: stage `work`, and the `labeled-after` predicate, an issues lane's go-live time.
`pr-run-activity.md` gains "Issue mode": the write runner's `issue-number` input runs a lane on an
`issues` event with no PR. The live config gains the `work-resolve-issue` lane (`resolve-issue`,
then `report-outcome`), admitting `work-class: read-only` issues labeled after a go-live time that
ships in the far future, so the lane starts nothing until the owner sets it. `version` stays 1.

## 1.11.1 - 2026-10-14

`pr-run-activity.md` "The lane token broker": the request body gains `issue_number`, which the
broker requires on an `issues` event, sent by `request-lane-token`'s new `issue-number` input.
`version` stays 1.

## 1.11.0 - 2026-10-14

Schema: `merge.report-only` (boolean, default false). README "Merge authority" describes it and
adds "The pr-merge lane": the babysit wrapper under `--authority pr-merge`. The live config gains a
`merge:` block for the pr-merge lane with `report-only: true`. `version` stays 1.

## 1.10.5 - 2026-10-12

README: `ci-status` on a draft passes its skipped lanes; the `ready_for_review` run tests the head
and the merge queue re-runs every lane before a merge. `version` stays 1.

## 1.10.4 - 2026-10-12

README gains "Planning lane work": a one-page plan per sub-topic, design and stress tests only for
trust-boundary changes, ADRs only for trust-boundary or irreversible choices, and stops limited to
owner-reserved items when the owner pre-approved the recommendations. `version` stays 1.

## 1.10.3 - 2026-10-12

`pr-run-activity.md` run job step 14: the lane-token revoke step never fails the job. A DELETE
other than 204 is a `::warning::`, and a 204 whose `GET /installation/repositories` is not yet
refused with 401 is a `::notice::`. A confirmed revoke is recorded in the step log.
`scripts/write-runner-revoke-step.test.sh` runs the step's script against each case. `version`
stays 1.

## 1.10.2 - 2026-10-12

`pr-run-activity.md` "The lane token broker": the broker now also requires the dispatcher run's `pr-unblock-dispatched-<ids>` record to list the requesting run, read once with no wait. `version` stays 1.

## 1.10.1 - 2026-10-12

`check-trusted-trigger` refuses a `pr-unblock.yml` run sent by `github-actions[bot]` with `untrusted-actor` unless the dispatcher run it names uploaded an unexpired `pr-unblock-dispatched-<id>[-<id>...]` artifact listing this run's id, waiting up to 2 minutes for it. `version` stays 1.

## 1.10.0 - 2026-10-12

The config names its merge authority and the identity the local babysit lane acts as. Additive:
`version` stays 1, and the live config gains no `merge:` block, so its rung stays `off`.

- `merge.authority` (`local-babysit` or `pr-merge`) names the repository's one merge authority.
  Absent means `pr-merge`, the meaning a rung had before this key existed, so an existing
  `rung: C2` config still validates; the babysit wrapper merges only when it reads `local-babysit`.
- `merge.agent-identity` (the `[bot]` login of a dedicated GitHub App; any other login, and the
  shared `github-actions[bot]` and `dependabot[bot]` in any letter case, fail the schema) names the
  login the local babysit lane acts as. The schema requires it when `merge.authority` is `local-babysit`.
- `resolve-config` ignores both keys, so its resolved output is unchanged.
- README "Merge authority" gains "The local babysit lane": the effective rung, same-repository
  heads only, LOW risk only, review evidence bound to the pinned head SHA, the human-only cap
  variable `CLAUDE_LANES_MERGE_RUNG_CAP` and its 404 rule, the kill-switch reads, the demotion
  issue and how a human clears it, the opt-in label `merge: agent-allowed`, the HIGH path floor,
  the merge queue with `--match-head-commit`, one merge in flight, and
  `pr-automerge-dependabot.yml` as the one exception to a single merge authority. A verdict
  carried over by content fingerprint now applies to `pr-merge` only. "Outside this repository"
  gains the agent identity row.
- The example config shows both keys, commented out.

## 1.9.1 - 2026-10-12

The lanes token broker denies a repository whose `CLAUDE_LANES_REPO_DISABLED` variable is absent,
on both its token and check endpoints, with reason `kill-switch` (the detail reads
`not-false: the repository switch CLAUDE_LANES_REPO_DISABLED is not set`; azure-iac#24). `version` stays 1. Every repository on the
broker's allowlist must declare the variable as `false`.

## 1.9.0 - 2026-10-11

The read runner asks the lanes token broker before its model step. `version` stays 1; callers of
the read file must grant `id-token: write`.

- `pr-run-activity-read.yml` gains a `broker-check` job that the run job `needs`. It holds
  `contents: read` and `id-token: write`, runs only default-branch-tip actions, and never checks
  out the PR head. After a local kill-switch stop it ends green without a broker call, so the run
  job stops the lane neutral as before. Otherwise it posts once to the broker's check endpoint
  (`LANES_BROKER_URL` with `/token` replaced by `/check`), which mints nothing, and fails on any
  answer but an allow (`lane-check-denied`) or on none (`broker-unreachable`). The report job
  reads that failure as the run result, so the check is a failure, not neutral. The run job still
  holds no OIDC token, and fails red with `kill-switch` unless the broker-check job allowed its own
  run attempt, so "Re-run failed jobs" cannot reuse an earlier allow.
- `request-lane-token` gains `mode: check`, which takes only the broker variables, lane and
  activity and fails red on any write-path input.
- `scripts/check-read-caller-keys.sh` allows `id-token` in the read file only inside its
  `broker-check` job, and fails when that job is a reusable call or checks out anything but this
  repository's default branch tip, when the read file's top level is not `permissions: {}` or a
  job has no permissions map, and on `permissions: write-all` in any file of a read run.
- Callers of either file grant `id-token: write` on the calling job.
- The broker's check endpoint sees a repository variable named `CLAUDE_LANES_DISABLED` that
  shadows the org value, so a shadow no longer lets a read lane run.

## 1.8.0 - 2026-10-11

The `pr-unblock` dispatcher lands, and the write runner trusts its dispatches. `version` stays 1.

- New workflow `.github/workflows/pr-unblock-dispatch.yml` (script
  `.github/scripts/pr-unblock/dispatch.mjs`) runs on each push to `main` and dispatches
  `pr-unblock.yml` for the open, non-draft, same-repository PRs GitHub reports as conflicting, at
  most 3 per run, skipping a head that already carries a `pr-unblock` check run.
- `pr-run-activity-write.yml` passes `check-trusted-trigger` its `dispatcher-run-id` with the
  `pr-unblock-dispatch.yml` and `pr-unblock.yml` paths, so a `github-actions[bot]` dispatch runs
  only through a checked dispatcher run instead of always stopping `untrusted-actor`.

## 1.7.0 - 2026-10-11

The `pr-unblock` lane gets its caller and live config. `version` stays 1.

- New caller `.github/workflows/pr-unblock.yml`, `workflow_dispatch` only (inputs `pr-number`,
  `dispatcher-run-id`): job `resolve-conflicts`, then job `report-escalation` only when the first
  job's `escalation-reason` output is set, which it passes on as that job's `escalation-reason`.
  Both jobs pass `dispatcher-run-id` and `trusted-base: default-tip`.
- Every write caller job, `pr-refine`'s included, queues in one per-PR job group
  `pr-pipeline-write-<n>` (`queue: max`); `pr-unblock` also has the workflow group
  `pr-unblock-<n>`. `pr-refine`'s caller job now also skips the lanes App's own `pull_request`
  events, so a lane push never waits in that group. README: new [Concurrency](README.md#concurrency)
  section.
- The live config adds the leaves `resolve-conflicts` (applies only to a conflicting, non-draft
  PR without `do-not-merge` or `needs-human`) and `report-escalation`, and the lane `pr-unblock`;
  `pr-refine / fix-docs` also skips while `do-not-merge` or `needs-human` is on the PR.
- README: a base merge escalates only on a conflicted `.github/workflows/` path or a model-staged
  change under it; a workflow change that merges cleanly from the base is pushed.

## 1.6.0 - 2026-10-11

The write runner performs `prepare: merge-base` and takes the pr-unblock lane's inputs. `version`
stays 1.

- `pr-run-activity-write.yml` passes `prepare-supported: true` to resolve-config and runs a
  `prepare: merge-base` leaf around a merge of the trusted base: the base's `prepare.sh` before
  any model turn (a clean merge skips the skill), the skill without the commit tool, `post.sh`,
  then a two-parent merge commit through the Git Data API, promoted onto the PR branch.
  `collect-base-activity` takes a `prepare` input that leaves out the commit tool and the
  instruction to commit. Paths and checks: `pr-run-activity.md`, "prepare: merge-base".
- New inputs `dispatcher-run-id` (passed to `check-trusted-trigger` with no dispatcher or
  dispatched workflow named, so every `github-actions[bot]` dispatch stops `untrusted-actor` until
  the dispatcher change names both), `trusted-base` (`pr-base` or `default-tip`, passed to
  `check-trusted-base` as `mode`; `default-tip` trusts the default branch tip for config, actions
  and the merge's second parent) and `escalation-reason` (enum-checked, exported to a script as
  `ESCALATION_REASON`). New `workflow_call` output `escalation-reason`.
- The write runner sends `dispatcher-run-id` to the lanes token broker as `dispatcher_run_id`, a
  positive JSON integer that the broker reads only for a run sent by `github-actions[bot]`
  (broker side: azure-iac#20).
- Every `mutate-branch` activity re-reads its PR branch from `git/ref` before the mint; a moved
  branch skips neutral `superseded-sha` with no token and no model turn. This changes pr-refine:
  such a run used to run the skill and then fail at promote.
- The promote step confirms the PR branch through `git/ref` after moving it, and the report job
  re-reads `GET /pulls/{n}` until its head matches that ref, at most 5 reads 2 s apart.
- New scripted leaf `.github/scripts/pr-unblock/report-escalation.sh` (effect
  `publish-artifact`): labels the PR with the human-gated role label and posts one comment with
  the reason and a resume key. The write runner hands a script the base's
  `.work-item-tracker.json` as `TRACKER_CONFIG`, copied before the head checkout and hash-checked.
- Hardening of the merge-base steps: workflow commands stop while the merge scripts and git run,
  `GIT_NO_REPLACE_OBJECTS=1`, an allowlisted environment and absolute binaries in the commit
  step, a fresh label read that stops the commit on `do-not-merge` or the human-gated label, and
  a promote that moves the PR branch only to the commit step's own commit.
- `scripts/write-runner-never-rules.test.sh` asserts the write runner's structure against the
  resolve-conflicts `never` row: no forced ref update, no commit unless `post.sh` cleared the
  merge, the mint before the head checkout, and base scripts run only after their hash check.

## 1.5.0 - 2026-10-11

Composite activities, three new predicates and the `unblock` stage. `version` stays 1: no config
in this repository or the sandbox used the removed `respond` stage or the retired lanes.

- The `respond` stage is now `unblock`. `lane-rules.json` gains `pr-unblock` (stage `unblock`,
  forbidden effect `merge`) and drops `pr-address-feedback`, `pr-fix-ci` and `pr-update`, so a
  config that still names one of those lanes fails `lane-stage`.
- An activity is a leaf or a composite. A composite lists `children:` slots and may set
  `applies-when`; it declares no effect. The reader expands it into its leaves, applies lane rules
  to each, ANDs `enabled` down the path, requires every predicate on the path to match, and
  rejects an undefined child, a non-sibling `needs:`, a cycle, a composite inside a composite, and
  a leaf that appears twice in a lane. `resolveGrant` grants a leaf only.
- A leaf may set `prepare: merge-base` (a writing skill only); resolve-config outputs it.
- New predicates: `mergeable` (`conflicting`, `clean`; read only from `GET /pulls/{n}` at the new
  `head-sha` input, re-read while unknown, then `prerequisite-missing`), `labels-absent` (a listed
  label on the PR skips with `awaiting-human`) and `draft`.
- New trust-root `resolve-config/activity-rules.json`: per-leaf `never` text and optional
  `forbidden-effects`. A leaf with no row is valid.
- The example config replaces the three `respond` lanes with `pr-unblock` and its
  `resolve-conflicts` and `report-escalation` leaves.

## 1.4.2 - 2026-10-10

Docs only. `version` stays 1.

- README: "Outside this repository" names where each external piece the lanes depend on is
  documented (broker, Lanes App, org variables, rulesets, sandbox, standards, ci-workflows).

## 1.4.1 - 2026-10-10

A skill activity can read its own plugin and a write activity commits its edits. `version` stays 1.

- Every skill gets `Read` on `$RUNNER_TEMP/base-marketplace`, where its plugin loads from.
- A write skill gets a scratch directory (`--add-dir` plus an `Edit` rule) and an appended system
  prompt naming it; when the grant can commit, the prompt tells it to commit every file it changed
  with `mcp__github_file_ops__commit_files`. `collect-base-activity` takes a `can-commit` input.

## 1.4.0 - 2026-10-10

Write activities get a narrower grant, the tools their skill needs and computed targets. `version`
stays 1.

- `effect-grants.json`: `mutate-branch` grants `contents: write` with `pull-requests: read` and
  `issues: read`. The broker reads the same file at the tip, so a job resolved from an older base
  fails `effect-mismatch` until the PR's base moves past this change.
- A skill with any effect but `read` gets `Edit`, `Write`, `Agent` and the signed-commit tool, and
  its own `allowed-tools` Bash; `WebFetch` and `WebSearch` stay off. No rule limits which files it
  changes; the PR is the review step. `collect-base-activity` takes a required `effect` input and
  drops its `reads-untrusted` and `trusted-context-path` inputs.
- The `changed-paths` input is now passed: `resolve-config` writes it to the resolved file from the
  PR's file list, and the prompt carries it after `args`. It selects what the skill is asked to
  fix and is not a control. For a write effect it leaves out instruction surfaces and every path
  the base `.github/CODEOWNERS` lists, and it drops a name with a leading `@`; an empty result
  skips the activity with `not-applicable-paths`.
- The trusted PR context reaches a `reads-untrusted` skill only as `TRUSTED_CONTEXT_FILE`; the
  prompt no longer carries a `Trusted PR context:` line.
- The write runner cuts the lane token string out of the skill's reply before showing or uploading
  it.
- `reads-untrusted` also covers PR head files, which can quote untrusted text.
- The trust-root section states the hardening in force now that code-owner review is off by owner
  decision, that a write lane can change any file, and the residuals, including what a skill's
  unbounded `Bash(git:*)` grant allows with the token in the origin URL.
- A skill that can commit commits to a lane branch made at the gated head SHA; the write runner
  fast-forwards the PR branch to it only while the PR branch is still at that SHA, so a push
  during the run is never overwritten, and fails the activity otherwise.

## 1.3.0 - 2026-10-10

The write runner gets its token from the lanes token broker. `version` stays 1; callers of the
write file must change.

- `pr-run-activity-write.yml` drops the `app-private-key` secret and the
  `create-github-app-token` mint. Its run job holds `id-token: write` and, before
  `select-trusted-text` and any head checkout, calls the new `request-lane-token` action, which
  sends the job's OIDC token to `LANES_BROKER_URL` for audience `LANES_BROKER_AUDIENCE` once,
  never retrying. Either variable empty fails red.
- The step fails red on any answer but 200 (`lane-token-denied` with the broker's reason, or
  `broker-unreachable`), and, after revoking the token, on a 200 whose effect, permissions, lane,
  activity or repository differ from the job's own (`effect-mismatch`). The contract lists the
  broker's reasons, `default-branch-not-main` included.
- A final `if: always()` step, `actions/github-script` pinned by SHA, revokes the token and fails
  red unless `DELETE /installation/token` returns 204 and a later
  `GET /installation/repositories` with the token returns 401.
- Callers of the write file pass no App key and grant `id-token: write` on the calling job.
  `AUTOMATION_LANES_APP_CLIENT_ID` is no longer read.
- With no App key in either runner, one lane may call both files.
- `scripts/check-app-key-references.sh` fails `lint-repo` on `AUTOMATION_LANES_APP_PRIVATE_KEY`,
  `app-private-key` or `AUTOMATION_LANES_APP_CLIENT_ID` anywhere under `.github/workflows/` or
  `.github/actions/`.

## 1.2.0 - 2026-10-04

The runner splits in two. `version` stays 1; callers of the old file must move.

- `pr-run-activity.yml` becomes `pr-run-activity-write.yml`, for every effect but `read`. It keeps
  the App key and its mint, fails red with `effect-read` on a `read` activity, and stops with
  `bot-actor` when the lanes App bot is the sender or a `workflow_run` actor. A `bot-actor` stop
  posts neutral `untrusted-trigger`, like the other trust stops.
- New `pr-run-activity-read.yml` runs `read` activities with no App key secret and no `id-token`
  permission, and fails red with `effect-not-read` before the head checkout on any other effect.
- Both pass the run attempt's `triggering_actor` to `check-trusted-trigger`. A re-run by an
  account not on the trusted-actor list, by a denied account, or with no triggering actor stops
  with `untrusted-rerunner`, which has no skip mapping, so the check posts failure rather than
  turning an earlier red check on the same SHA neutral.
- Until the token broker lands, a lane runs head-code read activities only when no file of its run
  references the App key; `scripts/check-read-caller-keys.sh` checks it.
- The README lists the trust-root paths, and `pr-merge` refuses any PR that touches one. The
  refusal is recorded now and enforced when `pr-merge` is built.

## 1.1.1 - 2026-10-04

Fixes to the runner and reader. `version` stays 1.

- A `no-pr` trigger stop on `pull_request` posts neutral `untrusted-trigger` on the event's head
  SHA instead of no check. Three runs post no check: a fork PR, a `pull_request` event sent by the
  lanes App, and a run on any other event whose run job gated no head SHA.
- With an activity requested, `resolve-config` decides only that slot's `applies-when`, so another
  slot's undecidable predicate no longer fails the run; the other slots carry `applies` null.
- A requested lane the config lacks is rejected as `undefined-lane`, not `undefined-activity`.
- The run job's unused `applies` output is removed.
- `select-trusted-text` takes the job's `GITHUB_TOKEN` for a `read` activity, as the runner already
  passed it; that token has no `issues` grant.

## 1.1.0 - 2026-10-04

Additive, except one tightening: the activity names `run` and `report` are now rejected.
`version` stays 1.

- Activities take optional `model` and `max-turns` (skill activities only); `args` now applies to
  `script` activities too.
- Skip reasons gain `untrusted-trigger` and `not-applicable`; the schema's `$defs/skip-reason`
  holds the full set. Fork PRs, `pull_request` events sent by the lanes App, a `no-pr` run with no
  head SHA, and a run on any other event whose run job gated no head SHA post no check.
- A lane is one workflow with one model job; scripted jobs beside it report its check runs.
- Mechanical and judgment `verify` lanes start together; a failed mechanical gate cancels the
  judgment lanes.
- The config path is the reader's `config-path` input, read at the base SHA, with its basename and
  location constrained; the vocabulary is read from the base SHA's synced copy.
- Each lane's stage, forbidden effects and gating, and "never" rule move to
  `.github/actions/resolve-config/lane-rules.json`, and each effect's App token grant is in
  `effect-grants.json` beside it.
- The reader rejects any `extends:` value and the activity names `run` and `report`.
- `resolve-config` outputs the selected activity's `gating`.
- An activity that runs head code (tests, linters, builds) takes effect `read`; a write-effect
  activity must not execute head code.
- A `gate` skill activity must not execute head code; gating tests, linters and builds run as a
  `script` activity.
- The example config drops the `format` slot (`toolchain:lint --fix`, `mutate-branch`), which ran
  head code with a write token, and disables the `fix-ci` slot for the same reason until a split
  design exists.

## 1.0.0 - 2026-10-03

Initial contract: pipeline stages and their order, lane boundaries, the activity contract, slot
ordering, outputs and skip reasons, merge rungs, loop caps, and the config schema.
