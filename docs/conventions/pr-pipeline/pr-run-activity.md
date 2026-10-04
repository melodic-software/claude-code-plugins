# pr-run-activity

[`pr-run-activity.yml`](../../../.github/workflows/pr-run-activity.yml) runs one activity of one
lane and ends in one check run named `<lane> / <activity>`: `success`, `failure`, or `neutral` with
a skip reason. Every lane workflow calls it once per activity. Which activity runs, with what
model, turn budget and token grant, comes from the base SHA's
[`pr-pipeline.yaml`](README.md), read by
[`resolve-config`](../../../.github/actions/resolve-config/README.md).

## Calling it

```yaml
jobs:
  simplify:
    permissions:
      contents: read
      pull-requests: read
      checks: write
    concurrency:
      group: pr-refine-${{ github.event.pull_request.number || inputs.pr-number }}
      queue: max
    uses: ./.github/workflows/pr-run-activity.yml
    with:
      lane: pr-refine
      activity: simplify
    secrets:
      claude-code-oauth-token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
      app-private-key: ${{ secrets.AUTOMATION_LANES_APP_PRIVATE_KEY }}
```

| Input | Default | Meaning |
|---|---|---|
| `lane` | required | The lane, its workflow's file stem |
| `activity` | required | The activity, one of the lane's slots |
| `config-path` | `docs/conventions/pr-pipeline.yaml` | For test callers only (below) |
| `pr-number` | `''` | The PR on `workflow_dispatch` |
| `default-model` | `''` | The model when the activity sets none; empty omits `--model` |
| `default-max-turns` | `75` | The turn budget when the activity sets none |

Secrets are passed by name, never `inherit`: `claude-code-oauth-token` (skill activities) and
`app-private-key` (the lanes App). Repository variables: `CLAUDE_LANES_DISABLED` (the kill switch),
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
- Leave concurrency off this workflow, which sets none.
- Expose `config-path` only from a test caller. A production lane never passes it and never offers
  it as a `workflow_dispatch` input, so no dispatch can point the reader at another YAML file in the
  base tree.

## The run job

Holds `contents: read` and `pull-requests: read`, and no other permission; it never holds
`checks: write` or `workflows`. In order:

1. Checks out the base SHA (the default branch outside `pull_request`) to `.base`, and runs every
   action from there as `./.base/.github/actions/<name>`.
2. [`check-kill-switch`](../../../.github/actions/check-kill-switch/README.md), then
   [`check-trusted-trigger`](../../../.github/actions/check-trusted-trigger/README.md). Neither has
   `continue-on-error`. A stop at either ends the job green with no token minted and no head
   checked out; the check is neutral.
3. Re-checks out `.base` at the trigger gate's `base-sha` when it differs (dispatch and
   `workflow_run`).
4. `resolve-config`. An invalid config fails the step red and the check is a failure, never a skip.
   A config skip (`disabled-by-config`, `not-applicable-paths`, `not-applicable`) mints nothing.
5. Asserts the grant's `contents`, `pull-requests` and `issues` are each exactly `read` or `write`,
   then mints the App token for this repository only with those three permissions. An empty
   `permission-*` would widen the token to every installation permission.
6. [`select-trusted-text`](../../../.github/actions/select-trusted-text/README.md) to
   `$RUNNER_TEMP/trusted-context.json` when the activity `reads-untrusted`.
7. Copies what the activity runs from the base out of `.base`: a script's whole directory to
   `$RUNNER_TEMP/base-script`, or for a skill the base `plugins/` and `.claude-plugin/` to
   `$RUNNER_TEMP/base-marketplace`.
8. Checks out the trigger gate's `head-sha` with the App token and `persist-credentials: false`,
   then fails red unless `git rev-parse HEAD` equals that SHA. This replaces `.base`.
9. Runs the activity (below), then for a `read` activity records whether the tree is dirty.
10. Writes `verdict.json` with `jq` (`if: always()`) and uploads it as
    `verdict-<lane>-<activity>-<run_attempt>`, unique per activity and attempt.

