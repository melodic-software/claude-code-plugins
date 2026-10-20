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
| `dispatcher-run-id` | `''` | The `pr-unblock-dispatch.yml` run that sent a `github-actions[bot]` `workflow_dispatch` (run job step 3); in the write file also a `pr-feedback-dispatch.yml` run |
| `trusted-base` | `pr-base` | `pr-base` trusts the PR's base SHA, `default-tip` the default branch tip (run job step 4) |
| `escalation-reason` | `''` | Write file only: the escalating run's `escalation-reason` output, for a `report-escalation` script; anything outside the enum fails step 1 |
| `review-replies` | `false` | Write file only: for the reply script of a [`prepare: review-threads`](#prepare-review-threads) round, download the model job's replies |
| `review-run-sha256` | `''` | Write file only: with `review-replies`, the model job's `feedback-run-sha256` output |
| `expected-upstream-head` | `''` | Write file only: for a job after pr-unblock's model job on a `pr-feedback-dispatch.yml` dispatch, that job's `head-sha` output, passed to the gate and the broker (step 3) |
| `review-run-attempt` | `''` | Write file only: with `review-replies`, the model job's `feedback-run-attempt` output, which names the replies artifact so a re-run of the reply job alone still finds it |
| `output-mode` | `clean-tree` | Read file only: `clean-tree` fails a run that leaves the tree changed; `patch` uploads the change instead ([Patch output mode](#patch-output-mode)); any other value fails red before the head checkout |
| `ci-context-attempt`, `ci-context-sha256` | `''` | Read file only: for [`prepare: ci-context`](#prepare-ci-context), the attempt naming the `ci-context-<attempt>` artifact and its file's SHA-256 |
| `patch-state`, `patch-sha256`, `patch-attempt`, `patch-head-sha`, `patch-activity`, `reply-attempt` | `''` | Write file only: for [`prepare: apply-patch`](#prepare-apply-patch), the read model job's outputs and its activity name |

The write file has six `workflow_call` outputs. `head-sha` is the PR head the gate passed, before
any push of the run; `issue-run-started` is described below; `feedback-run-sha256` and
`feedback-run-attempt` are described with
[`prepare: review-threads`](#prepare-review-threads). `escalation-reason` is empty, or why a
[`prepare: merge-base`](#prepare-merge-base) activity, a `prepare: review-threads` activity before
any model turn, or its reply script handed the PR to a person. `feedback-round` is `true` once a
`prepare: review-threads` skill ran, so its reply job must run.

The read file has five `workflow_call` outputs: `head-sha`, as in the write file,
`patch-state`, `patch-sha256` and `patch-attempt`, described with
[Patch output mode](#patch-output-mode), and `reply-attempt`, the attempt in the name of the
`skill-reply-<lane>-<activity>-<attempt>` artifact when the skill ran.

Secrets are passed by name, never `inherit`: `claude-code-oauth-token` (skill activities, both
files) is the only one. Variables: `CLAUDE_LANES_DISABLED` and `CLAUDE_LANES_REPO_DISABLED` (the org
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
   checked out; the check is neutral, with one exception. Both files pass
   `github.triggering_actor`, so a re-run started by an account not on the list, by a denied
   account, or with no triggering actor stops with `untrusted-rerunner`, and that check is a
   failure: a re-run cannot turn an earlier red check on the same SHA neutral. The write file also
   denies `AUTOMATION_LANES_APP_SENDER_ID`, so the lanes App bot as sender or `workflow_run` actor
   stops it with `bot-actor` (neutral) and one write activity never chains into the next. The read
   file denies nothing, so a `workflow_run` read lane still runs after a bot push; the bot's own
   `pull_request` events are skipped by the job `if:` in both files. Both files pass their
   `dispatcher-run-id` input with `dispatcher-workflow: .github/workflows/pr-unblock-dispatch.yml`
   and `dispatched-workflow: .github/workflows/pr-unblock.yml`, so a `workflow_dispatch` sent by
   `github-actions[bot]` proceeds only when it names a run of that dispatcher on the default branch
   whose window holds this run's creation and whose `pr-unblock-dispatched-<id>[-<id>...]`
   artifact lists this run's id, and this run is `pr-unblock.yml`; every other bot-sent dispatch
   stops with `untrusted-actor`. The write file alone also passes
   `run-dispatcher-workflow: .github/workflows/pr-feedback-dispatch.yml` with the two review
   workflows as `run-dispatcher-upstreams`: a run of that dispatcher, started by `workflow_run`,
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
   is the `base-sha` output either way, and the merge's second parent in
   [`prepare: merge-base`](#prepare-merge-base).
5. `resolve-config`, with the gated `head-sha` and `prepare-supported: true`; the read file also
   passes `applied-by-supported: patch` ([Patch output mode](#patch-output-mode)). The read file then
   fails red for any `prepare` but [`ci-context`](#prepare-ci-context), and for `ci-context`
   without `output-mode: patch`.
   An invalid config fails the step red and the check is a failure, never a skip. A config skip
   (`disabled-by-config`, `not-applicable-paths`, `not-applicable`, `awaiting-human`,
   `prerequisite-missing`) mints nothing. With a valid config, the read file fails red with
   `effect-not-read` unless the effect is `read`, and the write file fails red with `effect-read`
   when it is, whether or not the activity applies. For a `mutate-branch` activity the write file
   then re-reads the PR branch from `GET git/ref/heads/<head ref>` (`GET /pulls` can lag a push);
   when it no longer points at the gated head the activity skips with `superseded-sha`, mints
   nothing and runs no model turn. Other effects never write the branch and keep the gated head.
   In issue mode a skill run's `issue-prior` step then checks for an earlier run's work
   ([Issue mode](#issue-mode)); when it reuses a branch it skips the rest of the run, mints
   nothing and runs no model turn in this job, and the [summary job](#the-summary-job) runs next.
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
   `.claude-plugin/` to `$RUNNER_TEMP/base-marketplace`. For `prepare: merge-base` the write file
   also copies the base's `.github/scripts/merge-base/` scripts and
   `plugins/source-control/scripts/resolve-version-bump-conflict.sh` to
   `$RUNNER_TEMP/merge-base-bin`, recording each copy's SHA-256 as a step output, and reads
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
    history for `prepare: merge-base`, else depth 1), then fails red unless `git rev-parse HEAD`
    equals that SHA. This replaces `.base`.
12. For a skill, sets up Python from the copied `.python-version` and runs the copied
    `setup-env.sh`, which installs the hash-pinned wheels in `.github/requirements-ci.txt` into a
    venv under `$RUNNER_TEMP` and the locked Node packages, puts both on `PATH`, and copies the
    `node_modules` trees into the checkout. Both files install from the base copies in
    `$RUNNER_TEMP/setup-env`, so no head code runs before the skill's own Bash; a read skill that
    needs the head's own packages runs `npm ci` there.
    Then runs the activity (below) and, in the read file, records whether the tree is dirty, or
    in [patch output mode](#patch-output-mode) collects the change as a patch.
13. Writes `verdict.json` with `jq` (`if: always()`) and uploads it as
    `verdict-<lane>-<activity>-<run_attempt>`, unique per activity and attempt.
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
`act-outcome`, plus, in the write file, `head-ref`, `merge-state`, `escalation-reason` and
`run-failure`, the reason the lane-token step failed with, from the base's `request-lane-token`. Every
one is computed by a runner step, never read from model text. All but `act-outcome`,
`merge-state` and `escalation-reason` are outputs of steps that ran before any head code:
`gate-reason` is the kill switch's reason if it stopped, else the trigger's if it stopped, else
empty; `head-sha` and `head-ref` are the trigger gate's; `base-sha` is set only by step 4, so it
is always on the default branch. `merge-state` and a pre-model `escalation-reason` come from the
prepare step, before any model turn; a post-model `escalation-reason` comes from `post.sh` after
it, and a forged one can only hand the PR to a person. `act-outcome` is the activity step's
outcome, except that a skill step claude-code-action failed only because a `success` result went
over `--max-turns` counts as succeeded. That holds only when the execution file's last result
message has subtype `success`, `is_error` false and `num_turns` over the cap; any other failure,
or a missing or unreadable execution file, still fails the job. A skill whose step succeeded is a
failure when it took no model turn, when it is a gate skill and the verdict check (below) fails,
when its commits could not be moved onto the PR branch, or when its merge commit failed or was not
made; in `prepare: merge-base`, a clean merge that skipped the skill is a success once its commit
is promoted. These checks are steps that run after the skill.

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
sentence says to leave every change uncommitted for the runner to collect. A `prepare: merge-base` skill
gets neither tool nor those sentences: it stages its resolution and the runner commits
([below](#prepare-merge-base)). Under `--permission-mode dontAsk` a skill's own `allowed-tools`
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
itself, or hand the run a power it may hold. `resolve-issue` also lists skill-quality's
`check-evals-quality.sh` (bash and jq over `evals.json` files) and `check-skill.sh`, which runs each
checked skill's `scripts/*.test.sh` and the checkout's markdownlint: checkout code with the network
open and the token readable from an ancestor process, the power `scripts/run-test-file.sh` has. It lists two that limit themselves, each refusing (exit 2) an argument that is absolute,
has a `..` segment, starts with `-` or `:`, or resolves through a link to outside the checkout, including
a path that does not exist yet (`scripts/lib/checkout-path.sh`). `scripts/run-test-file.sh` takes
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
`WebFetch` and
`WebSearch` stay off (`--disallowedTools`) unless the activity sets `web-access`. With it on, the
runner allows `WebSearch`, one `WebFetch(domain:<host>)` rule per listed domain
(`WebFetch(domain:*)` for `any`), and `Skill` for `/discovery:read-docs`, `/discovery:research`,
`/knowledge:docpage-digest` and `/knowledge:map-corpus`; installs the `discovery` and `knowledge`
plugins from the base marketplace copy beside the skill's own; and says so in
`--append-system-prompt`. For `any` only, it also copies `fetch-docs.sh`, `docs-cache.sh` and
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
tip last: `do-not-merge`, the base's human-gated role label (left out only when the
[review-threads](#prepare-review-threads) select step reported a write-access fix request), a label in the activity's
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

The job's step summary shows the skill's final reply (at most 4000 characters, backticks
neutralized) for audit. It is model output, printed as data. The same text is uploaded as the
artifact `skill-reply-<lane>-<activity>-<run_attempt>` (7-day retention) whenever the skill step
ran, as audit evidence, because the REST API cannot read step summaries. Nothing in the workflow
reads that artifact.

A slash command whose expansion fails ends with a `success` result and no model turn: claude-code-action
reports success, but the skill did nothing. A skill pre-compute (`` !`...` ``) line with a command
that matches no `allowed-tools` grant does this under `--permission-mode dontAsk`. A step after the
skill reads the execution file and fails when `num_turns` is 0 or `modelUsage` is empty. It writes
`subtype`, `is_error`, `num_turns`, `duration_ms`, the model names, any `<local-command-stderr>`
text, and in the write file `denied`, each command the permission mode denied cut to 300
characters (lane token cut out of both) to the step summary and to `act-turns.json` in the same artifact. The
full execution file is not uploaded: it holds head text and tool output.

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

Read file only, chosen by the caller's `output-mode: patch` input. It lets an activity run head
code with no write token and hand its change to a separate job that holds one. The read file
collects the change as a patch only when the caller passes `output-mode: patch`. The config's
`applied-by.patch` is to state the same fact and name the `prepare: apply-patch` script that
applies it ([README.md, Activities](README.md#activities)); no activity sets `applied-by` today.
The read file passes
`applied-by-supported: patch` to `resolve-config`, so a leaf whose `applied-by` sets any other
key fails red before the head checkout. A `gating: gate` leaf cannot set `applied-by`. The steps:

1. Before the head checkout, the base's
   [`collect-patch.sh`](../../../.github/scripts/read-patch/collect-patch.sh) is copied to
   `$RUNNER_TEMP/read-patch`.
2. After an act step that succeeded, in place of the clean-tree check, the collector writes
   everything the activity changed against the gated head (committed, staged, unstaged and
   untracked, ignored files aside) as one `git diff --binary` patch, through a scratch index, with
   every diff option that changes the patch's form passed explicitly. A failed, cancelled or
   turnless act step collects nothing and the check fails as usual.
3. A non-empty patch is uploaded as the artifact `patch-<lane>-<activity>-<run attempt>`, holding
   one file, `patch.diff` (7-day retention). The run's `patch-state` output is then `written`,
   `patch-sha256` is that file's SHA-256 and `patch-attempt` is the attempt in the artifact's name.
   No change is `patch-state` `empty`, with no artifact and the other two empty. A run that
   collected no patch leaves all three empty.
4. The verdict's `patch` field repeats `patch-state` (`written`, `empty`, or `null` when the run
   collected no patch), and the check is
   `success` titled `Passed: patch written` or `Passed: no changes`.

Head code ran in the job that writes the patch, its SHA-256 and the verdict, and could have
replaced the collector copy or the patch, so none of them is trusted: the SHA-256 only binds the
artifact to this run's output. A job that applies the patch downloads it by `patch-attempt`, so a
re-run of that job alone still finds it. Before applying it, that job must check that:

- the artifact holds exactly `patch.diff`, a regular file within a size limit the job names, whose
  SHA-256 is `patch-sha256`;
- the PR head is still `head-sha`;
- `git apply --check` with `--index` or `--cached`, and no `--unsafe-paths` or `--directory`,
  succeeds on a fresh checkout of `head-sha`;
- no entry has mode `120000` (symlink) or `160000` (gitlink), and no path is under a protected
  path such as `.github/**`, `.gitattributes`, `.gitmodules` or `.husky`.

It then commits on `head-sha` and moves the PR branch without force, so a head that moved after
the check refuses the push. A forged `empty` can only hand the PR to a person; a forged `written`
meets those checks. A `gating: gate` activity fails red in patch mode before the head checkout: a
gate must judge the head it is posted on, unchanged.

### prepare: merge-base

A write skill leaf whose config sets `prepare: merge-base` (resolve-config's `prepare` output) is
run around a merge of the trusted base (step 4's `base-sha`) into the gated head. The scripts are
the base's copies from step 8, each checked against its recorded SHA-256 before it runs:

1. After the head checkout and before any model turn, `prepare.sh` runs with the gated head, the
   trusted base, the base's version-bump script and an output directory under `$RUNNER_TEMP`. The
   step's `env:` holds the lanes bot identity (`melodic-automation-lanes[bot]` and its noreply
   address), which a `--no-commit` merge needs and the repeat cap counts by, and `loop.no-progress`
   as `LOOP_NO_PROGRESS`. It escalates `repeat-cap` before merging, runs
   `git merge --no-commit --no-ff <trusted base>` and the version-bump script, snapshots the
   index, and escalates `protected-path-conflict` (a conflicted path under `.github/workflows/` or
   a path claude-code-action restores) or `unresolved-conflict` (a conflict with no markers to
   resolve). Its `merge-state` output is `clean`, `conflicted` or `escalate`; an escalation skips
   with `awaiting-human`.
2. The skill runs only when `merge-state` is `conflicted`, without the commit tool. A clean merge
   takes no model turn.
3. `post.sh` runs after a clean merge, or after the skill and its model-turn check succeeded, with
   prepare's hashes. It restores `.git/config` and `.git/info/attributes`, repairs the paths
   claude-code-action reset, and escalates `unresolved-conflict` (an unmerged entry, or conflict
   markers in a staged resolution) or `workflow-staged` (a `.github/workflows/` index entry changed
   since the snapshot, or differs from the gated head, as a workflow change merged in from the base
   does, unless the staged `.github/workflows/` entries are exactly the trusted base's (mode and
   blob), no head workflow is dropped, and the PR's own diff against every merge base touches no
   workflow) or `unexpected-path-staged` (an index entry added,
   changed or removed at a path the merge did not leave conflicted, as `git add -A` would stage);
   otherwise it writes the index as a tree.
4. With no escalation reason and a tree, a pinned `github-script` step commits through the Git
   Data API: it fails unless the lane branch is still at the gated head, uploads only the blobs
   `tree-entries.sh` flags (logging `created <k> blobs`), builds the tree on the gated head's tree
   and fails unless it hashes to `post.sh`'s tree, re-reads the PR's labels with the job's
   `GITHUB_TOKEN` and stops uncommitted (`awaiting-human`) when `do-not-merge`, the base's
   human-gated role label or a `labels-absent` label is on the PR, then creates the commit
   `Merge <default branch> into <head ref>` with trailer
   `Lane-Activity: pr-unblock/resolve-conflicts`, parents `[gated head, trusted base]` and no
   author, committer or signature, so GitHub signs it as the App, and moves the lane branch to it.
   The promote step then fast-forwards the PR branch only when the lane branch holds that step's
   own commit and `git/ref heads/<head ref>` is still at the gated head, and confirms the move by
   reading that ref again.

The merge scripts, `tree-entries.sh` and the commit step's `git` run with workflow commands
stopped (`::stop-commands::<random>`), since git's output can name head files, and with
`GIT_NO_REPLACE_OBJECTS=1`; the commit step runs `/usr/bin/git` and `/usr/bin/bash` under an
allowlisted environment. The kill switch (step 3) stops new runs only; a run already past it
stops for a hold only at the commit step's label re-read and the promote step's label and draft
re-read.

The run's `escalation-reason` output is prepare's or `post.sh`'s reason, one of
`protected-path-conflict`, `workflow-staged`, `unexpected-path-staged`, `repeat-cap` or
`unresolved-conflict`; a caller
passes it to its `report-escalation` job as that job's `escalation-reason` input. Every path and
its check:

| Path | act-outcome | skip reason | escalation-reason | Check |
|---|---|---|---|---|
| Head moved before mint | skipped | `superseded-sha` | empty | neutral |
| Broker refused a workflow file the PR changes | skipped | `workflow-modified` | empty | neutral |
| Hold label present | skipped | `awaiting-human` | empty | neutral |
| Pre-model escalation | skipped | `awaiting-human` | `protected-path-conflict` / `repeat-cap` / `unresolved-conflict` (no markers) | neutral |
| Clean merge, no model turn, committed, promoted | success | none | empty | success |
| Clean merge, `post.sh` exits non-zero | failure | none | empty | failure |
| Hold label added during the run, found before the commit | success | `awaiting-human` | empty | neutral |
| Hold label or draft set during the run, found before the promote | success | `awaiting-human` | empty | neutral |
| Model left a conflict | success | `awaiting-human` | `unresolved-conflict` | neutral |
| Model staged, or the merge brought in, a `.github/workflows/` change that is not the trusted base's own | success | `awaiting-human` | `workflow-staged` | neutral |
| Model staged a change to a path that did not conflict | success | `awaiting-human` | `unexpected-path-staged` | neutral |
| Resolved, committed, promoted | success | none | empty | success |
| Commit step fails or lane branch moved | failure | none | empty | failure |
| PR branch moved during run (promote) | failure | none | empty | failure |
| Conflicted but no model turn | failure | none | empty | failure |
| A prepare step fails | skipped | none | empty | failure (run job failed) |
| A post-skill step fails | success | none | empty | failure (run job failed) |

Residual: when every staged `.github/workflows/` entry is the trusted base's own and the PR
changes no workflow, the merge is committed and pushed. GitHub did not refuse that shape for the
App's missing `workflows` permission: sandbox probe run 38148710292 pushed it by all three methods.
A merged workflow blob that is on no branch was refused (`POST /git/trees` 403 in run
39066232629), and still escalates.

### prepare: review-threads

A round of review-thread answers is two jobs, since the broker mints one token per job and a token
with both `contents: write` and `pull-requests: write` can enqueue a PR. The model job is a
`mutate-branch` skill leaf whose config sets `prepare: review-threads`: it pushes the fixes and
posts nothing. The reply job is a `publish-artifact` script leaf with no model, called with
`review-replies: true`: it posts the model's replies exactly as written, or none. The scripts are
the base's `.github/scripts/pr-unblock/address-feedback.mjs` and `publish-feedback.mjs`.

1. After `resolve-config` and before the mint, the model job runs `address-feedback.mjs select`
   with the job's `GITHUB_TOKEN`. It keeps each unresolved thread whose first comment's review
   the reviewer bot (`claude[bot]` in the base's trusted-actors list, by id) submitted on a head
   that a `claude-lane-reviewed-head` marker from `github-actions[bot]` names, when every
   comment is the reviewer bot's; or the lanes App never commented and one comment is a fix
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
   reports `fix-requested=true`, which lifts only the human-gated hold for the run. No kept thread
   skips `not-applicable`, or `awaiting-human` on such a PR. A PR diff touching
   `.github/**` escalates `feedback-protected-path`, and `loop.review-rounds` earlier rounds
   escalate `feedback-round-cap`: the larger of the round markers the lanes App posted and the PR
   commits carrying a `github-actions` `pr-unblock / address-feedback` check run that ended
   `success` or `failure` (a round whose reply job was refused still counts). At the cap, a kept
   thread with a write-access human's fix request created after the newest counted round (its
   latest marker, or the completion of a model check run that ended `success`, `failure`,
   `cancelled` or `timed_out`) still runs one more round, on those threads only; a
   round with no readable time grants none. Both escalations skip `awaiting-human` with nothing
   minted. Otherwise
   it writes `$RUNNER_TEMP/lane-feedback/threads.json` and records its SHA-256 as a step output,
   which the promote and collect steps check before they read the file: on a mismatch or no
   recorded hash, the promote step does not move the PR branch and the collect step writes no
   `run.json`.
2. `collect-base-activity` makes that directory read-only and stages a wrapper over the base's
   `feedback-thread.sh` there. The skill keeps the commit tool and gets `Bash(<wrapper> *)`; Edit
   and Write are denied on the directory and on the tool's replies directory. The tool lists the
   kept threads, checks paths, and records a reply: it refuses a disposition file outside the
   scratch directory or off the template, and a `VALID` reply whose fix is not on the lane branch
   or whose lane branch changes a file outside every kept thread's scope or any `.github/` path.
   A thread's scope is its path; a file in the `plugins/<p>/` directory its path sits in, except
   one under `hooks/`, `.claude-plugin/` or a `.claude/` directory, a `CLAUDE.md` or `AGENTS.md`,
   or a `.sh`, `.py`, `.mjs`, `.js` or `.ts` file; and a test file (`test_*.py`, `*_test.py`, `*.test.*`, `*.spec.*`) in its path's
   directory. It posts nothing. The promote step then moves the PR branch only when every path the
   lane branch changes is in a kept thread's scope, none under `.github/`, in fewer than 300
   files, judged by a copy of the base's `thread-scope.mjs` taken before the head checkout and
   imported only when its SHA-256 matches.
3. After the promote step, and after a skill that failed, was cancelled or timed out, a pinned
   `github-script` step writes `run.json` (the gated head and the kept threads' ids, paths and
   comment ids, from the thread file) beside a copy of the tool's `replies.jsonl`, and the job
   uploads both as `feedback-replies-<run attempt>`. Its `feedback-round` output is then `true`,
   `feedback-run-sha256` is the SHA-256 of that `run.json`, and `feedback-run-attempt` is the
   attempt in the artifact's name.
4. The caller runs the reply job when `feedback-round` is `true`, passing `feedback-run-sha256` as
   `review-run-sha256` and `feedback-run-attempt` as `review-run-attempt` (a re-run of the reply
   job alone runs as a later attempt but keeps the model job's outputs). Otherwise, when the model
   job gated a head, a scripted job posts the reply job's check neutral `not-applicable` on that
   head with `report-check-run`'s `not-run-reason`, so a red one from an earlier run does not stay.
   Before the head checkout the reply job downloads that artifact and copies the base's
   trusted-actors list. `publish-feedback.mjs` then:
   - validates the whole artifact: `run.json` with exactly that SHA-256; each file a regular file
     read only when within the size limit; `replies.jsonl` at most
     256 KiB, each line an object with exactly `thread`, `disposition`, `evidence`, `fix_sha` and
     `note`; `thread` one `run.json` names, at most one reply per thread; `disposition` one of
     `VALID`, `INCORRECT`, `UNCERTAIN`, `VALID-defer`; at most 10 `path:line` evidence entries, no
     `.` or `..` segment, each a file in the checkout, at least one for `VALID` and `INCORRECT`;
     a 40-hex `fix_sha` on `VALID` only; a note of 1-2000 characters with no control, direction or
     zero-width character, no `<!--` or `-->`, and nothing shaped like a GitHub token. Any failure,
     or a missing artifact, posts no reply and escalates `feedback-invalid`;
   - requires exactly one reply per thread in `run.json`; an empty or partial set posts no reply
     and escalates `feedback-incomplete`;
   - when a reply is `VALID` or the PR branch moved, compares the model job's gated head with the
     PR's current head: the branch must be ahead, hold every fix commit, and change fewer than 300
     files, each in a kept thread's scope and none under `.github/`, and each fix commit must change
     its own thread's path. Otherwise it posts no reply and escalates `feedback-not-landed`;
   - re-reads every kept thread and, right before posting, the thread itself, and skips one that
     is resolved, on another PR, or whose comments are not exactly the ones the model job read;
   - re-reads `git/ref heads/<head ref>` right before each post and each resolve, since the
     compare above judged the branch only up to the head this job gated: once the PR branch is
     anywhere else it posts and resolves nothing more, escalating `feedback-not-landed` when no
     reply had posted and `feedback-partial` otherwise;
   - posts the reply on the thread's root comment in the fixed template (disposition label,
     backticked evidence, `Fix: <sha>` for `VALID`, the note in a `text` fence longer than any
     backtick run in it) and resolves the thread only for `VALID`, and only when a re-read after
     the reply shows exactly the model's comments plus that reply (one retry on a failed read or
     resolve). Once a reply posts, no later round selects the thread until a trusted human
     answers a reply left open, so a post, read or resolve failure stops the posting, and that or a `VALID`
     thread left open escalates `feedback-partial`, as does a round marker that cannot be posted;
   - posts the round marker as the lanes App whatever happened above, once per model run: its
     second line names the workflow run and `review-run-attempt`, and a re-run of the reply job
     alone finds a lanes App marker with that line and posts none, so one model turn counts one
     round. A model run that uploaded no replies names none, and its marker is always posted. It
     escalates
     `feedback-uncertain` for an `UNCERTAIN` or `VALID-defer` reply, or `feedback-disputed` when an
     `INCORRECT` evidence reply was posted: that thread stays open for a person to decide.

   The script writes its reason to `ESCALATION_REASON_FILE`; the runner accepts only those six
   reasons, and only with `review-replies`, as the run's `escalation-reason` output.

The skill's limits to kept-thread scope and away from `.github/` are instructions and the tool's
checks at record time; the promote step's path check is what holds the push, and the reply job's
compare withholds the replies when the branch changed anything else. A diff at the files listing's limit escalates as `feedback-protected-path`,
since it could hide a `.github/` path. Residual: a reviewed-head marker confirms a head, not one
review run, so any reviewer-bot review on that head is kept.

The head re-read in step 5 applies to every `mutate-branch` activity, not only this mode: a
pr-refine run whose PR branch moved before the mint now posts neutral `superseded-sha` without a
model turn.

### prepare: dependency-review

A review of one risky Dependabot pull request is two jobs, for the reason review-threads is: the
model job reads third-party release notes, so it holds `contents: write` and nothing that can
post, close or enqueue. The model job is a `mutate-branch` skill leaf whose config sets
`prepare: dependency-review` and `gating: advisory`; the verdict job is a `publish-artifact`
script leaf with no model, called with `dependency-verdict: true`. The scripts are the base's
`.github/scripts/pr-unblock/review-dependency.mjs` and `apply-dependency-verdict.mjs`. Both this
lane's dispatcher and select step sort pull requests with `dependency-classify.mjs`, a port of
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
also apply the [registry provenance](README.md#registry-provenance) gate, and the select step
warns of a [classifier gap](README.md#classifier-gaps).

1. After `resolve-config` and before the mint, the model job runs `review-dependency.mjs select`
   with the job's `GITHUB_TOKEN`, first recording the UTC time as its `started-at` output. A pull request whose author is not `dependabot[bot]` (by id,
   from the base's trusted-actors list) or that sorts `auto` skips `not-applicable`; one whose
   head is no longer the gated head skips `superseded-sha`.
   `loop.dependency-review-rounds` earlier rounds escalate `dependency-round-cap` and skip
   `awaiting-human`, nothing minted: the larger of the round markers the lanes App posted and
   the PR commits carrying a `github-actions` `pr-unblock / review-dependency` check run that
   ended `success` or `failure`. Otherwise it writes `$RUNNER_TEMP/lane-dependency/dependency.json`:
   the head, title, labels, classification, each changed file with its patch (20,000 characters
   each, 300,000 in all), `files_truncated` (the files listing reached its 3,000-file limit),
   and the body as data.
2. `collect-base-activity` makes that directory read-only, grants `Read` on it, denies Edit and
   Write there, keeps the commit tool, and passes a `--json-schema` for the verdict:
   `verdict` (`merge`, `fix`, `close`, `escalate`), 1-10 `reasons` of at most 500 characters and
   at most 20 `evidence` entries of at most 300. The activity's `web-access` names the release-note
   hosts. The skill runs no head code; `ci-status` runs the tests on the pushed head.
3. The promote step moves the PR branch only when the skill's structured verdict is `fix`, the
   lane branch changes nothing under `.github/` in fewer than 300 files, and every commit's
   message carries `[dependabot skip]`, so Dependabot may still rebase over the fix. Commits made
   beside any other verdict are discarded with the lane branch.
4. After the promote step, and after a skill that failed, was cancelled or timed out, a pinned
   `github-script` step writes `run.json` (`version`, `pr`, the gated `head_sha`, the select
   step's `security`, `config_unreadable` and `files_truncated` flags, its `started-at` as
   `started_at`, its `controls` (the matched review-only entries' `control` strings), and the
   skill's structured output as `output`, `null` when absent or
   unparsable) and the job uploads it as `dependency-verdict-<run attempt>`. Its
   `dependency-round` output is then `true`, with `dependency-run-sha256` and
   `dependency-run-attempt`.
5. The caller runs the verdict job when `dependency-round` is `true`. `apply-dependency-verdict.mjs`:
   - validates `run.json`: exactly that SHA-256, a regular file of at most 64 KiB, exactly the
     runner's fields, and an `output` with exactly the schema's fields within its limits, each
     string plain prose with no control character, code fence, HTML comment or @-mention. Any
     failure, or a missing artifact, escalates `dependency-invalid`;
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
     committer date no earlier than `run.json`'s `started_at` (taken before any model turn, so
     the verdict job reads no Actions API and needs no `actions` permission), else
     `superseded-sha`. Those commits may change
     nothing under `.github/`, either side of a rename, else `dependency-invalid`;
   - `merge`: posts the round marker, whose first line
     `<!-- pr-unblock:review-dependency-round head=<sha> verdict=merge run=<run id>-<attempt> -->`
     from the lanes App is the record the pr-merge lane merges a review-tier pull request on,
     at the current head and through its own gate. With `config_unreadable` it posts no merge
     marker and escalates `dependency-config-unreadable`; with `files_truncated` it posts no
     merge marker and escalates `dependency-files-truncated`; without each of `controls` quoted
     in `evidence` it escalates `dependency-control-uncited`
     ([README, "Review-only dependencies"](README.md#review-only-dependencies)). This job never
     merges or enqueues;
   - `close`: escalates `dependency-security-close` for a security update (the model job's flag,
     or the label or an advisory in the body read fresh); otherwise finds the lanes App issue whose first line is
     `<!-- pr-unblock:dependency-ignore pr=<n> head=<sha> -->` or files it, proposing the
     `.github/dependabot.yml` `ignore` entry, then posts the marker, then closes an open pull
     request. Each step is safe to repeat, so a re-run after a partial failure resumes;
   - `escalate`: escalates `dependency-escalate`;
   - posts the round marker once per model run, named `none` when the model run uploaded no
     verdict: a re-run that finds its own marker posts none.

   The runner accepts only those six reasons, and only with `dependency-verdict`.

### prepare: ci-context

pr-unblock's `fix-ci` fixes a lanes App pull request's failing checks in three jobs, so no model
holds a write token: a base job, a read model job in this mode, and an
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
3. `collect-base-activity` makes it read-only, grants `Read` on it, denies Edit and Write there,
   and grants the skill Bash, Edit, Write and Agent with the web tools denied: the job holds no
   write token, and the skill reruns the failing checks. The system prompt names the file.
   Residual: the skill runs head code by design, so head code can reach what any step of a read
   job can (the job's read-only token, the Actions runtime token through a process left running
   or `$GITHUB_ENV`, and the default branch's cache scope), as in `pr-verify.yml`. The patch it
   leaves is checked only by [`apply-patch`](#prepare-apply-patch), which refuses `.github/**` and
   the agent instruction paths (the owner's 2026-10-18 path-guard decision); a change elsewhere,
   such as `.gitattributes` or a check's own script, reaches the branch and its review.
4. The run is in [patch output mode](#patch-output-mode); its `reply-attempt` output names the
   skill's reply, whose `<check>: escalated <reason> <sentence>` lines are the report.

### prepare: apply-patch

A `mutate-branch` script leaf, the `apply-ci-fix` job after `fix-ci`, with no model. The caller
passes the model job's `patch-state`, `patch-sha256`, `patch-attempt`, `head-sha` (as
`patch-head-sha`) and `reply-attempt`, and its activity as `patch-activity`.

1. Before the mint, the write file downloads `patch-<lane>-<patch-activity>-<patch-attempt>`
   and the model job's reply, and runs the base's `apply-ci-fix.mjs select` with no token. A
   gated head other than `patch-head-sha` skips `superseded-sha`. An `empty` patch escalates
   `ci-fix-empty` (`ci-fix-escalated` when the report escalated a check). A `patch-state` other
   than `written` or `empty`, or an artifact that is not exactly one regular `patch.diff` of at
   most 1 MiB with that SHA-256, escalates `ci-fix-invalid`. Each skips `awaiting-human` with
   nothing minted. A report that escalated a check sets `ci-fix-escalated` and proceeds, so the
   fixes that landed are pushed and the rest go to a person.
2. The hold-label step runs as for a skill, before the head checkout (depth 1).
3. The script, from its base copy, with the lane token and `/usr/bin/git` under an allowlisted
   environment (no hooks, fsmonitor, global or system config): checks the SHA-256 again, reads
   the gated head into the index, runs `git apply --cached --check` then `git apply --cached`
   (escalating `ci-fix-not-applied` on failure), writes the tree, and lists it against the gated
   head with `git diff-tree -r --no-renames`. A path under `.github/` (thread-scope.mjs's
   `isProtectedPath`, the rule the review-threads mode applies), or an agent instruction path at
   any depth and in any case (`CLAUDE.md`, `AGENTS.md`, a `.claude/` or `.claude-plugin/` directory,
   a plugin's `hooks/`, `.mcp.json`, `.gitmodules`, `CODEOWNERS`), escalates
   `ci-fix-protected-path` and pushes none of the patch, whatever the report escalated; a mode `120000` or `160000` on either side, or no change, escalates
   `ci-fix-invalid`. It then re-reads the pull request and its labels and stops uncommitted
   (`awaiting-human`) on a draft or a hold label, fails when `git/ref heads/<head ref>` is no
   longer the gated head, uploads the changed blobs, builds the tree on the head's tree and fails
   unless it hashes to the applied tree, creates the commit `Fix failing CI checks on <head ref>`
   with the trailer `Lane-Activity: pr-unblock/fix-ci`, parent the gated head and no author,
   committer or signature, so GitHub signs it as the App, moves the PR branch with
   `force: false`, and confirms the move by reading the ref again.

The run's `escalation-reason` output is the script's reason, else the select step's. The runner
accepts the script's three reasons only in this mode.

The rules each producer's patch is to be held to are registered in
[`patch-rules.json`](../../../.github/actions/resolve-config/patch-rules.json), one row per
producer prepare mode ([README.md, Patch rules](README.md#patch-rules)): the refusals every row
carries, what else a path must meet, a file cap, the producer output required, the commit's
parents, message and trailer, and the row's escalation reasons. `apply-ci-fix` above keeps its
own fixed refusal and does not read the registry.

## The summary job

Write file, issue mode only: runs after the run job, unless the run was cancelled, when the run
job's `reuse-branch` output is not empty. It holds `contents: read` and nothing else, so no model
turn runs where `id-token: write` is granted, and it times out after 20 minutes. Every step is
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

Runs after the run job whatever its result, with `checks: write`, `contents: read` and
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

The verdict is written after head code ran in the same job, so it is never trusted: its lane,
activity, gate stop reason and `head-sha` must match the values above or the check fails, and its
`dirty-tree` counts only as `true` (failure); its `patch` field only picks the title of a success. A missing verdict is a failure. A cancelled run job
posts neutral `superseded-sha` only when the PR's current head SHA is non-empty and differs from
the gated `head-sha`; a cancel with no newer head, such as a manual cancel or a timeout, is a
failure. The full decision order is in the report-check-run README.

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
`claude_code_oauth_token`, `automations_claude_code_oauth_token` (the lanes' Claude Code OAuth
token), `github_token` (case-insensitive, `-` read as `_`); `toJSON(secrets)`,
`secrets[...]` and bare `secrets` fail. It also fails when any file of such a run sets
`permissions: write-all`, and, in the read file, when the top level is not `permissions: {}`, a
job has no permissions map, `id-token` is named anywhere outside the `broker-check` job, that job
is a reusable-workflow call or has no `steps`, or one of its `actions/checkout` steps has a `ref`
other than `${{ github.event.repository.default_branch }}` or a `with` key other than `ref`,
`path` and `persist-credentials`.

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
`pr_number` is the gate's PR and is required on `workflow_dispatch` and `workflow_run`. An `issues` request,
allowed only from `work-resolve-issue.yml`, sends `issue_number` (the `issue-number` input)
instead, and neither of the other two; its actor, the labeler, must be a listed human, or the lanes App. The broker (azure-iac's `lanes-token-broker`) still re-checks the retired ratification marker for the App, so until it drops that check an App-labeled issue without the marker gets no token and the run fails closed. A `merge` request from `pr-merge.yml` names no pull request either; its actor must be a listed human, except on a `schedule` run on `refs/heads/main`, whose actor is whoever last edited the workflow file and is not checked. A re-run of a scheduled run must be started by a listed human. `dispatcher_run_id`, a positive
JSON integer, is the `dispatcher-run-id` input, sent only when set. The broker reads it only when
the OIDC actor is `github-actions[bot]`: such a run mints only when the `pr-unblock-dispatch.yml`
run it names passes the checks the trusted-trigger gate applies. That run must be on `main`,
started by a push or a listed human, with a re-run attempt started by a listed human. Its head
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
| 403 | `event-not-allowed` | Not `pull_request` on `refs/pull/<n>/merge`, or `workflow_dispatch` or `workflow_run` on `refs/heads/main`, or `issues` on `refs/heads/main` from `work-resolve-issue.yml`, or `schedule` on `refs/heads/main` from `pr-merge.yml` or `work-unblock.yml` only |
| 403 | `workflow-not-allowed` | The job is not this repository's `pr-run-activity-write.yml`, or the caller is not a lane under `lanes:` in the tip's `pr-pipeline.yaml` |
| 403 | `workflow-modified` | The caller or `pr-run-activity-write.yml` differs from the default-branch tip (a report job, `work-resolve-issue` `report-outcome` or `pr-unblock` `report-escalation`, still mints when every main commit that changed the file is signed, GitHub-made, on a linear range and landed after run start, at most 50 minutes ago: [azure-iac#39](https://github.com/melodic-software/azure-iac/pull/39)) |
| 403 | `workflow-modified` | With `dispatcher_run_id`: the dispatcher workflow at the dispatcher run's head differs from the tip (same report-job exception) |
| 403 | `lane-mismatch` | The requested lane is not the caller's file stem |
| 403 | `activity-not-in-lane`, `slot-disabled`, `config-invalid`, `effect-forbidden-by-lane` | The tip config does not give this activity a write grant |
| 403 | `effect-read` | The activity is `read`; it belongs in the read file |
| 403 | `untrusted-actor`, `untrusted-author`, `bot-actor` | The actor, the PR author or a re-runner is not on the tip's trusted-actor list (a scheduled `pr-merge.yml` run has no actor check, and its re-runner must be a listed human; a scheduled `work-unblock.yml` run has no actor check either and skips the workflow's own closer check, so the broker alone gates its re-runs), or is the lanes bot |
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

The write file's `issue-number` input runs a lane on an issue instead of a PR. Its one caller is
[`work-resolve-issue.yml`](../../../.github/workflows/work-resolve-issue.yml): the `agent-ready`
label on an issue runs `resolve-issue` (`/work-items:work --issue <n> --ci`), then
`report-outcome` (a script) in a second run job. At most three `resolve-issue` jobs run at once:
a `pick-slot` job takes the issue number modulo `SLOTS` (3), and `resolve-issue` joins the
`work-resolve-issue-slot-<n>` concurrency group with `queue: max`, so a burst of admissions waits
in line, holding no runner, instead of spending the lanes App's hourly API quota at once.
`report-outcome` takes no slot. A waiting run keeps the workflow files of its label event, so when
a change to either lane workflow file merges while it waits, the broker would refuse its mint as
`workflow-modified`. Before the mint, the `workflow-current` step compares both files' blobs at
`github.workflow_sha` with the default branch checkout, the broker's rule, and on a difference
fails red `workflow-stale` with no token request and no outcome marker; work-unblock's hourly sweep
re-fires such a failed run on main's files. What changes from the PR flow:

- Step 1 also fails red unless the event is `issues`, `issue-number` is the event's issue,
  `trusted-base` is `default-tip`, and `pr-number` and `dispatcher-run-id` are empty, and unless a
  non-empty `reuse-branch` is this issue's `work-resolve-issue/issue-<n>-<run id>-<attempt>`.
- The trigger gate runs with `require-pr: false` and `require-kind: human`: the account that
  applied the label, and any re-runner, must be listed as a human. The one exception is the
  caller's `app-label` (`agent-ready` for `work-resolve-issue.yml`): the lanes App may apply it,
  and the label alone admits the issue; the re-runner is then the App or a listed human. The
  App's other labels never start a run, and no step of the lane adds `agent-ready`. `check-trusted-base` trusts the
  default branch tip, and that commit is the head the job checks out.
- `resolve-config` reads the issue's labels now, for the hold labels, and `labeled-after`, the
  lane's go-live time, from the issue's update time. The token request sends `issue_number`.
- Each issue is worked once. In a skill run, the `issue-prior` step (`report-outcome.mjs
  --find-prior`) runs after `resolve-config` and before the mint, with the job's read-only
  `GITHUB_TOKEN`, and reads the issue's lane branches (`git/matching-refs` on
  `work-resolve-issue/issue-<n>-`), their PRs, their tip commits, their commits ahead of the
  default branch, the issue's open closing PRs and the lanes App's outcome markers on it. It skips
  the run `not-applicable`, with no lane token, no model and no comment, when a lanes-App PR from a
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
  by `web-flow` (a listing the compare cuts short resumes nothing), the run resumes it; when that
  run's branch is gone or fails a check, the run starts from the default branch, never from an
  older run's branch: `issue-prior`
  outputs `resume-branch`, `resume-tip` (the tip it read) and `resume-cause`, and the job checks
  out that tip and makes its lane branch there instead of at the default branch tip. Any failed
  read, or an answer of the wrong shape, fails the step, so nothing is minted.
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
  base and each changed file with its line counts, from `GET /compare`. The skill commits to a new branch,
  `<lane>/issue-<n>-<run id>-<attempt>`, which is kept only when it holds commits. The skill's
  `work-outcome.json` and the runner's `lane.json` (the kept branch, or empty, and on a resume the
  resumed branch) are uploaded as the
  `work-outcome-<n>` artifact, and the job output `issue-run-started` is `true` once the token
  was minted.
- `report-outcome` downloads that artifact. A `done` run that committed nothing on a resume opens its PR from the
  resumed branch only when `run-checks` checked that whole branch (it checks one only when `lane.json`'s `resume` equals
  the `resume-branch` `issue-prior` output), every check passed and at least one ran, the branch is still at the tip
  checked (the compare reads that SHA, and a new PR whose head is another commit is closed), and every commit on it ahead of the default branch is verified, authored by the lanes App
  and committed by `web-flow`; the PR body's Verification section says so. Otherwise it hands the issue to a person,
  naming the resumed branch. On `done` it opens a ready (not draft) PR from the branch whose
  body starts `Closes #<n>` (or `Refs: #<n>` when the outcome sets
  `"link": "refs"` because a recorded decision keeps the issue open), puts no label on it (the work class stays on the issue), and adds
  `Hold: a human merges this` for structural or untrusted-provenance work, for a diff that
  touches a path the merge lane refuses (`merge.diff-check.denied-paths`, read from the run's
  resolved config; unreadable holds every PR), or, while some path is denied, for one too large
  for the compare listing to show whole. It adds the same line when the issue carries `merge: human` whose newest `labeled`
  event is a listed human's or the lanes App's, or cannot be read, and never for anyone else's.
  The run's own summary is quoted with issue references broken, so squash-merging the PR closes only `#<n>`. On `pushback` or `stopped`, and when the outcome file is missing
  or invalid, it labels the issue with the human-gated role label and comments why; pushback also
  removes `agent-ready`. Each comment opens with the marker
  `<!-- work-resolve-issue outcome=<exit> run=<run id> -->`, which `issue-prior` matches to the
  branches of that run (a marker naming no run covers every branch whose tip is older than it).
  A run that wrote no readable outcome file and whose lane record has class `max-turns` is a
  turn-cap stop: the comment opens with `<!-- work-resolve-issue outcome=turn-cap cap=<n> run=<run id> -->`
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
- On a reuse the skill run mints nothing, and the [summary job](#the-summary-job) has a read-only
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
