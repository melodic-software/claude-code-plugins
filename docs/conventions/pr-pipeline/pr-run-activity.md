# pr-run-activity

Two reusable workflows run one activity of one lane each and end in one check run named
`<lane> / <activity>`: `success`, `failure`, or `neutral` with a skip reason.

- [`pr-run-activity-read.yml`](../../../.github/workflows/pr-run-activity-read.yml) runs an
  activity whose effect is `read`. It declares no App key secret and no `id-token` permission, and
  fails red with `effect-not-read` before the head checkout for any other effect.
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

A write activity calls `./.github/workflows/pr-run-activity-write.yml` the same way, passes no App
key, and adds `id-token: write` to the calling job's permissions.

| Input | Default | Meaning |
|---|---|---|
| `lane` | required | The lane, its workflow's file stem |
| `activity` | required | The activity, one of the lane's slots |
| `config-path` | `docs/conventions/pr-pipeline.yaml` | For test callers only (below) |
| `pr-number` | `''` | The PR on `workflow_dispatch` |
| `default-model` | `''` | The model when the activity sets none; empty omits `--model` |
| `default-max-turns` | `75` | The turn budget when the activity sets none |
| `timeout-minutes` | `30` | The run job's timeout; the report job's is fixed at 10 |
| `dispatcher-run-id` | `''` | Write file only: the `pr-unblock-dispatch.yml` run that sent a `github-actions[bot]` `workflow_dispatch` (run job step 3) |
| `trusted-base` | `pr-base` | Write file only: `pr-base` trusts the PR's base SHA, `default-tip` the default branch tip (run job step 4) |
| `escalation-reason` | `''` | Write file only: the escalating run's `escalation-reason` output, for a `report-escalation` script; anything outside the enum fails step 1 |