Its outputs are `base-sha`, `head-sha`, `pr-number`, `gate-reason`, `can-commit`, `applies` and
`act-outcome`. Each is a step outcome or an output of a step that ran before any head code:
`gate-reason` is the kill switch's reason if it stopped, else the trigger's if it stopped, else
empty; `head-sha` is the trigger gate's.

### Skill activities

The prompt is `/<plugin>:<skill> <args>`. `claude_args` passes `--setting-sources user`, so no
project or local settings, hooks, `CLAUDE.md`, `AGENTS.md` or `.mcp.json` from the PR head load;
`--permission-mode dontAsk`; `--allowedTools "Skill(<plugin>:<skill>)"`, so the skill's own
`allowed-tools` decide what else it may use; `--max-turns`; and `--model` when one is set. The
plugin installs only from `$RUNNER_TEMP/base-marketplace`. Commits go through the API, signed
(`use_commit_signing`), on the gate's head branch (`CLAUDE_BRANCH`). A mutating activity's commits
are made against that branch, which may have moved since the gate; the push that moved it starts
its own `synchronize` run, which gates the new head again.

### Script activities

The script runs from its base copy, with the PR head as its working directory, and must be
executable. It must sit in a subdirectory: the copy takes the script's whole directory, so a
root-level script path fails red rather than copying the whole base tree. Its environment:

| Variable | Value |
|---|---|
| `PR_NUMBER`, `HEAD_SHA`, `BASE_SHA` | The gated PR, its head SHA, and the base SHA in `.base` |
| `ACTIVITY_ARGS` | The activity's `args`, verbatim; empty when unset |
| `SKIP_REASON_FILE` | Write one `$defs/skip-reason` value here and exit 0 for neutral |
| `GH_TOKEN` | The App token, only when the effect is not `read`; unset otherwise |

Exit 0 is success, non-zero is failure, and a reason file whose value is not a skip reason is a
failure. A script that gets `GH_TOKEN` must not execute code from the PR head. The head checkout
persists no credentials, so a `read` script cannot push.

## The report job

Runs after the run job whatever its result, with `checks: write`, `contents: read` and
`pull-requests: read`, and no model step. It checks out exactly the run job's `base-sha` output to
`.base` (the event's base only when the run job stopped before its own checkout), downloads the
verdict, runs [`check-signed-commits`](../../../.github/actions/check-signed-commits/README.md)
with its `GITHUB_TOKEN` unless `can-commit` is `false`, and posts the check with
[`report-check-run`](../../../.github/actions/report-check-run/README.md).

What it trusts:

- Lane and activity from this workflow's own inputs.
- `needs.run.result`, and the run job's `act-outcome`, `can-commit`, `gate-reason`, `head-sha` and
  `base-sha` outputs, all computed by the runner from steps that ran before any head code.
- Its own signed-commit result. On an unverified commit, `check-signed-commits` fails closed: the
  check is a failure, and the report job adds no label and posts no comment, because its
  `GITHUB_TOKEN` cannot write issues or pull requests.

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

The verdict is written after head code ran in the same job, so it is never trusted: its lane,
activity, gate stop reason and `head-sha` must match the values above or the check fails, and its
`dirty-tree` counts only as `true` (failure). A missing verdict is a failure; a cancelled run job
posts neutral `superseded-sha`. The full decision order is in the report-check-run README.

## Runs that post no check

- A fork PR, whose read-only `GITHUB_TOKEN` cannot write checks: the report job's `if:` skips it.
- A `pull_request` event sent by the lanes App (`AUTOMATION_LANES_APP_SENDER_ID`): both jobs skip.
- A `no-pr` trigger stop with no head SHA.

## Bounds

On `pull_request`, the caller and this workflow run from the PR's merge commit: a `./` reusable
workflow comes from the same commit as its caller. A PR that edits `.github/workflows/**`
therefore controls both, and the base-SHA reads above guard only against changes outside
`.github/workflows`. The real bound is who can push `.github/workflows`: kyle-sexton, and Apps
holding the `workflows` permission, such as the standards sync bot.
