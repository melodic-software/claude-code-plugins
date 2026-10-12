# Changelog for the PR pipeline convention

## 1.9.2 - 2026-10-12

`check-trusted-trigger` refuses a `pr-unblock.yml` run sent by `github-actions[bot]` with `untrusted-actor` unless the dispatcher run it names uploaded an unexpired `pr-unblock-dispatched-<id>[-<id>...]` artifact listing this run's id, waiting up to 2 minutes for it. `version` stays 1.

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
