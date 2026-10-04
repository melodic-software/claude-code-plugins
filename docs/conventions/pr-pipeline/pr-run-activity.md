# pr-run-activity

Two reusable workflows run one activity of one lane each and end in one check run named
`<lane> / <activity>`: `success`, `failure`, or `neutral` with a skip reason.

- [`pr-run-activity-read.yml`](../../../.github/workflows/pr-run-activity-read.yml) runs an
  activity whose effect is `read`. It declares no App key secret and no `id-token` permission, and
  fails red with `effect-not-read` before the head checkout for any other effect.
- [`pr-run-activity-write.yml`](../../../.github/workflows/pr-run-activity-write.yml) runs every
  other effect. It takes the App key, mints the effect's token, never runs for the lanes App bot,
  and fails red with `effect-read` for a `read` activity.

Every lane workflow calls one of them once per activity; the activity's effect decides which. Which
activity runs, with what model, turn budget and token grant, comes from the base SHA's
[`pr-pipeline.yaml`](README.md), read by
[`resolve-config`](../../../.github/actions/resolve-config/README.md). Both files share the steps
before the head checkout through local composite actions
([`check-trusted-base`](../../../.github/actions/check-trusted-base/action.yml),
[`stage-activity`](../../../.github/actions/stage-activity/action.yml),
[`isolate-runner`](../../../.github/actions/isolate-runner/action.yml)) run from `.base`. Steps
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

A write activity calls `./.github/workflows/pr-run-activity-write.yml` the same way and also passes
`app-private-key: ${{ secrets.AUTOMATION_LANES_APP_PRIVATE_KEY }}`.

| Input | Default | Meaning |
|---|---|---|
| `lane` | required | The lane, its workflow's file stem |
| `activity` | required | The activity, one of the lane's slots |
| `config-path` | `docs/conventions/pr-pipeline.yaml` | For test callers only (below) |
| `pr-number` | `''` | The PR on `workflow_dispatch` |
| `default-model` | `''` | The model when the activity sets none; empty omits `--model` |
| `default-max-turns` | `75` | The turn budget when the activity sets none |
| `timeout-minutes` | `30` | The run job's timeout; the report job's is fixed at 10 |

Secrets are passed by name, never `inherit`: `claude-code-oauth-token` (skill activities, both
files) and `app-private-key` (the lanes App, the write file only). Repository variables: `CLAUDE_LANES_DISABLED` (the kill switch),
`AUTOMATION_LANES_APP_CLIENT_ID`, and `AUTOMATION_LANES_APP_SENDER_ID`, the App bot's numeric user
id, the one place it is written. The run job's first step fails red when
`AUTOMATION_LANES_APP_SENDER_ID` is not a numeric id, since an unset value would let the App's own
events through the self-trigger guard.

Both jobs set up Node 24: `resolve-config` uses `path.matchesGlob`, and the actions' suites run on
Node 24.

The caller must:

- Grant the calling job `contents: read`, `pull-requests: read` and `checks: write`. The `run` job
  narrows this to the two reads; only the `report` job uses `checks: write`.
- Put the calling job in a per-PR concurrency group with `queue: max`, or an equivalent that never
  cancels a pending run. A group that drops a pending run leaves that activity with no check, and
  silence is not a skip.
- Leave concurrency off the reusable workflow, which sets none.
- Call the file that matches the activity's effect. A mismatch fails red before the head
  checkout, so the file a caller names, and any `app-private-key` it passes, is what a human
  reviews.
