# Changelog for the PR pipeline convention

## 1.25.0 - 2026-10-17

Both Dependabot classifiers make an otherwise tier `auto` npm or pip update tier `review` when its
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