The write file has one `workflow_call` output, `escalation-reason`: empty, or why a
[`prepare: merge-base`](#prepare-merge-base) activity handed the PR to a person.

Secrets are passed by name, never `inherit`: `claude-code-oauth-token` (skill activities, both
files) is the only one. Variables: `CLAUDE_LANES_DISABLED` (the kill switch),
`AUTOMATION_LANES_APP_SENDER_ID`, the App bot's numeric user id, the one place it is written, and,
for the write file, `LANES_BROKER_URL` and `LANES_BROKER_AUDIENCE`
([below](#the-lane-token-broker)). The run job's first step fails red when
`AUTOMATION_LANES_APP_SENDER_ID` is not a numeric id, since an unset value would let the App's own
events through the self-trigger guard.

Both jobs set up Node 24: `resolve-config` uses `path.matchesGlob`, and the actions' suites run on
Node 24.

The caller must:

- Grant the calling job `contents: read`, `pull-requests: read` and `checks: write`, plus
  `id-token: write` when it calls the write file. The `run` job narrows this to the two reads, and
  `id-token: write` in the write file; only the `report` job uses `checks: write`.
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
   `pull_request` events are skipped by the job `if:` in both files. The write file passes its
   `dispatcher-run-id` input with `dispatcher-workflow: .github/workflows/pr-unblock-dispatch.yml`
   and `dispatched-workflow: .github/workflows/pr-unblock.yml`, so a `workflow_dispatch` sent by
   `github-actions[bot]` proceeds only when it names a run of that dispatcher on the default branch
   whose window holds this run's creation, and this run is `pr-unblock.yml`; every other
   bot-sent dispatch stops with `untrusted-actor`. The checks are in the gate's README.
4. `check-trusted-base` asserts the PR targets the default branch and fails red otherwise. On `pull_request` the base
   branch is the event's `pull_request.base.ref`; on any other event (`workflow_dispatch`,
   `workflow_run`) it is read from the PR with the job's `GITHUB_TOKEN`. It then fails red unless
   the gate's `base-sha` is an ancestor of the default branch tip (`git merge-base --is-ancestor`),
   and checks that SHA out in `.base`. Nothing the PR's base branch chose runs before this check.
   With the write file's `trusted-base: default-tip` (`mode: default-tip`) it checks out the
   default branch tip instead, after the same checks: a PR in merge conflict keeps a stale base
   SHA, and the lane must run the tip's config and actions and merge the tip. The checked-out SHA
   is the `base-sha` output either way, and the merge's second parent in
   [`prepare: merge-base`](#prepare-merge-base).
5. `resolve-config`, with the gated `head-sha` and, in the write file, `prepare-supported: true`.
   An invalid config fails the step red and the check is a failure, never a skip. A config skip
   (`disabled-by-config`, `not-applicable-paths`, `not-applicable`, `awaiting-human`,
   `prerequisite-missing`) mints nothing. With a valid config, the read file fails red with
   `effect-not-read` unless the effect is `read`, and the write file fails red with `effect-read`
   when it is, whether or not the activity applies. For a `mutate-branch` activity the write file
   then re-reads the PR branch from `GET git/ref/heads/<head ref>` (`GET /pulls` can lag a push);
   when it no longer points at the gated head the activity skips with `superseded-sha`, mints
   nothing and runs no model turn. Other effects never write the branch and keep the gated head.
6. Write file only:
   [`request-lane-token`](../../../.github/actions/request-lane-token/README.md) gets the lane
   token from the broker ([below](#the-lane-token-broker)), before `select-trusted-text` and before
   any head checkout. The broker mints once per job, so a second request from this job is denied
   `already-minted`. The
   step fails red unless the grant this job resolved is `read` or `write` for each of `contents`,
   `pull-requests` and `issues` and the broker's answer equals it. The read file requests nothing
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
11. Checks out the trigger gate's `head-sha` with `persist-credentials: false` (full history for
    `prepare: merge-base`, else depth 1), then fails red unless `git rev-parse HEAD` equals that
    SHA. This replaces `.base`.
12. Runs the activity (below), then, in the read file, records whether the tree is dirty.
13. Writes `verdict.json` with `jq` (`if: always()`) and uploads it as
    `verdict-<lane>-<activity>-<run_attempt>`, unique per activity and attempt.
14. Write file only, `if: always()` whenever step 6 output a token: `actions/github-script`,
    pinned by SHA, so no binary resolved through `PATH` or `BASH_ENV` runs with the token, sends
    `DELETE /installation/token` with it, then `GET /installation/repositories`, and fails red
    unless they return 204 and 401. It is a backstop for an honest activity that did not clean
    up, not a control against a hostile one: the activity holds the token and can write the
    runner's files.

A stacked PR, one whose base is not the default branch, gets a failure check from step 4. Retarget
it to the default branch to run its lanes.

Its outputs are `base-sha`, `head-sha`, `pr-number`, `gate-reason`, `can-commit` and
`act-outcome`, plus, in the write file, `head-ref`, `merge-state` and `escalation-reason`. Every
one is computed by a runner step, never read from model text. All but `act-outcome`,
`merge-state` and `escalation-reason` are outputs of steps that ran before any head code:
`gate-reason` is the kill switch's reason if it stopped, else the trigger's if it stopped, else
empty; `head-sha` and `head-ref` are the trigger gate's; `base-sha` is set only by step 4, so it
is always on the default branch. `merge-state` and a pre-model `escalation-reason` come from the
prepare step, before any model turn; a post-model `escalation-reason` comes from `post.sh` after
it, and a forged one can only hand the PR to a person. `act-outcome` is the activity step's
outcome, except that a skill whose step succeeded is a failure when it took no model turn, when it
is a gate skill and the verdict check (below) fails, when its commits could not be moved onto the
PR branch, or when its merge commit failed or was not made; in `prepare: merge-base`, a clean merge
that skipped the skill is a success once its commit is promoted. These checks are steps that run
after the skill.

### Skill activities

The prompt is `/<plugin>:<skill> <args>`, followed, for an activity with the `changed-paths`
input, by those paths as further words. `resolve-config` computes them from the PR's file list
(`pulls/{n}/files`), never from head text: files the head still holds, matching the slot's `paths`
predicate when it has one, with a name of letters, digits and `_ @ + . -` only, no `.` or `..`
segment, no segment starting with `-` and no leading `@`, which would read as a file mention.
The paths are the job's scope, what the skill is asked to work on, not a limit on what it can
touch. For any effect but `read` they leave out instruction surfaces (`CLAUDE.md`,
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
`allowed-tools` decide what else it may use; `--max-turns`; and `--model` when one is set. The
plugin installs only from `$RUNNER_TEMP/base-marketplace` and loads from there, outside the working
directory, so `--allowedTools` also carries `Read(/$RUNNER_TEMP/base-marketplace/**)`: without
it the skill cannot read its own reference files. Commits go through the API, signed
(`use_commit_signing`), on a lane branch (`CLAUDE_BRANCH`) the job makes at the gated head SHA
when the grant can commit.

A skill with any effect but `read` also gets what it needs to do its job: `Edit`, `Write`, `Agent`
(for subagents such as a fix flow's semantic-diff check or a rubric fan-out) and
`mcp__github_file_ops__commit_files`, the action's signed-commit tool on `CLAUDE_BRANCH`, and a
scratch directory, `$RUNNER_TEMP/lane-scratch`, passed as `--add-dir` with an `Edit` rule on it so
its state files and its sandboxed `Bash` redirects land there. `--append-system-prompt` names that
directory, says no one can answer a question, and, when the grant can commit, tells it to commit
every file it changed with that tool: the prompt is the slash command alone, so without this the
skill leaves its edits uncommitted and the lane moves nothing. A `prepare: merge-base` skill
gets neither the tool nor that sentence: it stages its resolution and the runner commits
([below](#prepare-merge-base)). Its
`Bash` comes from its own `allowed-tools`, git included. `WebFetch` and `WebSearch` stay off
(`--disallowedTools`) unless a skill needs them. No rule limits which files it changes: with its
token it can change, commit and push any file in the repository, and claude-code-action writes
the token into the origin URL under `use_commit_signing`
(`src/github/operations/git-config.ts:129-133` at `ed670b4`), so a `git push` works too. The PR is
the review step: the review lanes, `ci-status`, review-thread resolution and the merge gate see
every lane commit. The hardening is the broker's scoped, hour-long token revoked when the job
ends, base-SHA config and runner, the trusted-actor filter, the kill switch,
`--setting-sources user`, an explicit `--permission-mode` and never `bypassPermissions`. The
residuals are in [Trust-root paths](README.md#trust-root-paths): the model can read its token
(`GH_TOKEN`, `GITHUB_TOKEN`, `.git/config`) until it is revoked, which is
[ADR 0055](../../adr/0055-load-nothing-head-controlled-into-a-pipeline-skill-activity.md)'s
accepted residual, a skill's own `Bash` grant can exceed its job (`Bash(git:*)` in
`ai-slop:audit`), and a lane commit can change instruction files the PR author's local session
later loads. The skill's final reply is uploaded as an artifact with the token string cut out.
`commit_files` builds each commit on the live tip of `CLAUDE_BRANCH` with file bytes from the
gated checkout (`src/mcp/github-file-ops-server.ts:226-367` at `ed670b4`), so committing straight
to the PR branch would overwrite a push made during the run. After the skill, a pinned
`github-script` step fast-forwards the PR branch to the lane branch only while the PR branch is
still at the gated SHA, and deletes the lane branch either way. When the PR branch has moved, the
lane's commits are dropped and the activity fails; the push that moved it starts its own
`synchronize` run, which gates the new head and redoes the activity. A raw `git push` from the
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
`subtype`, `is_error`, `num_turns`, `duration_ms`, the model names, and any `<local-command-stderr>`
text (lane token cut out) to the step summary and to `act-turns.json` in the same artifact. The
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
(or its recorded absence) before the script runs.

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
   since the snapshot); otherwise it writes the index as a tree.
4. With no escalation reason and a tree, a pinned `github-script` step commits through the Git
   Data API: it fails unless the lane branch is still at the gated head, uploads only the blobs
   `tree-entries.sh` flags (logging `created <k> blobs`), builds the tree on the gated head's tree
   and fails unless it hashes to `post.sh`'s tree, re-reads the PR's labels with the job's
   `GITHUB_TOKEN` and stops uncommitted (`awaiting-human`) when `do-not-merge` or the base's
   human-gated role label is on the PR, then creates the commit
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
stops for a hold only at the commit step's label re-read.

The run's `escalation-reason` output is prepare's or `post.sh`'s reason, one of
`protected-path-conflict`, `workflow-staged`, `repeat-cap` or `unresolved-conflict`; a caller
passes it to its `report-escalation` job as that job's `escalation-reason` input. Every path and
its check:

| Path | act-outcome | skip reason | escalation-reason | Check |
|---|---|---|---|---|
| Head moved before mint | skipped | `superseded-sha` | empty | neutral |
| Hold label present | skipped | `awaiting-human` | empty | neutral |
| Pre-model escalation | skipped | `awaiting-human` | `protected-path-conflict` / `repeat-cap` / `unresolved-conflict` (no markers) | neutral |
| Clean merge, no model turn, committed, promoted | success | none | empty | success |
| Clean merge, `post.sh` exits non-zero | failure | none | empty | failure |
| Hold label added during the run, found before the commit | success | `awaiting-human` | empty | neutral |
| Model left a conflict | success | `awaiting-human` | `unresolved-conflict` | neutral |
| Model staged a `.github/workflows/` change | success | `awaiting-human` | `workflow-staged` | neutral |
| Resolved, committed, promoted | success | none | empty | success |
| Commit step fails or lane branch moved | failure | none | empty | failure |
| PR branch moved during run (promote) | failure | none | empty | failure |
| Conflicted but no model turn | failure | none | empty | failure |
| A prepare step fails | skipped | none | empty | failure (run job failed) |
| A post-skill step fails | success | none | empty | failure (run job failed) |

Residual: a `.github/workflows/` change from the base side of the merge (not conflicted, not
staged by the model) is committed and pushed. GitHub does not refuse it for the App's missing
`workflows` permission: sandbox probe run 38148710292 pushed such merges by all three methods.

The head re-read in step 5 applies to every `mutate-branch` activity, not only this mode: a
pr-refine run whose PR branch moved before the mint now posts neutral `superseded-sha` without a
model turn.

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
`dirty-tree` counts only as `true` (failure). A missing verdict is a failure. A cancelled run job
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
OIDC token.
[`scripts/check-read-caller-keys.sh`](../../../scripts/check-read-caller-keys.sh) enforces the
key rule in `lint-repo`: it parses every workflow, walks up from `pr-run-activity-read.yml` to every workflow
whose run can reach it (a job-level `uses:` in `./` or `melodic-software/claude-code-plugins/...@ref`
form, any case) and down through every reusable workflow those runs call. It fails when a file of
such a run names `AUTOMATION_LANES_APP_PRIVATE_KEY` or `app-private-key` in a key or value, has a
`private-key` key, passes `secrets: inherit`, or has a `${{ }}` expression, in a key, a value or a `#` line of
a `run:` block, whose `secrets` reference is not `secrets.<name>` with `<name>` on the allowlist
`claude_code_oauth_token`, `github_token` (case-insensitive, `-` read as `_`); `toJSON(secrets)`,
`secrets[...]` and bare `secrets` fail. It also fails when the read file names `id-token`.

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
`pr_number` is the gate's PR and is required off `pull_request`. `dispatcher_run_id`, a positive
JSON integer, is the `dispatcher-run-id` input, sent only when set. The broker reads it only when
the OIDC actor is `github-actions[bot]`: such a run mints only when the `pr-unblock-dispatch.yml`
run it names passes the checks the trusted-trigger gate applies. That run must be on `main`,
started by a push or a listed human, with a re-run attempt started by a listed human. Its head
must be an ancestor of the tip and no tag may be named `main`. This run must be a `pr-unblock.yml`
`workflow_dispatch` created between the dispatcher run's `run_started_at` and the earlier of its
`updated_at` and `run_started_at` plus 10 minutes. The client sends it once and never retries: the broker
reserves the job's `check_run_id` when it mints, so a second request is denied `already-minted`,
and a 200 lost in transit leaves a token nobody revokes until it expires within the hour.

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
| 400 | (none) | The body is not `{lane, activity, pr_number?, dispatcher_run_id?}` with valid names and positive integers |
| 403 | `invalid-token`, `wrong-audience` | The OIDC token does not verify, or is for another audience |
| 403 | `wrong-owner`, `repo-not-allowed`, `self-hosted-runner` | Not a melodic-software repository on the broker's allowlist, or not a GitHub-hosted runner |
| 403 | `event-not-allowed` | Not `pull_request` on `refs/pull/<n>/merge`, or `workflow_dispatch` or `workflow_run` on `refs/heads/main` |
| 403 | `workflow-not-allowed` | The job is not this repository's `pr-run-activity-write.yml`, or the caller is not a lane under `lanes:` in the tip's `pr-pipeline.yaml` |
| 403 | `workflow-modified` | The caller or `pr-run-activity-write.yml` differs from the default-branch tip |
| 403 | `workflow-modified` | With `dispatcher_run_id`: `pr-unblock-dispatch.yml` at the dispatcher run's head differs from the tip |
| 403 | `lane-mismatch` | The requested lane is not the caller's file stem |
| 403 | `activity-not-in-lane`, `slot-disabled`, `config-invalid`, `effect-forbidden-by-lane` | The tip config does not give this activity a write grant |
| 403 | `effect-read` | The activity is `read`; it belongs in the read file |
| 403 | `untrusted-actor`, `untrusted-author`, `bot-actor` | The actor, the PR author or a re-runner is not on the tip's trusted-actor list, or is the lanes bot |
| 403 | `untrusted-actor` | With `dispatcher_run_id` from `github-actions[bot]`: the dispatcher run or this run is missing or fails a dispatcher check above |
| 503 | `github-unavailable` | With `dispatcher_run_id`: a dispatcher, run, tag or compare read failed; nothing was minted |
| 403 | `pr-not-eligible` | The PR is not open, not from a branch of this repository, or does not target `main` |
| 403 | `default-branch-not-main` | The repository's default branch is not `main` |
| 403 | `kill-switch` | The organization's `CLAUDE_LANES_DISABLED` is not exactly `false`, or a repository variable of that name is set to anything else |
| 403 | `already-minted` | This job already received its mint |
| 503 | `key-unavailable`, `github-unavailable`, `store-unavailable` | The broker could not sign, read GitHub, or record the mint; nothing was minted |

A `kill-switch` denial is red, not neutral: step 3 already stopped the common case, so the denial
means the job's read and the broker's read of the switch disagreed.

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