- Reference no App key anywhere in a caller of the read file ([below](#secrets-and-the-two-files)).
- Expose `config-path` only from a test caller. A production lane never passes it and never offers
  it as a `workflow_dispatch` input, so no dispatch can point the reader at another YAML file in the
  base tree.

## The run job

Holds `contents: read` and `pull-requests: read`, and no other permission; it never holds
`checks: write` or `workflows`. It times out after the `timeout-minutes` input. In order:

1. Fails red unless `AUTOMATION_LANES_APP_SENDER_ID` is a numeric id and the event names a default
   branch.
2. Checks out the default branch tip, with full history, to `.base`. Every action runs from `.base`
   as `./.base/.github/actions/<name>`, so the next two run from the default branch whatever branch
   the PR targets.
3. [`check-kill-switch`](../../../.github/actions/check-kill-switch/README.md), then
   [`check-trusted-trigger`](../../../.github/actions/check-trusted-trigger/README.md). Neither has
   `continue-on-error`. A stop at either ends the job green with no token minted and no head
   checked out; the check is neutral. Both files pass `github.triggering_actor`, so a re-run
   started by an account not on the list stops with `untrusted-actor`. The write file also denies
   `AUTOMATION_LANES_APP_SENDER_ID`, so the lanes App bot as sender, `workflow_run` actor or
   re-runner stops it with `bot-actor` and one write activity never chains into the next; the read
   file denies nothing, so bot-chained read activities still run.
4. `check-trusted-base` asserts the PR targets the default branch and fails red otherwise. On `pull_request` the base
   branch is the event's `pull_request.base.ref`; on any other event (`workflow_dispatch`,
   `workflow_run`) it is read from the PR with the job's `GITHUB_TOKEN`. It then fails red unless
   the gate's `base-sha` is an ancestor of the default branch tip (`git merge-base --is-ancestor`),
   and checks that SHA out in `.base`. Nothing the PR's base branch chose runs before this check.
5. `resolve-config`. An invalid config fails the step red and the check is a failure, never a skip.
   A config skip (`disabled-by-config`, `not-applicable-paths`, `not-applicable`) mints nothing.
   With a valid config, the read file fails red with `effect-not-read` unless the effect is
   `read`, and the write file fails red with `effect-read` when it is, whether or not the activity
   applies.
6. Write file only: asserts the grant's `contents`, `pull-requests` and `issues` are each exactly
   `read` or `write`, then mints the App token for this repository only with those three
   permissions. An empty `permission-*` would widen the token to every installation permission.
   The read file mints nothing and uses the job's read-only `GITHUB_TOKEN` throughout.
7. [`select-trusted-text`](../../../.github/actions/select-trusted-text/README.md) to
   `$RUNNER_TEMP/trusted-context.json` when the activity `reads-untrusted`, with the App token or,
   in the read file, the `GITHUB_TOKEN`, which has no `issues` grant: in a private repository a PR
   that closes an issue may fail the step red.
8. `stage-activity` copies what the activity runs from the base out of `.base`: a script's whole
   directory to `$RUNNER_TEMP/base-script`, or for a skill the base `plugins/` and
   `.claude-plugin/` to `$RUNNER_TEMP/base-marketplace`.
9. `isolate-runner`: for a skill, installs bubblewrap and socat with `apt-get` (three tries) and, where
   `/proc/sys/kernel/apparmor_restrict_unprivileged_userns` exists, sets it to `0`. It fails red
   if `bwrap` is not on `PATH` afterwards. The skill step needs it for subprocess isolation (below).
10. Removes sudo and docker access for the rest of the job: `/var/run/docker.sock` becomes
   root-only and the runner user's `/etc/sudoers.d/runner` entry is deleted. It fails red if
   `sudo -n true` still succeeds or the socket is still open to the runner user.
11. Checks out the trigger gate's `head-sha` with `persist-credentials: false`, then fails red
    unless `git rev-parse HEAD` equals that SHA. This replaces `.base`.
12. Runs the activity (below), then, in the read file, records whether the tree is dirty.
13. Writes `verdict.json` with `jq` (`if: always()`) and uploads it as
    `verdict-<lane>-<activity>-<run_attempt>`, unique per activity and attempt.

A stacked PR, one whose base is not the default branch, gets a failure check from step 4. Retarget
it to the default branch to run its lanes.

Its outputs are `base-sha`, `head-sha`, `pr-number`, `gate-reason`, `can-commit` and
`act-outcome`. All but `act-outcome` are outputs of steps that ran before any head code:
`gate-reason` is the kill switch's reason if it stopped, else the trigger's if it stopped, else
empty; `head-sha` is the trigger gate's; `base-sha` is set only by step 4, so it is always on the
default branch. `act-outcome` is the activity step's outcome, except that a gate skill whose step
succeeded takes the outcome of the verdict check (below), a step that runs after the skill.

### Skill activities

The prompt is `/<plugin>:<skill> <args>`; for a `reads-untrusted` activity a second line,
`Trusted PR context: <path>`, names the `select-trusted-text` output, which the step also gets as
`TRUSTED_CONTEXT_FILE`. A `reads-untrusted` skill must read PR text (title, body, comments,
reviews, linked issues) only from that file, never through the API. Existing skills are not yet
adapted to this and still read PR text themselves; until each is, its untrusted-text exposure is a
known residual. The skill gets the App token as `github_token` in the write file, and the job's
read-only `GITHUB_TOKEN` in the read file. `claude_args` passes `--setting-sources user`, so no
project or local settings, hooks, `CLAUDE.md`, `AGENTS.md` or `.mcp.json` from the PR head load;
`--permission-mode dontAsk`; `--allowedTools "Skill(<plugin>:<skill>)"`, so the skill's own
`allowed-tools` decide what else it may use; `--max-turns`; and `--model` when one is set. The
plugin installs only from `$RUNNER_TEMP/base-marketplace`. Commits go through the API, signed
(`use_commit_signing`), on the gate's head branch (`CLAUDE_BRANCH`). A mutating activity's commits
are made against that branch, which may have moved since the gate; the push that moved it starts
its own `synchronize` run, which gates the new head again. Why a skill activity loads nothing from
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
persists no credentials, so a `read` script cannot push.

## The report job

Runs after the run job whatever its result, with `checks: write`, `contents: read` and
`pull-requests: read`, no model step, and a 10-minute timeout. It checks out the default branch
tip, with full history, to `.base`, then checks out the run job's `base-sha` output only when that
SHA is an ancestor of the tip; otherwise it stays on the tip. It never checks out the event's base
SHA, so a PR into another branch cannot choose the actions that write its check. It then downloads
the verdict (`continue-on-error`: a missing verdict is already decided below), runs
[`check-signed-commits`](../../../.github/actions/check-signed-commits/README.md) with its
`GITHUB_TOKEN` unless `can-commit` is `false`, reads the PR's current head SHA with its
`GITHUB_TOKEN` (empty when there is no PR or the read fails), and posts the check with
[`report-check-run`](../../../.github/actions/report-check-run/README.md), passing that SHA as
`pr-head-sha`. Why the check is written by this job and not the run job:
[ADR 0053](../../adr/0053-run-each-pipeline-activity-as-a-model-job-and-a-scripted-report-job.md).

What it trusts:

- Lane and activity from the reusable workflow's own inputs.
- `needs.run.result`, and the run job's `act-outcome`, `can-commit`, `gate-reason`, `head-sha` and
  `base-sha` outputs, computed by the runner. All but a gate skill's `act-outcome` come from steps
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

Secrets in the job that runs head code: the read file never references `app-private-key`, and its
run holds the key only if its caller passes it elsewhere
([below](#secrets-and-the-two-files)). The write file still references `app-private-key` to mint,
and every skill job references the Claude OAuth token. Two routes reach them:

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

Both are mitigations, not a fix: the full fix is a token broker that keeps the App key off any
runner that runs head code. The broker is decided and not yet built; until it lands, no live lane
holds a write effect, and a lane runs head code only under the rule in
[Secrets and the two files](#secrets-and-the-two-files).

The verdict is written after head code ran in the same job, so it is never trusted: its lane,
activity, gate stop reason and `head-sha` must match the values above or the check fails, and its
`dirty-tree` counts only as `true` (failure). A missing verdict is a failure. A cancelled run job
posts neutral `superseded-sha` only when the PR's current head SHA is non-empty and differs from
the gated `head-sha`; a cancel with no newer head, such as a manual cancel or a timeout, is a
failure. The full decision order is in the report-check-run README.

## Secrets and the two files

GitHub scrubs secrets per workflow run, not per job: a caller and every reusable workflow it calls
are one run, and a secret referenced anywhere in that run must be assumed to reach every job in
it, the read job that runs PR head code included. Lane is the caller's file stem, so one lane
cannot be split across two caller files.

Until the token broker lands, a lane may go live with head-code read activities only if its caller
file references no App key at all, so every activity it calls runs through the read file, and only
after the trust-root ruleset ([README](README.md#trust-root-paths)) is in force. A lane that mixes
read and write activities waits for the broker.
[`scripts/check-read-caller-keys.sh`](../../../scripts/check-read-caller-keys.sh) enforces it: it
fails when a workflow that calls `pr-run-activity-read.yml`, or a repository-local reusable
workflow that caller reaches, names `AUTOMATION_LANES_APP_PRIVATE_KEY`, `app-private-key` or
`private-key:`, and when the read file names `id-token`.

The read file stays after the broker lands: its guarantee, no key and no OIDC token in a run that
runs head code, is structural, while the write file's comes from the broker.

## Runs that post no check

- A fork PR, whose read-only `GITHUB_TOKEN` cannot write checks: the report job's `if:` skips it.
- A `pull_request` event sent by the lanes App (`AUTOMATION_LANES_APP_SENDER_ID`): both jobs skip.
- Any event other than `pull_request` whose run job gated no head SHA: the fallback there would be
  `github.sha`, the dispatch ref, not the PR's commit. The report job notes it in its step summary.

## Bounds

On `pull_request`, the caller and the reusable workflow run from the PR's merge commit: a `./` reusable
workflow comes from the same commit as its caller. A PR that edits `.github/workflows/**`
therefore controls both, and the default-branch base reads above guard only against changes
outside `.github/workflows`. The real bound is who can push `.github/workflows`: kyle-sexton, and Apps
holding the `workflows` permission, such as the standards sync bot.
