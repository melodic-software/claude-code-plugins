# pr-run-activity

Two reusable workflows run one activity of one lane each and end in one check run named
`<lane> / <activity>`: `success`, `failure`, or `neutral` with a skip reason.

- [`pr-run-activity-read.yml`](../../../.github/workflows/pr-run-activity-read.yml) runs an
  activity whose effect is `read`. It declares no App key secret. Only its `broker-check` job,
  which runs no head code, holds `id-token: write`, to ask the lanes token broker's check endpoint
  whether the lane may run ([below](#the-broker-check-job)). It fails red with `effect-not-read`
  before the head checkout for any other effect.
- [`pr-run-activity-write.yml`](../../../.github/workflows/pr-run-activity-write.yml) runs every
  other effect. It declares no App key either: its run job holds `id-token: write` and gets the
  effect's token from the lanes token broker before any head checkout. It never runs for the lanes
  App bot, and fails red with `effect-read` for a `read` activity.

Every lane workflow calls one of them once per activity; the activity's effect decides which. Which
activity runs, with what model, turn budget and token grant, comes from the base SHA's
[`pr-pipeline.yaml`](README.md), read by
[`resolve-config`](../../../.github/actions/resolve-config/README.md). Both files share the steps
before the head checkout through local composite actions
([`check-trusted-base`](../../../.github/actions/check-trusted-base/action.yml),
[`collect-base-activity`](../../../.github/actions/collect-base-activity/action.yml),
[`setup-runner-isolation`](../../../.github/actions/setup-runner-isolation/action.yml)) run from `.base`. Steps
after the head checkout stay in each file: the checkout replaces `.base`, so a `./.base/...` action
there would load from the PR head.

## Calling it

```yaml
jobs:
  claude:
    permissions:
      contents: read
      pull-requests: read
      checks: write
      id-token: write
    concurrency:
      group: pr-review-${{ github.event.pull_request.number || inputs.pr-number }}
      queue: max
    uses: ./.github/workflows/pr-run-activity-read.yml
    with:
      lane: pr-review
      activity: claude
    secrets:
      claude-code-oauth-token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
```

A write activity calls `./.github/workflows/pr-run-activity-write.yml` the same way, with the same
permissions, and passes no App key.

| Input | Default | Meaning |
|---|---|---|
| `lane` | required | The lane, its workflow's file stem |
| `activity` | required | The activity, one of the lane's slots |
| `config-path` | `docs/conventions/pr-pipeline.yaml` | For test callers only (below) |
| `pr-number` | `''` | The PR on `workflow_dispatch` |
| `timeout-minutes` | `30` | The run job's timeout; the report job's is fixed at 10 |
| `issue-dimensions` | `''` | Issue mode: the `models.issue-dimensions` dimensions the caller resolved for `timeout-minutes`; the run takes them instead of reading the issue's fields again |
| `dispatcher-run-id` | `''` | The `pr-unblock-dispatch.yml` or `pr-feedback-dispatch.yml` run that sent a `github-actions[bot]` `workflow_dispatch` (run job step 3) |
| `trusted-base` | `pr-base` | `pr-base` trusts the PR's base SHA, `default-tip` the default branch tip (run job step 4) |
| `dimension-skip` | `''` | Write file, issue mode, `report-outcome`: the issue-dimension skip reason (`split-required`, `research-first` or `probe-first`) that kept the run from starting; any other value, or one outside issue mode, fails step 1 |
| `escalation-reason` | `''` | Write file only: the escalating run's `escalation-reason` output, for a `report-escalation` script; anything outside the enum fails step 1 |
| `review-replies` | `false` | Write file only: for the reply script of a [`prepare: review-threads`](#prepare-review-threads) round, download the select job's `run.json` and the model run's replies |
| `review-run-sha256` | `''` | Write file only: with `review-replies`, the select job's `run-sha256` output |
| `expected-upstream-head` | `''` | Write file only: for a job after pr-unblock's model job on a `pr-feedback-dispatch.yml` dispatch, the head the select job read, passed to the gate and the broker (step 3) |
| `review-run-attempt` | `''` | Write file only: with `review-replies`, the select job's `context-attempt` output, which names its `feedback-context-<attempt>` artifact so a re-run of the reply job alone still finds it |
| `review-replies-attempt` | `''` | Write file only: with `review-replies`, the read file's `feedback-attempt` output, which names the scanned replies artifact |
| `review-replies-sha256`, `review-patch-state` | `''` | Write file only: with `review-replies`, the same read call's `feedback-sha256` and `scan-patch-state` outputs, which bind the replies' bytes and, with the scan refusal marker, decide whether missing replies are a `no-model-turn` skip |
| `feedback-context-attempt`, `feedback-context-sha256` | `''` | Read file only: for [`prepare: review-threads`](#prepare-review-threads), the attempt naming the select job's `feedback-context-<attempt>` artifact and its thread file's SHA-256 |
| `patch-threads-attempt`, `patch-threads-sha256` | `''` | Write file only: for [`prepare: apply-patch`](#prepare-apply-patch) under the `review-threads` row, the select job's artifact attempt and its thread file's SHA-256 |
| `patch-fix-requested` | `''` | Write file only: for [`prepare: apply-patch`](#prepare-apply-patch), a base-code job's verdict that lifts the human-gated hold of this push: the review-threads select job's `fix-requested`, or `lane-escalated` from `fix-ci-context`, `resolve-conflicts-select` or `fix-docs-head` when another lane's escalation put the label on |
| `merge-base-sha`, `merge-conflict-tree` | `''` | Read file only: for [`prepare: merge-base`](#prepare-merge-base), the base the caller's select job pinned and the conflict tree its merge reached; this run's merge must reach the same tree, and the scan job then reads the patch as text only |
| `patch-merge-base-sha`, `patch-merge-state`, `patch-conflict-tree` | `''` | Write file only: for [`prepare: apply-patch`](#prepare-apply-patch) under the `merge-base` row, the select job's pinned base, merge state and conflict tree, which this run's merge must reach |
| `dependency-context-attempt`, `dependency-context-sha256` | `''` | Read file only: for [`prepare: dependency-review`](#prepare-dependency-review), the attempt naming the select job's `dependency-context-<attempt>` artifact and its context file's SHA-256 |
| `patch-verdict-attempt`, `patch-verdict-sha256` | `''` | Write file only: for [`prepare: apply-patch`](#prepare-apply-patch) under the `dependency-review` row, the read file's `dependency-attempt` and `dependency-sha256` outputs, which name the scanned verdict and bind its bytes |
| `dependency-verdict` | `false` | Write file only: for the verdict script of a [`prepare: dependency-review`](#prepare-dependency-review) round, download the select job's `context.json` and the scanned verdict |
| `dependency-context-attempt`, `dependency-run-sha256`, `dependency-head-sha` | `''` | Write file only: with `dependency-verdict`, the select job's `context-attempt`, `run-sha256` and `head-sha` outputs |
| `dependency-run-attempt`, `dependency-verdict-sha256`, `dependency-patch-state` | `''` | Write file only: with `dependency-verdict`, the same read call's `dependency-attempt`, `dependency-sha256` and `scan-patch-state` outputs |
| `fallback` | `''` | Read file only, PR mode: `''` for the caller's first call, on `claude-api-key`; `credit-stop`, `no-key` or `handoff` for its fallback call, on `claude-code-oauth-token` ([Two calls on one credential each](#two-calls-on-one-credential-each)); any other value fails red in step 1 |
| `model-rung` | `''` | Read file only: the model rung the activity's profile runs at, resolve-config's `model-rung` (`1` takes its `escalate-to`) |
| `patch-model-rung` | `''` | Write file only: for [`prepare: apply-patch`](#prepare-apply-patch), the rung the patch's producer ran at; at `0` (or empty) an empty fix-ci patch may skip `rung-up` |
| `ci-context-attempt`, `ci-context-sha256` | `''` | Read file only: for [`prepare: ci-context`](#prepare-ci-context), the attempt naming the `ci-context-<attempt>` artifact and its file's SHA-256 |
| `patch-state`, `patch-sha256`, `patch-attempt`, `patch-head-sha`, `patch-activity`, `patch-prepare`, `reply-attempt` | `''` | Write file only: for [`prepare: apply-patch`](#prepare-apply-patch), the read model job's outputs, its activity name and that activity's prepare mode, which picks the `patch-rules.json` row (empty: `default`) |

In the write file's `workflow_call` outputs, `head-sha` is the PR head the gate passed, before
any push of the run, and `escalation-reason` is empty, or why a reply, verdict or apply-patch
script handed the PR to a person (under the `merge-base` row, the
[`prepare: merge-base`](#prepare-merge-base) push job's reasons).

The read file has five `workflow_call` outputs: `head-sha`, as in the write file,
`patch-state`, `patch-sha256` and `patch-attempt`, described with
[Patch output mode](#patch-output-mode), and `reply-attempt`, the attempt in the name of the
`skill-reply-<lane>-<activity>-<attempt>` artifact when the skill ran. In PR mode it also outputs
`lane-class`, `credential-present` and `handed-off`, from the launcher and the credential steps,
never from model text ([Two calls on one credential each](#two-calls-on-one-credential-each)),
and, set by the scan job alone, `feedback-attempt` and `feedback-sha256`, the attempt naming a
`prepare: review-threads` skill's scanned replies and their SHA-256
([`prepare: review-threads`](#prepare-review-threads)); `dependency-attempt`,
`dependency-sha256` and `dependency-verdict`, the attempt naming a `prepare: dependency-review`
skill's scanned verdict, its SHA-256 and its `verdict` field held to the four verdicts
([`prepare: dependency-review`](#prepare-dependency-review)); `scan-collect-refused`, `true` when
the run's collector refused the change (step 2 of [Patch output mode](#patch-output-mode)); and
`scan-patch-state`, `scan-patch-sha256`, `scan-patch-attempt` and `scan-reply-attempt`, the
patch outputs with no run job fallback, which a caller that takes nothing from a run job reads.

A scan refusal is no output: a failed scan fails the caller's job for the whole read file, and a
failed job's outputs are not documented to reach a `workflow_call` caller. When the scan job fails
or is cancelled in PR mode, the `scan-refusal` job, which needs the scan job alone, uploads
`scan-refused-<lane>-<activity>-<attempt>` holding `patch` when the scan refused a patch over its
cap and `output` otherwise. In the write file, `review-replies` and `dependency-verdict` download
every such marker for the model call's activity in the run, and the reply and verdict scripts
read a marker, or a failed download, as the refusal. A forged marker only hands the round to a
person.

Secrets are passed by name, never `inherit`: `claude-code-oauth-token` (skill activities, both
files) and, in the read file, `claude-api-key` (a PR-mode skill's first call), one of the two
per call. Variables: `CLAUDE_LANES_DISABLED` and `CLAUDE_LANES_REPO_DISABLED` (the org
and repository kill switches),
`AUTOMATION_LANES_APP_SENDER_ID`, the App bot's numeric user id, the one place it is written, and
`LANES_BROKER_URL` and `LANES_BROKER_AUDIENCE` ([below](#the-lane-token-broker)). The run job's first step fails red when
`AUTOMATION_LANES_APP_SENDER_ID` is not a numeric id, since an unset value would let the App's own
events through the self-trigger guard.

Both jobs set up Node 24: `resolve-config` uses `path.matchesGlob`, and the actions' suites run on
Node 24.

The caller must:

- Grant the calling job `contents: read`, `pull-requests: read`, `checks: write` and
  `id-token: write`. The `run` job narrows this to the two reads, plus `id-token: write` in the
  write file; in the read file only the `broker-check` job uses `id-token: write`, and only the
  `report` job uses `checks: write`.
- Put the calling job in a per-PR concurrency group with `queue: max`, or an equivalent that never
  cancels a pending run. A group that drops a pending run leaves that activity with no check, and
  silence is not a skip.
- Leave concurrency off the reusable workflow, which sets none.
- Call the file that matches the activity's effect. A mismatch fails red before the head
  checkout, so the file a caller names, and any `id-token: write` it grants, is what a human
  reviews.
- Reference no App key anywhere in a caller of the read file ([below](#secrets-and-the-two-files)).
- Expose `config-path` only from a test caller. A production lane never passes it and never offers
  it as a `workflow_dispatch` input, so no dispatch can point the reader at another YAML file in the
  base tree.

## The broker-check job

Read file only, before the run job, which `needs` it. It holds `contents: read` and
`id-token: write`, runs only actions from the default branch tip, never checks out the PR head, and
times out after 10 minutes. In order:

1. Fails red when the event names no default branch.
2. Checks out the default branch tip to `.base`, `persist-credentials: false`.
3. `check-kill-switch`. A stop ends the job green with no broker call; the run job's own
   `check-kill-switch` step then stops the lane, and the check is neutral `kill-switch`.
4. [`request-lane-token`](../../../.github/actions/request-lane-token/README.md) in `check` mode
   asks the broker's check endpoint whether the lane may run
   ([below](#the-check-endpoint)). The check mints nothing.

Any answer but an allow, or no answer, fails the job, which skips the run job. The report job
passes the broker-check job's result as `run-result` whenever it is not `success`, so a failure
posts a failure check and a cancel follows `report-check-run`'s cancel rule. A broker denial is
red, not neutral, for the same reason as the write file's `kill-switch` denial: step 3 already
stopped the common case. Off `pull_request`, a failed broker-check job posts no check, since no
head SHA was gated ([Runs that post no check](#runs-that-post-no-check)).

The job outputs `allowed` (`true` only when step 4 succeeded) and `attempt`
(`github.run_attempt`). "Re-run failed jobs" reuses a successful broker-check job and its outputs,
so in the read file, right after its own kill-switch step proceeds, the run job fails red with
`kill-switch` unless `allowed` is `true` and `attempt` equals its own run attempt. That also fails
a run whose broker-check job skipped the broker on a kill-switch stop its run job no longer sees.
Re-running all jobs asks the broker again.

Residual: `scripts/check-read-caller-keys.sh` checks the job's permissions, its shape and its
`actions/checkout` steps, not what its `run:` steps do. A `run:` step that fetched
`refs/pull/<n>/head` with git would put head content in the job; review catches that, the lint
does not.

## The run job

Holds `contents: read` and `pull-requests: read`, plus `id-token: write` in the write file for
the broker request, and no other permission; it never holds `checks: write` or `workflows`. It times out after the `timeout-minutes` input. In order:

1. Fails red unless `AUTOMATION_LANES_APP_SENDER_ID` is a numeric id and the event names a default
   branch.
2. Checks out the default branch tip, with full history, to `.base`. Every action runs from `.base`
   as `./.base/.github/actions/<name>`, so the next two run from the default branch whatever branch
   the PR targets.
3. [`check-kill-switch`](../../../.github/actions/check-kill-switch/README.md), then
   [`check-trusted-trigger`](../../../.github/actions/check-trusted-trigger/README.md). Neither has
   `continue-on-error`. A stop at either ends the job green with no token minted and no head
   checked out; the check is neutral, with two exceptions. The gate reads the re-runner's id from
   the run's own record, so a re-run started by an account not on the list, by a denied account,
   or with no readable triggering actor stops with `untrusted-rerunner`, and that check is a
   failure: a re-run cannot turn an earlier red check on the same SHA neutral. A PR whose base is
   not the default branch stops with `untrusted-base`, also a failure. The write file also
   denies `AUTOMATION_LANES_APP_SENDER_ID`, so the lanes App bot as sender or `workflow_run` actor
   stops it with `bot-actor` (neutral) and one write activity never chains into the next. The read
   file denies nothing, so a `workflow_run` read lane still runs after a bot push; the bot's own
   `pull_request` events are skipped by the job `if:` in both files. Both files pass their
   `dispatcher-run-id` input with `dispatcher-workflow: .github/workflows/pr-unblock-dispatch.yml`
   and `dispatched-workflow: .github/workflows/pr-unblock.yml`, so a `workflow_dispatch` sent by
   `github-actions[bot]` proceeds only when it names a run of that dispatcher on the default branch
   whose window holds this run's creation and whose `pr-unblock-dispatched-<id>[-<id>...]`
   artifact lists this run's id, and this run is `pr-unblock.yml`; every other bot-sent dispatch
   stops with `untrusted-actor`. The write file, and the read file for a call that passes
   `feedback-context-sha256` (which it fails red unless the skill is `prepare: review-threads`),
   also pass `run-dispatcher-workflow: .github/workflows/pr-feedback-dispatch.yml` with the two
   review workflows as `run-dispatcher-upstreams`: a run of that dispatcher, started by `workflow_run`,
   vouches with no actor check when its `pr-feedback-dispatched-<upstream id>-<this run's id>`
   artifact names a `pull_request` run of one of those workflows in this repository, started by
   the lanes App or a listed human, at the PR's current head. A job after pr-unblock's model job
   passes that job's `head-sha` as `expected-upstream-head`: the review must then be of that head,
   and every commit from it to the PR's current head one GitHub signed for the lanes App (author
   the App, committer `web-flow`, signature `valid`) after this run was created. The
   gate waits up to 2 minutes for that record while the
   dispatcher run is still going. The checks are in the gate's README. Only
   with a `dispatcher-run-id` does the skill step pass claude-code-action
   `allowed_bots: github-actions`, which otherwise refuses a run a bot started.
4. `check-trusted-base` asserts the PR targets the default branch and fails red otherwise. On `pull_request` the base
   branch is the event's `pull_request.base.ref`; on any other event (`workflow_dispatch`,
   `workflow_run`) it is read from the PR with the job's `GITHUB_TOKEN`. It then fails red unless
   the gate's `base-sha` is an ancestor of the default branch tip (`git merge-base --is-ancestor`),
   and checks that SHA out in `.base`. Nothing the PR's base branch chose runs before this check.
   With `trusted-base: default-tip` (`mode: default-tip`) it checks out the
   default branch tip instead, after the same checks: a PR in merge conflict keeps a stale base
   SHA, and the lane must run the tip's config and actions and merge the tip. The checked-out SHA
   is the `base-sha` output either way. A [`prepare: merge-base`](#prepare-merge-base) round
   merges the tip its select job pinned instead, which both files check is on the default
   branch.
5. `resolve-config`, with the gated `head-sha` and `prepare-supported: true`; the read file also
   passes `applied-by-supported: patch` ([Patch output mode](#patch-output-mode)). The read file then
   fails red for any `prepare` but [`ci-context`](#prepare-ci-context), and for `ci-context`
   without an `applied-by.patch`.
   An invalid config fails the step red and the check is a failure, never a skip. A config skip
   (`disabled-by-config`, `not-applicable-paths`, `not-applicable`, `awaiting-human`,
   `prerequisite-missing`) mints nothing. With a valid config, the read file fails red with
   `effect-not-read` unless the effect is `read`, and the write file fails red with `effect-read`
   when it is, whether or not the activity applies. For a `mutate-branch` activity the write file
   then re-reads the PR branch from `GET git/ref/heads/<head ref>` (`GET /pulls` can lag a push);
   when it no longer points at the gated head the activity skips with `superseded-sha`, mints
   nothing and runs no model turn. Other effects never write the branch and keep the gated head.
   In issue mode the read file's `issue-prior` step then checks for an earlier run's work
   ([Issue mode](#issue-mode)); when it reuses a branch it skips the rest of the run and runs no
   model turn in this job, and the [summary job](#the-summary-job) runs next.
6. Write file only:
   [`request-lane-token`](../../../.github/actions/request-lane-token/README.md) gets the lane
   token from the broker ([below](#the-lane-token-broker)), before `select-trusted-text` and before
   any head checkout. The broker mints once per job, so a second request from this job is denied
   `already-minted`. The
   step fails red unless the grant this job resolved is `read` or `write` for each of `contents`,
   `pull-requests` and `issues` and the broker's answer equals it. On a `pull_request` run, one
   refusal skips instead: a 403 `workflow-modified` whose detail names a `.github/workflows/` file the PR
   itself changes ([below](#a-workflow-file-the-pr-changes)). The read file requests nothing
   and uses the job's read-only `GITHUB_TOKEN` throughout.
7. [`select-trusted-text`](../../../.github/actions/select-trusted-text/README.md) to
   `$RUNNER_TEMP/trusted-context.json` when the activity `reads-untrusted`, with the App token or,
   in the read file, the `GITHUB_TOKEN`, which has no `issues` grant: in a private repository a PR
   that closes an issue may fail the step red.
8. `collect-base-activity` copies what the activity runs from the base out of `.base`: a script's whole
   directory to `$RUNNER_TEMP/base-script`, or for a skill the base `plugins/` and
   `.claude-plugin/` to `$RUNNER_TEMP/base-marketplace`. For
   [`prepare: merge-base`](#prepare-merge-base) the read file, and the write file under the
   `merge-base` patch row, also copy the base's `.github/scripts/merge-base/` scripts and
   `plugins/source-control/scripts/resolve-version-bump-conflict.sh` to
   `$RUNNER_TEMP/merge-base-bin`, recording each copy's SHA-256 as a step output, and read
   `loop.no-progress` from the resolved config.
9. `setup-runner-isolation`: for a skill, installs bubblewrap and socat with `apt-get` (three tries) and, where
   `/proc/sys/kernel/apparmor_restrict_unprivileged_userns` exists, sets it to `0`. It fails red
   if `bwrap` is not on `PATH` afterwards. The skill step needs it for subprocess isolation (below).
10. Removes sudo and docker access for the rest of the job: `/var/run/docker.sock` becomes
   root-only and the runner user's `/etc/sudoers.d/runner` entry is deleted. It fails red if
   `sudo -n true` still succeeds or the socket is still open to the runner user.
11. For a skill, copies the base's [`scripts/setup-env.sh`](../../../scripts/setup-env.sh) and the
    files it installs from (`.python-version`, `.github/requirements-ci.txt`, the root and
    `.github/standards/runner-policy` `package.json` and `package-lock.json`) to
    `$RUNNER_TEMP/setup-env`; a base without the script skips this and step 12's install with a
    notice. Then checks out the trigger gate's `head-sha` with `persist-credentials: false` (full
    history for a merge, else depth 1), then fails red unless `git rev-parse HEAD`
    equals that SHA. This replaces `.base`.
12. For a skill, sets up Python from the copied `.python-version` and runs the copied
    `setup-env.sh`, which installs the hash-pinned wheels in `.github/requirements-ci.txt` into a
    venv under `$RUNNER_TEMP` and the locked Node packages, puts both on `PATH`, and copies the
    `node_modules` trees into the checkout. Both files install from the base copies in
    `$RUNNER_TEMP/setup-env`, so no head code runs before the skill's own Bash; a read skill that
    needs the head's own packages runs `npm ci` there.
    Then runs the activity (below) and, in the read file, records whether the tree is dirty, or
    in [patch output mode](#patch-output-mode) collects the change as a patch. Both run the
    base's `collect-patch.sh`, so no git config the activity planted in `.git` runs, and the
    dirty-tree check prints no path. After them, a PR-mode read run removes `.git` and `.base/.git`
    from the workspace, so neither `actions/checkout` post step finds a `.git/config` to run git
    in.
13. Writes `verdict.json` with `jq` (`if: always()`) and uploads it as
    `verdict-<lane>-<activity>-<run_attempt>`, unique per activity and attempt. In the read file
    the [scan job](#the-scan-job) does this instead.
14. Write file only, `if: always()` whenever step 6 output a token: `actions/github-script`,
    pinned by SHA, so no binary resolved through `PATH` or `BASH_ENV` runs with the token, sends
    `DELETE /installation/token` with it, then `GET /installation/repositories`. It never fails
    the job (`continue-on-error: true`): a DELETE other than 204 is a `::warning::`, and a 204
    whose GET is not yet refused with 401 is a `::notice::`; a confirmed revoke, 204 then 401,
    raises no annotation and is recorded in the step log. It is a backstop for an honest
    activity that did not clean up, not a control against a hostile one: the activity holds the
    token and can write the runner's files.

A stacked PR, one whose base is not the default branch, gets a failure check from step 4. Retarget
it to the default branch to run its lanes.

Its outputs are `base-sha`, `head-sha`, `pr-number`, `gate-reason`, `can-commit` and
`act-outcome`, plus, in the write file, `head-ref`, `escalation-reason` and
`run-failure`, the reason the lane-token step failed with, from the base's `request-lane-token`. Every
one is computed by a runner step, never read from model text. All but `act-outcome` and
`escalation-reason` are outputs of steps that ran before any head code:
`gate-reason` is the kill switch's reason if it stopped, else the trigger's if it stopped, else
empty; `head-sha` and `head-ref` are the trigger gate's; `base-sha` is set only by step 4, so it
is always on the default branch. `escalation-reason` comes from the base's reply, verdict and
apply-patch scripts, which run no model and no head code. `act-outcome` is the activity step's
outcome, except that a skill step claude-code-action failed only because a `success` result went
over `--max-turns` counts as succeeded. That holds only when the execution file's last result
message has subtype `success`, `is_error` false and `num_turns` over the cap; any other failure,
or a missing or unreadable execution file, still fails the job. A skill whose step succeeded is a
failure when it took no model turn, when it is a gate skill and the verdict check (below) fails,
or when its commits could not be moved onto the PR branch. These checks are steps that run after
the skill.

The write file also outputs the lane record of a skill run: `lane-class` and `lane-resets`, the
failure class and usage-limit reset that ci-workflows' `report-lane-outcome` reads from the
execution file's structured fields, `lane-turns` and `lane-max-turns`, the turns taken and the
cap, `lane-models`, the comma list of model IDs the result's `modelUsage` names, and
`lane-profile`, the models profile `resolve-config` gave the skill. They come from steps after the
skill. The report job passes them to `report-check-run`, which checks each against a fixed shape
and writes them into the posted check run: as the first line of `output.summary`,
`lane=<lane> activity=<activity>` then `class`, `resets`, `turns`, `max-turns`, `models` and
`profile` in that order, each omitted when absent; as one JSON block in `output.text`; and as
`external_id` `<lane>:<activity>:<run id>:<run attempt>`. A failed run whose record says `class=rate-limit`
is the limit stop the pr-unblock dispatchers read from the check-run list they already fetch; a
failed run with no record line is not one. In issue mode the
same `class` and `resets` go into `lane.json` beside the kept branch, for report-outcome's
`limited` exit. Any code the activity runs, not only the model, can forge this record, for
example by planting the execution file. A forged limit stop can only restart the lane, at least an
hour later and a bounded number of times.

### Skill activities

The prompt is `/<plugin>:<skill> <args>`, followed, for an activity with the `changed-paths`
input, by those paths as further words. `resolve-config` computes them from the PR's file list
(`pulls/{n}/files`), never from head text: files the head still holds, matching the slot's `paths`
predicate when it has one, with a name of letters, digits and `_ @ + . -` only, no `.` or `..`
segment, no segment starting with `-` and no leading `@`, which would read as a file mention.
The paths are the job's scope, what the skill is asked to work on, not a limit on what it can
touch. For an activity that edits (any effect but `read`, or a skill whose `applied-by` sets
`patch`) they leave out instruction surfaces (`CLAUDE.md`,
`CLAUDE.local.md`, `AGENTS.md` at any depth, case-insensitive, and anything under a `.claude`,
`.claude-plugin`, `skills`, `agents`, `commands`, `hooks`, `output-styles` or `prompts`
directory) and every path the base `.github/CODEOWNERS` lists, owned or not, so a lane is not
asked to rewrite them. When nothing is left the activity skips with `not-applicable-paths` and
mints nothing. `collect-base-activity` fails red on a path outside that name set. For a
`reads-untrusted` activity the step gets the `select-trusted-text` output's path as
`TRUSTED_CONTEXT_FILE`, and only there: the prompt holds the command line alone, so nothing after
the slash command reaches the skill's arguments. A `reads-untrusted` skill must read PR text (title, body, comments,
reviews, linked issues) only from that file, never through the API. Existing skills are not yet
adapted to this and still read PR text themselves; until each is, its untrusted-text exposure is a
known residual. The skill gets the App token as `github_token` in the write file, and the job's
read-only `GITHUB_TOKEN` in the read file. `claude_args` passes `--setting-sources user`, so no
project or local settings, hooks, `CLAUDE.md`, `AGENTS.md` or `.mcp.json` from the PR head load;
`--permission-mode dontAsk`; `--allowedTools "Skill(<plugin>:<skill>)"`, so the skill's own
`allowed-tools` decide what else it may use; and `resolve-config`'s `claude-args` for the
activity's models profile (`--max-turns`, `--model` unless the model is `default`, `--effort` when
set), with its `settings-json` as the action's `settings`
([README.md, Models](README.md#models)). The
plugin installs only from `$RUNNER_TEMP/base-marketplace` and loads from there, outside the working
directory, so `--allowedTools` also carries `Read(/$RUNNER_TEMP/base-marketplace/**)`: without
it the skill cannot read its own reference files. Commits go through the API, signed
(`use_commit_signing`), on a lane branch (`CLAUDE_BRANCH`) the job makes at the gated head SHA
when the grant can commit.

A skill with any effect but `read`, or a `read` skill whose `applied-by` sets `patch` (other than
in [`ci-context`](#prepare-ci-context), which has its own set), also gets what it needs to do its
job: `Edit`, `Write`, `Agent`
(for subagents such as a fix flow's semantic-diff check or a rubric fan-out) and
`mcp__github_file_ops__commit_files` and `mcp__github_file_ops__delete_files`, the action's
signed-commit tools on `CLAUDE_BRANCH` (the second carries a rename's old path or a removal), and a
scratch directory, `$RUNNER_TEMP/lane-scratch`, passed as `--add-dir` with an `Edit` rule on it so
its state files and its `Bash` redirects land there. `--append-system-prompt` names that
directory, says no one can answer a question, and, when the grant can commit, tells it to commit
every file it changed, and delete every committed path it renamed or removed, with those tools: the prompt is the slash command alone, so without this the
skill leaves its edits uncommitted and the lane moves nothing. `commit_files` takes each file's
mode from disk, and `Write` creates a file without the executable bit, so that grant also allows
`Bash(chmod +x *)` and the sentence says to run `chmod +x` first on every new or changed file that
starts with `#!` or ends in `.sh`. A `read` skill that hands on a patch gets neither tool, and its
sentence says to leave every change uncommitted for the runner to collect; a
`prepare: merge-base` skill is one ([below](#prepare-merge-base)). Under `--permission-mode dontAsk` a skill's own `allowed-tools`
grants nothing: its `Bash` is only what this list allows, one rule per entry in the activity's
`checks` and `self-checks`: `collect-base-activity` copies the base `scripts/` to `$RUNNER_TEMP/lane-checks`, outside
the working directory, writes a wrapper there that runs the copy with the entry's fixed flags,
`CHECK_DATA_ROOT` naming the checkout, `GH_TOKEN` and `GITHUB_TOKEN` unset, and the same git config
pins as a verify-script's wrapper, makes the copy read-only and denies `Edit` and `Write` on
it, allows `Bash(<wrapper>)` with no arguments, and names the
wrappers in `--append-system-prompt` as checks to run before reporting done, with what a check
reports fixed in the working tree and anything left unfixed named in the report (a skill that
commits runs the checks, fixes and re-runs them before it commits). For each entry in
the activity's `verify-scripts`, it checks the path's shape and that the base holds the script,
copies the script's whole base plugin directory (or the base `scripts/`) to
`$RUNNER_TEMP/lane-verify`, so the files the script reads beside itself come along, fails if that
directory holds a symbolic link (whose target `chmod` would leave writable), makes the copy
read-only, denies `Edit` and `Write` on it, allows `Bash(<copy>/bin/<name> *)`, and names each
wrapper in `--append-system-prompt`. The wrapper changes to the checkout, refuses any argument (or
the value after an `=`) naming an existing path whose real path lies outside the checkout, since a
script may print lines of a file it reads, unsets `GH_TOKEN` and `GITHUB_TOKEN` in the script's
own environment (code the script runs can still read the token from the wrapper's or the Bash
shell's `/proc/<pid>/environ`), sets `GIT_CONFIG_NOSYSTEM`, `GIT_CONFIG_GLOBAL=/dev/null`
and command-scope `core.fsmonitor=false` and `core.hooksPath=/dev/null`, for skill-quality's
`check-skill.sh` alone sets `HOME` to a fresh `mktemp -d` directory and `CLAUDE_CONFIG_DIR` to its
`.claude`, since the skill tests it runs write there and the runner's `~/.claude` is read-only,
then runs the copy with
the arguments and prints `exit status: <n>` to stderr before exiting with that status, since the
lane denies a chained `; echo "$?"`. The system prompt says Bash runs only the named wrappers,
each as its own command, and that the run inspects files with Read, Grep and Glob and changes them
with Edit or Write, never with `cd`, `;`, `&&`, a pipe or an interpreter one-liner; when
`git-mv-rm.sh` is listed, it names that wrapper for a rename or a removal.
Any other arguments match, so a listed script that changes files or runs checkout code must limit
itself, or hand the run a power it may hold. Code a listed script runs can read the token from
any same-user process's `/proc/<pid>/environ`, so `resolve-issue` lists no script that runs
checkout code: not `scripts/run-test-file.sh`, and not skill-quality's `check-skill.sh`, which runs
each checked skill's `scripts/*.test.sh` and the checkout's markdownlint. It lists skill-quality's
`check-evals-quality.sh` (bash and jq over `evals.json` files), and `scripts/git-mv-rm.sh`, which
limits itself, refusing (exit 2) an argument that is absolute,
has a `..` segment, starts with `-` or `:`, or resolves through a link to outside the checkout, including
a path that does not exist yet (`scripts/lib/checkout-path.sh`); `scripts/run-test-file.sh` does
the same when an activity lists it. `scripts/run-test-file.sh` takes
one test file and runs it by name, `test_*.py` under `python3 -m pytest`, `*.test.sh` under
`bash`, `*.test.mjs` under `node --test`, each after `--`, and a `*.test.js` or `*.test.ts` file
that imports `vitest` under `npx --no-install vitest run <absolute path>` from the nearest
directory inside the checkout holding a `package.json`, so the package's locked vitest runs, first
running `npm ci --ignore-scripts` there once when it has a `package-lock.json` and no
`node_modules`; all
without `GH_TOKEN` or `GITHUB_TOKEN`. It refuses any other file and any name outside
`[A-Za-z0-9._/-]`, so pytest reads no node id. When it is listed, the system prompt names its
wrapper as the way to run a test file and says a compound `cd <dir>; <command>` is refused. Its tests are checkout code with the network open. When the stage grants its wrapper,
the write runner sets up Python from the base `.python-version` and installs the base's
hash-pinned `.github/requirements-ci.txt` before the head checkout. `scripts/git-mv-rm.sh` runs
`git mv <source> <destination>` or `git rm -r -f <path>...`, first recording an untracked path as
intent-to-add so a file the run created can be renamed or removed, with `GIT_LITERAL_PATHSPECS=1`
so git reads each path literally, never as a glob or pathspec magic. The index is local: the
change reaches the branch through `commit_files` and `delete_files`. `resolve-issue` also lists
`scripts/new-changelog-fragment.sh`, which finds the work tree with `git rev-parse
--show-toplevel` from its working directory (exit 2 outside one), writes only new
`.changes/<plugin>/<slug>.md` files there, refuses a plugin name outside `[a-z0-9-]` and a linked
`.changes` or `.changes/<plugin>`, and reads `--carriers-of` through its own copy's
`sync-shared-copies.sh`, never the checkout's; that script reads the checkout's registry.
Every activity whose effect is not `read`, and a read skill that hands on a patch, also gets
`--disallowedTools` rules for the shell commands that can print a file or the environment,
including read-only ones that run with no allow rule (`echo`, `printf`, `cat`, `head`, `tail`,
`grep`, `find`, `env`, `printenv`, `strings`, `od`, `xxd`, `diff`, `sed`, `awk`, `sort`, `cut`,
`tr`, `base64`, `nl`, `tac`, `rev`, `uniq`, `fold`, `column`, `jq`, `xargs`, `more`, `less`, `wc`, each as
`Bash(<command> *)`), and `Read(//proc/**)`; the skill reads files with `Read`, `Grep` and `Glob`.
Every activity whose effect is not `read` also gets `Bash(git *)`: it reaches git only through
the base wrappers. A `prepare: merge-base` skill runs only on the read file's launcher, with no
Bash. `WebFetch` and
`WebSearch` stay off (`--disallowedTools`) unless the activity sets `web-access`. With it on, the
runner allows `WebSearch`, one `WebFetch(domain:<host>)` rule per listed domain
(`WebFetch(domain:*)` for `any`), and `Skill` for `/discovery:read-docs`, `/discovery:research`,
`/knowledge:docpage-digest` and `/knowledge:map-corpus`; installs the `discovery` and `knowledge`
plugins from the base marketplace copy beside the skill's own; and says so in
`--append-system-prompt`. With a domain list the prompt names the hosts and WebFetch as the way to
read a page on them, since the docs scripts `/discovery:read-docs` runs stay denied. For `any` only, it also copies `fetch-docs.sh`, `docs-cache.sh` and
`html2md.py` from the base `discovery` plugin to `$RUNNER_TEMP/lane-docs`, makes the copy
read-only, denies `Edit` and `Write` on it (else the skill's bare `Edit` and `Write` could rewrite
a script its rule then runs), allows `Bash(bash <copy>/fetch-docs.sh *)` and the same rule for
`docs-cache.sh`, and tells the model to run that copy for every skill that runs the two scripts,
with `--cache-dir` and `--out` in the scratch directory; a domain list gets none of it, since the
scripts curl any host. A Bash rule matches the words before its `*` as written, so a differently
spelled path does not match while arguments after it may be quoted; each script therefore also
gets the rule for its double-quoted path, the form the skills' examples use, and the path guard
keeps quotes and spaces out of the path
([permissions: What a Bash rule doesn't match](https://code.claude.com/docs/en/permissions#bash-rule-limits);
as of 2026-10-15; recheck when that table changes). No sandbox is enabled, so a `domain:` rule
limits `WebFetch` alone; a shell command the lane may run reaches any host.
`/discovery:research` can also start its `discovery:research-sweep` workflow, whose subagents run
under the same grant. `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB` strips credentials other than GitHub tokens from the shell's
environment and gives Bash its own PID namespace; it does not sandbox the network
([env vars: What the subprocess environment scrub removes](https://code.claude.com/docs/en/env-vars#what-the-subprocess-environment-scrub-removes);
as of 2026-10-15). Without `web-access` the skill has no web tool and no `Bash` rule that fetches,
so `dontAsk` refuses every fetch. Fetched pages are
untrusted text, so the activity must set `reads-untrusted: true`. No rule limits which files it changes: with its
token it can change, commit and push any file in the repository, and claude-code-action writes
the token into the origin URL under `use_commit_signing`
(`src/github/operations/git-config.ts:129-133` at `ed670b4`), so a `git push` works too. The PR is
the review step: the review lanes, `ci-status`, review-thread resolution and the merge gate see
every lane commit. The hardening is the broker's scoped, hour-long token revoked when the job
ends, base-SHA config and runner, the trusted-actor filter, the kill switch,
`--setting-sources user`, an explicit `--permission-mode` and never `bypassPermissions`. The
residuals are in [Trust-root paths](README.md#trust-root-paths): the model can read its token
(`GH_TOKEN`, `GITHUB_TOKEN`, `.git/config`) until it is revoked, and under `web-access` send it to
any domain the activity allows, which is
[ADR 0055](../../adr/0055-load-nothing-head-controlled-into-a-pipeline-skill-activity.md)'s
accepted residual, a skill's own `Bash` grant can exceed its job (`Bash(git:*)` in
`ai-slop:audit`), and a lane commit can change instruction files the PR author's local session
later loads. The skill's final reply is uploaded as an artifact with the token string cut out.
`commit_files` builds each commit on the live tip of `CLAUDE_BRANCH` with file bytes from the
gated checkout (`src/mcp/github-file-ops-server.ts:226-367` at `ed670b4`), so committing straight
to the PR branch would overwrite a push made during the run. After the skill, a pinned
`github-script` step fast-forwards the PR branch to the lane branch only while the PR branch is
still at the gated SHA, and deletes the lane branch either way. When the PR branch has moved, the
lane's commits are dropped and the activity fails; a later run (a reopen or a dispatch) gates the
new head and redoes the activity. Right before the move it
re-reads the PR's labels and draft flag with the job's `GITHUB_TOKEN`, then reads the PR branch's
tip last: `do-not-merge`, the base's human-gated role label, a label in the activity's
`labels-absent` list (both read from the base before the head checkout) or a draft drops the lane's
commits and skips `awaiting-human`, and a read that fails or a second page of labels moves nothing
and fails the step. A raw `git push` from the
skill skips this check. Why a skill activity loads nothing from
the PR head:
[ADR 0055](../../adr/0055-load-nothing-head-controlled-into-a-pipeline-skill-activity.md).

On PR events claude-code-action adds a second head-isolation layer beside `--setting-sources user`:
when it treats the PR head as untrusted, it replaces `.claude`, `.mcp.json`, `CLAUDE.md` and its
other listed config paths with the PR base branch's copies before Claude starts. In the read
file, the next step puts back only what that restore changed, so the dirty-tree check does not
fail on the action's own edits, and a file the skill created or edited under those paths still
counts as dirty. That step sets `GIT_LITERAL_PATHSPECS=1`, so a head file name is never read as a
glob. Its one blind spot is accepted: a head file under those paths that the skill deletes is put
back from the head, so the deletion does not count as dirty. A `read` skill's token cannot push, so
the deletion never leaves the runner.

A skill whose `gating` is `gate` must end with a verdict. `claude_args` adds `--json-schema` with a
schema requiring `{"verdict": "pass" | "fail", "summary": string}`; claude-code-action fails its
step when no structured output returns. The next step reads the action's `structured_output`
output through `env`, parses it with `jq`, writes the summary to the step summary as data, and fails
red unless the verdict is exactly `pass`. A `fail` verdict therefore makes `act-outcome` `failure`
and the check a failure. A `gating` value other than `gate` or `advisory` fails the job red before
the head checkout.

A `gating: gate` skill must not execute head code: no test, linter or build of the PR runs through
its Bash. The verdict check runs after the skill in the same job, so head code that ran first could
forge it, for example by writing a `$RUNNER_TEMP` file-command file such as one `BASH_ENV` points
at, or by leaving a process running. Tests, linters and builds that gate run as a `script` activity,
or under a separate design that judges their result in a job head code never touched.

The step summary (in a PR-mode read run, the scan job's) shows the skill's final reply (at most 4000 characters, backticks
neutralized) for audit. It is model output, printed as data. The same text is uploaded as the
artifact `skill-reply-<lane>-<activity>-<run_attempt>` (7-day retention) whenever the skill step
ran, as audit evidence, because the REST API cannot read step summaries. Nothing in the workflow
reads that artifact.

A slash command whose expansion fails ends with a `success` result and no model turn: claude-code-action
reports success, but the skill did nothing. A skill pre-compute (`` !`...` ``) line with a command
that matches no `allowed-tools` grant does this under `--permission-mode dontAsk`. A step after the
skill reads the execution file and fails when `num_turns` is 0 or `modelUsage` is empty. It writes
`subtype` and up to 10 model names, each cut to 100 characters, `is_error`, `num_turns`,
`duration_ms`, the first 4 `<local-command-stderr>` messages, each cut to 2000 characters, with
`local_command_stderr_total` counting all of them, `denied`, one `{tool_name, input}` for each of
the first 20 calls the permission mode denied, where `tool_name` is cut to 100 characters and
`input` is the call's `command`, else `file_path`, else `path`, else `pattern` (null when it has
none), cut to 300 characters, and `denied_total`, the count of all of them. Until the file fits
the 32768-byte cap a read run's scan job carries it under, the oldest stderr messages drop first,
then denials from the end. It writes them to `act-turns.json`, which goes into the
same artifact and onto the step summary, where each denial shows as `tool: input` followed by
`(+N more)` when some were cut; in the write file the lane token is cut out
of both. In a PR-mode read run, `act-turns.json` is sealed with the reply for the scan job, which
shows and uploads it only after a clean leak scan. The full execution file is not uploaded: it
holds head text and tool output.

### Script activities

The script runs from its base copy, with the PR head as its working directory, and must be
executable. It must sit in a subdirectory: the copy takes the script's whole directory, so a
root-level script path fails red rather than copying the whole base tree. Its environment:

| Variable | Value |
|---|---|
| `PR_NUMBER`, `HEAD_SHA`, `BASE_SHA` | The gated PR, its head SHA, and the default-branch base SHA from run job step 4 |
| `ACTIVITY_ARGS` | The activity's `args`, verbatim; empty when unset |
| `SKIP_REASON_FILE` | Write one `$defs/skip-reason` value here and exit 0 for neutral |
| `GH_TOKEN` | The App token, only when the effect is not `read`; unset otherwise |

Exit 0 is success, non-zero is failure, and a reason file whose value is not a skip reason is a
failure. A script that gets `GH_TOKEN` must not execute code from the PR head. The head checkout
persists no credentials, so a `read` script cannot push. The write file also exports its
`escalation-reason` input as `ESCALATION_REASON` (empty unless a caller passes one), which the
`report-escalation` leaf reads, and `TRACKER_CONFIG`, the base's `.work-item-tracker.json` copied
to `$RUNNER_TEMP/base-script` before the head checkout and checked against its recorded SHA-256
(or its recorded absence) before the script runs. It exports `APP_SENDER_ID` and
`ESCALATION_REASON_FILE`, and with `review-replies` `FEEDBACK_REPLIES_DIR` and `TRUSTED_ACTORS`
([prepare: review-threads](#prepare-review-threads)).

### Patch output mode

Read file only, chosen by the activity's `applied-by.patch` in the base config, which names the
`prepare: apply-patch` script that applies it ([README.md, Activities](README.md#activities));
`resolve-config` outputs it as `applied-by-patch`. It lets an activity run head code with no
write token and hand its change to a separate job that holds one; `fix-docs`, `fix-ci`,
`address-feedback` and `resolve-issue` use it. The read file passes `applied-by-supported` to
`resolve-config`: `patch feedback-replies` in PR mode, `patch work-outcome` in issue mode, so a
leaf whose `applied-by` sets any other key fails red before the head checkout. A `gating: gate` leaf cannot
set `applied-by`, and an issue-mode activity must set it. The steps:

1. Before the head checkout, the base's
   [`collect-patch.sh`](../../../.github/scripts/read-patch/collect-patch.sh) is copied to
   `$RUNNER_TEMP/read-patch`.
2. After an act step that succeeded, in place of the clean-tree check, the collector writes
   everything the activity changed against the gated head (committed, staged, unstaged and
   untracked, ignored files and `.lane/` aside) as one `git diff --binary` patch, through a scratch index, with
   every diff option that changes the patch's form passed explicitly. Its git runs against a fresh
   repository that borrows only the checkout's objects, with no global or system config, so no
   filter, hook, fsmonitor or include the activity wrote into `.git` runs. A failed, cancelled or
   turnless act step collects nothing and the check fails as usual. The collector also leaves out
   the empty files the CLI's Bash leaves at the top of the checkout under its environment scrub,
   a fixed set of names (`package.json`, `.env` and others) that the gated head does not track. A
   name from that set the head does not track that holds anything other than an empty regular
   file makes the collector exit 3 with no patch written: the collect step fails, nothing is
   collected and `patch-state` stays empty, and the dirty-tree check counts it as dirty. The
   collect step sets `state` `refused` on exit 3 alone; the scan job holds the run's
   `patch-collected` output to `written`, `empty` or `refused` and sets `scan-collect-refused`
   `true` on `refused`, so a caller can hand the refused change to a person. A forged `refused`
   can only do that.
3. A non-empty patch is uploaded as the artifact `patch-<lane>-<activity>-<run attempt>`, holding
   one file, `patch.diff` (7-day retention): in PR mode by the [scan job](#the-scan-job), after
   its scan, in issue mode by the run job. The run's `patch-state` output is then `written`,
   `patch-sha256` is that file's SHA-256 and `patch-attempt` is the attempt in the artifact's name.
   No change is `patch-state` `empty`, with no artifact and the other two empty. A run that
   collected no patch leaves all three empty.
4. The verdict's `patch` field repeats `patch-state` (`written`, `empty`, or `null` when the run
   collected no patch), and the check is
   `success` titled `Passed: patch written` or `Passed: no changes`.

Head code ran in the job that collects the patch, and could have replaced the collector copy or
the patch, so neither the patch nor the run outputs the verdict is built from is trusted: the SHA-256 only binds the
artifact to this run's output. A job that applies the patch downloads it by `patch-attempt`, so a
re-run of that job alone still finds it. Before applying it, that job must check that:

- the artifact holds exactly `patch.diff`, a regular file within a size limit the job names, whose
  SHA-256 is `patch-sha256`;
- the PR head is still `head-sha`;
- `git apply --check` with `--index` or `--cached`, and no `--unsafe-paths` or `--directory`,
  succeeds on a fresh checkout of `head-sha`;
- no entry has mode `120000` (symlink) or `160000` (gitlink), and no path is a protected path
  such as `.github/workflows/**`, `CODEOWNERS`, `.gitmodules` or a settings file.

It then commits on `head-sha` and moves the PR branch without force, so a head that moved after
the check refuses the push. A forged `empty` can only hand the PR to a person; a forged `written`
meets those checks. A `gating: gate` activity fails red in patch mode before the head checkout: a
gate must judge the head it is posted on, unchanged.

### Two calls on one credential each

Read file, PR mode: a skill runs on ci-workflows'
[`run-claude-cli`](https://github.com/melodic-software/ci-workflows/blob/7b362428c76085a160e28656cd2c75c3147a69ff/README.md)
(v0.54.0), which takes exactly one credential and falls back to the subscription only as a second
job. The caller calls the read file twice, each call with one secret, named for its `role`:
`pr-unblock.yml`'s `fix-ci` passes only `claude-api-key` (`PR_UNBLOCK_CLAUDE_API_KEY`), and
`fix-ci-subscription` passes only `claude-code-oauth-token`
(`PR_UNBLOCK_CLAUDE_CODE_OAUTH_TOKEN`); its `address-feedback` and `review-dependency` calls,
`pr-refine.yml`'s `fix-docs`, and their `-subscription` calls do the same. Both queue in
`pr-pipeline-write-<pr>`. Each fallback call starts on no first-call output: a handoff job
(`fix-ci-handoff`, `fix-ci-rung-up-handoff`, `address-feedback-handoff`,
`review-dependency-handoff`, and `pr-refine.yml`'s `fix-docs-handoff`) with only `actions: read`
that checks out nothing reads this run's jobs through the Actions API once, and the fallback runs
unless the first call's `<call> / report` job has a `Post the check run` step that succeeded. A
failed read runs the fallback too, except for `fix-docs`. `fix-docs-subscription` also needs the
first call's `<call> / broker-check` job to show the broker's allow: `fix-docs` posts nothing on a
decline, so a kill switch or a refusal starts no second leg, and a failed read starts none either,
since with no check posted `fix-docs-dispatch.mjs` dispatches the PR again. These fallback calls
pass `fallback: handoff`, so the lane record says the key posted no check, not why: only the run
job, which head code can forge, knows whether it was a credit stop or an empty key.

1. Before any head code, the run job fails red unless the `role` is lower-case kebab, the model
   route resolves an alias (`default` resolves to none) and the skill is advisory. While sudo
   still works it applies ci-workflows' Claude managed settings, then isolates the runner.
2. `collect-base-activity` (launcher `run-claude-cli`) stages the skill's plugin, the CI context,
   a scratch directory and the prompt file; after the head checkout the run job copies them to
   `.lane/`, failing red when the head already holds `.lane`, makes the plugin and the context
   read-only and has git ignore the directory. `--restricted` reads nothing outside the checkout,
   so `plugin-dirs` is `.lane/plugins/<plugin>`, never `$RUNNER_TEMP`. It also ignores the
   head's user, project and local settings files, so a head `.claude/settings.json` sets no
   hook, permission or env; `--strict-mcp-config` ignores the head's `.mcp.json`; and the managed
   settings pin `apiKeyHelper` and `ANTHROPIC_BASE_URL` and allow managed hooks only, which
   run-claude-cli checks before every leg. This is why PR mode needs no swap of the head's config
   paths for the base's. A head `CLAUDE.md` is still read, as untrusted text. The tools, allow
   and deny rules come from the stage, with the activity's `permission-mode`; the preamble stands
   in for the system prompt, and the prompt asks for the Skill tool. The launcher takes a read
   skill, either `prepare: ci-context` or one that hands on a patch with no prepare mode
   (`fix-docs`) or with `prepare: review-threads` (`address-feedback`, which also gets the
   review-thread tool: [`prepare: review-threads`](#prepare-review-threads)), and fails red on
   any other prepare mode and on `checks`, `self-checks` or `verify-scripts`, which have no
   wrapper there. The no-prepare patch skill gets
   the tools `Read`, `Glob`, `Grep`, `Skill`, `Bash`, `Edit`, `Write` and `Agent`; its allow rules
   name its skill, `Grep`, `Glob`, `Edit`, `Write`, `Agent` and `Edit(./.lane/scratch/**)`, which
   approves a shell redirect into the scratch directory, and for `ai-slop:audit` each of
   its scripts by absolute path under `.lane/plugins`, bare and double-quoted, plus
   `Bash(sha256sum *)` and `Bash(mkdir -p <workspace>/.lane/scratch/*)` for the fix flow's
   digests; no other `Bash` rule, and the lane does not rely on the skill's frontmatter grants. It
   adds the deny rules `Bash(git *)`, the `user-scope.sh` script, `NotebookEdit(./.lane/plugins/**)`
   and the write lanes' shell deny set to the base set, which already denies `Read(./.git/**)`
   and `Read(//proc/**)`. The preamble says to keep scratch files in `.lane/scratch`, leave every
   change uncommitted, and run one plain command per call, redirecting only into `.lane/scratch`.
   The staging step makes `.lane/prompt.md` and `.lane/` itself read-only, so a script's `--out`
   lands only in `.lane/scratch`. With `web-access` (`domains: any` only; a domain list fails red) it also gets the
   `WebFetch` and `WebSearch` tools, no longer denied, the rules `WebFetch(domain:*)`, `WebSearch`
   and the four research skills, and the `discovery` and `knowledge` plugins staged read-only
   beside its own, one `plugin-dirs` line each. The docs scripts are not staged, so the preamble
   says to read each page with WebFetch and cite it.
3. One step checks the call's secret is set (only that leaves it), and one launcher step per
   secret runs the skill: `act-key` on the first call, `act-token` on the fallback call, with
   `continue-on-error`, a 50-minute step timeout and a 45-minute leg. setup-python's
   `LD_LIBRARY_PATH` is cleared for the launcher, which refuses a loader variable. Each leg runs
   in `resolve-config`'s `permission-mode` output, `dontAsk` unless the activity sets `auto`, and
   a step after it fails the job, so no patch is collected, unless the CLI's init message in the
   leg's execution file reports that mode; a credit stop hands off unchecked.
4. The first call hands off (`handed-off: true`) when its key is empty or its key leg ends in a
   credit stop. It then skips the scan job, so it uploads no reply, patch or verdict, and records
   no lane outcome, collects no patch and posts no check, so the fallback call's artifacts and check are the run's. Otherwise
   the call records its lane outcome with `report-lane-outcome`, on the fallback call under the
   name `<lane>/<activity> (key <ROLE>_CLAUDE_API_KEY hit a credit stop)` or `(... is empty)`.
5. The run job's last step fails it when the launcher left no success and the call did not hand
   off, an empty token on the fallback call included.
6. The run job uploads nothing and writes no step summary. It hands the reply, the run fields,
   the patch and a `review-threads` skill's replies to the [scan job](#the-scan-job) as sealed
   job outputs, which the scan job opens and scans before anything is published.

The issue lane's skill stays on claude-code-action.

### prepare: merge-base

A conflict round is five pr-unblock jobs, so no model holds a write token or runs git. The skill
leaf sets `prepare: merge-base`, `effect: read` and `applied-by` `patch: apply-conflict-patch`
(resolve-config's `prepare` and `applied-by-patch` outputs); `apply-conflict-patch` is a
`prepare: apply-patch` script leaf. Every job that merges runs the base's copies of
`.github/scripts/merge-base/prepare.sh` and the version-bump script through `run-prepare.sh`,
each checked against its recorded SHA-256 before it runs, with workflow commands stopped
(`::stop-commands::<random>`, since git's output can name head files), the lanes bot identity
(`melodic-automation-lanes[bot]` and its noreply address, which a `--no-commit` merge needs and
the repeat cap counts by), `loop.no-progress` as `LOOP_NO_PROGRESS` and
`GIT_NO_REPLACE_OBJECTS=1`.

1. `resolve-conflicts-select` runs only default-branch-tip code with a read-only token. It reads
   the PR head, resolves the slot (`applied-by-supported: patch`), pins the default branch tip as
   the round's base, checks the head out with full history and no persisted credentials, and runs
   `prepare.sh`: it escalates `repeat-cap` before merging, runs
   `git merge --no-commit --no-ff <pinned base>` and the version-bump script (under `LC_ALL=C`),
   snapshots the index, and escalates `protected-path-conflict` (a conflicted path under
   `.github/workflows/`, a `.gitmodules` or a `settings*.json`) or `unresolved-conflict` (a
   conflict with no markers to resolve). Its `merge-state` output is `clean`, `conflicted` or
   `escalate`; for `clean` and `conflicted` it also prints `conflict-tree`, T0: the merge's stage-0
   entries plus each conflicted path's file as git left it, markers and all, hashed with
   `--no-filters` under the head's mode, built in a scratch index. The job's outputs are
   `proceed` (`true` only for `conflicted`), `merge-state`, `head-sha`, `base-sha`,
   `conflict-tree`, `escalation-reason` and `skip-reason`.
2. `resolve-conflicts-not-run` posts the `resolve-conflicts` check neutral on that head when the
   select job does not proceed: the slot's skip reason, else `clean-merge`, else `awaiting-human`,
   so the dispatcher does not send that head again.
3. On `conflicted`, `resolve-conflicts` and its subscription fallback (started, as
   address-feedback's is, by `resolve-conflicts-handoff`'s read of this run's jobs) call the read file with
   `merge-base-sha` and `merge-conflict-tree` from the select job
   ([Two calls on one credential each](#two-calls-on-one-credential-each)). Before the head
   checkout it fails red unless both are full ids, they go with `prepare: merge-base` alone, and the
   pinned base is on the default branch; it copies the base's merge scripts and `context.sh` with
   their SHA-256s and checks the head out with full history. Before any model turn it merges the
   pinned base again and fails red unless the merge reaches `conflicted` at the same conflict tree,
   then `context.sh` writes `.lane/merge/`, read-only and denied to the file tools:
   `conflicts.json` (the head, the base, the merge bases and each conflicted path with its
   directory) and per path its `base`, `ours` and `theirs` stages and `head.log` and `base.log`,
   `git log -p` of each side for that path, each cut at a cap with a note (a stage at 1 MiB, a log
   at 64 KiB; past 16 MiB in all, a path's files are left out and its entry says `omitted`). The
   skill gets Read, Grep, Glob, Skill, Edit, Write and Agent with no Bash (git and the shell read
   commands are denied all the same), resolves the conflicted files in place and edits nothing
   else. The collector measures the patch from the conflict tree, so it holds the model's edits
   alone. The scan job scans such a patch as text and never applies it to the head (GitHub does
   not hold T0); a binary hunk blocks it.
4. `apply-conflict-patch` runs on a `clean` merge, or on a `conflicted` one whose answering leg's
   scan handed on a written or empty patch. Before the mint the write file checks the pinned base
   is on the default branch and `apply-patch.mjs select` decides under the `merge-base` row: a head
   that moved since the select job skips `superseded-sha`; `clean` proceeds with no patch;
   `conflicted` with an empty patch escalates `unresolved-conflict`. After the head checkout (full
   history) it merges the pinned base again and fails red unless the merge reaches the select
   job's state and conflict tree. `apply-patch.mjs` then applies the patch to T0 in a scratch index
   (attributes read from the base tree), holds only the patch's own changes to the row's refusals,
   `max-files`, `merge-result` (a path the merge left conflicted, read from the checkout's index,
   else `unexpected-path-staged`), the credential scan and the blob caps, and escalates
   `unresolved-conflict` when a conflicted path still in the tree holds conflict markers, or
   `workflow-staged` when the tree's `.github/workflows/` differs from the head's unless it is
   exactly the base's, no head workflow is dropped, and the PR's own diff against every merge base
   touches no workflow. The base-side changes the merge brings pass through untouched. It lists
   the tree against the head with the base's `tree-entries.sh` (checked against its SHA-256),
   refuses before any write when more than `max-blobs` blobs neither parent holds would be
   uploaded, re-reads the holds and the draft state, uploads only those blobs, builds the tree on
   the head's tree and fails unless it hashes to the merge tree, creates
   `Merge <default branch> into <head ref>` with trailer
   `Lane-Activity: pr-unblock/resolve-conflicts` and parents `[gated head, pinned base]`, so
   GitHub signs it as the App, and moves the PR branch with `force: false`.
5. `conflict-scan-refusal` runs on a `conflicted` round whose answering leg handed on no patch
   state, which a scan that refused the model's output leaves. With no model and no head code it
   downloads the read runner's `scan-refused-pr-unblock-resolve-conflicts-*` markers by name, never
   a job output, and escalates `unresolved-conflict` when one says the scan refused or the
   download failed (`conflict-scan-refusal.mjs`, through `scanRefusal`); no marker escalates
   nothing.
6. `report-conflict-status` posts a failing `pr-unblock/conflict` status on the select job's head
   when the select, push or `conflict-scan-refusal` job escalates `unresolved-conflict`; `report-escalation`
   takes any of their reasons.

The three merges of one round must agree on the conflict tree; one that does not fails red and
nothing is resolved or pushed. The kill switch (step 3) stops new runs only; a run already past it
stops for a hold only at the push job's label and draft re-read. Every path and its check:

| Path | Job | skip reason | escalation-reason | Check |
|---|---|---|---|---|
| Slot does not apply, or a hold label | select | the slot's | empty | neutral `resolve-conflicts` |
| Pre-model escalation | select | `awaiting-human` | `protected-path-conflict` / `repeat-cap` / `unresolved-conflict` (no markers) | neutral `resolve-conflicts` |
| Clean merge, committed and pushed | push | `clean-merge` on `resolve-conflicts` | empty | success `apply-conflict-patch` |
| A later merge reaches another tree | model call or push | none | empty | failure |
| Head moved since the select job | push | `superseded-sha` | empty | neutral `apply-conflict-patch` |
| Empty patch, or a conflicted path left with markers | push | `awaiting-human` | `unresolved-conflict` | neutral `apply-conflict-patch` |
| The scan refused the model's output (leak-scan block, oversize patch) | conflict-scan-refusal | none | `unresolved-conflict` | failure `resolve-conflicts` |
| A model edit outside the conflicted set | push | `awaiting-human` | `unexpected-path-staged` | neutral `apply-conflict-patch` |
| A model edit a refusal names | push | `awaiting-human` | `conflict-patch-protected-path` / `conflict-patch-invalid` | neutral `apply-conflict-patch` |
| A `.github/workflows/` change that is not the base's own | push | `awaiting-human` | `workflow-staged` | neutral `apply-conflict-patch` |
| Hold label or draft set during the run | push | `awaiting-human` | empty | neutral `apply-conflict-patch` |
| Resolved, committed and pushed | push | none | empty | success `apply-conflict-patch` |

Residual: when every `.github/workflows/` entry the merge brings is the base's own and the PR
changes no workflow, the merge is committed and pushed. GitHub did not refuse that shape for the
App's missing `workflows` permission: sandbox probe run 38148710292 pushed it by all three methods.
`apply-conflict-patch` has not been probed on that shape. A merged workflow blob that is on no branch was refused (`POST /git/trees` 403 in run
39066232629), and still escalates.

### prepare: review-threads

A round of review-thread answers is five jobs of `pr-unblock.yml`, so no model ever holds a write
token, and the broker mints one token per job (one with both `contents: write` and
`pull-requests: write` could enqueue a PR). `address-feedback-select` runs only base code with a
read-only token. The model job is a `read` skill leaf whose config sets `prepare: review-threads`
and `applied-by` `patch` and `feedback-replies`, called on this read file twice
([Two calls on one credential each](#two-calls-on-one-credential-each)); it posts and commits
nothing. The push job, `apply-feedback-patch`, is the write file's
[`prepare: apply-patch`](#prepare-apply-patch) under the `review-threads` row. The reply job,
`publish-feedback`, is a `publish-artifact` script leaf with no model, called with
`review-replies: true`: it posts the model's replies exactly as written, or none. The scripts are
the base's `.github/scripts/pr-unblock/address-feedback.mjs`, `apply-patch.mjs` and
`publish-feedback.mjs`.

1. Before any model turn, the select job reads the PR head, resolves the slot as the read file
   does (a draft or `do-not-merge` skips it), and runs `address-feedback.mjs select` with its
   `GITHUB_TOKEN`. It keeps each unresolved thread whose first comment's review
   the reviewer bot (`claude[bot]` in the base's trusted-actors list, by id, or `github-actions[bot]`
   for a comment whose last non-blank line is a review lane's `claude-lane:` footer) submitted on a head
   that a `claude-lane-reviewed-head` marker from `github-actions[bot]` names, or
   `github-actions[bot]` submitted there for a verifier note (a first comment by it whose first
   line is `<!-- pr-verify:fail-note -->`, author `verifier`), when every comment is the reviewer
   bot's but that note; or the lanes App never commented and one comment is a fix
   request (a line starting `PR-fix lane: please fix this finding`, any case, outside a fenced
   block) by a `human` on that list whose permission on the repository reads `write` or `admin`
   (`GET /repos/{owner}/{repo}/collaborators/{username}/permission`), whose review may be on any
   head, so a request on a thread from an earlier review is worked; or the lanes App's last
   comment is a reply the reply job left open (`INCORRECT`, `UNCERTAIN` or `VALID-defer`) and
   every comment after it is by such a `human` (any permission), created after it, whose review
   may also be on any head. A human's
   comment counts only when never edited or last edited by such a human. Every other comment must
   be the reviewer bot's, the lanes App's or such a human's, or the thread is left alone. The
   thread file gives each comment an `author` (`reviewer`, `lane`, `trusted-human`) and marks
   `direction: true` the replies after the escalation, or with no escalation every human comment
   from the first such fix request on,
   which the skill follows within the same path rules. The reply job's re-read judges threads the
   same way. On a PR carrying the base's human-gated role label it keeps a thread only when one of
   those replies is such a fix request by a write-access human, and
   reports `fix-requested=true`, which lifts only the human-gated hold of the push job. No kept
   thread skips `not-applicable`, or `awaiting-human` on such a PR. A PR diff touching
   `.github/workflows/**` escalates `feedback-protected-path`, and `loop.review-rounds` earlier rounds
   escalate `feedback-round-cap`: the larger of the round markers the lanes App posted and the PR
   commits carrying a `github-actions` `pr-unblock / address-feedback` check run that ended
   `success` or `failure` (a round whose reply job was refused still counts). At the cap, a kept
   thread with a write-access human's fix request created after the newest counted round (its
   latest marker, or the completion of a model check run that ended `success`, `failure`,
   `cancelled` or `timed_out`) still runs one more round, on those threads only; a
   round with no readable time grants none. Both escalations skip `awaiting-human`, and no model
   job runs. Otherwise it writes `threads.json` and `run.json` (the gated head and the kept
   threads' ids, paths, comment ids and named paths, and `pr_paths`, from the thread file) and uploads both as
   `feedback-context-<run attempt>`. Its outputs are `proceed`, the head it read, the
   escalation, `fix-requested`, both files' SHA-256 and that attempt; every later job takes its
   gate, head and reply inputs from them, never from a model call's run job, whose runner head
   code could forge. A skip or an escalation runs `address-feedback-not-run` instead, which posts
   the `address-feedback` and `publish-feedback` checks neutral with the select job's skip reason
   on that head, so the dispatcher counts it handled; a stop before the head read posts nothing.
2. Before the head checkout, the model job's run job downloads that artifact by its attempt and
   fails red unless it holds exactly a regular `threads.json` and `run.json` of at most 1 MiB
   each, the thread file with the select job's SHA-256, for the PR and head its own gate passed.
   `collect-base-activity` stages both, a copy of the base's `feedback-thread.sh` and a wrapper
   over it under `feedback/` with an empty `feedback/state/`; after the head checkout the run job
   copies them to `.lane/feedback/` and makes the files, the wrapper and the directory read-only,
   all but `state/`. Edit, Write and NotebookEdit are denied on each staged file. The skill gets
   the tool set of a read skill that hands on a patch and one Bash rule, the wrapper's absolute
   path, bare and double-quoted, and the preamble names that path and its three subcommands. The
   tool lists the kept threads, checks paths, and records a reply in `state/replies.jsonl`: it
   refuses a disposition file outside the scratch directory or off the template (`fix_sha`
   empty), and a `VALID` reply while the working tree changes, against the gated head (renames
   as both paths, untracked files that git does not ignore included), a file outside every kept
   thread's scope or any `.github/workflows/` path, read with no hook, fsmonitor or untracked-cache config.
   Every path must be plain ASCII letters, digits and `_@+.-` in `/`-separated segments. A
   thread's scope is its path; a file in the `plugins/<p>/` directory its path sits in, except an
   instruction path
   (`.gitmodules`, `CODEOWNERS`, a `settings*.json`, `package.json`, `package-lock.json` or `requirements*.txt`, at any depth) or a `.sh`, `.bash`, `.zsh`, `.ps1`,
   `.py`, `.mjs`, `.cjs`, `.js`, `.ts`, `.mts` or `.cts` file; a test file (`test_*.py`, `*_test.py`, `*.test.*`, `*.spec.*`) in its path's
   directory; and its `named_paths`. The select job sets those from the thread's fix requests by a
   trusted person with write access: each file-shaped word outside fenced code and quoted lines,
   read from the repository root when it holds a `/` and from the thread path's directory when it
   does not, kept when it is in the thread path's `plugins/<p>/` directory, in normal form, not
   under `.github/workflows/` and not an instruction path (the same list), and
   a regular file, not a symbolic link or gitlink, at the gated head (ten per thread
   at most). Every kept thread's scope also holds the thread file's `pr_paths`: each file the
   pull request's file listing changes, rename sources included, in normal form, not under
   `.github/workflows/`, not a `.gitmodules`, `CODEOWNERS`, `settings*.json`, package manifest or
   `requirements*.txt`, and not a control-plane or agent-instruction surface: anything under
   `.github/` (the pr-merge HIGH floor's trusted-actor list, trusted-trigger check and
   `resolve-config` among it), `CLAUDE.md`, `AGENTS.md`, `.mcp.json` or `.lsp.json`, a `.claude`
   or `.claude-plugin` directory, or a plugin's `hooks/`, `monitors/` or `bin/`. A path the fix creates gets no scope from `pr_paths`: the tool checks it exists at
   the gated head, `apply-patch.mjs` refuses an added entry, and the reply job an `added`,
   `renamed` or `copied` file.
3. After the skill, the run job carries the tool's `replies.jsonl` beside the patch, at most
   49152 bytes, sealed for the scan job ([Patch output mode](#patch-output-mode)), and only for a
   `review-threads` skill. The scan job scans it with the reply and the patch and, on a clean
   scan, uploads its scanned copy as `feedback-replies-<lane>-<activity>-<run attempt>`; the read
   file's `feedback-attempt` and `feedback-sha256` outputs, set by the scan job alone, name that
   attempt and the uploaded bytes' SHA-256.
4. One call answers the round: the subscription call when it ran (its job result is not
   `skipped`), else the first. The push and reply jobs take every model-call input from that call
   alone, so one call's patch never pairs with the other's replies and an empty output never falls
   through to the other call. The push job runs on that call's written patch, read from its
   `scan-*` outputs, never a run job's, and only when that call's scan also uploaded replies.
   Before the mint it downloads the select
   job's thread file and fails red unless its SHA-256 is the select job's; `apply-patch.mjs` then
   admits only paths in a kept thread's scope (the `kept-threads` rule, `named_paths` and
   `pr_paths` included),
   skips `superseded-sha` when the head moved since the select job read it, keeps the
   human-gated hold unless the select job reported `fix-requested`, and commits with the
   `Lane-Activity: pr-unblock/address-feedback` trailer. An empty patch (every reply needs no fix)
   runs no push job, and `report-escalation` does not need it: a patch that does not land leaves
   no fix commit, which the reply job escalates.
5. The reply job runs whenever the select job proceeded, so a round whose model or push job
   failed, or whose model job forged a handoff, still counts. Before the head checkout it
   downloads `run.json` from the select job's artifact (`review-run-attempt`) and `replies.jsonl`
   from the scan job's (`review-replies-attempt`), and copies the base's trusted-actors list.
   `publish-feedback.mjs` then:
   - with no `replies.jsonl`, which the run job can arrange, records the round and: escalates
     `feedback-invalid` when the same call's scan refused its output (its refusal marker) or
     named replies it uploaded (`review-replies-attempt` or `review-replies-sha256`) that did not
     arrive; escalates `feedback-not-landed` when the head moved; escalates `feedback-invalid`
     beside a scanned patch; and otherwise, with the PR head still the one in `run.json`, skips
     `no-model-turn`, escalating nothing (no model turn: a credit stop on both calls, a broker
     refusal, the kill switch). The dispatcher dispatches a head whose newest reply job skipped
     `no-model-turn` again on its next trigger, a review or `pr-verify` run completing at that
     head, or the half-hourly sweep after each scheduled `pr-unblock-dispatch.yml` run, which
     dispatches one such head per tick through its newest completed review run and stops after
     three `no-model-turn` skips at a head; the round cap bounds those retries;
   - refuses a `replies.jsonl` whose SHA-256 is not the scan job's (`review-replies-sha256`) as
     `feedback-invalid`;
   - validates the whole artifact: `run.json` with the select job's SHA-256
     (`review-run-sha256`) and at most 1 MiB; each file a regular file read only when within its
     size limit; `replies.jsonl` at most 49152 bytes, each line an object with exactly `thread`,
     `disposition`, `evidence`, `fix_sha` and `note`; `thread` one `run.json` names, at most one
     reply per thread; `disposition` one of `VALID`, `INCORRECT`, `UNCERTAIN`, `VALID-defer`; at
     most 10 `path:line` evidence entries, no `.` or `..` segment, each a file in the checkout, at
     least one for `VALID` and `INCORRECT`; an empty `fix_sha` on every reply; a note of 1-2000
     characters with no control, direction or zero-width character, no `<!--` or `-->`, and
     nothing shaped like a GitHub token. Any failure, or a missing `run.json`, posts no reply and
     escalates `feedback-invalid`;
   - requires exactly one reply per thread in `run.json`; an empty or partial set posts no reply
     and escalates `feedback-incomplete`;
   - when a reply is `VALID` or the PR branch moved, compares the select job's head with the PR's
     current head: the branch must be ahead and change fewer than 300 files, each in a kept
     thread's scope and none under `.github/workflows/`, and with a `VALID` reply hold exactly one commit the
     lanes App authored with the push job's trailer, committed by `web-flow` with a `valid`
     signature, which must change each `VALID` thread's path, a file in `run.json`'s `pr_paths` at a
     line the reply's evidence cites inside one of the fix commit's hunks,
     or for a thread on a skill's `SKILL.md` any file in that skill's directory. With no such
     commit in the range and no patch written this round, as on a retry after a round whose fix
     landed but whose replies did not post, each `VALID` thread's fix is instead the newest
     earlier commit on the PR of the same kind (the lanes App's, the push job's trailer,
     `web-flow`, `valid`), committed after the thread's newest comment by the reviewer, the
     verifier or the lane, that changed the thread's path or, for a `SKILL.md`, a file in its
     skill's directory, and a line the reply's evidence cites in a file no later commit on the PR
     changed, and that no lane reply already names as a fix. Otherwise it posts no reply and escalates `feedback-not-landed`: a push
     that was superseded, refused, escalated or held made no such commit;
   - re-reads every kept thread and, right before posting, the thread itself, and skips one that
     is resolved, on another PR, or whose comments are not exactly the ones the model job read;
   - re-reads `git/ref heads/<head ref>` right before each post and each resolve, since the
     compare above judged the branch only up to the head this job gated: once the PR branch is
     anywhere else it posts and resolves nothing more, escalating `feedback-not-landed` when no
     reply had posted and `feedback-partial` otherwise;
   - posts the reply on the thread's root comment in the fixed template (disposition label,
     backticked evidence, `Fix: <sha>` naming the push job's commit for `VALID`, the note in a
     `text` fence longer than any backtick run in it) and resolves the thread only for `VALID`,
     and only when a re-read after the reply shows exactly the model's comments plus that reply
     (one retry on a failed read or resolve). Once a reply posts, no later round selects the
     thread until a trusted human answers a reply left open, so a post, read or resolve failure
     stops the posting, and that or a `VALID` thread left open escalates `feedback-partial`, as
     does a round marker that cannot be posted;
   - posts the round marker as the lanes App whatever happened above, once per model run: its
     second line names the workflow run and `review-replies-attempt`, and a re-run of the reply
     job alone finds a lanes App marker with that line and posts none, so one round counts once,
     while a re-run of the model job counts another. A round with no replies attempt names none,
     and its marker is always posted. It escalates
     `feedback-uncertain` for an `UNCERTAIN` or `VALID-defer` reply;
   - after the replies, settles each posted `INCORRECT` reply by the adjudicator's verdict
     ([below](#the-adjudicator)): `lane` posts the fixed finding-answered reply and resolves the
     thread; `reviewer` posts the fixed finding-stands reply and leaves the thread open for the
     next round; when the PR head did not move this round, no review run follows to start that
     round, so the reply job skips `finding-stands` (when nothing escalates), and the dispatcher's
     half-hourly sweep dispatches the head again, within the select job's round cap and three
     such skips per head; `human` posts nothing and escalates
     `feedback-question-intent`, `feedback-question-design` or `feedback-question-security`; no
     verdict escalates `feedback-unadjudicated`. A thread whose finding stood at an earlier
     adjudication is not adjudicated again: any reply but `VALID` on it escalates
     `feedback-disputed`. A thread or head that changed after the lane's reply, or a failed write,
     escalates `feedback-partial`. One round records one reason, the most urgent in that order.

   The script writes its reason to `ESCALATION_REASON_FILE`; the runner accepts only those
   reasons, and only with `review-replies`, as the run's `escalation-reason` output.

The skill's limits to kept-thread scope and away from `.github/workflows/` are instructions and the tool's
checks at record time; the push job's `kept-threads` rule is what holds the push, and the reply
job's compare withholds the replies when the branch changed anything else. A diff at the files
listing's limit escalates as `feedback-protected-path`, since it could hide a `.github/workflows/`
path.
Residuals: a reviewed-head marker confirms a head, not one review run, so any reviewer-bot review
on that head is kept; and the replies file is the model's to write, so the tool's checks are
advisory and `publish-feedback.mjs` is what holds the template. The write file fails red on a
`review-threads` activity: it keeps no threads and collects no replies.

The write file's head re-read (run job step 5) applies to every `mutate-branch` activity: a
pr-unblock run whose PR branch moved before the mint posts neutral `superseded-sha` without a
model turn.

#### The adjudicator

pr-unblock.yml's `adjudicate-feedback` job runs after the model job, before the push and reply jobs, whenever
the leg the reply job reads uploaded replies. It runs only base code with a read-only token and
no OIDC token. `adjudicate-feedback.mjs prepare` checks the select job's thread file and the
scan job's replies against the SHA-256 each writer recorded, then stages each `INCORRECT` reply on
a thread no adjudication stood before and no trusted person directed, up to three: the finding's
path, line and claim (the review comment's first paragraph and its `severity:` line, never the
later rationale or the lane's footer; a verifier note's whole quoted finding), the locations the
lane cited, at most ten (never its note), and those files at the select job's head, read through
the contents API, each up to 200 KiB and staged with a `.txt` suffix so a cited `CLAUDE.md` or
`.claude/**` file is never loaded as instructions. A thread a trusted person directed (a fix
request, or a reply after an escalation) stays theirs: an `INCORRECT` reply on it escalates
`feedback-disputed` with no adjudication. Each thread gets one fresh
`run-claude-cli` call, after `apply-claude-managed-settings` and runner isolation, on the
pr-unblock API key (`PR_UNBLOCK_CLAUDE_API_KEY`), under `dontAsk` with Read alone, `Read(./adjudicate/**)` the one allow rule, Read
denied on the base checkout and the runner's temp directory (which holds the lane's replies and
the other slots), Glob, Grep and MCP tools denied, and only that thread's files in the workspace. The prompt
(`.github/scripts/pr-unblock/adjudicate-feedback.prompt.md`) frames every staged file as
untrusted data. The model route is `adjudicate-feedback` ([README.md, Models](README.md#models)).
The call returns `verdict` (`lane`, `reviewer` or `human`) and `question` (`none`, or for `human`
`intent`, `design` or `security`) to `adjudicate-feedback.schema.json`, and a leg whose init
message reports another permission mode keeps no verdict. `collect` writes `verdicts.json`, and
the job uploads it as `feedback-adjudication-<attempt>` with `overwrite: false`, passing its
attempt and SHA-256 out only once the upload succeeded. The reply job downloads it through the
write file's `review-adjudication-attempt` and `review-adjudication-sha256` inputs and reads
verdicts only for the select job's head (`run.json`), the code the adjudicator read, with that
SHA-256; a round that pushed a fix still applies them. The posted replies are fixed text and the
lane's validated evidence; no model text reaches the pull request.

The next round reads the finding-stands reply: `threadAuthors` keeps a thread whose last lanes
App comment is that reply, so `pr-feedback-dispatch.yml` dispatches it once the review lanes
review the next head, or, after a `finding-stands` skip at an unmoved head, at its next
half-hourly sweep. The push job waits for this job, so it lands right before the reply job,
as it did without one: a review run on that head that finished while this run still went would
find it in progress and dispatch nothing.

### prepare: dependency-review

A review of one risky Dependabot pull request is six pr-unblock jobs, for the reason
review-threads is: the model job reads third-party release notes, so it holds no write token. A
base job selects the pull request; the model job, a read skill leaf whose config sets
`prepare: dependency-review`, `gating: advisory` and `applied-by` `patch` and
`dependency-verdict`, runs on the read file, with its subscription fallback
([Two calls on one credential each](#two-calls-on-one-credential-each)); `apply-dependency-patch`
pushes a fix verdict's patch; and the verdict job, a `publish-artifact` script leaf with no
model called with `dependency-verdict: true`, acts on the verdict. The scripts are the base's
`.github/scripts/pr-unblock/review-dependency.mjs`, `apply-patch.mjs` and
`apply-dependency-verdict.mjs`. Both this lane's dispatcher and select job sort pull requests with `dependency-classify.mjs`, a port of
the pr-merge lane's `babysit_dependabot.py` and its content step, so the tiers, the content rule
and the `directories` globs are the ones
[README, "Dependabot pull requests"](README.md#dependabot-pull-requests) states. They read the
same inputs: the pull request, its REST commits and files with patches, each non-Dependabot
commit's files, and the base's `.github/dependabot.yml`. The pr-merge lane's commit and content
refusals are review reasons here, so the AI review owns the pull request: a commit whose
`verification.verified` is not `true` (`commit-unverified:<sha>`), whose git committer email is
not `noreply@github.com` (`commit-not-committed-by-github:<sha>`), or that is neither signed
`dependabot[bot]` nor the `[dependabot skip]` version-bump commit (`commit-not-dependabot:<sha>`,
`commit-not-version-bump:<sha>`); no commits (`commits-missing`); a commits listing short of the
pull request's commit count, which the dispatcher reads as GraphQL `commits.totalCount`
(`commits-listed:<listed>-of:<total>`); a commit whose files cannot be
read whole; a fix commit touching `.github/`. The lanes App admission is left out, so a pull
request carrying a lanes App fix stays `review`. The `updated-dependencies` metadata is read only
from commits signed `dependabot[bot]`, and a pull request sorts `auto` only when every commit
passes those checks. A base `dependabot.yml` that cannot be read, or holds no entry that
reads, is `dependabot-config-unreadable`, with a warning naming which. A security update is the
`security` label or an advisory, GHSA or CVE id in the body; it is a flag on either tier. Both
also apply the [registry provenance](README.md#registry-provenance) gate, and the select job
warns of a [classifier gap](README.md#classifier-gaps).

1. pr-unblock's `review-dependency-select` job, which runs only default-branch-tip code with a
   read-only token, reads the PR head, resolves the slot (`applied-by-supported: patch
   dependency-verdict`) and runs `review-dependency.mjs select`. A pull request whose author is
   not `dependabot[bot]` (by id, from the base's trusted-actors list) or that sorts `auto` skips
   `not-applicable`; one whose head is no longer the head read skips `superseded-sha`.
   `loop.dependency-review-rounds` earlier rounds escalate `dependency-round-cap` and skip
   `awaiting-human`: the larger of the round markers the lanes App posted and the PR commits
   carrying a `github-actions` `pr-unblock / review-dependency` check run that ended `success` or
   `failure`. A select that does not proceed posts that check neutral on the head it read
   (`review-dependency-not-run`), so the dispatcher does not send that head again; a neutral check
   counts no round. Otherwise it writes `dependency.json`, the context file (the head, title,
   labels, classification, each changed file with its patch, 20,000 characters each and 300,000
   in all, `files_truncated` when the files listing reached its 3,000-file limit, and the body as
   data), and `context.json`, the run fields the verdict job reads (`version`, `pr`, `head_sha`,
   the `security`, `config_unreadable` and `files_truncated` flags, `started_at`, the UTC time
   before any model turn, `controls`, the matched review-only entries' `control` strings, and
   `config`, the base `.github/dependabot.yml`'s `[ecosystem, directory]` pairs), and uploads both
   as `dependency-context-<attempt>`, with each file's SHA-256 as an output.
2. The read file downloads that artifact by the caller's `dependency-context-attempt` and checks
   it before the head checkout: exactly `dependency.json` and `context.json`, regular files of at
   most 1 MiB, the context file's SHA-256 the caller's `dependency-context-sha256`, written for
   the gated PR and head. `collect-base-activity` stages the context file under `.lane/dependency/`,
   read-only and denied to the file tools; gives the skill Read, Grep, Glob, Skill, Edit, Write and
   Agent, no Bash (git and the shell read commands are denied all the same), and one
   `WebFetch(domain:)` rule per `web-access` host with WebSearch; and writes the verdict schema to
   `$RUNNER_TEMP/lane-dependency-schema/verdict.schema.json`, which both launcher legs take as
   `json-schema-file`: `verdict` (`merge`, `fix`, `close`, `escalate`), 1-10 `reasons` of at most
   500 characters and at most 20 `evidence` entries of at most 300. The skill runs no head code and
   leaves a fix uncommitted; `ci-status` runs the tests on the pushed head.
3. After the leg, a step writes the last result message's `structured_output` from the execution
   file to `dependency-verdict.json` with `jq`, as data; a run with none writes no file. The run
   job carries it at 49,152 bytes beside the reply, run fields and patch, never beside a
   review-threads skill's replies, so the sealed payloads still fit five chunks. The scan job
   scans it with the rest, uploads it from its copy as
   `dependency-verdict-<lane>-<activity>-<attempt>`, and sets `dependency-attempt`,
   `dependency-sha256` (of the scanned bytes) and `dependency-verdict` (its `verdict` field when it
   is one of the four, else empty). A refused payload, or any other scan failure, leaves the
   `scan-refusal` job's marker.
4. `apply-dependency-patch` runs when the leg that answered (the fallback call when it ran, else
   the first) handed on a written patch beside a `fix` verdict, every input from that leg's scan
   job. Before the mint the write file downloads the scanned verdict by `patch-verdict-attempt`,
   checks it against `patch-verdict-sha256` (a missing or altered file fails the job, so no patch
   applies without a scanned verdict), and hands its `verdict` field, held to the four verdicts,
   to `apply-patch.mjs` as `DEPENDENCY_VERDICT`. Under `patch-rules.json`'s `dependency-review`
   row it requires `fix`; admits only `dependency-manifests` paths, an npm (`package.json`,
   `package-lock.json`, `npm-shrinkwrap.json`) or pip (`requirements*.txt` or `.in`) manifest or
   lock file outside `.github/` in a directory the base `.github/dependabot.yml` lists for that
   ecosystem (the write file copies that file out of the base; one that does not read fails the
   job before any write); holds each file to the `dependency-version-change` content rule
   (`fixRefusal` in `dependency-classify.mjs`, on the local blobs before any commit is built:
   modified in place, a regular `100644` file, and changed only by a version), escalating
   `patch-protected-path`; skips a head that moved since the select job read it; and pushes one
   commit, `Fix the dependency update on <ref> [dependabot skip]`, so Dependabot may still rebase
   over it. report-escalation does not need this job: a patch that does not land leaves no fix
   commit, and the verdict job escalates `dependency-fix-not-landed`.
5. The verdict job runs whenever the select job proceeded, whatever the model and push jobs did.
   `apply-dependency-verdict.mjs`:
   - validates `context.json` (exactly the select job's SHA-256, a regular file of at most
     64 KiB, exactly its fields, and `head_sha` the select job's head) and
     `dependency-verdict.json` (exactly the scan job's SHA-256, a regular file of at most 64 KiB,
     and exactly the schema's fields within its limits, each string plain prose with no control
     character, code fence, HTML comment or @-mention). Any failure escalates
     `dependency-invalid`. With no verdict, the round still counts: it skips `no-model-turn` only
     when the same call's scan handed on no patch, refused nothing, and the PR head is still the
     select job's; a scan that refused an oversize patch escalates `dependency-fix-not-landed`,
     and any other case `dependency-invalid`. The dispatcher dispatches a head whose newest
     verdict job skipped `no-model-turn` again on its next run, a limit stop aside; the round cap
     bounds those retries;
   - re-reads the pull request: a closed one gets nothing, unless it is a `close` this job
     started at the reviewed head (its issue or marker is there), which resumes. `merge`,
     `close` and `escalate` need the reviewed head; a moved head skips `superseded-sha` and the
     next dispatcher run reviews the new one. `fix` needs the PR head ahead of the reviewed head
     (else `dependency-fix-not-landed` when it is that head, `superseded-sha` otherwise). The
     comparison must be listed whole: `commits` and `files` are lists, fewer than 250 commits
     and 300 files (the compare listing's limits), and `total_commits` equals the commits listed,
     else `dependency-invalid`. Every commit must be one GitHub signed for the lanes App during
     this workflow run, as `check-trusted-trigger` checks a commit after a model job: author id
     the App's, committer `web-flow`, `verification.verified` `true` with reason `valid`, and a
     committer date no earlier than `context.json`'s `started_at` (so the verdict job reads no
     Actions API and needs no `actions` permission), else `superseded-sha`. Those commits must
     pass the fix rule apply-patch applies ([README, "Dependabot pull requests"](README.md)),
     with the `[ecosystem, directory]` pairs this job reads from `.github/dependabot.yml` at
     `BASE_SHA` (never `context.json`'s `config`): each file modified in place, a regular `100644`
     file at the head (read from the tree before any content), a manifest or lock file in fix
     scope, and changed from the reviewed head only by a version; else `dependency-fix-refused`,
     or `dependency-config-unreadable` when the base config does not read;
   - `merge`: posts the round marker, whose first line
     `<!-- pr-unblock:review-dependency-round head=<sha> verdict=merge run=<run id>-<attempt> -->`
     from the lanes App is the record the pr-merge lane merges a review-tier pull request on,
     at the current head and through its own gate. With `config_unreadable` it posts no merge
     marker and escalates `dependency-config-unreadable`; with `files_truncated` it posts no
     merge marker and escalates `dependency-files-truncated`; when the pull request's files
     (re-read here) change a workflow or action file (`.github/workflows/**` or an
     `action.yml`), either side of a rename, it posts no merge marker and escalates
     `dependency-workflow-held`, so a person merges it; a listing at its 3,000-file limit
     escalates `dependency-files-truncated`; unless the pull request's commits are listed whole
     (fewer than 250, the pull request's count, the last one the head) and each is Dependabot's
     own (author id 49699333, committer `web-flow`, a valid signature, Dependabot's name and
     email), the version-bump commit (only plugins' `plugin.json` `version` and `CHANGELOG.md`
     changing, as regular files), or a single-parent commit that passes the fix rule against
     its parent, it posts no merge marker and escalates `dependency-fix-refused`; it reads
     `.github/dependabot.yml` at `BASE_SHA` itself, and a config that does not read escalates
     `dependency-config-unreadable`; without each of `controls` quoted
     in `evidence` it escalates `dependency-control-uncited`
     ([README, "Review-only dependencies"](README.md#review-only-dependencies)). This job never
     merges or enqueues;
   - `close`: escalates `dependency-security-close` for a security update (the select job's
     flag, or the label or an advisory in the body read fresh); otherwise finds the lanes App
     issue whose first line is `<!-- pr-unblock:dependency-ignore pr=<n> head=<sha> -->` or files
     it, proposing the `.github/dependabot.yml` `ignore` entry, then posts the marker, then closes
     an open pull request. Each step is safe to repeat, so a re-run after a partial failure
     resumes;
   - `escalate`: escalates `dependency-escalate`;
   - posts the round marker once per model run, the scan job's verdict attempt; a run with none
     is named `none`, and its marker always posts, since a re-run cannot tell it from another
     round's.

   The runner accepts only the reasons above, and only with `dependency-verdict`. The write file
   fails red on a `dependency-review` activity: it selects no pull request and collects no
   verdict.

### prepare: ci-context

pr-unblock's `fix-ci` fixes a lanes App or [adopted](README.md#adoption) owner pull request's
failing checks in separate jobs, so no model
holds a write token: a base job, a read model job in this mode on the pr-unblock role's API key,
its fallback call on the role's OAuth token after a credit stop or with the key empty
([Two calls on one credential each](#two-calls-on-one-credential-each)), and an
[`apply-patch`](#prepare-apply-patch) script job.

1. `pr-unblock.yml`'s `fix-ci-context` job runs the default branch tip's
   `.github/scripts/pr-unblock/fix-ci-context.mjs` with a token that reads pull requests, checks
   and Actions, and checks out no PR head. After the kill switch it hands the pull request to a
   person (`ci-fix-round-cap`) once the lanes App has pushed `loop.fix-ci-rounds` commits with
   the trailer `Lane-Activity: pr-unblock/fix-ci`. Otherwise it reads the head's latest check run
   per name and keeps those that ended `failure`, `timed_out` or `startup_failure`, except
   `ci-status` and any GitHub Actions check run that is no workflow job (a lane's own check),
   at most 10. For each it writes the name, the workflow file that defines the job (or `null`),
   at most 20 annotations of at most 500 characters, and the last 80 lines, at most 3,000
   characters, of the job log, as `context.json`, uploaded as `ci-context-<run attempt>` with its
   SHA-256 as a job output. A closed pull request or a head with no such check skips the rest,
   and a scripted job posts the fix-ci check neutral `not-applicable` on that head with
   `report-check-run`'s `not-run-reason`, so the dispatcher counts the head as handled.
2. The read file, before the head checkout, downloads that artifact and fails red unless it
   holds exactly one regular `context.json` of at most 1 MiB, with that SHA-256, written for the
   head this run gated.
3. `collect-base-activity` stages it for `.lane/ci/context.json`, which the run job makes
   read-only, denies Edit and Write there and on the staged plugin, and grants the skill Bash,
   Edit, Write and Agent with the web tools denied: the job holds no write token, and the skill
   reruns the failing checks. The launcher's preamble names the file, since run-claude-cli takes
   no system prompt ([Two calls on one credential each](#two-calls-on-one-credential-each)).
   Residual: the skill runs head code by design, so head code can reach what any step of a read
   job can (the job's read-only token, the Actions runtime token through a process left running
   or `$GITHUB_ENV`, and the default branch's cache scope), as in `pr-verify.yml`. The patch it
   leaves is checked only by [`apply-patch`](#prepare-apply-patch), which refuses
   `.github/workflows/**`, `CODEOWNERS`, `.gitmodules`, settings files, symlinks and gitlinks; a
   change elsewhere, such as `.gitattributes`, an agent instruction file or a check's own script,
   reaches the branch and its review.
4. The run is in [patch output mode](#patch-output-mode); its `reply-attempt` output names the
   skill's reply, whose `<check>: escalated <reason> <sentence>` lines are the report.

### prepare: apply-patch

A `mutate-branch` script leaf, the `apply-patch` job after `fix-ci`, with no model, running
[`apply-patch.mjs`](../../../.github/scripts/apply-patch/apply-patch.mjs) with the `ci-context` row
of `patch-rules.json`. The caller passes the outputs of whichever `fix-ci` call ran the activity
([Two calls on one credential each](#two-calls-on-one-credential-each)): `patch-state`,
`patch-sha256`, `patch-attempt` and `reply-attempt` from that call's scan job (`scan-patch-state`
and the rest), the fallback call's when it ran and the first's otherwise, never a run job's;
`fix-ci-context`'s head as `patch-head-sha`; the activity as `patch-activity`; and its prepare
mode as `patch-prepare` (`ci-context`). The job runs on a `written` or `empty` patch, or on that
call's `scan-collect-refused`, which reaches `select` with no `patch-state` and so escalates
`ci-fix-invalid`.
`fix-ci-unreported`, after every fix-ci call, reads this run's jobs as `fix-ci-handoff` does and,
when a call's broker-check job allowed the lane and no call's report posted, posts fix-ci
failure on `fix-ci-context`'s head, so fix-ci-dispatch counts the round toward
`fix-ci-restarts` whatever the calls reported. As in the report job, a kill switch or a broker
refusal posts nothing.

1. Before the mint, the write file downloads `patch-<lane>-<patch-activity>-<patch-attempt>`
   and the model job's reply, and runs the script's `select` with no token. A gated head other
   than `patch-head-sha` skips `superseded-sha` (the row's `skip-moved-head`), and the script checks it again. An `empty` patch escalates `ci-fix-empty`
   (`ci-fix-escalated` when the report escalated a check), except that at `patch-model-rung` 0 a
   report whose every escalated check is `unfixed` or `not-reproducible` skips `rung-up` with no
   escalation (output `rung-up` `true`), so the caller runs the producer once more at
   `model-rung` 1. A `patch-state` other than `written`
   or `empty`, or an artifact that is not exactly one regular `patch.diff` of at most 1 MiB with
   that SHA-256 and no credential shape, escalates `ci-fix-invalid`. Each skips `awaiting-human`
   with nothing minted. A report that escalated a check sets `ci-fix-escalated` and proceeds, so
   the fixes that landed are pushed and the rest go to a person.
2. The hold-label step runs as for a skill, before the head checkout (depth 1).
3. The script, from its base copy, with the lane token and `/usr/bin/git` under an allowlisted
   environment (no hooks, fsmonitor, global or system config), applies the patch to the gated
   head's index (escalating `ci-fix-not-applied` on failure) and refuses the whole patch,
   whatever the report escalated, on any change the row refuses: the universal set
   (`.github/workflows/**`, `CODEOWNERS` at the root, in `.github/` or in `docs/`, `.gitmodules`,
   `**/settings*.json`, a symbolic link or gitlink, a rename into a refused path, a backslash),
   escalating `ci-fix-protected-path`; more than the row's `max-files`
   (300) paths, a credential shape, an oversized blob or a patch that changes nothing (the row's
   `empty-at-push`) escalates `ci-fix-invalid`. It then
   re-reads the pull request and its labels, throws unless the head is this repository's, stops
   uncommitted (`awaiting-human`) on a draft or a hold label, fails when
   `git/ref heads/<head ref>` is no longer the gated head, uploads the changed blobs, creates the
   commit `Fix failing CI checks on <head ref>` with the trailer `Lane-Activity: pr-unblock/fix-ci`,
   parent the gated head and no author, committer or signature, so GitHub signs it as the App,
   moves the PR branch with `force: false`, and confirms the move by reading the ref again.

The run's `escalation-reason` output is the script's reason, else the select step's. The runner
accepts the script's reasons only in this mode.

In `pr-refine.yml` the same leaf, as the `apply-docs-patch` job, follows `fix-docs`, which has
no prepare mode: the caller passes no `patch-prepare`, so the script takes the `default` row, and
runs the job only on a `written` patch. As fix-ci's `apply-patch` does, it takes one leg (the
fallback call when it ran, else the first) and every patch input from that leg's scan job
(`scan-patch-state`, `scan-patch-sha256`, `scan-patch-attempt`, `scan-reply-attempt`), never from
a run job. That row refuses the universal set, escalating
`patch-protected-path`, caps a patch at 300 paths (`patch-invalid`), takes a moved head with
`--3way` when the moved commits touch no patched path (`skip-moved-head: false`), and commits
`Apply fix-docs on <head ref>` with the trailer `Lane-Activity: pr-refine/fix-docs`.
`pr-refine.yml` has no escalation job, so a refusal leaves only the neutral `awaiting-human`
check.

In issue mode the same leaf is `apply-issue-patch`, which runs
[`apply-patch.mjs`](../../../.github/scripts/apply-patch/apply-patch.mjs) with `PATCH_TARGET=issue`
and the `issue` row of `patch-rules.json`. The caller passes `patch-base-sha` and
`patch-resume-tip` instead of `patch-head-sha`; the start commit is the resume tip, else the base,
which a step before the mint checks is on the default branch. The select step and the script run
from the base with that start commit as both heads, so a patch made on another commit is refused
`patch-invalid`, never applied with `--3way`. The hold-label step also outputs the activity's
`applies-when.labels` (`agent-ready`). After the universal checks, the script re-reads the issue's
labels and stops uncommitted (`awaiting-human`) when a hold label is on it or `agent-ready` is
gone, creates the commit `Resolve issue #<n>` with the trailer
`Lane-Activity: work-resolve-issue/resolve-issue`, creates the branch (which fails if it exists,
so no branch is ever moved), reads it back, and outputs `commit` and `branch`. The row's
`max-files` (300) bounds its blob uploads. On a resume it checks out the full history and also
holds every change the final tree makes since the commit the resume tip forked from
`patch-base-sha` to the refusals, so an earlier lane commit cannot carry a refused path onto the
new branch. Every target refuses `patch-invalid` a patched blob over 5 MiB, or patched blobs over
20 MiB in all, by `git cat-file -s` before any is read. The script's base copy imports `thread-scope.mjs`, and
reads `patch-rules.json` from a copy the write file makes before the checkout.

The rules each producer's patch is to be held to are registered in
[`patch-rules.json`](../../../.github/actions/resolve-config/patch-rules.json), one row per
producer prepare mode ([README.md, Patch rules](README.md#patch-rules)): the refusals every row
carries, what else a path must meet, a file cap, the producer output required, the commit's
parents, message and trailer, and the row's escalation reasons.

## The scan job

Read file: runs after the run job when it succeeded or failed, unless the run was cancelled or the
call handed off, on a fresh `ubuntu-24.04` VM, in the `pr-pipeline-scan-carrier` environment. It
holds `contents: read`, one secret (`SCAN_CARRIER_PRIVATE_KEY`, that environment's, which each
caller passes by name as `scan-carrier-private-key`, read by its open step alone), no `id-token`, no cache, and nothing from the run job but its outputs. run-claude-cli's
contract puts the reporting and uploads of a lane that grants unrestricted Bash in a downstream
job that validates its inputs
([`action.yml`](https://github.com/melodic-software/ci-workflows/blob/7b362428c76085a160e28656cd2c75c3147a69ff/.github/actions/run-claude-cli/action.yml)).

The carrier. After the collector, a PR-mode run job stages each of `reply.txt`, `act-turns.json`,
`patch.diff` and, for a `prepare: review-threads` skill, the review-thread tool's
`replies.jsonl` within its cap and sets `carry-<name>-bytes`; the caps are 16 KiB for the reply,
32 KiB for the run fields (at most four `<local-command-stderr>` entries), 256 KiB for the
patch and 48 KiB for the replies, `publish-feedback.mjs`'s limit, and a payload over its cap
carries only its byte count. All four at their caps fit the five chunks
(`seal.test.mjs` seals them with the real sealer). It then seals the staged copies
with [`seal-lane-output`](../../../.github/actions/seal-lane-output/README.md), copied from the
base before the head checkout, to the base's `.github/lane-keys/scan-carrier.pub`, bound to the run
id and the `run` job, as `carry-sealed-length` and `carry-sealed-<n>` job outputs (at most five
chunks of 98304 characters, each fitting one environment variable). None is a `workflow_call`
output, so no caller can echo one. In order:

1. Checks out the default branch tip the event names, never a run job output (sparse: the opener
   and the key file), reads the key id, and
   opens the bundle with [`open-lane-output`](../../../.github/actions/open-lane-output/README.md)
   into a fresh directory under `runner.temp`, the one step that reads the private key. It fails
   closed, writing nothing, on `output-withheld` (a chunk the runner left empty, as it does for an
   output that may hold a secret
   ([`jobs.<job_id>.outputs`](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#jobsjob_idoutputs));
   it asks for rotation), and without rotation on `sealed-mismatch` (a wrong key, a failed tag,
   truncation, an unknown key id, a bad version, or a record from another run, job or payload
   name) or `too-large`.
2. Checks every output from `env`, never inlined into a script, and fails closed, publishing
   nothing, on:
   - `too-large`: a byte count over the cap;
   - `payload-mismatch`: a byte count with no opened payload, an opened payload with none or of
     another size, or a patch that does not match the state its collector reported;
   - `bad-output`: a run job output set after head code (`skip-reason`, `dirty-tree`,
     `patch-collected`, `act-outcome`, `lane-class`) or a gate field outside its closed set.
3. Checks out the gated `head-sha` with `persist-credentials: false` when a patch arrived.
4. `leak-scan` runs the default branch's `findSecret` (`lib/publish-gate.mjs`, read through the API
   at the default branch's tip, which the step resolves itself with the scan job's read token
   (`getBranch`), never from a run job output, an older PR base or a checkout; a failed call or a
   malformed SHA fails the scan closed with no fetch) over the reply, the run fields, the replies and the patch. It applies the
   patch as apply-patch does, onto the gated head's objects copied through `git index-pack`, and
   scans every file the patch makes, by name and bytes. It scans copies, which the uploads and the
   summary then read, and the run's `patch-sha256` is the scanned copy's. A credential format
   fails the job naming the pattern and asking for rotation, uploads and summarizes nothing, and
   leaves `patch-state` empty. A patch that does not apply, or a scan that does not finish within
   the step's timeout, fails it without the rotation line. A `password or secret assignment` on a
   plain line only warns, naming the kind of source, never its path; beside markup or escapes the
   gate folds it blocks as `assignment hidden by markup or escapes`, without the rotation line.
5. After a clean scan, writes the step summary and uploads `skill-reply-*`, `patch-*` and
   `feedback-replies-*`, with `overwrite: false`; its `feedback-attempt` output names the last.
6. Builds `verdict.json` from the run job's checked outputs and its own patch upload, and uploads
   `verdict-*` (`overwrite: false`) once every step before it succeeded. A run that stopped
   before head code skips the scan and still posts its skip; a scan hit leaves no verdict.

Its `patch-state`, `patch-sha256`, `patch-attempt` and `reply-attempt` outputs are the read
file's in PR mode; in issue mode the run job's, which still uploads its own reply, patch and
outcome. The issue lane's run job holds the OAuth token alone and runs no scan.

### Leak-scan limits

Recorded, not fixed:

- The scan blocks credential formats only (owner ruling Q37). Beside the per-line scan it reads
  each text with its NUL bytes removed, so a UTF-16LE credential is caught, and each pair of
  adjacent lines joined (in the patch, hunk lines without their `+`, `-` or space prefix), so a
  credential split across two lines is caught (N16). The split-line pass leaves out the OpenAI key
  pattern (`sk-` and 20 token characters): it is too loose to join safely, since a line ending in
  an `sk-` word joined to the next line's first word matches it, and a false block fails fix-ci
  closed and asks for a rotation. A split OpenAI key and a credential wrapped in base64 still
  pass.
- Issue mode still publishes from the run job, unscanned: its `Show the skill's run in the step
  summary`, `Upload the skill's final reply` and `Upload the patch` steps, and the gate verdict's
  step summary (`Check the gate skill's verdict`). That predates the scan job and is slated for 6b.
- A leaked scan-carrier private key also opens the payloads the scan blocked, which stay in the
  run's job outputs as ciphertext. Rotate the key on a block, as the rotation line says.
- The verdict's step outcomes, `act-outcome` among them, come from the run job, which a hostile
  run can forge, so the check-run conclusion this workflow posts is not evidence. No PR-mode gate
  skill runs on it, and no consumer treats that conclusion as merge or apply evidence: not a
  required check, ci-status, pr-merge's verify evidence or risk score, apply-patch, or a
  `workflow_run` trigger keyed on it.

## The summary job

Read file, issue mode only: runs after the run job, unless the run was cancelled, when the run
job's `reuse-branch` output is not empty. It holds `contents: read` and nothing else, and it
times out after 20 minutes. Every step is
`continue-on-error` and runs only when the one before it succeeded, so a failed or limit-stopped
pass turns no job red and leaves no summary. In order:

1. Checks out the run job's `base-sha` to `.base` with `persist-credentials: false`, and sets up
   Node.
2. Fails unless the issue number, base SHA and `reuse-branch` have their runner shapes (the branch
   is this issue's lane branch). With the job's `GITHUB_TOKEN`, `write-issue.mjs` writes the issue,
   frozen as the skill would get it. A blobless fetch of the base and the branch into a repository
   outside the workspace, with `GIT_CONFIG_GLOBAL=/dev/null` and no system config, writes the
   branch's diff (`git diff --no-ext-diff --no-textconv`, cut at 1 MB) and `branch.json`, so
   nothing on the branch is checked out or run. The fetch carries no credentials, so the pass
   needs a public repository; in a private one this step fails and the PR keeps the fixed text.
3. `resolve-config` with `model-route: summarize-reuse` ([Models](README.md#models)), then builds
   the prompt and the `--allowedTools "Read(<data directory>/**)"`, `--disallowedTools` and
   `--json-schema` arguments, passing the prompt through a random heredoc delimiter.
4. `setup-runner-isolation` with subprocess isolation (steps 9 and 10 of the run job).
5. `claude-code-action` with the job's `GITHUB_TOKEN`, no plugins and no commit signing, under
   `--permission-mode dontAsk`, returning `title`, `summary` and `changes` as structured output.
6. Writes `reuse-summary.json` with `jq`: the issue, branch and diffed tip from the runner's own
   steps beside the structured output, read through `env` and parsed (null when it does not
   parse), and uploads it as the `reuse-summary-<n>` artifact.

The caller's `report-outcome` job needs the whole `resolve-issue` call, this job included, and
runs with `!cancelled()`, so it opens the PR whether this job succeeded, failed or skipped.

## The report job

Runs after the run job (and, in the read file, the scan job) whatever its result, with `checks: write`, `contents: read` and
`pull-requests: read`, no model step, and a 10-minute timeout. It checks out the default branch
tip, with full history, to `.base`, then checks out the run job's `base-sha` output only when that
SHA is an ancestor of the tip; otherwise it stays on the tip. It never checks out the event's base
SHA, so a PR into another branch cannot choose the actions that write its check. It then downloads
the verdict (`continue-on-error`: a missing verdict is already decided below), runs
[`check-signed-commits`](../../../.github/actions/check-signed-commits/README.md) with its
`GITHUB_TOKEN` unless `can-commit` is `false`, reads the PR's current head SHA with its
`GITHUB_TOKEN` (empty when there is no PR or the read fails; in the write file, when the branch's
`git/ref` is readable, `GET /pulls/{n}` is re-read until its head matches it, at most 5 reads 2 s
apart, since it can lag the promote step's push), and posts the check with
[`report-check-run`](../../../.github/actions/report-check-run/README.md), passing that SHA as
`pr-head-sha`. Why the check is written by this job and not the run job:
[ADR 0053](../../adr/0053-run-each-pipeline-activity-as-a-model-job-and-a-scripted-report-job.md).

In the read file the run job is hostile (its head code can tamper with the runner before its
outputs are sent), so the report job differs:

- It stays on the default branch tip and never checks out the run job's `base-sha`.
- The PR number comes from the caller's `pr-number` input or the event, never from the run job; a
  run job `pr-number` that names another PR fails closed.
- It posts on the run job's `head-sha` only when that equals the gated head: the caller's
  `head-sha` input (pr-unblock passes `fix-ci-context`'s) or the event's PR head. The PR head it
  reads is never a gated head, since a head that moved mid-run was never gated: with neither set,
  any run head is forged and posts failure on it. Any other value or a mismatched PR number posts
  failure on the trusted head and never on the run's SHA. The run job itself fails before the
  head checkout when its trigger gate read a head other than a non-empty `head-sha` input. With no trusted head it posts nothing and fails. A handoff skips the report job; the fallback
  call posts that check.
- An empty run head (the run stopped before its trigger gate passed) never posts failure, which
  babysit reads as a merge blocker. After the kill switch, which the report job reads from its
  variables, or the broker-check job's refusal, it posts what it did before (the event's head on
  `pull_request`, otherwise nothing), so the owner's switch blocks no merge and the head is
  dispatched again once the switch is off. Otherwise it posts neutral `not-assessed` on the
  caller's or the event's head: babysit counts a neutral check as passing, and fix-ci-dispatch
  reads it as that head's run and dispatches it no more, without counting a restart. A trigger
  decline cannot be told from a forged empty head in the report job, so both take this neutral.
- pr-unblock passes `fix-ci-context`'s head, not the read runner's `head-sha` output, as
  apply-patch's `patch-head-sha`; apply-patch compares it with the head its own trigger gate reads
  at apply time and pushes only while the branch is still there. Both `fix-docs` calls pass the
  head `fix-docs-head` reads, a job that runs no head code, as `head-sha`, so a push while the run
  goes posts its check on the head it ran on, not failure on the new head. They also pass
  `post-decline: false`: fix-docs is dispatched once per PR, so a run that stops before its
  trigger gate posts no `not-assessed` neutral and the PR is dispatched again; and
  `apply-docs-patch` passes `fix-docs-head`'s head as `patch-head-sha`, never the read runner's
  run-job `head-sha` output; apply-patch still applies onto the head its own gate reads and measures the
  `default` row's refusals from there.

What it trusts:

- Lane and activity from the reusable workflow's own inputs.
- `needs.run.result`, and the run job's `act-outcome`, `can-commit`, `gate-reason`, `head-sha`,
  `base-sha` and, in the write file, `run-failure` outputs, computed by the runner. All but a gate skill's `act-outcome` come from steps
  that ran before any head code; that one rests on the rule that a gate skill runs no head code.
- Its own signed-commit result. On an unverified commit, `check-signed-commits` fails closed: the
  check is a failure, and the report job adds no label and posts no comment, because its
  `GITHUB_TOKEN` cannot write issues or pull requests. Why signing is not also enforced by an
  all-branch rule:
  [ADR 0054](../../adr/0054-keep-commit-signing-on-the-default-branch-rule-and-add-no-all-branch-rule.md).

The activity ran on exactly the commit the check is posted on: the run job checks out the gate's
`head-sha`, not the branch, and fails before the activity if `HEAD` differs. A push after the gate
cannot make the activity judge a different commit than the one its check marks, so a later
force-push back to the checked SHA never carries a result for code the activity did not see.

`persist-credentials: false` does not hold for a skill activity. claude-code-action writes the App
token into the origin URL in `.git/config` and exports it to Claude as `GH_TOKEN` and
`GITHUB_TOKEN`. A skill activity whose effect is not `read` therefore holds a contents-write App
token inside the Claude process and the git config. Such a skill must not execute head code: no
test or build of the PR runs through Bash. A lane that needs to run head code with a write effect
is outside this contract until a split design exists (a read-only run, then a separate step that
makes the signed commit).

Secrets in the job that runs head code: neither file references the App key, and a run holds it
only if a caller passes it ([below](#secrets-and-the-two-files)). Every skill job references the
Claude OAuth token. Two routes reach it and the activity's GitHub token:

- Environment inheritance, no root needed. claude-code-action puts `CLAUDE_CODE_OAUTH_TOKEN` and
  the token it was given (as `GH_TOKEN` and `GITHUB_TOKEN`) in Claude's environment, so every Bash
  child of Claude inherits them and can read them from its own environment or from
  `/proc/<ancestor>/environ`. The skill step sets `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1`, which
  strips the OAuth token and other credentials from Bash, hook and MCP subprocesses and gives
  Bash its own PID namespace, so an ancestor's `environ` is out of reach. The scrub keeps
  `GH_TOKEN` and `GITHUB_TOKEN`, so a subprocess still holds the activity's GitHub token: the
  job `GITHUB_TOKEN` in the read file, the effect-scoped App token in the write file. The action installs
  bubblewrap only for `allowed_non_write_users`, so run job step 9 installs it and fails the job
  when it is missing.
- Runner memory, with root. A hosted runner holds referenced secrets in the runner's memory.
  Removing sudo and docker access before the head checkout blocks the documented memory-dump
  route.

Both are mitigations for the OAuth token and the activity's own GitHub token. The App key is kept
off every runner by the broker instead: no workflow holds it.

The verdict is built from run job outputs some of which are set after head code ran (in the write
file, in the same job), so it is never trusted: its lane,
activity, gate stop reason and `head-sha` must match the values above or the check fails, and its
`dirty-tree` counts only as `true` (failure); its `patch` field only picks the title of a success. A missing verdict is a failure. A cancelled run job
posts neutral `superseded-sha` only when the PR's current head SHA is non-empty and differs from
the gated `head-sha`; a cancel with no newer head, such as a manual cancel or a timeout, is a
failure. In the read file the run result passed to `report-check-run` is the scan job's when the
broker check and the run job succeeded, so a failed scan fails the check. The full decision order
is in the report-check-run README.

## Secrets and the two files

GitHub scrubs secrets per workflow run, not per job: a caller and every reusable workflow it calls
are one run, and a secret referenced anywhere in that run must be assumed to reach every job in
it, the read job that runs PR head code included. Lane is the caller's file stem, so one lane
cannot be split across two caller files.

So no file of a run that reaches the read file may reference an App key. Code-owner review of
trust-root paths is off by owner decision; the controls a lane relies on instead, and the residual,
are in [Trust-root paths](README.md#trust-root-paths). With the broker,
the write file references no key either, so one caller may call both files: the read file's run
job sets its own permissions, without `id-token`, so its head code holds neither the key nor an
OIDC token. `id-token: write` in the read file is allowed only in its `broker-check` job, which
runs no head code, on its own runner. The run job lacks the permission, so its runner gets no OIDC
request URL.
[`scripts/check-read-caller-keys.sh`](../../../scripts/check-read-caller-keys.sh) enforces the
key rule in `lint-repo`: it parses every workflow, walks up from `pr-run-activity-read.yml` to every workflow
whose run can reach it (a job-level `uses:` in `./` or `melodic-software/claude-code-plugins/...@ref`
form, any case) and down through every reusable workflow those runs call. It fails when a file of
such a run names `AUTOMATION_LANES_APP_PRIVATE_KEY` or `app-private-key` in a key or value, has a
`private-key` key, passes `secrets: inherit`, or has a `${{ }}` expression, in a key, a value or a `#` line of
a `run:` block, whose `secrets` reference is not `secrets.<name>` with `<name>` on the allowlist
`claude_code_oauth_token`, `pr_unblock_claude_code_oauth_token`,
`issue_lane_claude_code_oauth_token`, `claude_api_key`, `pr_unblock_claude_api_key`, `github_token` (case-insensitive, `-` read as `_`); `toJSON(secrets)`,
`secrets[...]` and bare `secrets` fail. It also fails when any file of such a run sets
`permissions: write-all`, and, in the read file, when the top level is not `permissions: {}`, a
job has no permissions map, `id-token` is named anywhere outside the `broker-check` job, that job
is a reusable-workflow call or has no `steps`, or one of its `actions/checkout` steps has a `ref`
other than `${{ github.event.repository.default_branch }}` or a `with` key other than `ref`,
`path` and `persist-credentials`. One exception, the scan-carrier key: the read file declares
`scan-carrier-private-key` (required) and its `scan` job may hold one step that uses
`./.base/.github/actions/open-lane-output` with `private-key: ${{ secrets.scan-carrier-private-key }}`
exactly; a job that calls the read file passes it by name only,
`scan-carrier-private-key: ${{ secrets.SCAN_CARRIER_PRIVATE_KEY }}` in its `secrets` map; and only
the `scan` job may name an `environment`, `pr-pipeline-scan-carrier`. GitHub gives an environment
secret to a reusable workflow only when the caller passes it by name, and the value it then holds
is the environment's only in the job that names the environment
([Reuse workflows](https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows)).
Everywhere else in the run the name resolves to a repository or organization secret of that name,
so none may exist: [`scripts/check-scan-carrier-secret-shadow.sh`](../../../scripts/check-scan-carrier-secret-shadow.sh)
`<owner/repo>` lists both by name and exits 1 on one.

The read file stays alongside the broker: its guarantee, no key and no OIDC token in a job that
runs head code, is structural, while the write file's comes from the broker.

Residuals the split does not close:

- Head code in the read job can reach `ACTIONS_RUNTIME_TOKEN` through a process it leaves running.
  On `workflow_run` and `workflow_dispatch` that token's cache scope is the default branch.
- `collect-base-activity` and `setup-runner-isolation` load from the PR's base SHA, which can lag
  the default-branch tip, so a later hardening fix to either reaches a stale-base PR only after it
  is rebased.
- Listed bots other than the lanes bot, such as `claude[bot]` and `cursor[bot]`, can start a write
  activity. Its own pushes are denied, so the chain stops after one hop.

## The lane token broker

The write file's run job exchanges its GitHub OIDC token for the lane token at an Azure Function
that holds the App key as a sign-only Key Vault key. Why:
[ADR 0058](../../adr/0058-mint-lane-app-tokens-through-an-oidc-broker.md). Its code and Azure
resources live in `melodic-software/azure-iac`; its operations are not yet documented there
([Outside this repository](README.md#outside-this-repository)).

| Variable | Value |
|---|---|
| `LANES_BROKER_URL` | The token endpoint, `https://<host>/api/token`. Empty, or not `https://`, fails step 6 red |
| `LANES_BROKER_AUDIENCE` | The audience the job requests its OIDC token for, `melodic-lanes-token-broker`. Empty fails step 6 red |

Both are organization variables declared in github-iac
([ADR 0015](https://github.com/melodic-software/github-iac/blob/main/docs/adr/0015-oidc-token-broker-for-pr-pipeline-lane-app-tokens.md)).

The request is `POST <LANES_BROKER_URL>` with `Authorization: Bearer <OIDC token>` and the JSON
body `{"lane": "<lane>", "activity": "<activity>", "pr_number": <n>, "dispatcher_run_id": <id>}`;
`pr_number` is the gate's PR and is required on `workflow_dispatch` and `workflow_run`, except from
`intake-triage.yml`. An `issues` request, allowed from `work-resolve-issue.yml`, `work-unblock.yml`
and `intake-triage.yml`, sends `issue_number` (the `issue-number` input) instead, and neither of the
other two. From `work-resolve-issue.yml` its actor, the labeler, must be a listed human, or the
lanes App; from the other two a listed human. `work-unblock.yml` (also on its hourly `schedule`)
and `intake-triage.yml` (also on a `workflow_dispatch` that sends `issue_number`) run their minting
job in the caller file itself, get an issues-write grant only, and a re-run must be started by a
listed human. A dispatch `github-actions[bot]` sent (intake-reenter.yml, the triage sweep) mints
for `intake-triage.yml` only while the issue it names is open. The broker (azure-iac's `lanes-token-broker`) still re-checks the retired ratification marker for the App, so until it drops that check an App-labeled issue without the marker gets no token and the run fails closed. A `merge` request from `pr-merge.yml` names no pull request either; its actor must be a listed human, except on a `schedule` run on `refs/heads/main`, whose actor is whoever last edited the workflow file and is not checked. A re-run of a scheduled run must be started by a listed human. `dispatcher_run_id`, a positive
JSON integer, is the `dispatcher-run-id` input, sent only when set. The broker reads it only when
the OIDC actor is `github-actions[bot]`: such a run mints only when the `pr-unblock-dispatch.yml`
run it names passes the checks the trusted-trigger gate applies. That run must be on `main`,
started by a push, a schedule or a listed human, with a re-run attempt started by a listed human. Its head
must be an ancestor of the tip and no tag may be named `main`. This run must be a `pr-unblock.yml`
`workflow_dispatch` created between the dispatcher run's `run_started_at` and the earlier of its
`updated_at` and `run_started_at` plus 10 minutes. The dispatcher run must also hold an unexpired
`pr-unblock-dispatched-<ids>` artifact whose ids include this run's; the broker reads it once,
with no wait, since the trusted-trigger gate in step 3 has already waited for it. A
`pr-feedback-dispatch.yml` run started by `workflow_run` passes the same checks except the actor
check, with a `pr-feedback-dispatched-<upstream id>-<this run's id>` artifact whose upstream run is
a `pull_request` run of `pr-review-hosted.yml` or `pr-review-security-hosted.yml` in this
repository, started (and any re-run) by the lanes bot or a listed human, at the PR's current head,
or, with `expected_upstream_head` in the body, at that head when every commit from it to the PR's
current head is one GitHub signed for the lanes bot (committer `web-flow`, signature `valid`) after
this run was created, and the upstream run lists this pull request. The client
retries only a 503 `github-unavailable`, with backoff, or `github-rate-limited`, after its
`Retry-After`
([`request-lane-token`](../../../.github/actions/request-lane-token/README.md#what-it-does), step 3):
the broker reserves the job's `check_run_id` before it mints, so a request after a mint or a failed
mint (`mint-unavailable`) is denied `already-minted`, and a 200 lost in transit leaves a token
nobody revokes until it expires within the hour.

The broker derives the grant from the default-branch tip's config and `effect-grants.json`, never
from the request, and mints a token for this repository only, with exactly `contents`,
`pull_requests` and `issues`. A 200 returns `token`, `expires_at`, `repository_ids`, `permissions`,
`lane`, `activity`, `effect` and `mint_id`. The client fails red with `effect-mismatch`, after
revoking the token, unless `effect`, `permissions`, `lane`, `activity` and `repository_ids` equal
this job's own: the job runs actions from the PR's base SHA, which can resolve the activity
differently from the tip. Re-running after a rebase onto the tip clears it.

Any other answer fails step 6 red with `lane-token-denied`, the HTTP status and the broker's
reason; no response at all is `broker-unreachable`. Broker reasons:

| Status | Reason | Meaning |
|---|---|---|
| 400 | (none) | The body is not `{lane, activity, pr_number?, issue_number?, dispatcher_run_id?}` with valid names and positive integers, or `issue_number` is missing on `issues` or present off it |
| 403 | `invalid-token`, `wrong-audience` | The OIDC token does not verify, or is for another audience |
| 403 | `wrong-owner`, `repo-not-allowed`, `self-hosted-runner` | Not a melodic-software repository on the broker's allowlist, or not a GitHub-hosted runner |
| 403 | `event-not-allowed` | Not `pull_request` on `refs/pull/<n>/merge`, or `workflow_dispatch` or `workflow_run` on `refs/heads/main`, or `issues` on `refs/heads/main` from `work-resolve-issue.yml`, `work-unblock.yml` or `intake-triage.yml`, or `schedule` on `refs/heads/main` from `pr-merge.yml` or `work-unblock.yml` only |
| 403 | `workflow-not-allowed` | The job is not this repository's `pr-run-activity-write.yml`, or the caller is not a lane under `lanes:` in the tip's `pr-pipeline.yaml` |
| 403 | `workflow-modified` | The caller or `pr-run-activity-write.yml` differs from the default-branch tip (a report job, `work-resolve-issue` `report-outcome` or `pr-unblock` `report-escalation`, still mints when every main commit that changed the file is signed, GitHub-made, on a linear range and landed after run start, at most 50 minutes ago: [azure-iac#39](https://github.com/melodic-software/azure-iac/pull/39)) |
| 403 | `workflow-modified` | With `dispatcher_run_id`: the dispatcher workflow at the dispatcher run's head differs from the tip (same report-job exception) |
| 403 | `lane-mismatch` | The requested lane is not the caller's file stem |
| 403 | `activity-not-in-lane`, `slot-disabled`, `config-invalid`, `effect-forbidden-by-lane` | The tip config does not give this activity a write grant |
| 403 | `effect-read` | The activity is `read`; it belongs in the read file |
| 403 | `untrusted-actor`, `untrusted-author`, `bot-actor` | The actor, the PR author or a re-runner is not on the tip's trusted-actor list (a scheduled `pr-merge.yml` run has no actor check, and its re-runner must be a listed human; a scheduled `work-unblock.yml` run has no actor check either and skips the workflow's own closer check, so the broker alone gates its re-runs; a `github-actions[bot]` dispatch of `intake-triage.yml` has no actor check and needs its issue open, and its re-runner must be a listed human), or is the lanes bot |
| 403 | `untrusted-actor` | With `dispatcher_run_id` from `github-actions[bot]`: the dispatcher run or this run is missing or fails a dispatcher check above |
| 503 | `github-unavailable` | With `dispatcher_run_id`: a dispatcher, run, tag or compare read failed; nothing was minted |
| 403 | `pr-not-eligible` | The PR is not open, not from a branch of this repository, or does not target `main` |
| 403 | `default-branch-not-main` | The repository's default branch is not `main` |
| 403 | `kill-switch` | The organization's `CLAUDE_LANES_DISABLED` is not exactly `false`, a repository variable of that name exists (it would shadow the org value), or the repository's `CLAUDE_LANES_REPO_DISABLED` is absent or not exactly `false` |
| 403 | `already-minted` | This job already received its mint |
| 503 | `key-unavailable`, `github-unavailable`, `store-unavailable` | The broker could not sign, read GitHub, or record the mint; nothing was minted; the client retries `github-unavailable` |
| 503 | `github-rate-limited` | GitHub rate-limited the broker before it reserved the mint; `Retry-After` carries GitHub's wait (1-3600 s) and the body adds `limit`, `resource` and `retry_after`; retryable after that wait |
| 503 | `mint-unavailable` | The mint failed after the broker reserved the job's one mint; final, never retried |

A `kill-switch` denial is red, not neutral: step 3 already stopped the common case, so the denial
means the job's read and the broker's read of the switch disagreed.

### A workflow file the PR changes

A PR that changes the caller or `pr-run-activity-write.yml` gets `workflow-modified` on every write
lane run until it merges, and a re-run cannot help. On a `pull_request` run, which executes the
PR's copy of the workflow files, the run job passes `pr-workflow-change-ok`, and the step skips
instead of failing when all of these hold. A dispatched or issue run executes the default
branch's files, so its refusal means the default branch moved, and it stays red:

- the answer is 403 with reason `workflow-modified`;
- its detail is exactly `<file> differs from refs/heads/<default branch>`, `<file>` a
  `.github/workflows/` YAML file;
- GitHub's compare of the default branch with the gated head
  (`GET /repos/{owner}/{repo}/compare/<default branch>...<head SHA>`, read with the job's
  `GITHUB_TOKEN`, whose `contents: read` covers it) lists `<file>` as a changed `filename` or
  `previous_filename`.

The refusal does not say whether the PR or the default branch changed the file, so the compare,
which reads neither model output nor anything the PR's code writes, decides. A compare lists at
most 300 changed files; a file it does not list keeps the step red. The step then sets no token,
names the reason and file in the job summary, and sets the skip reason `workflow-modified`, so
every later step skips and the check is neutral. Any other answer, a detail that does not parse, a
file the compare does not list, and a compare that cannot be read stay red.

### The check endpoint

The read file's `broker-check` job sends `POST` to `LANES_BROKER_URL` with its final `/token`
replaced by `/check`, with `Authorization: Bearer <OIDC token>` and the body
`{"lane": "<lane>", "activity": "<activity>"}`; any other body field is a 400. The broker runs the
same token, claim, repository and kill-switch checks as a mint, with `pr-run-activity-read.yml` as
the job's workflow, and mints and reserves nothing, so re-running all jobs asks again. It answers 200
`{"decision": "allow", "lane", "activity"}`; the client fails red with `lane-check-denied` unless
`decision` is `allow` and `lane` and `activity` are its own. Any other status fails red with
`lane-check-denied`, the status and the broker's reason, from the table above minus the
mint-only rows; no response is `broker-unreachable`. The lanes bot is refused only on a mint, so
a `workflow_run` read lane still runs after a bot push. It checks no actor either, so a
`github-actions[bot]` dispatch is allowed here and judged by the run job's trigger gate (step 3).
The endpoint is served from
`melodic-software/azure-iac`; a read lane fails red until it is deployed.

[`scripts/check-app-key-references.sh`](../../../scripts/check-app-key-references.sh) fails
`lint-repo` when any file under `.github/workflows/` or `.github/actions/` names
`AUTOMATION_LANES_APP_PRIVATE_KEY`, `app-private-key` or `AUTOMATION_LANES_APP_CLIENT_ID`, so no
workflow holds the lanes key or mints as the lanes App outside the broker.

Step 14 revokes the token as soon as the activity is done. Residuals:

- Any step of the write job can request an OIDC token for another audience, so whatever the
  claude-code-action process runs, its MCP servers included, can reach any relying party that
  trusts this organization's tokens. The broker refuses a second mint for the job.
- The job runs trusted actions from the base SHA while the grant comes from the tip; the effect
  check fails a skewed job red rather than running it.

## Issue mode

The `issue-number` input of both files runs a lane on an issue instead of a PR. Its one caller is
[`work-resolve-issue.yml`](../../../.github/workflows/work-resolve-issue.yml): the `agent-ready`
label on an issue runs `resolve-issue` (`/work-items:work --issue <n> --ci`) in the read file
in [patch output mode](#patch-output-mode), so the model job holds no write token, then `apply-issue-patch` and
`report-outcome` (scripts) in the write file. The write file refuses an issue skill red
(`issue-skill-in-write-runner`). The model job's run job holds `contents: read` and
`pull-requests: read` only; `claude-code-action` needs a GitHub token and exports it to the
CLI's environment, so that job's read-only `GITHUB_TOKEN` is the one token it holds. Before any job that
gets the lane's Claude credential, the caller's `admit` job runs `check-trusted-trigger` from the
default branch tip, with `contents: read` and no secret (`require-pr: false`, `require-kind:
human`, `app-label: agent-ready`, the lanes App id): `pick-slot` and `resolve-issue` need it and
run only on its `proceed` output `true`, so an unlisted account's label on an issue anyone can
open starts no credentialed job. The read file's own trigger gate checks the same again. At most three `resolve-issue` jobs run at once:
a `pick-slot` job takes the issue number modulo `SLOTS` (3), and `resolve-issue` joins the
`work-resolve-issue-slot-<n>` concurrency group with `queue: max`, so a burst of admissions waits
in line, holding no runner, instead of spending the lanes App's hourly API quota at once.
`report-outcome` takes no slot; `apply-issue-patch` joins `work-resolve-issue-write-<n>` with
`queue: max`. A waiting run keeps the workflow files of its label event, so when a change to the
caller or the write file merges while it waits, the broker would refuse the apply job's mint
as `workflow-modified`. Before any model turn, the read file's `workflow-current` step compares
the caller's and the write file's blobs at `github.workflow_sha` with the default branch checkout, the broker's
rule. On a difference it sets `stale=true` and ends green: the `Stop on stale workflow files`
step runs, `go` is `false`, so no model turn, no outcome marker and no caller job follows, and
the run counts as no failure. work-unblock's hourly sweep finds that step in the run's job
listing and re-fires the issue on main's files, once per version of the two files. An issue that
`pick-slot`'s resolve skips on its dimensions (`split-required`, `research-first` or
`probe-first`) takes no model turn and leaves no outcome, so the caller's `report-skip` job,
which needs `admit` and `pick-slot` only, runs `report-outcome` in the write file with
`dimension-skip`: it labels the issue `needs-human`, removes `agent-ready`, and comments the next
step under the escalation marker and an `outcome=<reason>` marker. What changes from the PR flow:

- Step 1 also fails red unless the event is `issues`, `issue-number` is the event's issue,
  `trusted-base` is `default-tip`, and `pr-number` and `dispatcher-run-id` are empty; in the read
  file unless `fallback` is empty too, and after `resolve-config` unless the activity's
  `applied-by` names a patch; and in the write file unless a non-empty `reuse-branch` is
  this issue's `work-resolve-issue/issue-<n>-<run id>-<attempt>` and `patch-base-sha` and
  `patch-resume-tip` are commit ids or empty.
- The trigger gate runs with `require-pr: false` and `require-kind: human`: the account that
  applied the label, and any re-runner, must be listed as a human. The one exception is the
  caller's `app-label` (`agent-ready` for `work-resolve-issue.yml`): the lanes App may apply it,
  and the label alone admits the issue; the re-runner is then the App or a listed human. The
  App's other labels never start a run, and no step of the lane adds `agent-ready`. `check-trusted-base` trusts the
  default branch tip, and that commit is the head the job checks out.
- `resolve-config` reads the issue's labels now, for the hold labels. The read file passes
  `applied-by-supported: patch work-outcome`. The write file's token request sends
  `issue_number`.
- Each issue is worked once. In a skill run, the `issue-prior` step (`report-outcome.mjs
  --find-prior`) runs after `resolve-config` and before any model turn, with the job's read-only
  `GITHUB_TOKEN`, and reads the issue's lane branches (`git/matching-refs` on
  `work-resolve-issue/issue-<n>-`), their PRs, their tip commits, their commits ahead of the
  default branch, the issue's open closing PRs and the lanes App's outcome markers on it. It skips
  the run `not-applicable`, with no model and no comment, when a lanes-App PR from a
  lane branch is open, or when an open PR in this repository closes the issue and the lanes App or
  a listed human (`trusted-actors.json`) opened it; anyone's other closing PR is ignored. It also
  skips `not-applicable` and sets the `reuse-branch` output to the first lane branch, newest run
  and attempt first, that has commits ahead, a tip commit GitHub verified whose author is the
  lanes App bot and whose committer is `web-flow`, as the App's API commits are (a branch name
  alone proves nothing, and anyone can sign a commit naming the App as author), no lanes-App PR in any state (a
  closed one was rejected or merged) and no lanes-App outcome marker for its run: the work was
  made and its report never posted. Branches that fail any of these are passed over, not stopped at, so an older unreported
  branch is reused even when a newer branch's run was handed back or limit-stopped. A branch whose
  own run posted a hand-back or limited marker is never reused. With nothing to reuse, when the
  newest lanes-App outcome marker is `turn-cap`, `stopped`, `limited` or `funding` (passing over
  those markers that carry `branch=resumed`, left by a resumed run that kept no branch of its own)
  and names a run whose newest lane branch passes the same commit, tip and PR checks
  with every commit ahead of the default branch verified, authored by the lanes App and committed
  by `web-flow` (a listing the compare cuts short resumes nothing) and no commit behind the default
  branch, the run resumes it; when that run's branch is gone, fails a check or is behind the
  default branch (its stale base would fail the runner's whole-branch checks), the run starts from
  the default branch under a new lane branch, never from an older run's branch, and leaves the old
  branch as it is: `issue-prior`
  outputs `resume-branch`, `resume-tip` (the tip it read) and `resume-cause`, and the job checks
  out that tip, so its patch is made there instead of on the default branch tip. Any failed
  read, or an answer of the wrong shape, fails the step, so no model runs.
- Before the skill, the runner writes the issue's number, title, body and labels to `issue.json`
  in the skill's scratch directory, with only the comments `select-trusted-text`'s author and edit
  rules keep (`write-issue.mjs`), oldest first, so a listed maintainer's recorded decision reaches
  the skill. The lanes App's own comments are left out, a listed human's comment whose first line
  is `**Decision recorded.**` is marked `decision: true`, and comments other than decisions are
  capped at the newest 20. The issue is frozen at the `labeled` event that started this run (the
  labeler's newest such event no later than the payload's issue `updated_at`; a later label event
  by anyone never moves it, and the lanes App's remove-and-re-add after a limit stop anchors at
  the label it restarted): a
  comment created or edited after that is left out, and a title or body changed since fails the
  step, so text edited after admission does not steer the run. On a resume, `issue.json` also
  carries `resume`: the branch, the cause, the tip, the subject of each commit ahead of the trusted
  base and each changed file with its line counts, from `GET /compare`. The skill leaves its
  change uncommitted; the read file collects it as a patch against the commit it checked out
  ([Patch output mode](#patch-output-mode)), also after a failed skill step (a turn cap or a usage
  limit), so partial work reaches a branch a resumed run continues. A failed skill step fails the
  job unless it is only the turn cap on a successful result. The skill's `work-outcome.json` and
  the runner's `lane.json` (no branch yet, and on a resume the resumed branch) are uploaded as the
  `work-outcome-<n>` artifact, and the job output `issue-run-started` is `true` once the run chose
  to run the skill, before any model turn. The read file also outputs `base-sha` and
  `resume-tip`, the commit the patch was made on.
- `apply-issue-patch` runs when the patch is `written` ([prepare: apply-patch](#prepare-apply-patch),
  issue target): it makes `<lane>/issue-<n>-<run id>-<attempt>` (the attempt the patch's), with one
  commit, at `patch-resume-tip` or else `patch-base-sha`, which must be on the default branch,
  writes that branch into `lane.json` and uploads `work-outcome-<n>` again. An empty patch makes
  no branch, as a run with no commit kept none.
- `report-outcome` downloads that artifact and takes `apply-issue-patch`'s escalation reason. A `done` run whose
  patch it refused (`patch-protected-path`, `patch-invalid` or `patch-not-applied`) hands the issue to a person naming
  that reason, and opens no PR, from a resumed branch either. A `done` run that committed nothing on a resume opens its PR from the
  resumed branch only when `run-checks` checked that whole branch (it checks one only when `lane.json`'s `resume` equals
  the `resume-branch` `issue-prior` output), every check passed and at least one ran, the branch is still at the tip
  checked (the compare reads that SHA, and a new PR whose head is another commit is closed), and every commit on it ahead of the default branch is verified, authored by the lanes App
  and committed by `web-flow`; the PR body's Verification section says so. Otherwise it hands the issue to a person,
  naming the resumed branch. On `done` it opens a ready (not draft) PR from the branch whose
  body starts `Closes #<n>` (or `Refs: #<n>` when the outcome sets
  `"link": "refs"` because a recorded decision keeps the issue open), puts no label on it (the work class stays on the issue), and adds
  `Hold: a human merges this` for untrusted-provenance work, for a diff that
  touches a path the merge lane refuses (`merge.diff-check.denied-paths`, read from the run's
  resolved config; unreadable holds every PR), or, while some path is denied, for one too large
  for the compare listing to show whole. It adds the same line when the issue carries `merge: human` whose newest `labeled`
  event is a listed human's or the lanes App's, or cannot be read, and never for anyone else's.
  The run's own summary is quoted with issue references broken, so squash-merging the PR closes only `#<n>`. On `pushback` or `stopped`, and when the outcome file is missing
  or invalid, it labels the issue with the human-gated role label, removes `agent-ready`, and
  comments why. Every comment that adds the human-gated label opens with the attended
  queue's escalation marker `<!-- work-items:escalation lane=work-resolve-issue kind=escalated -->`,
  so `/work-items:attend-queue` lists the issue, and then the outcome marker
  `<!-- work-resolve-issue outcome=<exit> run=<run id> -->`, which `issue-prior` matches to the
  branches of that run (a marker naming no run covers every branch whose tip is older than it).
  Comments that keep `agent-ready` open with the outcome marker alone.
  A run that wrote no readable outcome file and whose lane record has class `max-turns` is a
  turn-cap stop: the comment's outcome marker is `<!-- work-resolve-issue outcome=turn-cap cap=<n> run=<run id> -->`
  and says "turn cap <n> reached" and names the branch. While the turn-cap markers since a person
  listed human last added `agent-ready` are fewer than `limits.turn-cap-restarts`, it keeps `agent-ready` and
  adds no label, and the work-unblock sweep restarts the issue as it does after a limit stop;
  otherwise it hands back like `stopped`. `lane.json` carries the run's `max-turns` for the cap,
  and the `pipeline/resolve-issue` status reads "Stopped at the turn cap.". A run that exited
  non-zero, wrote no readable outcome file, and whose result carries `api_error_status` 400 with
  "regain access on <date>" (a spend limit or no credit) or 401 (a disabled key) is a funding
  stop, whatever its class or turn cap (`lane.json` carries `failed`, `api-error-status` and
  `error-text`, read by the `Read the run's API error` step from the execution file's result
  fields): the comment opens with `<!-- work-resolve-issue outcome=funding resets=<date> run=<run id> -->`
  (no `resets` when no date is readable), it keeps `agent-ready` and adds no label, it counts
  toward `limits.limit-stops-per-issue` with limit stops (not `turn-cap-restarts`), and work-unblock restarts the issue after the date, held
  within `limits.reset-clamp-min` and `reset-clamp-max`; with no date a person restarts it. The
  status reads "Stopped on the lane's funding.". The next run resumes a funding-stopped run's
  branch like a `limited` one's.
- On a reuse the skill run runs no model, and the [summary job](#the-summary-job) has a read-only
  model pass describe the branch from its diff and the issue, as the `reuse-summary-<n>` artifact.
- A non-empty `reuse-branch` also starts `report-outcome` and `report-statuses`, and reaches the
  script as `REUSE_BRANCH`; `report-outcome` also downloads `reuse-summary-<n>`. The downloaded
  outcome counts only when its `lane.json` names that branch (a re-run attempt of the run that
  made it). Otherwise, and when that outcome cannot be read, `report-outcome` opens a held PR from
  the branch, ignoring any limit record: the earlier run's artifact would need `actions: read`,
  which no lane token holds. When the summary names this issue and branch, the branch is still at
  its tip, and its `summary` is not empty, the PR carries the summary and its changes, quoted as
  model text. Otherwise the PR has fixed text naming the earlier run and none of the model's text.
  Either way its Fix section lists the files `GET /compare` names, those on a
  `merge.diff-check.denied-paths` glob marked and listed first; a failed compare says the list is
  unavailable and still opens the PR.
  The summary never reaches a status or the hold line, which every reuse PR carries:
  `report-statuses` then posts only `pipeline/report-outcome` on that branch, so any statuses the
  earlier run posted on the same head stand.
- No check run is posted: there is no PR head. The lane's `report-statuses` job (in
  `work-resolve-issue.yml`, the lane's only `statuses: write`, on its own `GITHUB_TOKEN`) posts a
  `pipeline/<activity>` commit status on the lane branch's head for `resolve-issue` and
  `report-outcome` (from their job results) and for each prep step the run reports in
  `work-outcome.json`'s `steps` (`review`, `verify`, `checks`). On `done`, a prep step the run
  never reported posts `error`; one it reported `skipped` posts nothing. No step is skipped on a
  `pipeline/*` success, and no required check names one, but a `failure` or `error` status
  counts as a failing check, so it holds the pr-merge gate (fail closed). Descriptions are fixed text.

## Runs that post no check

- An issue-mode run (above): the report job's `if:` skips it.

- A fork PR, whose read-only `GITHUB_TOKEN` cannot write checks: the report job's `if:` skips it.
- A `pull_request` event sent by the lanes App (`AUTOMATION_LANES_APP_SENDER_ID`): both jobs skip.
- Any event other than `pull_request` whose run job gated no head SHA, including a read run whose
  `broker-check` job failed: the fallback there would be `github.sha`, the dispatch ref, not the
  PR's commit. The report job notes it in its step summary.

## Bounds

On `pull_request`, the caller and the reusable workflow run from the PR's merge commit: a `./` reusable
workflow comes from the same commit as its caller. A PR that edits `.github/workflows/**`
therefore controls both, and the default-branch base reads above guard only against changes
outside `.github/workflows`. The real bound is who can push `.github/workflows`: kyle-sexton, and Apps
holding the `workflows` permission, such as the standards sync bot.
