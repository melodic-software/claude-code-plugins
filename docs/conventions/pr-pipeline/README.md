# PR pipeline convention

## Contents

- [Files](#files)
- [Stages](#stages)
- [Lanes](#lanes)
- [Activities](#activities)
- [Patch rules](#patch-rules)
- [Slots and order](#slots-and-order)
- [Concurrency](#concurrency)
- [Outputs and skips](#outputs-and-skips)
- [Merge authority](#merge-authority)
- [Trust-root paths](#trust-root-paths)
- [The lane sweep](#the-lane-sweep)
- [The monitoring lane](#the-monitoring-lane)
- [Models](#models)
- [Funding](#funding)
- [Loop caps](#loop-caps)
- [Limits](#limits)
- [WIP cap](#wip-cap)
- [Planning lane work](#planning-lane-work)
- [Changing this config](#changing-this-config)
- [Outside this repository](#outside-this-repository)
- [Names](#names)
- [Not settled yet](#not-settled-yet)
- [Versioning](#versioning)

Owner doc for the PR pipeline: the fixed sequence of GitHub Actions lanes a pull request passes
through once it is marked ready, until it merges. Local sessions stop at "ready"; the lanes run the
rest and a human steps in only where a lane escalates or a rung requires it. This doc fixes the
shape every PR-side lane builds on. Each lane's mechanics live in its workflow and the skills it
calls, not here.

The loop-lane convention ([`loop-lane`](../loop-lane/README.md)) governs local loop sessions; this
convention governs CI lanes. Holds, escalation and work classes stay owned by loop-lane and the
autonomy plugin, and this doc points at them.

## Files

| File | Holds |
|---|---|
| `README.md` | This contract. No config values. |
| `pr-pipeline.schema.json` | Schema for a repository's pipeline config. |
| `examples/` | Worked configs that show the shape. Script paths in them are placeholders until their lanes land. |
| `CHANGELOG.md` | Contract versions, written by the release pull request from fragments under `.changes/pr-pipeline/`. |

A repository's config lives at `docs/conventions/pr-pipeline.yaml` unless the lane passes another
path as the config reader's `config-path` input. The reader reads that path at the base SHA; it
must be relative with no `..`, have the basename `pr-pipeline.yaml`, and sit outside
`.github/actions/**`. Config values live only in that YAML file; agent instructions live only in
Markdown.

## Stages

A PR moves through these stages in order. Stages are named, never numbered, so a new stage needs
no renumbering.

| Stage | What happens | Starts on |
|---|---|---|
| `intake` | Issues are triaged into work items. | issue events |
| `work` | An agent works one issue a person labeled `agent-ready` to a PR opened ready, or hands it back ([Issue mode](pr-run-activity.md#issue-mode)). | the `agent-ready` label |
| `pre-ready` | The implementer writes the change and may push draft checkpoints at any time. Local today; the design assumes no particular implementer. | the implementer |
| `refine` | Behavior-preserving changes that make the PR review-ready: simplify, tidy, docs and format fixes. One push at the end. | ready (or opened ready) |
| `verify` | Checks, reviews and outcome verification on the refined commit. Mechanical and judgment lanes start together; a failed mechanical gate cancels the running judgment lanes, and `pr-require-checks` aggregates the results into `ci-status`. | dispatch from `refine` |
| `unblock` | Take the action that unblocks a PR: today, resolve conflicts with the base branch. Fixing failing CI and addressing review feedback join as composites. | see [Lanes](#lanes) |
| `merge` | Merge, within the configured rung. | final check green, or a hold removed |
| `post-merge` | Verify the default branch and sweep late comments into issues. | push to the default branch |

`maintenance` and `upstream` are scheduled producers, not steps in a PR's path. They file work
into `intake`.

An answered issue re-enters `intake` through
[`intake-reenter.yml`](../../../.github/workflows/intake-reenter.yml), a scripted workflow with no
model. On a new comment on an open issue, not a pull request, it acts on a `status: needs-decision`
issue whose comment is a decision (first line `**Decision recorded.**`, by a human on the
trusted-actors list, not posted through an App, unedited or last edited by a listed human), or on a
`status: needs-info` issue whose comment is by the issue's author or a listed human. It removes that
status label, and `needs-human` for a decision, and adds `needs-triage`. It dispatches
`intake-triage.yml` once only when the issue's author is one intake admits on open (a listed human
or the lanes App); any other issue waits in `needs-triage` for a person, so an outside author
cannot start a model run with each reply. A dispatch skips the born-triaged check. Removing the status label is the
claim, so a second answer dispatches nothing. It never adds `agent-ready`, and it holds the job's
own `GITHUB_TOKEN` (`actions: write`, `contents: read`, `issues: write`), never a lanes App token.

Pipeline lanes skip draft PRs; `ci-status` still reports on them, and passes the skipped lanes.
The `ready_for_review` run tests the head, and the merge queue re-runs every lane before a merge.
Converting a PR back to draft
cancels every running pipeline lane for it.

## Lanes

A lane is one workflow with one model job; scripted jobs beside it report its check runs. The lane
name is its workflow file stem, and the lane never does another lane's job. Each activity runs
through one of two shared runners:
[`pr-run-activity-read.yml`](../../../.github/workflows/pr-run-activity-read.yml) for a `read`
effect, with no App key and no OIDC token in the job that runs head code, after a separate job
asks the lanes token broker whether the lane may run, and
[`pr-run-activity-write.yml`](../../../.github/workflows/pr-run-activity-write.yml) for any other
effect, which gets its effect-scoped App token from the lanes token broker before any head
checkout. No workflow holds the App key. Their job contract is
[`pr-run-activity.md`](pr-run-activity.md).

Each lane's stage, the effects and gating it may not use, and what it never does are in
[`lane-rules.json`](../../../.github/actions/resolve-config/lane-rules.json), which the config
reader applies.

| Lane | Starts on |
|---|---|
| `pr-refine` | a PR opened, reopened or marked ready, or a `workflow_dispatch`; not each push, so a docs change pushed after its first run waits for a reopen or a dispatch |
| `pr-run-checks` | dispatch from `pr-refine` |
| `pr-review`, `pr-review-security` | dispatch from `pr-refine` |
| `pr-verify` | dispatch from `pr-refine` |
| `pr-explain` | dispatch from `pr-refine`, alongside verify |
| `pr-require-checks` | each verify result |
| `pr-unblock` | a dispatch for each conflicting PR and each unreviewed review-tier Dependabot PR after a push to the default branch, a dispatch after a review lane finishes on a lanes App PR with an open reviewer-bot thread, or a trusted human's dispatch |
| `pr-merge` | final check green, or a hold removed |
| `work-unblock` | an issue closing, by a listed human, and an hourly sweep of the issues a listed human or a merge (a merged PR or a commit) closed in the last three hours (catching PR merges a bot ran); labels `agent-ready` on each issue it blocked that is now unblocked, unheld and owner-ratified; the label starts `work-resolve-issue` once resolve-issue accepts App-added labels (follow-up by Automation Lanes) |
| `post-merge-verify` | push to the default branch |
| `post-merge-sweep-comments` | push to the default branch |

`pr-unblock`'s dispatches come from `pr-unblock-dispatch.yml`, a scripted workflow with no model
that runs on a push to `main` and on a trusted human's `workflow_dispatch`:

- It lists open, non-draft, same-repository PRs into `main` that GitHub reports as `CONFLICTING`,
  re-querying an `UNKNOWN` PR up to 5 times, 10 s apart.
- It skips a PR whose head already has a `pr-unblock / resolve-conflicts` check run from the
  GitHub Actions app, unless that run is a neutral `Skipped: untrusted-trigger`.
- It dispatches `pr-unblock.yml` on `refs/heads/main` for at most 3 PRs per run, lowest number
  first, passing `pr-number` and `dispatcher-run-id`.
- A hand run or a re-run must be started by a listed human (`check-trusted-trigger` with
  `require-pr: false` and `require-kind: human`).
- With the kill switch on, the run ends green with a notice and dispatches nothing.

GitHub starts no `pull_request` workflow on a PR with a merge conflict, so a conflicted head gets
no CI. When `resolve-conflicts` escalates with `unresolved-conflict`, `pr-unblock.yml`'s
`report-conflict-status` job (a script job with no model, the lane's only `statuses: write`, on its
own `GITHUB_TOKEN`) posts a `failure` commit status with context `pr-unblock/conflict` on that
head, saying CI does not run until the conflicts are resolved. A push that resolves them is a new
head, which the status does not reach. A conflict that clears with the head unchanged (main moved
again) leaves the failing status on it until a push or a person replaces it. The other
`resolve-conflicts` escalations post no status; they hand the PR to a person through the comment
and label alone.

`pr-unblock`'s `address-feedback` dispatches come from `pr-feedback-dispatch.yml`, also scripted,
on `workflow_run` `completed` of `pr-review-hosted` and `pr-review-security-hosted`. It takes only
the upstream run id from the event and reads the rest back. It dispatches `pr-unblock.yml` with
`activity: address-feedback` when the upstream is a `pull_request` run of one of those two paths in
this repository, exactly one open non-draft PR into `main` has its head, the lanes App opened that
PR, it carries no `do-not-merge`, both lanes' newest reviewed-head markers
name the head, an unresolved thread exists that `address-feedback` would keep (left only by the
reviewer bot, one the lane never answered where a fix request, below, follows the reviewer bot's
finding, or answered by a trusted human after the lane escalated it; on a PR carrying the
human-gated label, only one whose answer is a fix request), the head has no
`pr-unblock / address-feedback` check run, and no `pr-unblock.yml` run titled
`pr-unblock address-feedback #<n>` is still queued or going (both lanes finishing at once). Then it
runs the base's resolve-config for that PR and head with `address-feedback` selected, so only that
slot's `applies-when` is decided, and dispatches only when the `pr-unblock` lane and its
`address-feedback` and `publish-feedback` slots are enabled and `address-feedback` applies. It records `pr-feedback-dispatched-<upstream id>-<run
id>`, which the gate and the broker read to tie the run to a review of the PR's current head.
In `pr-unblock.yml`, `address-feedback` (the model job, `mutate-branch`) is followed by
`publish-feedback` (a script job with no model, `publish-artifact`), which posts the replies the
model job recorded ([`pr-run-activity.md`](pr-run-activity.md#prepare-review-threads)).

A fix request is a reply by a person on the trusted-actor list who holds write or admin
permission on the repository, never edited, or last edited by a person on that list, with a line that starts with
`PR-fix lane: please fix this finding`, in any letter case, outside a fenced code block (a quoted
`>` line never matches). On a thread the lanes App never commented on, one fix request after the
reviewer bot's finding makes the thread one `address-feedback` works, as long as every other
comment is the reviewer bot's or a trusted person's; their comments from the first fix request on
are direction. Such a thread, and one a trusted person answered after the lane escalated it, is
worked even when its review is on an earlier head than the one the reviewed-head markers name.
`pr-feedback-dispatch.yml` runs only when a review run completes, so a fix request posted after
the head's review starts nothing on its own. To start the round, an account on the trusted-actor
list dispatches the lane directly:

```bash
gh workflow run pr-unblock.yml -R melodic-software/claude-code-plugins -f pr-number=<n> -f activity=address-feedback
```

That run names no dispatcher run, so the gate checks that account as the actor, and the select
step judges the threads as above.

On a PR carrying the human-gated role label (`needs-human` unless the base's
`.work-item-tracker.json` names another), `address-feedback` works a thread only when it carries
a fix request, after the lane's escalation when there is one. Without such a
thread the dispatcher starts nothing and the select step skips with `awaiting-human`, so the PR
stays held; with one, the write runner lifts only the human-gated hold for that run, and
`do-not-merge` still stops it. `pr-merge` refuses the PR either way.

`pr-unblock`'s `review-dependency` dispatches come from the same `pr-unblock-dispatch.yml` run,
so the gate and the broker check them as they check a conflict dispatch. After the conflict
dispatches it lists open, non-draft, same-repository Dependabot PRs into `main`, sorts each with
`dependency-classify.mjs`, and dispatches `pr-unblock.yml` with `activity: review-dependency` for
at most 2 `review`-tier PRs per run whose head has no `pr-unblock / review-dependency` check run
from the GitHub Actions app (the untrusted-trigger skip aside). Their run ids join the same
dispatched-runs record. It has no schedule: the broker accepts a dispatcher run started only by a
push or a listed human, so a push to `main` or a hand run wakes it. In `pr-unblock.yml`,
`review-dependency` (the model job, `mutate-branch`) is followed by `apply-dependency-verdict` (a
script job with no model, `publish-artifact`), which acts on the verdict the model job recorded
and never merges; the pr-merge lane merges on its `verdict=merge` marker at the current head
([`pr-run-activity.md`](pr-run-activity.md#prepare-dependency-review);
[ADR 0074](../../adr/0074-review-risky-dependabot-updates-in-a-model-job-and-act-in-a-scripted-job.md)).

`pr-unblock`'s `fix-ci` runs in three jobs of `pr-unblock.yml`, so no model holds a write token:
`fix-ci-context` (base code only, read-only token) writes the failing checks' context or hands
the pull request to a person once `loop.fix-ci-rounds` fixes were pushed; `fix-ci` (a `read`
skill in [patch output mode](pr-run-activity.md#patch-output-mode)) runs
`source-control:pull-request ci --ci`, which reruns, fixes and reruns the checks; and
`apply-ci-fix` (a `mutate-branch` script, no model, no head code) pushes the patch as one commit
without force, refusing the whole patch on any change to `.github/**`, an agent instruction path
(`CLAUDE.md`, `AGENTS.md`, `.claude/` or `.claude-plugin/`, a plugin's `hooks/`, `.mcp.json`,
`.gitmodules`, `CODEOWNERS`), a symbolic link or a gitlink
([`prepare: ci-context`](pr-run-activity.md#prepare-ci-context),
[`prepare: apply-patch`](pr-run-activity.md#prepare-apply-patch)). An empty, invalid or
unappliable patch, or a check the model escalated, goes to `report-escalation`. The same
`pr-unblock-dispatch.yml` run starts `fix-ci`, after the conflict and Dependabot dispatches: one
GraphQL query per page of 50 open pull requests, its `rateLimit.cost` logged, lists the non-draft,
same-repository ones into `main` that the lanes App opened (by bot id), with no `do-not-merge`
or `needs-human` label, whose head's `ci-status` check run from the GitHub Actions app ended
`failure`. It dispatches those whose head has no `pr-unblock / fix-ci` run yet (an
untrusted-trigger skip aside), or only failed ones, at most `limits.fix-ci-restarts` of them,
and no `fix-ci` run for the PR still queued or going, at most `limits.fix-ci-per-run` per run,
lowest number first. Their run ids join the dispatched-runs record. The dispatcher job's
concurrency group cancels a run in progress, so a burst of pushes ends in one listing.

`workflow_run` runs the default-branch copy of a workflow with secrets; the conditions fixing CI
from it holds to are in [ADR 0051](../../adr/0051-start-pr-fix-ci-from-workflow-run-for-same-repository-trusted-prs.md).
Lanes run on GitHub-hosted runners without default-deny egress under the conditions in
[ADR 0049](../../adr/0049-run-ci-lanes-on-github-hosted-runners-under-trigger-and-token-hardening.md).
Lane commits are signed, and signing is enforced by the default-branch rule only:
[ADR 0054](../../adr/0054-keep-commit-signing-on-the-default-branch-rule-and-add-no-all-branch-rule.md).

Every lane:

- Acts only on same-repository PRs, and only trusted actors' text reaches its prompt. The filter
  runs per item: each comment, review reply and linked issue is checked by its own author, not by
  the PR's. Web pages and CI logs are untrusted wherever they came from and stay data. The
  trusted-actor list is one central standards component that every lane reads.
- Runs Claude Code with `--permission-mode dontAsk` and the tools its skill needs to do its job: a
  write-effect skill can change, commit and push any file in the repository with its token
  ([`pr-run-activity.md`](pr-run-activity.md#skill-activities)). It gets the write access its job
  needs through a short-lived, job-scoped App token, revoked when the job ends. Local lanes keep
  auto mode (AGENTS.md). Capability is never removed for safety: a lane's scope comes from how
  granular its activity is, the PR is the review step, and safety comes from who can trigger a
  lane, token lifetime and scope, workflow execution protections, the kill switch, and a
  `ci-status` no lane can write (below).
- Reads its config, scripts and the trusted-actor list from the base SHA, never from the PR head,
  so a PR cannot change the rules it is judged by. Only the default branch is a trusted base, and a
  skill activity loads nothing else from the head:
  [ADR 0055](../../adr/0055-load-nothing-head-controlled-into-a-pipeline-skill-activity.md).
- Checks the org and repository kill switches before its model step starts, and runs only when
  both read exactly `false`.
- Never holds `checks: write` or `workflows` permission in a job that runs the model. `ci-status`
  and the `<lane> / <activity>` check runs are written by scripted jobs with no model step, and
  branch protection pins `ci-status` to the source that writes it
  ([ADR 0053](../../adr/0053-run-each-pipeline-activity-as-a-model-job-and-a-scripted-report-job.md)).
  A base merge escalates to a human instead of being pushed when a path under
  `.github/workflows/` is left conflicted by the merge (before any model turn), or when the model
  staged a change under `.github/workflows/` (after it). A workflow change that comes cleanly from
  the base is merged and pushed with the rest.
- Writes through one per-PR queue (a concurrency group that queues, never cancels; see
  [Concurrency](#concurrency)). It pushes its own commits as fast-forward updates, never with
  force. A head that moved before the token mint skips the run with `superseded-sha`; one that
  moved during the run fails its push. Either way a later run on the new head does the work.
- Works each layer of a stack but touches only the lowest unmerged layer when fixing, and never
  rebases a stack.
- Respects the cross-lane hold, the `do-not-merge` label
  ([loop-lane](../loop-lane/README.md#cross-lane-pr-hold)), and the merge rule in AGENTS.md. A lane
  escalates through the `needs-human` role in the same section's escalation contract.

## Activities

An activity is one unit of lane work with a declared contract. A leaf is a skill invocation, or a
scripted step with no model in it (the merge act and `ci-status` are scripted). A composite groups
leaves under `children:`, a list of slots with the same keys and order rules as a lane's
`slots:`, and may set an `applies-when` that gates every child. Every activity is defined once
under `activities:` and referenced by key from lane slots or composite children, so moving it is a
config edit and the skill itself never changes.

A composite holds only leaves, so no leaf sits more than two layers below its lane. It declares no
effect, gating or inputs: each leaf keeps its own, gets its own grant, runs as its own job and
reports its own `<lane> / <leaf>` check, and the lane's rules apply to every leaf. A leaf runs only
when its lane, every slot on its path and its own slot are enabled, and when the composite's
predicate and its own both match. A leaf key appears at most once in a lane, so the key alone
selects it.

Each leaf declares:

- `skill` (`<plugin>:<skill>`) or `script` (a repository path), with optional `args` passed
  verbatim: after the skill name in that skill's own syntax, or to the script.
- `prepare` (optional): what the runner does around the activity. `apply-patch` is the one mode
  for a script (a `mutate-branch` one), `ci-context` the one mode for a `read` skill, and the
  others need a skill with an effect other than `read` until their activity hands its change on
  as a patch ([`pr-run-activity.md`](pr-run-activity.md#prepare-ci-context)). `merge-base` merges the base tip into the gated head without committing before the
  skill runs, and commits the result with both as parents after it. `review-threads` keeps the
  PR's unresolved reviewer-bot threads and decides skip, escalate or proceed before any model
  turn, gives the skill the review-thread tool, and uploads the replies it records for a reply job
  with no model to post ([`pr-run-activity.md`](pr-run-activity.md#prepare-review-threads)). A runner performs this
  only where it declares support by passing `prepare-supported: true` to `resolve-config`; anywhere
  else an applying leaf that sets `prepare` fails red rather than running without it.
- `applied-by` (optional, `skill` only, effect `read` and gating `advisory`): what the skill
  hands on, keyed by artifact (`patch`, `feedback-replies`, `dependency-verdict`,
  `work-outcome`), each naming the script activity that applies it. A `patch` target runs
  `prepare: apply-patch` ([patch rules](#patch-rules)). Every lane that holds the producer holds each target, in a slot
  whose `needs` names the producer. A runner hands on only the keys it passes as
  `applied-by-supported` to `resolve-config` (`pr-run-activity-read.yml` passes `patch`); an
  applying leaf with any other key fails red before the head checkout. A skill that hands on a
  patch gets the same edit tools as a write skill and commits nothing. The read runner collects
  its uncommitted change as a patch only when the caller passes `output-mode: patch`; no activity
  sets `applied-by` today. Those edit tools and the `changed-paths` filter key on "an effect other than
  `read`, or `applied-by.patch`"; the effect half goes once the last skill leaves
  `pr-run-activity-write.yml`.
- `checks` (optional, `skill` only): repository check scripts, each `scripts/<name>.sh` with its
  flags fixed, that the skill may run. The runner that gives the skill its edit tools (the write
  runner, or the read runner for a skill that hands on a patch) runs each from the base copy
  against the checkout, so no head code runs, and tells the skill to fix what
  a check reports before it reports done
  ([`pr-run-activity.md`](pr-run-activity.md#skill-activities)). The schema refuses `checks`,
  `self-checks`, `verify-scripts` and `web-access` turned on for any other skill (effect `read`
  without `applied-by.patch`, or with `prepare: ci-context`), where they would do nothing.
- `self-checks` (optional, `skill` only): the same shape as `checks`, run and fixed by the skill
  through the same wrapper before it commits or hands its change on. Advisory: unlike `checks`, no
  runner job reruns them, so a failure the skill cannot fix still opens the PR and is named in its
  report. A script in both lists fails red.
- `verify-scripts` (optional, `skill` only): exact repository-relative paths of scripts, each `scripts/<name>.sh`, `plugins/<plugin>/scripts/<name>.sh` or
  `plugins/<plugin>/skills/<skill>/scripts/<name>.sh`, that the skill may run with any arguments
  but a path outside the checkout. The runner that gives the skill its edit tools runs each from a read-only base copy of its plugin (or of `scripts/`) against
  the checkout, with `GH_TOKEN` and `GITHUB_TOKEN` unset; code it runs can still read the token
  from an ancestor process's `/proc/<pid>/environ`
  ([`pr-run-activity.md`](pr-run-activity.md#skill-activities)). The arguments are the model's, so
  a script that changes files, runs code from the checkout or reaches the network hands the run
  that power: list one only when it limits itself, as `scripts/run-test-file.sh` (one test file
  inside the checkout), `scripts/git-mv-rm.sh` (`git mv` and `git rm` inside the checkout) and
  `scripts/new-changelog-fragment.sh` (new files under the checkout's `.changes/` only) do,
  or when the run may hold that power, as `plugins/skill-quality/scripts/check-skill.sh` (each
  checked skill's `scripts/*.test.sh` and the checkout's markdownlint) does.
- `web-access` (optional, `skill` only, off when absent): `enabled` and `domains`, either `any` or
  a list of host names (`*.` allowed as a prefix). When on, the skill may search the web, fetch
  those domains, and run the research skills, wherever the runner gives it its edit tools
  ([`pr-run-activity.md`](pr-run-activity.md#skill-activities)). An activity that turns it on must
  set `reads-untrusted: true`.
- `effect`: one of `read`, `mutate-branch`, `mutate-tracker`, `publish-artifact`, `merge`. The
  runner derives ordering from it, takes the token grant from
  [`effect-grants.json`](../../../.github/actions/resolve-config/effect-grants.json), and fails a
  `read` activity that leaves the working tree dirty unless it hands its change on as a patch. An
  activity that runs head code (tests, linters, builds) takes effect `read`, because a
  write-effect activity must not execute head code. To change the branch it hands its change on
  to a `prepare: apply-patch` script with no model and no head code: today fix-ci does this
  through its caller's `output-mode: patch` and `apply-ci-fix`; the target state names the script
  in the skill's `applied-by.patch`.
- `gating`: `gate` feeds `ci-status`; `advisory` is reported only. `ci-status` stays the only
  required check. A `gate` skill activity must not execute head code, since its verdict is read
  in the same job after the skill ran; tests, linters and builds that gate run as a `script`
  activity or under a separate design.
- `reads-untrusted`: whether it reads issue, PR, comment, web or CI-log text, or PR head files,
  which can quote such text. Ingested text is data, never instructions
  ([`untrusted-content`](../untrusted-content/README.md)).
- `inputs`: typed, from a closed set (`base-sha`, `head-sha`, `changed-paths`, `pr`, `issue`,
  `baseline`, `findings`). An activity reads nothing from a session. `changed-paths` is computed
  by the base-SHA config reader from the PR's file list, never from head text. It names what the
  activity is asked to work on, not what it can touch; for an activity that edits (an effect
  other than `read`, or a skill that hands on a patch) it leaves out instruction surfaces and
  paths `.github/CODEOWNERS` lists
  ([`pr-run-activity.md`](pr-run-activity.md#skill-activities); `changedPathTargets` in
  [`resolve.mjs`](../../../.github/actions/resolve-config/resolve.mjs)). When nothing is left, the
  activity skips with `not-applicable-paths`: `pr-refine / fix-docs` does not run on a PR whose
  only changed Markdown is instruction surfaces or CODEOWNERS paths, such as this directory.
- `scope` (`diff`, `tree`, `target`) and `applies-when` (paths, labels, `labels-absent`, work
  classes, events, `mergeable`, `draft`, `labeled-after`, `admission`). `mergeable` is `conflicting` or `clean`,
  read from the PR at the gated head SHA only; unknown mergeability never matches. `labels-absent`
  matches only when none of its labels is on the PR. `labeled-after`, a UTC time, is an issues
  lane's go-live time: it matches only an issue labeled after it. `admission` is an issues lane's
  work-class rule: an issue carrying a `work-class:` label outside `classes` is refused, even
  beside a listed one; otherwise a listed class admits it. With no `admission`, the triggering
  label alone admits the issue; this repository's resolve-issue sets none, so `agent-ready`
  added by a listed human or the lanes App admits, and its `labels-absent` holds keep an issue a
  person must decide.

An activity is idempotent: a rerun on the same commit gives the same verdict or reuses it, a
mutating activity with nothing to change makes no commit, and each commit it makes names the
activity in a trailer. A verdict is bound to the commit it judged and is not reused for any other commit.

When an activity needs a human, it escalates with a resume key and exits instead of blocking. An
activity whose `labels-absent` lists `needs-human` or `do-not-merge` skips with `awaiting-human`
while that label is on the PR; a human removes the label, then dispatches the lane, to resume it.
`labels-absent` reads only whether a label is present, not who set or removed it: it is a hold, not
a trust gate. An expedite label from a human with write access skips
`refine`. A label counts only when the actor on its label event is a trusted human: a label the App
set never resumes an item, expedites it, sets its work class or lifts a hold.

A pr-unblock escalation whose reason repository state can settle is also cleared without a
person. On its schedule, `pr-merge` rechecks each open PR into main carrying the human-gated
label and removes it, after one comment naming the reason and the head, when every reason the
lanes App's escalation comments recorded since the label went on no longer holds at the current
head:

| Reason | Cleared when |
|---|---|
| `workflow-staged` | main changes nothing under `.github/workflows/` since its merge base with the head |
| `unresolved-conflict`, `protected-path-conflict` | GitHub reports the PR mergeable |
| `feedback-protected-path` | the PR changes nothing under `.github/` |
| `head-moved` (pr-merge's `babysit-merge-verify-escalation` and `babysit-merge-risk`, with no pr-unblock escalation since the label, and the marked App comment written last before the label is pr-merge's and within a minute of it) | the newest App comment carrying each marker names, as ``at head `<sha>` ``, a 40-hex head other than the current one; pr-merge then judges the new head and escalates again if its refusal still holds |

It removes only a label whose newest `labeled` event has the lanes App as its actor, and keeps it
when a person commented, reviewed or left a review comment since that event (a bot account, such
as an AI review or another lane, does not count), or when an App comment
written or edited since then carries any marker other than the escalation being judged (another
`babysit-merge-*` marker, another lane's). Every other reason
(`unexpected-path-staged`, the round and repeat caps, and the `feedback-*`, `dependency-*` and
`ci-fix-*` verdicts) waits for a person. Rules: `.github/scripts/pr-merge/clear-escalations.mjs`.

Accepted risk: a person's request relayed through an App posts as a Bot account (`claude[bot]`
replying to an `@claude` mention that asks to wait), and so does a third-party App writing "needs
a human"; neither keeps the label. A person who wants the hold comments themselves or adds the
label back.

## Patch rules

[`patch-rules.json`](../../../.github/actions/resolve-config/patch-rules.json) is the registry
of what one `prepare: apply-patch` script is to admit from a producer's patch, read from the
trusted base: one row per prepare mode a patch-producing skill uses (`ci-context`,
`review-threads`, `dependency-review`, `merge-base`), `default` for one with no prepare mode, and
`issue` for a patch that goes to a new issue-lane branch made at the run's base or resume tip. No
apply step reads it yet; that script lands later, and until then fix-ci's patch goes through
`apply-ci-fix` with its own fixed refusal
([`prepare: apply-patch`](pr-run-activity.md#prepare-apply-patch)).
[`patch-rules.schema.json`](../../../.github/actions/resolve-config/patch-rules.schema.json) closes
each row to these keys:

| Key | Holds |
|---|---|
| `refuse` | Named refusals; any match refuses the whole patch. |
| `allow` | What every other changed path must also meet: `any`, `kept-threads` (the path of a thread the run kept) or `merge-result` (the blob the base merge leaves there, or a conflicted path left with no conflict markers). |
| `max-files` | The most paths one patch may change, or `null`. |
| `requires` | What the producer's output must say before anything applies: `dependency-verdict: fix`. |
| `commit` | `parents` (`[head]`, or `[head, base]` for a merge), `message` and `trailer`, with `{ref}`, `{base}`, `{lane}`, `{activity}` and `{issue}` filled in. |
| `reads-report` | The producer report the apply reads (`ci-escalations`: the checks the model escalated), or `null`. |
| `escalations` | The escalation reasons the apply may give for the row. |

Every row refuses `.github/**` in any case and through any `..` segment, `.claude/**` at any depth,
the root `.mcp.json`, `.gitmodules`, `**/settings*.json`, a symbolic link, a gitlink, an
executable bit on a file not already executable, and a rename into any of those. Plugin hooks,
`.claude-plugin/`, `lib/`, `scripts/`, `CLAUDE.md` and `AGENTS.md` are admitted: the
[HIGH path floor](#merge-authority) holds a pull request that touches them for a human merge.
`checkPatchRules` in
[`resolve.mjs`](../../../.github/actions/resolve-config/resolve.mjs) rejects a row without that
set, a `[head, base]` commit whose `allow` is not exactly `[merge-result]`, a refusal, allow or requirement name
the schema does not list, and a patch-producing activity whose prepare mode has no row;
`resolve-config` runs it before every lane resolve and fails closed when either file is missing.
`loadConfig` and `resolveGrant` do not read the registry, so the lanes token broker needs neither
file.

## Slots and order

A lane's `slots:` list names the activities it runs. Stage order is fixed by the table above; the
order inside a lane comes from config:

- Mutating slots run one at a time, in list order.
- Read slots run in parallel, each after the slots named in its `needs:`.
- A slot may replace its activity's `applies-when` or set `enabled: false`.

`refine` runs its steps in list order, format last, because earlier steps change whitespace.
`verify` runs on the refined commit; a push during `unblock` makes earlier verify results stale,
and verify reruns on the new head. `refine` does not rerun on `unblock` pushes.

The schema checks each file's shape. The config reader also rejects:

- an activity whose `effect` or `gating` the lane's row in `lane-rules.json` forbids, such as a
  branch-writing activity in `pr-run-checks` or a `merge` effect outside `pr-merge`;
- a leaf whose `effect` its row in
  [`activity-rules.json`](../../../.github/actions/resolve-config/activity-rules.json) forbids; a
  leaf with no row is valid;
- a lane whose `stage` differs from its `lane-rules.json` row, or a lane with no row;
- a `needs:` entry naming an activity that is not in the same `slots:` or `children:` list;
- a composite child that is undefined or itself a composite, a composite that contains itself, or
  a leaf that appears twice in one lane;
- `prepare` with an effect its mode does not take;
- an `applied-by` target that is not a script activity, a `patch` target without
  `prepare: apply-patch`, or a lane holding the producer without the target in a slot that
  needs it;
- a [patch rules](#patch-rules) row that does not refuse the universal set, or that commits with
  the base as a parent and whose `allow` is not exactly `[merge-result]`;
- a lane or activity name missing from the vocabulary ([Names](#names));
- an activity named `run` or `report`, `pr-run-activity`'s own job names;
- any `extends:` value ([Not settled yet](#not-settled-yet)).

The reader also adds the config file's own path, `.github/**` and the trusted-actor list to
`merge.diff-check.denied-paths`, whatever the config says.

## Concurrency

| Scope | Rule | Set by |
|---|---|---|
| Triggers of one PR's `pr-unblock` activity | A newer dispatch replaces one still waiting; a running one finishes | workflow group `pr-unblock-<activity>-<n>`, `cancel-in-progress: false` |
| Within one run | Leaves run in slot order: `publish-feedback` after `address-feedback` once its skill ran; `report-escalation` after the others, and only when one escalated | the caller's `needs:` |
| Across PRs | Unbounded: every group is per PR | group names |
| Within one PR, across write lanes | One queue: a write job waits for the one ahead and never cancels it | job group `pr-pipeline-write-<n>`, `queue: max`, on every write caller job |
| `pr-unblock-dispatch` | One run at a time; a newer push replaces a waiting run | workflow group `pr-unblock-dispatch` |
| `pr-feedback-dispatch` | One run per reviewed head at a time; a waiting one is replaced | workflow group `pr-feedback-dispatch-<head SHA>` |

The write group sits on each caller job, behind an `if:` that leaves out the lanes App's own
`pull_request` events, so a lane's push never queues a job in it.

## Outputs and skips

Each leaf reports:

- A verdict: `pass`, `fail`, `neutral` or `skipped`.
- Findings in the detector-findings shape ([`detector-findings`](../detector-findings/README.md)),
  for the commit the leaf judged. A new commit gets a new verdict, even when its content is
  unchanged.
- An artifact bundle per [`record-bundle`](../record-bundle/README.md).
- A check run named `<lane> / <leaf>`, for example `pr-refine / simplify`; a composite gets none.

A skip reports as a neutral check with one reason from the schema's `$defs/skip-reason`:
`not-applicable-paths` (a `paths` predicate missed, or every matching path was left out of
`changed-paths`), `not-applicable` (a label, event, work-class, `mergeable` or `draft` predicate
missed), `prerequisite-missing` (among others, mergeability still unknown at the gated head after
bounded re-reads), `cost-gated`, `awaiting-human` (among others, a `labels-absent` label is on the
PR), `superseded-sha`, `disabled-by-config`, `untrusted-trigger` (a fork, no same-repository PR, or an
actor or author not on the trusted-actor list), `workflow-modified` (the token broker refused a
write lane's mint for a workflow file the PR itself changes), or, for an issue run under
`models.issue-dimensions`, `not-assessed` (a dimension field empty or set by an untrusted
account), `research-first` or `probe-first` (its Uncertainty), or `split-required` (its Size is
`split`). Silence is not a skip, with three exceptions that
post no check: a fork PR, whose read-only token cannot write checks; a `pull_request` event sent
by the lanes App; and a run on any other event whose run job gated no head SHA.

Each review finding goes to an independent validator. Valid: fix it and reply with a citation.
Invalid: reply with a cited disagreement. Unsure: escalate. A script resolves bot threads after
the reply; human threads stay open for the human.

## Merge authority

`merge.authority` names the repository's one merge authority: `local-babysit`, the babysit wrapper
run by the local babysit lane (loop-lane), or `pr-merge`. When it is absent the authority is
`pr-merge`, the meaning a rung had before this key existed. The babysit wrapper merges only when it
reads the authority the wrapper runs as: `local-babysit` by default, `pr-merge` under
`--authority pr-merge` (below). `merge.report-only: true` makes that authority report each
decision and write nothing. `merge.rung` is the highest work class that authority merges without a
human. Work classes are defined in
[`work-classes.md`](../../../plugins/autonomy/reference/guardrails/work-classes.md).

- `off` is the default. The first rung a repository adopts is `C2`, together with
  `merge.diff-check`: the diff touches no denied path and stays under the size cap.
- The work class comes from the linked issue's label and is re-checked against the diff. No class,
  or a class the diff contradicts, means no lane merge.
- C5 always needs a human. C4 becomes promotable under
  [ADR 0050](../../adr/0050-let-merge-authority-reach-c4-by-evidence-and-drop-the-vendor-hosted-cap.md),
  but the schema adds no C4 rung until the autonomy plugin and loop-lane carry the matching change.
- A rung rises only through a merged change to the config file. Under `pr-merge` it falls
  automatically: when the default branch fails after a lane merge, that lane's merge rights turn off
  through a repository variable that can only lower the rung, and a `needs-human` issue is filed.
  The local babysit lane falls through a demotion issue instead (below).
- A `pr-merge` merge needs a review verdict bound to the commit being merged. This is a
  precondition of the lane's own merge, not a required check. A lane merge commit, including one
  where the lane resolved conflicts, needs a fresh verdict on that commit before the merge. The
  local babysit lane accepts only evidence bound to the pinned head SHA (below).
- `merge.stack-landing` defaults to `manual`.
- A repository has one merge authority, Dependabot pull requests included: the pr-merge lane
  merges tier `auto` ones, and tier `review` ones once the pr-unblock lane's review activity
  leaves a merge verdict ([Dependabot pull requests](#dependabot-pull-requests), below).

### The local babysit lane

The babysit wrapper does not enforce these reads yet; until it does, the live config does not set
`local-babysit`.

The babysit wrapper (`babysit_merge.py` in the source-control plugin) may merge without a human
only when every read below allows it. Each read happens at one captured base SHA, and any read
that fails counts as a refusal.

- **Authority and identity.** `merge.authority` reads `local-babysit` and `merge.agent-identity`
  names the login the lane acts as. The schema rejects `local-babysit` without an identity. The
  identity must be the `[bot]` login of a GitHub App dedicated to this lane, and the schema rejects
  any other login: a machine user is a GitHub user and would pass every human test, and the shared
  `github-actions[bot]` and `dependabot[bot]` are refused in any letter case. With no `merge:` block,
  or no `authority`, the wrapper merges nothing.
- **Same repository.** The pull request's head is in this repository, never a fork.
- **Risk score.** Only a diff the risk scorer rates LOW merges; MEDIUM and HIGH are refused.
- **Review evidence.** For each review lane, the newest run of the lane's caller workflow on the
  pinned head SHA concluded success and carries the lane's completion record for that SHA.
- **Effective rung.** The lowest of `merge.rung`, the `babysit_loop_merge` key in
  `.claude/source-control.md`, the cap variable, and `off` while any demotion issue is open.
- **Cap variable.** `CLAUDE_LANES_MERGE_RUNG_CAP` (`off`, `C2` or `C3`) is a repository variable
  only a human sets, and it can only lower the rung. The wrapper never writes it, and the identity
  can read variables but not write them. A 404 after the variables listing proved readable means no
  cap; any other failure means `off`.
- **Kill switches.** The org variable `CLAUDE_LANES_DISABLED` and the repository variable
  `CLAUDE_LANES_REPO_DISABLED` must each read exactly `false`. A read error, or a repository-level
  variable named `CLAUDE_LANES_DISABLED` that shadows the org one, refuses.
- **Demotion issue.** A failed post-merge check files an issue whose body starts with
  `<!-- babysit-merge-demotion sha=<S> signal=<name> -->` and that carries the `needs-human` label.
  It holds the rung at `off` until a human closes it directly. A close through a pull request's or
  commit's `Closes #N` does not count, and an issue that a non-human edited at any time stays in
  force. The wrapper finds these issues by author (the agent identity or `github-actions[bot]`), so
  removing the marker or the label does not clear one. When `post-merge-demotion-alert.yml` proves
  that no merge the failing run covers was enqueued by the agent identity, it files a
  post-merge-failure record instead, first line `<!-- post-merge-failure sha=<S> signal=<name> -->`,
  also `needs-human`. That record does not hold the rung off.
- **Opt-in label.** `merge: agent-allowed` makes a pull request eligible; it does not make it safe,
  and the diff risk score still decides. It counts only when a human added it last and the pull
  request body was not edited afterwards.
- **HIGH path floor.** A fixed set of paths in the wrapper's code, joined with
  `merge.diff-check.denied-paths` and, while `high-path-floor` is true, `floor-paths`,
  `floor-script-scopes` and the capability check (see the pr-merge lane), matched
  case-insensitively. A diff that touches any of them
  scores HIGH and is never merged unattended.
- **Merge queue.** The wrapper enqueues with `--match-head-commit`, never `--auto`, and only when
  every required check is green. An armed auto-merge request on the pull request is a refusal, and
  the wrapper disarms it.
- **Merges in flight.** `merge.max-in-flight` (default 1) caps the identity's merge-queue entries
  plus its merged pull requests that have not passed the post-merge check. It is read at the default
  branch head once per cache window, not at the pull request's base (the base's value when that
  read fails), and read again uncached after an enqueue. The wrapper
  refuses at the cap, and an entry enqueued past it (another host's came first) dequeues itself. A
  red full run or canary run charges every unverified merge whose commit it contains, so a breakage
  found with several in flight demotes the rung and fails the post-merge check for all of them.
- **Repeat queue ejections.** `merge.max-queue-ejections` (default 2, at most 20) stops the
  wrapper enqueuing a head the merge queue has removed that many times for failed checks since the
  head last changed; the queue would eject it again on the same commits. A push resets the count.
  An unreadable timeline, or 20 timeline items with no head change among them, refuses the
  enqueue. A refused head gets one `<!-- babysit-merge-queue-ejections -->` comment naming the
  failing `merge_group` runs.
- **Stale check inputs.** `merge.check-inputs` lists git pathspecs the pull request checks read.
  When the base changed one since a pull request's merge base, the wrapper updates the branch from
  the base (`update-branch`, a merge) instead of enqueuing it; the new head enqueues on a later run
  once its checks pass. The answer comes from the local full-history clone of the base (never a
  shallow or partial one) with no API read; a head the clone lacks is fetched by SHA. The shared-copy registry (`scripts/shared-copies.txt`) counts
  only for a pull request whose own changes since the merge base touch the registry or a canonical
  or copy path it registers at the base tip, since a pull request touching none of them merges
  cleanly whatever the base registered; every other listed path counts for every pull request. Any
  doubt, an update the API refused with a 4xx (its status and message recorded as `updateError`),
  or a Dependabot head enqueues as before. An update with no answer (a timeout, no status, a server
  error) may have landed, so it holds the old head instead. Empty or absent updates nothing.
- **Dependabot.** A dependency-manager author is never eligible for a local unattended merge. The
  pr-merge lane owns Dependabot pull requests (below).

A human here is a GitHub user, not the agent identity and not an automation login, with write or
admin permission on the repository.

### The pr-merge lane

The same wrapper run with `--unattended --authority pr-merge` is the pr-merge lane's gate. It needs
`merge.authority: pr-merge` and `merge.agent-identity` at the base, and keeps every read above
except six:

- **Eligibility.** Not a fork or a dependency manager's pull request, opened by
  `merge.agent-identity` (the lanes App; refused `not-lane-authored` otherwise), exactly one closing issue
  (`closingIssuesReferences`) in this repository, and a diff where no path, either side of a
  rename, matches `merge.diff-check.denied-paths`. Such a pull request is class C2, as a
  Dependabot pull request is: no `work-class:` label is read, on the issue or the pull request,
  and the diff-derived C2 checks of the risk score still apply. No opt-in label or lane claim is
  read. No closing issue, or more than one, refuses (`linked-issues:<n>`); right before the
  enqueue the closing issue is read again and a different one refuses
  (`closing-issue-changed:<was>><now>`). A pull request into any branch but the default refuses
  `base-not-default:<ref>`, read at eligibility and again before the enqueue; any read that fails
  refuses.
- **Verdict criterion.** No promotion evidence is read. The merge criterion is the pr-verify
  verdict at the head ([Verifier verdict](#verifier-verdict)), which binds to that one closing
  issue and its trusted spec, so with a rung above off the gate refuses
  `verifier-verdict-not-required` unless `merge.require-verifier-verdict` is true, and the schema
  rejects such a config. The lane starts with `merge.report-only: true`; the owner reads its
  reports and sets `false` to let it merge.
- **Risk switches.** Each check below is a `merge.diff-check` setting that is off when absent:
  `denied-paths` (an empty list denies no path; a listed path makes the pull request ineligible),
  `high-path-floor` (true scores the scorer's fixed HIGH path set HIGH, and a SKILL.md,
  agents/**/*.md or commands/**/*.md file whose head text, compared with its base text, gains or
  changes `hooks`, `allowed-tools`, `tools`, `permissionMode`, `mcpServers`, `memory` or another
  frontmatter key `babysit_risk.py` lists, adds or changes a `!` backtick command, gains a
  ```` ```! ```` block,
  changes a line inside a ```` ```! ```` block, has changed frontmatter the strict reader cannot
  follow, or cannot be read, and a rename or copy into such a path), `floor-paths` (globs joined to
  that floor while it applies; a HIGH pull request waits for a human), `floor-script-scopes`
  (globs inside which, as at the top level, a `.ps1`, `.cjs` or mode-100755 file scores HIGH with
  the floor), `c2-contradictions` (true
  scores a removed, renamed or copied file, a schema change or more than one plugin MED),
  `max-changed-files` and `max-changed-lines` (absent is no cap). This repository lists
  `floor-paths` and `floor-script-scopes` and sets `high-path-floor: true` (owner decision
  2026-10-18, reversing Q661: lanes may edit runnable plugin files and fix-ci's patch guard
  covers only `.github/**` and agent instruction paths), so a lane pull request on the floor waits for a human; the non-author verifier
  verdict, both AI review lanes, `ci-status` and the post-merge revert breaker gate the rest. It
  leaves the rest off (owner decision,
  2026-10-17). The local babysit lane ignores the other switches and keeps the rest of
  the fixed floor, both caps and the C2 contradictions, but `high-path-floor` governs it too:
  false leaves out `floor-paths`, `floor-script-scopes`, the capability check and the floor
  entries for plugin monitors and workflows. The review evidence and the security lane's findings
  still count.

  What is left with every switch off: a lane pull request may change the merge gate, the
  workflows and their tokens, these lane rules, skills, hooks, agent instructions and CI checks,
  at any size.
  The brakes that remain are the verifier verdict, the kill switch, the fork and Dependabot
  refusals, lane authorship with one closing issue, the review evidence and the demotion stop;
  setting `merge.report-only` back to true stops every merge. A verdict reads the diff only and runs no changed code, and a pull request
  that weakens a later run's gate (this file, the gate, `pr-merge.yml`) is judged by the gate as
  it stood at its base.
- **Kill switches.** The lane token cannot read Actions variables, so the workflow checks the
  switches itself and passes `--lane-kill-switch proceed`. A missing value or any other value
  stops the lane. The value is read once per run, and a stopped run cannot dequeue: to stop at
  once, cancel the running pr-merge run and dequeue the lane's pull request by hand.
- **Cap variable.** For the same reason the workflow passes `CLAUDE_LANES_MERGE_RUNG_CAP` from its
  `vars` context as `--lane-rung-cap`. Empty (unset) is no cap; `off`, `C2` or `C3` caps the rung;
  a missing flag or any other value holds the rung at `off`.
- **Post-merge check and merges in flight.** Only merges the agent identity enqueued count. A
  merge by a person or by another App, such as a release pull request, is not the lane's.

An eligible pull request scored MED or HIGH gets one `<!-- babysit-merge-risk -->` reasons comment
naming the score, the reasons and the head. While `merge.report-only` is false, a run that finds the
lane identity's reasons comment from an earlier run unchanged (same score, reasons and head) for at
least `merge.risk-escalation-minutes` (default 60, timed from the comment's last change; 0 is no
minimum) escalates the refusal ([loop-lane §2](../loop-lane/README.md#2-escalation-contract)): it
rewrites that comment once to end with a line saying the refusal persisted and needs a person, then
adds the tracker's human-gated role label when no label matches it ignoring case, so the pull
request leaves the WIP count and reaches the attended queue. The rewrite dates the comment beside
the label, which the head-moved clear needs to pair them. The minimum lets a review still
running at the head, which scores MED, finish first. Changed reasons rewrite the comment and
restart the time; a new head, or a score back at LOW, writes no label. A LOW score rewrites a
refusal comment naming that head, unless it is escalated, to say the refusal no longer holds, so a
later refusal at the head starts its time afresh. The merge gate never removes the label; the
`head-moved` clear above removes it once the head moves, and otherwise a person does.

Finding closure (owner decision, #8450, narrowed to whole reviews): a clean **whole** review of the
current head closes a review finding whoever resolved its thread, and a HIGH security finding also
needs the security review lane's own clean whole review of that head. The gate applies it per lane
(`_open_findings` in `babysit_review_evidence.py`): a resolved thread closes when it was opened
before that review's job completed and the review chain covering the head, here the whole review
alone, reports no finding. An incremental review reads only what changed since the last review, so
it never closes an unchanged thread: a lane that resolved an unfixed finding and pushed an unrelated
commit leaves it open. A resolved thread also closes when a human resolved it, or when it is
outdated with none of its flagged lines left at the head; an unresolved thread stays open.

Whole-review request (`babysit_whole_review.py`): when a lane pull request passes every other gate
and its only risk reasons are open findings a clean whole review of the head would close (no review
of that head reported a finding or was whole, and no lane thread is unresolved), the gate writes a
`Whole review requested at head` line into its reasons comment, then converts the pull request to a
draft and marks it ready with the lane token, so `ready_for_review` runs both review lanes whole.
That event also re-runs `pr-require-checks.yml`, `pr-test-windows.yml` and pr-merge itself. The
line, stamped with the time it was written, is kept on every rewrite, so a head is toggled once and a pull
request at most twice; past that it waits for a person. A run toggles at most one
pull request, and only while fewer than 35 jobs are running or queued and the lane token and the job token
each have 30% of every rate-limit bucket's hourly limit left; an escalated comment is not toggled. Each toggle logs
`::notice::pr-merge whole-review-toggle pr=<n> head=<sha>`. A draft a run left between the two
writes is marked ready by the next run, only when the lane token made its newest conversion to draft within ten minutes after a record's time;
a draft a person made stays one.

While `merge.report-only` is true and `merge.dependabot.mode` is not `enforce`, the workflow starts
no full CI run either; its summary says whether it would have.

The workflow's gate loop starts no further candidate once it has run `merge.gate-budget-minutes`
(absent: no budget); the candidate in progress finishes first, so the budget never stops a gate
between its check and its enqueue. Each run starts after the last candidate the previous loop
reached and wraps round to the lowest PR number, so every candidate is reached across runs. The
position is the `pr-merge-gate-cursor` artifact, read only from a scheduled or hand-started
`pr-merge.yml` run on the default branch, found through that workflow's run list; it sets the order
and never a verdict.

Before the loop, the workflow sets aside each candidate the last gating run refused on inputs that
have not changed, and reports it with that refusal, marked `carried`. A skip only repeats a refusal:
it never enqueues. The inputs are the head and `updatedAt`, labels, base SHA, check rollup at the
head, reviews, review threads, comments, closing issues, the verdict artifacts naming the pull request
or its head, the gate's config and code on the default branch, and the rung cap. Check runs and
statuses do not move `updatedAt`, so that is never the key alone. Only `risk:MED`, `risk:HIGH` and
the `verify:` refusals `fail`, `earlier-fail`, `missing`, `too-old`, `spec-changed` and
`untrusted-spec` are skipped. A refusal whose gate process failed a write or has a review re-run due
is not. Neither is a pull request in the merge queue, nor `verify:missing` while a PASS artifact
names the head. `merge.skip-unchanged` bounds each skip: `max-minutes` (default 60) after the
refusal was judged, or `max-skips` (default 3) runs in a row, the candidate is gated again. `0` in
either turns skipping off. When every candidate would be skipped, the first is gated, and any read
that fails or comes back incomplete gates the candidate (`babysit_merge_skip.py`). The refusals live
in the same `actions/cache` entry as the carried verdict reads, so a forged entry can only repeat a
refusal, for at most `max-minutes` from the judgment time it names. A change the key does not cover,
such as a demotion record, a ruleset, an edit to a comment older than the newest 50 or a gate import
outside the keyed paths, delays re-gating by at most those limits; a skip never merges, enqueues or
drops an escalation.

### Dependabot pull requests

No Dependabot pull request waits on a human
([ADR 0073](../../adr/0073-merge-dependabot-pull-requests-in-the-pr-merge-lane.md)), except a major
update, an unreadable version or disagreeing sources under `merge.dependabot.majors: hold`
(below). The pr-merge
lane is the one merge authority for both tiers. It lists Dependabot's open pull requests beside
its own and judges each as its own class, in place of the eligibility above. Both lanes sort by
the same rules (`babysit_dependabot.py` here, `dependency-classify.mjs` in pr-unblock):

- **Tier `auto`.** Every update is non-major: the first numeric version component does not change,
  and below 1.0 the second does not either. Every update on a `dependabot/github_actions/...`
  branch comes from the `actions`, `github` or `anthropics` publisher. The newest `ci-status` run
  on the head is not red (`failure`, `cancelled`, `timed_out`, `action_required`,
  `startup_failure`). The updates come from the `updated-dependencies` metadata in Dependabot's
  verified commit when it is there, and from the title (`bump <name> from <a> to <b>`) or a
  group's body `Updates` lines otherwise; when both read, they must name the same dependencies and
  agree on which are major.
- **Tier `review`.** Anything else, including anything unreadable (a SHA version, an unparsed
  title), every update to a [review-only dependency](#review-only-dependencies), and an npm or
  pip update whose [registry provenance](#registry-provenance) changed. The pr-unblock lane's review activity reviews it, and the pr-merge lane merges it only
  when the newest round marker the lanes App posted on it
  (`<!-- pr-unblock:review-dependency-round head=<sha> verdict=merge run=<id>-<attempt> -->`)
  names the current head with `verdict=merge`. A marker from any other author is ignored.
- **Commits.** Every commit is a GitHub-verified Dependabot commit, or the repository's
  `[dependabot skip]` version-bump commit (authored by `github-actions[bot]`, verified, touching
  only a plugin's `plugin.json` or `CHANGELOG.md`). On a reviewed pull request the lanes App's
  verified `[dependabot skip]` fix commits count too. The commits listing must hold the pull
  request's whole commit count, else the reason is `commits-listed:<listed>-of:<total>` (the
  listing stops at 250). A commit's author is text whoever creates it
  chooses, so two more checks bind the pull request to Dependabot:
  - **Pushes.** The repository activity API for the head branch, read back to Dependabot's newest
    branch creation or force push, shows every push by `dependabot[bot]`, or by
    `github-actions[bot]` (or, after a review, the lanes App) pushing its own commit, and the
    newest push is the head.
  - **Content.** Every changed path, either side of a rename, is a manifest or lock file of an
    ecosystem and directory `.github/dependabot.yml` lists at the base (npm `package.json`,
    `package-lock.json` and the like; pip `requirements*.txt`/`.in`, `pyproject.toml`, `uv.lock`
    and the like), or a workflow or action file of a `github-actions` entry whose diff changes only
    `uses:` lines (`/` covers `.github/workflows/` and the action files under `.github/actions/`).
    A directory holding `*` or `?` is a glob, read the same way in both lanes: `*` and `?` stay
    inside one path segment, `**/` is zero or more whole segments (so `**/*` covers the root and
    every layer below), any other `**` crosses segments, and everything else is literal. A path the version-bump or lanes App fix
    commit touched counts as checked; a fix commit may not touch `.github/`, and one whose file
    list cannot be read whole refuses. Anything else (a rebuilt bundle, a manifest outside a listed
    directory) makes the pull request tier `review` with the reason `dependabot-content:<path>`,
    so the AI review judges it; it is never left for a person. A failed push check, by contrast,
    always refuses, verdict or not.
- **Gate.** Either tier merges only once `ci-status` succeeded on its head, through the same gate
  as the lane's own: mergeable, no `do-not-merge` label, no body hold, no blocking comment from a
  human with write access, the rung (C2) and its cap, the kill switches, the post-merge check and
  the merges in flight. No closing issue, denied-path rule or diff risk score applies: `ci-status`
  (and, for tier `review`, the review verdict) is the gate, and a workflow pin bump touches
  `.github/**` by definition.
- **Switch.** `merge.dependabot.mode` decides it, not `merge.report-only`: `enforce` merges,
  `report` reports and writes nothing, and `off` (the default) refuses every Dependabot pull
  request and leaves them unlisted.
- **Majors.** `merge.dependabot.majors` decides a pull request with a major update, or with an
  update whose version cannot be read (a SHA pin, an unparsed title): `hold` (the default, and any
  value but `review`) refuses it with the reason `dependabot-major-held:<names>`, an unreadable
  entry written `<name>(unreadable)` (`updates(unreadable)` when no update reads), whatever the
  review verdict says; when the title and the commit metadata disagree, every update is held,
  written `<name>(disagree)` unless it is already major or unreadable. The lane escalates every
  held pull request once, as for a verifier refusal below: one upserted
  `<!-- babysit-merge-dependabot-major -->` comment, whose first line is the attended queue's
  `<!-- work-items:escalation lane=pr-merge kind=escalated -->` marker so
  `/work-items:attend-queue` lists it, then the tracker's human-gated role label, so
  a person merges it. `review` leaves it tier `review`, merged on the verdict above.

The class is `babysit_dependabot.py` beside the wrapper. Auto-merge armed with `GITHUB_TOKEN` is not used: GitHub's
[`GITHUB_TOKEN` page](https://docs.github.com/en/actions/concepts/security/github_token) says
"events triggered by the `GITHUB_TOKEN` will not create a new workflow run" (`workflow_dispatch`,
`repository_dispatch` and some `pull_request` events excepted, not `merge_group`), so the queue
entry such an arm makes never gets its `ci-status` run and never lands (#6717, #7512).

`.github/workflows/pr-merge.yml` runs the lane's `merge-pr` activity with no model and no head
checkout. A label, body or ready change on a PR, a manual dispatch and a schedule every 15 minutes
each only wake it; it lists the candidates from the API and runs the gate on each under the lanes
App token the broker mints for that file on `main`. A finished `ci-status` or review run is picked
up by the next scheduled run, not by a wake-up of its own: runs are serialized, and the triggers
must start them more slowly than they finish to stay under GitHub's cap on queued runs.

After the gate, a `gate-check` job of its own writes each candidate's verdict on its head as one
`pr-merge / gate` check run with its `GITHUB_TOKEN`, from the gate's rows the merge job hands it as
an artifact. Only that job holds `checks: write`, since main's ruleset requires `ci-status` from
the same GitHub Actions app and a token with that permission could pass it; the merge job keeps
`checks: read` and the lane token holds no Checks permission. The check is:
neutral and titled with the top refusal, the gate's reason or else its first blocker, with the
blockers in the summary; success once enqueued or merged, only over a refusal already on show. It
reads the heads' existing check runs in one GraphQL query per 50 candidates and writes only where
the title or conclusion changed, so an unchanged sweep writes nothing; the step logs one line of
written and unchanged counts per sweep. The same query reads each candidate pull request's current
head (`pull-requests: read`, the job's only other permission besides `contents: read`), and a row
whose head differs gets no write. A pull request the read reports `NOT_FOUND` (deleted or
transferred) skips only its own row; any other GraphQL error leaves that read's 50 candidates
unwritten and fails the step. It reads and rewrites only check runs carrying its own
external id, since every workflow's `GITHUB_TOKEN` posts as the same GitHub Actions app. The check
is display-only: it is never required and is not part of `ci-status`, and the gate reads neutral as
passing, so it holds no merge. Not while `merge.report-only` is true.

#### Review-only dependencies

A non-major release of a hijacked package passes tier `auto` on a green `ci-status`. A dependency
that runs inside a job holding a secret or a write token is therefore listed in the standards
Dependabot policy's `autoMerge.reviewOnly` (melodic-software/standards
`components/dependabot-policy/policy.json`), which the sync places at
`.github/standards/dependabot-policy/policy.json`. Both lanes read that file at the base:

- **Match.** An entry matches an update when its `repository` is this repository (any case), its
  `ecosystem` is the head branch's ecosystem in `dependabot.yml` spelling
  (`dependabot/npm_and_yarn/...` is `npm`, `dependabot/github_actions/...` is `github-actions`,
  any other segment such as `pip` is itself), its `directory` covers a changed path (any path
  when the config or the files listing does not read whole), and its `dependency` is one of the
  updates. A directory covers a path that sits in it, read as the content rule reads a
  `dependabot.yml` directory (globs included); a `github-actions` entry also covers the workflow
  and action files the content rule gives its directory (`/` covers `.github/workflows/` and the
  action files under `.github/actions/`). A match makes the pull request tier `review` with the
  reason `review-only:<dependency>`, whatever the version change.
- **Unreadable.** A missing policy file, one that is not JSON, or one whose `reviewOnly` is not a
  list of entries with string `repository`, `ecosystem`, `directory`, `dependency` and `control`
  makes every Dependabot pull request tier `review` with the reason
  `dependabot-policy-unreadable`; so does a classifier call that passes no policy at all.
- **Review.** The review activity gets the matched entries. A `merge` verdict on such a pull
  request cites each entry's `control` (this section, for this repository's entries) and states
  what it checked: the release's provenance (who published it and how), maintainer or publisher
  changes since the previous version, new or changed install scripts, and dependencies the
  release adds that its changelog does not explain. Anything it cannot check is `escalate`.
- **Citation check.** The verdict job checks that by script: a `merge` verdict whose `evidence`
  does not hold each matched entry's `control` string verbatim (as a substring of one entry)
  posts no merge marker and escalates `dependency-control-uncited`. This proves only that the
  verdict followed the review-only procedure, not that the model checked anything: the control
  string is public, and a model steered by release text can quote it as easily as one that did
  the work. The deterministic defenses are the routing to review and the registry provenance
  gate below; against steering text the review relies on the model escalating it.

#### Registry provenance

A stolen publish token can ship a non-major release from outside the project's CI, which tier
`auto` would merge on a green `ci-status`. Both lanes therefore compare who published each npm or
pip update (`dependabot/npm_and_yarn/...` and `dependabot/pip/...` branches; `github_actions`
updates are covered by the publisher allowlist), with no model, and only for a pull request every
other rule left tier `auto`:

- **Identity.** npm: when the version's packument entry (`GET https://registry.npmjs.org/<name>`,
  a scoped name as `@scope%2Fname`) has `dist.attestations.url`, the SLSA provenance from
  `GET https://registry.npmjs.org/-/npm/v1/attestations/<name>@<version>` names the identity:
  `predicate.buildDefinition.externalParameters.workflow` `repository` and `path` (SLSA v0.2:
  `predicate.invocation.configSource` `uri` without its `@<ref>`, and `entryPoint`), compared
  without `https://github.com/` and in any case. The ref is never part of it, so a release from a
  new tag is the same identity. With no attestation, `_npmUser.trustedPublisher` `id` and
  `oidcConfigId` (any `oidc:` prefix stripped) are the identity. pip: the version's files in
  `GET https://pypi.org/simple/<name>/` (`Accept: application/vnd.pypi.simple.v1+json`); the
  first by name with a `provenance` URL is read with
  `Accept: application/vnd.pypi.integrity.v1+json`, and the first attestation bundle's
  `publisher` `kind`, `repository` (any case) and `workflow` are the identity. A version with
  neither has none.
- **Rule.** The previous identity is the newest stable version (npm `x.y.z`; pip digits and dots
  with an optional `.postN`, not yanked) published before the new one that has an identity. With
  one, a new version with no identity is `provenance-missing:<name>` and one with a different
  identity `provenance-changed:<name>`; either makes the tier `review`. With none, the gate adds
  nothing: a package that never published provenance keeps the cooldown and the other rules.
- **Fail closed.** A registry read that fails, takes over 10 seconds or does not parse, a new
  version the registry does not list, an update with no version, or more than 20 registry reads
  for one pull request is `provenance-unreadable:<name>`, tier `review`.

The review activity then judges the release as it judges any review-tier pull request.

#### Classifier gaps

A pull request whose every reason is a read failure (`unparsed-updates`, `sources-disagree`,
`dependabot-config-unreadable`, `dependabot-policy-unreadable`, `provenance-unreadable:<name>`)
is review tier because the classifier could not read it, not because it is risky. The
review-dependency select step writes a `::warning::classifier gap` naming those reasons, so a
parse bug shows in the run log instead of quietly spending AI reviews; fix the classifier.

### Verifier verdict

`.github/workflows/pr-verify.yml` runs on main after each successful `pr-require-checks` run of a
same-repository, non-draft pull request into main. It never runs the pull request's code: a model
(the `verify-pr` route of [Models](#models)) reads the diff, the trusted pull request text and its linked issues as
data, and judges whether the diff delivers the issue's intent correctly and safely. The model runs
on ci-workflows' `run-claude-cli` as the `automations` role ([Funding](#funding)), with the Read
tool alone, allowed only on the data files in the working directory's `pr-verify-data`. The run
uploads one artifact, `pr-verify-<pr>-<head-sha>-<pass|pass-notes|fail>`, holding the verdict JSON
(`pr`, `head_sha`, `base_sha`, `head_ref`, `linked_issues` with each issue's author login, id and
account type, `verdict`, `summary`, `notes`, `run_id`). The head SHA is the one `pr-require-checks`
ran on, never the pull request's live head. A model error, an output that fails the schema, a
summary or note shaped like an Anthropic key or OAuth token, or a run with any permission denial
uploads nothing, and the run fails. A head that already has a counted verdict from a completed run (a `fail` under any
pull request number) is not judged again. Runs share one concurrency group per pull request and
head and never cancel a running judgment.

`merge.verify-authors` decides whose pull requests are judged. Under `lane`, the default, only one
the lanes App opened is: a `Bot` account whose login is `merge.agent-identity`, compared as the
pr-merge lane decides lane authorship. Any other author's is skipped before the model runs, with
the reason `author-not-lane` and the step summary line `skipped: author not the lanes App`, since
only lane-authored pull requests reach the pr-merge lane. `any` judges every author's. Any other
value judges none (`verify-authors-invalid`). The trusted-spec rule below is scoped to that: on a
lane pull request the App is the author and a human wrote the issue, so the spec can be trusted,
while a human author who also wrote the linked issue would read `verify:untrusted-spec`, which
never arises because such a pull request is neither judged nor read by the pr-merge lane.

With `merge.require-verifier-verdict: true` the pr-merge lane reads the artifacts through their
run records, since only steps of a run can upload its artifacts. A run is of verifier origin when
it is `pr-verify.yml`, event `workflow_run`, on main, in this repository with a head on main. A
`fail` counts from any such run, whatever its conclusion, because the upload comes before the
run's later steps; a `pass` or `pass-notes` counts only from one that completed with success. Any
other artifact with such a name is ignored. The resolver and the gate each hold this rule and the
dependency-manager list, and one test runs both to keep them equal. At the pull request's vetted
head:

- created more than 80 days ago refuses (`verify:too-old`): artifacts last at most 90 days in this
  repository (the retention maximum and its setting), so an older verdict may be gone;
- a counted `fail` at the head, under any pull request number, refuses (`verify:fail`);
- a counted `fail` at another head of the pull request (its number, one of its commits, or a
  verdict recording its head branch) refuses (`verify:earlier-fail`);
- a `fail` artifact tied to it (its number or one of its commits) whose run cannot be read, an
  untied `fail` whose run is readable and of verifier origin but whose verdict record cannot be
  downloaded, or any other failed read, refuses (`verify:unreadable`). An untied `fail` whose run
  cannot be read is ignored. One unreadable record of an untied `fail` therefore blocks every pull
  request until it can be read, expires or is deleted;
- every counted `pass` or `pass-notes` for this pull request at the head is checked, whatever order
  the listing returns them in, and the merge is allowed only when each allows (a changed spec is
  reported before an untrusted one). Each refuses (`verify:spec-changed`) unless the
  pull request's closing issues in this repository now are the ones its verdict recorded, none
  was edited after the verdict's run started, and each issue's spec comments (written, and last
  edited if ever, by a `User` on the trusted-actor list's humans other than the pull request's
  author) are the ones it recorded by id and update time, none added, edited or deleted; a partial
  comment read refuses `verify:unreadable`. It then allows the merge only when every linked
  issue it records was written, and its body last edited if ever, by a `User` on the trusted-actor
  list's humans other than the pull request's author (otherwise `verify:untrusted-spec`). The
  model's spec text holds only what such accounts wrote;
- no counted verdict refuses (`verify:missing`).

The trusted-spec rule trusts an account, not a person. An agent session that uses an owner's `gh`
login posts as that owner, so until agent sessions have their own GitHub identity, an issue or an
`agent-ready` label from a trusted account counts as the owner's authority, including when an agent
acting as that account wrote it. The owner accepts that risk: unattended merge is on
(`merge.report-only: false`) before that identity exists (#7711).

`verify:fail`, `verify:too-old`, `verify:earlier-fail`, `verify:spec-changed` and
`verify:untrusted-spec` need a human. While `merge.report-only` is false the lane escalates such a
refusal on the pull request ([loop-lane §2](../loop-lane/README.md#2-escalation-contract)): it
keeps one `<!-- babysit-merge-verify-escalation -->` comment naming the refusal and the head, and
for `verify:fail` quoting as data the first 1500 characters of the `summary` in the newest head
`fail` verdict when its record can be read and names this pull request. The comment is rewritten
only when any of these changes. A `verify:fail` whose record cannot be read, or a
`verify:earlier-fail`, quotes the summary the lane's last such comment quoted, under the head it
was given at, so a failed read rewrites nothing and the reason outlives a push; an earlier-fail
whose last quote is a fail at this head stays `verify:fail`. Then the lane adds the tracker's human-gated role label (`needs-human` unless
`.work-item-tracker.json` maps it) when no label matches it ignoring case. The comment goes first,
so a label never stands unexplained, and a failed label is added by the next run; a rerun that
finds both writes nothing. While it is true the refusal is only reported. The
lane token's `issues: write` and `pull-requests: write` cover both writes. A human clears them
by merging in person: the verdict is not a check run and stays out of `ci-status` and the required
checks (github-iac ADR 0011), so a human merge needs `ci-status` alone. A queued entry without an
allowing verdict at its live head leaves the queue. A dependency manager's pull request (a `Bot`
account with a dependency manager's login; a `User` named like one is judged) needs no verdict: the lane decides it in its Dependabot class before the verdict is read, or refuses it, and
its queued entry is not held for one. pr-merge.yml runs the gate once per candidate and names a file
in `BABYSIT_VERIFY_LISTING`: the first candidate lists every repository artifact and saves the
listing there, and later candidates and their queued-entry checks read it instead of paging again.
No judgment, of a candidate or a queued entry, uses a listing (saved or in memory) begun more than
two minutes before it: an older one is read again and saved. A saved listing can only lack artifacts uploaded since, so a refusal on it stands; a candidate it
would allow is judged again on a listing of its own before it is allowed, which is saved in turn.
A listing that got a 5xx or a fast
network error is read again, three reads in all with backoff, all inside the one gh timeout a single
read would get; any other failure, a timeout, a 429 or a rate-limit 403 included, is not. A failed listing is never
saved, and is kept for that candidate's gate run: the pull request and every queued entry refuse `verify:unreadable` without the
listing being paged again, so a listing outage holds the whole queue rather than merging blind.
The lane token holds no Actions permission, so pr-merge.yml grants its job `actions: read` and passes the job's `GITHUB_TOKEN` as
`BABYSIT_VERIFY_GH_TOKEN`; the reader uses it as `GH_TOKEN` for the artifact listing, the run
records, the download and the compare of a run's head to main (a `contents: read` call) alone, and
every other call keeps the lane token. That job checks out only main and runs no pull request code.

pr-merge.yml also names a file in `BABYSIT_RUN_CACHE`, where the run's gate processes share reads
that are the same for every candidate. The acting login and a credential pass are reused only under
the same credentials (`gh`'s token variables and `hosts.yml`); a credential refusal is read again. A
collaborator permission and the trusted-actor list are reused for two minutes, and a failed read is
never shared. A run head found on main is shared for the run, since main's ruleset forbids force
pushes; one not found is compared again. In the merge-queue sweep, a queued entry another candidate
judged and kept is skipped only while the oldest read behind that judgment (its verdict listing, or a
shared permission or trusted list) was taken at most two minutes ago; a gate always judges its own entry, a held entry is judged by every
candidate, and a failed dequeue keeps nothing. A FAIL's run record is reused for two minutes: a FAIL
counts whether its run is still running or finished, and a re-run keeps every field that decides
whether the run is pr-verify's, so a stale record never turns a FAIL away. A PASS's run record is
read by each gate process, because a re-run can undo a completed success. An untied FAIL's
recorded head ref is shared for the run under the artifact's id, since the contents an id names
never change (an overwrite uploads a new id). On the `--unattended` path only, the default branch
and the base's rules are reused for two minutes, and a failed read is never shared; before an
enqueue, a default branch or rules a gate took from the file are read again for the branch read,
and any change holds. An attended gate run reads both fresh. Without the variable nothing is shared.

## Trust-root paths

A lane's token grant and the rules it is judged by come from these default-branch paths, so a
change to any of them is a change to every lane's powers:

- `docs/conventions/pr-pipeline.yaml` and `docs/conventions/pr-pipeline/**` (config and schema);
- `.github/actions/**`, which holds `resolve-config/effect-grants.json`,
  `resolve-config/lane-rules.json`, `resolve-config/activity-rules.json`,
  `resolve-config/patch-rules.json` and every action a lane job runs from its base checkout;
- `.github/standards/**`, which holds the trusted-actor list and the runner-policy script;
- `.github/workflows/**`;
- `.github/CODEOWNERS`.

Code-owner review is off on the default branch by owner decision: the `trust-root` and `base`
rulesets require no code-owner review and no approvals
([github-iac ADR 0007](https://github.com/melodic-software/github-iac/blob/main/docs/adr/0007-no-required-approving-reviews.md),
amendment 2026-10-09; only azure-iac, which holds the broker, keeps it). `.github/CODEOWNERS`
still lists the trust-root paths, owned or not, and only requests review. The controls on a
trust-root change are:

- base-SHA config: every lane reads its config, grants, actions and trusted-actor list from the
  default branch, so a PR's own edit to them never governs its own run;
- the trusted-actor filter: the trigger gate and the broker refuse an untrusted actor, PR author
  or re-runner, and the lanes bot never starts a write run;
- the broker's workflow-path rule: it mints only for a lane caller listed in the default-branch
  config, calling a `pr-run-activity-write.yml` byte-equal to the tip, and the App token never
  holds `workflows`, so no lane can push `.github/workflows/`. The one exception is a lane's
  post-run report job, which may still mint after a signed GitHub-made commit changed a lane
  workflow on main during the run
  ([azure-iac#39](https://github.com/melodic-software/azure-iac/pull/39)). After main changes a lane
  workflow, `gh run rerun` on an older lane run fails: a rerun replays that run's workflow file and
  the broker denies it as `workflow-modified`. Start a fresh event instead (`gh pr update-branch`, a
  new dispatch or a push); the denial is intended, since lane workflows always come from main;
- the merge queue and the required `ci-status` check, which no lane can write;
- required review-thread resolution;
- the kill switch;
- broker scoping: one mint per job, this repository only, the effect's grant, at most an hour,
  revoked when the job ends;
- the lane session: `--setting-sources user`, an explicit `--permission-mode dontAsk`, and never
  `bypassPermissions`.

A write lane can change and commit any file in the repository its token reaches, trust-root and
instruction paths included; no tool rule limits which files it touches. The PR is the review step:
the review lanes, `ci-status`, review-thread resolution and the merge gate see every lane commit
before it reaches the default branch. Residuals, accepted by the owner:

- a trust-root change merges with no human approval; what stands between it and the default
  branch is the list above and whoever merges it;
- the model can read its token (`GH_TOKEN`, `GITHUB_TOKEN`, `.git/config`) until the job revokes
  it;
- a skill's `Bash` grant can be wider than its job: `ai-slop:audit`, which `fix-docs` runs,
  allows `Bash(git:*)` with no subcommand bound, and claude-code-action puts the token in the
  origin URL. A run, including one steered by untrusted text it reads, can then push to any branch
  no ruleset protects (the token is scoped to the repository, not the PR branch; rulesets cover
  the default branch and `release/plugins`), run any shell command through `git -c
  core.hooksPath=<dir>` or `git -c alias.<name>='!<command>'`, and push unsigned commits that skip
  the signed-commit tool and the lane-branch freshness check. Unsigned commits on the PR branch
  fail the check run's signed-commit step; a push to another branch is not checked;
- a lane commit can change instruction files (`CLAUDE.md`, `AGENTS.md`, `.claude/`, skills) that
  the PR author's local session loads once it checks out the branch.

The paths `.github/CODEOWNERS` lists with no owner are the eight synced data files (the
vocabulary, pyright and runner-policy data files) and the synced caller workflow
`pr-check-managed-files-hosted.yml`. The required `check-managed-files` job in `ci-status` fails
any hand edit or deletion of them. The hosted review callers (`pr-review-hosted.yml`,
`pr-review-security-hosted.yml`) are locally owned, so `/.github/workflows/**` owns them.
`pr-merge` refuses a PR that touches a path `merge.diff-check.denied-paths` lists and leaves it
for a human. This repository lists none, so a lane PR touching a trust-root path merges on a
passing verdict like any other (see the switches above).

## The lane sweep

[`maintenance-audit-lane-runs.yml`](../../../.github/workflows/maintenance-audit-lane-runs.yml) is a
`maintenance` producer: once a day (and on a manual run from `main`) it audits the last 24 hours of
this repository's lane runs and open pull requests and files what it finds into `intake`. It never
labels an issue `agent-ready`, so nothing it files starts work. Its scripts and tests are in
[`.github/scripts/maintenance-audit-lane-runs/`](../../../.github/scripts/maintenance-audit-lane-runs/).

- **collect**, a script with the job's read-only token, writes one data file per unit, at most 8,
  in this order: slice A, the failed runs of each of the four workflows with the most failures, with
  failed jobs, annotations and log tails; slice D, every run of each of the two lane workflows with
  the most runs, successes included, with sampled green runs' failed steps; slice C, ten open pull
  requests by listed authors per unit, with labels, ages and head check results. Runs from forks
  never count. It stops at 350 REST calls and says so.
- **judge**, one model leg per unit, holds read permissions only, runs with `--setting-sources
  user` and `--permission-mode dontAsk`, and has Read, Grep and Glob over its data and the main
  checkout and no shell. It takes the `triage-issue` route's profile. CI logs and titles reach it
  as data. It returns at most three findings, each citing at least one `path`, `line` and exact
  `quote` from main.
- **file**, a script with no model and `issues: write`, drops a finding when any quote is not on its
  line in the run's main commit, then de-duplicates it by fingerprint: a hash of the slice, workflow,
  job and the error signature with numbers, SHAs and times removed, kept as the last line of the
  issue body. An open match gets a "seen again" comment; a match closed as not planned is skipped;
  a match fixed in the last 14 days is filed again, linked as a possible regression. A finding whose
  `covered_by` names an open item is skipped. It files at most 5 issues a run, labeled
  `needs-triage` and `source: lane-sweep` where those labels exist, writes 1 s apart, and stops at 50
  calls.

CI logs can carry text written to steer the judge, so every model-written field of an issue renders
inside a code fence and its title has links, mentions and references defused. A person rewrites
such an issue before marking it `agent-ready`.

The file job writes with the job's own `GITHUB_TOKEN`, not a lanes App token, so its issues come
from `github-actions[bot]` and start no workflow, intake triage included. The kill switch stops
every job.

A fourth job, **triage-sweep**, runs alone every hour and with the daily run, with no model
([`triage-sweep.mjs`](../../../.github/scripts/maintenance-audit-lane-runs/triage-sweep.mjs)). It
selects open issues, not pull requests, over an hour old, written by a human on the trusted-actors
list or by the lanes App, that have no intake comment, no born-triaged marker and no triage, status,
priority or work-class label. Issues from `github-actions[bot]`, the lane sweep's own included, are
left out. For each it re-dispatches `intake-triage.yml`, at most 5 a pass, and records the runs in
one comment on the issue; after 2 dispatches leave it untriaged it labels the original
`needs-triage`, then files one `needs-triage` issue naming the runs. It holds the job's own `GITHUB_TOKEN`
(`actions: write`, `contents: read`, `issues: write`), never a lanes App token, and stops at 120
REST calls.

## The monitoring lane

[`maintenance-monitor-signals.yml`](../../../.github/workflows/maintenance-monitor-signals.yml) runs
every hour (and on a manual run from `main`) with no model. It reads the signals below over the last
65 minutes, counting a run in the window it completed in, and keeps one issue per key. Its scripts and tests are in
[`.github/scripts/maintenance-monitor-signals/`](../../../.github/scripts/maintenance-monitor-signals/).

| Signal | Fires when | Key |
|---|---|---|
| 1 main red | the newest dispatched or scheduled `pr-require-checks` run on `main` failed, read from each failed job's failure-level annotations; the flake class is named only from GitHub's own runner messages (a timeout, a lost runner) | `main-red:<job>` |
| 2 ceiling | a reading in the window is over 90%: the lanes App and `GITHUB_TOKEN` REST quotas from pr-merge's `api-budget` notices plus the lane's own `GET /rate_limit`, and this repository's in-progress Actions jobs against 60 | `ceiling:lanes-app-rest`, `ceiling:github-token`, `ceiling:actions-jobs` |
| 3 throttling | a failure annotation in a failed lane run (not a `pr-require-checks` or `pr-test-windows` suite run) names a rate limit, a 429 or `github-rate-limited`, or a reading shows 0 remaining; or the broker refused a lane token (any status except `workflow-modified`, which pr-merge re-fires) or was unreachable | `throttle:rate-limited`, `broker-deny:<status>-<reason>` |
| 4 merge-queue ejections | more than 2 merge groups failed in the last 24 hours, each listed with its PR and failing steps | `merge-queue-ejections` |
| 5 held PRs | pr-merge's newest `pr-merge-summary` lists PRs blocked and untouched for over 24 hours, batched | `held-over-24h` |
| 6 report-only audit | the newest scheduled run of `maintenance-audit-test-selection` or `maintenance-check-upstream-drift` failed, which each does on findings | `audit:<workflow>` |
| 7 platform incident | githubstatus.com has an incident naming Actions that is open or began in the window, or shows Actions not operational | `platform:<incident>`, `platform:actions` |
| 8 throughput | no PR by `merge.agent-identity` merged for 3 hours while pr-merge's newest live sweep, at most 70 minutes old, counts candidates | `throughput-zero` |

An issue's first body line is `<!-- factory-monitor key=<key> fp=<fingerprint> -->`; the body names
the signal, the owning area and the key, and carries the evidence inside a text fence as inert lines.
The fingerprint changes only when the evidence does: the failure text, the run or PR set, the newest
failed merge group, the incident status, the last merge, or the day for a ceiling. The newest issue for a key
decides: open with the same fingerprint, nothing is written; open with a new one, a comment carries
the evidence and the marker records it; closed as not planned, the key is muted; closed as completed,
a new issue is filed only on new evidence, or for `main-red` on a failed run that started after the
close, naming the old one. Issues of every age are read, page by page until a short page, so a quiet key stays open or muted; a run that spends its call budget there stops before writing. It files at most 8 issues a run,
labeled `needs-triage` and `source: factory-monitor` where those labels exist, writes 1 s apart,
and stops at 250 REST calls. A source it cannot read is listed in the step summary and the other
signals still run.

It holds the job's own `GITHUB_TOKEN` (`actions`, `checks`, `contents` and `pull-requests` read,
`issues: write`), never a lanes App token, so its issues come from `github-actions[bot]` and start no
workflow. The kill switch stops it. The lanes App reading in signal 2 is what pr-merge's token sees
at the start and end of each run, not the broker's own quota record, which this token cannot read.

## Models

`models` sets the model, effort and turn budget of every model run, so a model change is one edit.
Each profile under `models.profiles` names:

- `model`: an alias (`default`, `best`, `fable`, `opus` or `sonnet`), never a full model ID, passed
  as `--model`. `default` passes no `--model`, so the account's default model runs.
- `effort` (optional): `low`, `medium`, `high`, `xhigh` or `max`, passed as `--effort`. Unset
  passes none, so the model's default effort applies.
- `subagent-model` (optional, default `inherit`): an alias set as `CLAUDE_CODE_SUBAGENT_MODEL`
  through the run's `settings` env; `inherit` sets nothing. A spawn's own `model` and an agent
  definition's still win.
- `max-turns`: the turn budget, passed as `--max-turns`.

`models.routes` maps a run to a profile: a skill activity by its name, and a run that is no
activity by its run route: `verify-pr` for the [verifier](#verifier-verdict), `review-code` and
`review-security` for the code and security review lanes, `triage-issue` for intake triage, and
`summarize-reuse` for the read-only pass that describes a lane branch work-resolve-issue reuses
([pr-run-activity.md, Issue mode](pr-run-activity.md#issue-mode)). A run no route names takes `models.default-profile`. The config reader rejects a route or default
naming an undefined profile, and a route that is neither a skill activity nor a run route. A config with no `models` block gives every run the built-in `standard`
profile: model `default` and 75 turns. `resolve-config` turns the run's profile into its
`claude-args` and `settings-json` outputs, which the runners on claude-code-action pass as
`claude_args` and `settings`, and into `model`, `effort` and `max-turns`, which a run on
`run-claude-cli` ([Funding](#funding)) passes as those inputs; `model` is empty for `default`,
which that action cannot pass, so such a run fails. The values come only from this file on the
base, never from text the run reads.

This repository's block has five profiles: `standard` (model `default`, 75 turns, no effort),
every skill activity's; `review` (`opus`, 60 turns, no effort), the verifier's; `pr-review`
(`sonnet`, effort `high`, 75 turns), both review lanes'; `triage` (`sonnet`, effort `medium`,
30 turns), intake triage's and the [lane sweep](#the-lane-sweep)'s; and `summary` (`sonnet`, effort `medium`, 10 turns), the reuse
summary pass's.

`models.issue-dimensions` budgets a skill activity with input `issue` from its issue's Size,
Complexity and Uncertainty org issue fields. `fields` maps each field id and its single-select
option ids to the keys of `sizes`, `complexity` and `uncertainty`; ids, not names, so a renamed
option keeps its meaning. A field with no value, or whose latest setter (from the GraphQL field
events) is neither a listed human on the trusted-actor list nor the lanes App, is not assessed;
an option no entry maps fails the resolve with `unmapped-dimension`. Before any model turn the
activity skips with `not-assessed` when a field is not assessed, then with its Uncertainty's
mode when that is not `run` (`research-first` or `probe-first`), then with `split-required` when
its Size is `split`. Otherwise its `max-turns` is the size's `base-turns` times the complexity
factor, rounded up, replacing the profile's, and the size's `timeout-minutes` is the run job's
timeout; a skip takes the shortest size timeout. resolve-config outputs `issue-dimensions`
(`<size>/<complexity>/<uncertainty>`, or `not-assessed`) and `timeout-minutes`;
work-resolve-issue.yml resolves them before its run job starts, since a job's timeout is fixed
then, and passes the dimensions on (`issue-dimensions`), so a field set while the run waits for
its slot cannot give it more turns than its timeout allows; without `issue-dimensions` the
timeout is 25 minutes. This repository's budgets are owner-approved starting values, tuned in
[`pr-pipeline.yaml`](../pr-pipeline.yaml) (`models.issue-dimensions`) from per-run measures. Large
is `split`, and Uncertainty Known, Knowable and Unknown map to `run`, `research-first` and
`probe-first`. No model name is set here.

## Funding

Each Claude lane's runs are paid by one funding role: `reviews`, `automations` or `issue-lane`. A
lane on ci-workflows' `run-claude-cli` action passes its role with the role's two secrets,
`<ROLE>_CLAUDE_API_KEY` and `<ROLE>_CLAUDE_CODE_OAUTH_TOKEN` (role upper-snake, so `issue-lane`
gives `ISSUE_LANE_`); the key runs first and the subscription token only after a credit stop.
`pr-verify` holds one credential per job: `check-intent` runs on the key, and
`check-intent-subscription` runs on the token, on a new runner, only after `check-intent`'s credit
stop with no permission denial or when the key is empty. Each lane's workflow names its role as a
literal, and the runner policy admits it; no config key records it. `intake`, `pr-unblock`,
`fix-ci`, `pr-verify` and `pr-refine` take `automations`; `claude-review` and
`claude-security-review` take `reviews`; `work-resolve-issue` takes `issue-lane`.

`intake` and `pr-verify` run on `run-claude-cli` today. Every other lane runs claude-code-action
with its role's OAuth token alone until it moves there, and it never gets an API key, since
claude-code-action runs are not paid from API credits. A lane on pr-run-activity-write.yml passes
its role as the `role` input, and the lane record names that role's token as the run's credential.

## Loop caps

One counter per PR, in the findings store, is shared by every lane. After `loop.review-rounds`
full review rounds, one more high-severity-only pass runs; if it still has findings, the PR
escalates. The address-feedback activity hands a PR to a person once `loop.review-rounds` of its
rounds have run, unless a write-access trusted person asked for a fix on a thread after the
newest round: that runs one more round, on the requested threads only. The default is 2; this
repository sets 3. Separately, after `loop.no-progress` lane runs in a row that change nothing, the PR
escalates. `loop.fix-ci-rounds` (default 3, at most 10) is the number of fix-ci commits the lanes
App may push to one PR; the next fix-ci run hands it to a person before any model turn.

## Limits

The optional `limits` block sets when the lanes restart work the usage limit stopped. Durations
are whole hours, at most 720; stop caps are at most 10 and `restarts-per-run` at most 50, so a
typo cannot let a forged limit stop restart a lane without bound. resolve-config emits all twelve
with defaults.

| Key | Default | What it sets |
|---|---|---|
| `fallback-reset` | 5 | Hours after a limit stop that names no reset time before the limit counts as reset. |
| `reset-clamp-min` | 1 | Fewest hours after a stop before a restart, whatever reset the stop names. |
| `reset-clamp-max` | 168 | Most hours after a stop before a restart, whatever reset the stop names. |
| `restarts-per-run` | 5 | Issues one work-unblock sweep restarts or re-fires. |
| `limit-stops-per-head` | 3 | Limit stops on one PR head after which pr-unblock stops dispatching it again. |
| `limit-stops-per-issue` | 3 | Limit and funding stops since a person last added `agent-ready` before work-unblock hands the issue to a person. |
| `wip-cap` | 60 | The issue lane's WIP cap when the lane merge rate cannot be read ([WIP cap](#wip-cap)); at most 500. |
| `turn-cap-restarts` | 0 | Restarts after a run reaches its turn cap, since a listed human last added `agent-ready`, before report-outcome hands the issue to a person; at most 5, and 0 never restarts. |
| `fix-ci-per-run` | 2 | fix-ci dispatches one pr-unblock-dispatch run sends; at most 20. |
| `fix-ci-restarts` | 1 | Further fix-ci dispatches on one PR head after its first fix-ci run failed; 0 to 5. |
| `admission-window-hours` | 24 | Hours of issue-lane admissions the admitted backlog (open issues labeled `agent-ready`) may hold before new `agent-ready` labels pause. |
| `admission-factor` | 0.8 | Share of the lane's hourly merge rate admitted per hour; greater than 0, at most 1. |

report-outcome and the work-unblock sweep read them from resolve-config's output;
pr-feedback-dispatch, pr-unblock-dispatch and work-resolve-issue's WIP cap check resolve the base
config themselves. A config the resolver refuses fails the two dispatchers before any dispatch;
the WIP cap check fails open and starts the run. This repository sets `wip-cap`,
`turn-cap-restarts` (0), the two fix-ci limits, the two admission limits and the `wip` block.

`node .github/scripts/work-resolve-issue/admission-window.mjs` reports whether admissions are
open: the admitted backlog is under `admission-factor` times lane merges per hour (the last 24
hours) times `admission-window-hours`. It prints one line and exits 0 open, 1 held, 2 on error.
No lane reads it yet.

## WIP cap

The optional `wip` block sizes the issue lane's work in progress from the lane merge rate. The WIP
cap check (`.github/actions/check-wip-cap`) runs before work-resolve-issue takes a slot, and
work-unblock's sweep runs it before a re-fire. It reads, one request at a time and none once
`x-ratelimit-remaining` reaches 0, the lanes App's open pull requests, those merged in the window
and those opened in it.

| Key | Default | What it sets |
|---|---|---|
| `target-lead-time-hours` | 2 | Target open-to-merge hours. The WIP cap is merged lane PRs per hour times this, rounded up, at least `min-cap`. |
| `min-cap` | 1 | Floor under the computed WIP cap, so a day with few merges cannot shrink the cap until the lane stalls. This repository sets 12. |
| `merge-rate-window-hours` | 24 | Rolling window for the merged and opened counts. |
| `opened-to-merged-ratio` | 0.8 | Lane PRs opened in the window may be at most this share of those merged in it. Not `limits.admission-factor`, which sizes the agent-ready backlog. |
| `held-cap` | 60 | Held lane PRs at or above which the held buffer is over its cap. |
| `held-alarm-hours` | 24 | Age past which a held lane PR raises the alarm. |
| `pause-from` | empty | UTC date or date-time from which the lane pauses over the WIP cap; empty never pauses. |

A held lane PR carries `needs-human` or `do-not-merge`, or has a body line exactly
`Hold: a human merges this`. Held PRs never count against the WIP cap; countable PRs are the open
lane PRs that are not held. Over the WIP cap (countable at or above it), over the held cap, over
the admission share, or with a held PR past the alarm age, the check writes a warning annotation.
Over the WIP cap on or after `pause-from` it pauses the lane: work-resolve-issue starts no run and
work-unblock re-fires none. The held cap only alerts; it never pauses the lane. A read that fails
never caps; without a merged count the cap is `limits.wip-cap`. A held PR's age runs from when it
opened.

The check publishes its status as one flat JSON object: the step output `wip`, the step summary
and the log line `check-wip-cap: <json>`. `capped` is `true` only while the lane pauses.

| Field | Meaning |
|---|---|
| `countable_lane_prs` | Open lane PRs not held; null when the listing failed. |
| `held_lane_prs` | Open lane PRs held. |
| `held_oldest_age_hours` | Hours since the oldest held PR opened; null with none. |
| `held_over_alarm_count` | Held PRs older than `held-alarm-hours`. |
| `wip_cap` | The WIP cap in effect. |
| `wip_cap_source` | `computed` from the merge rate, or `config` (`limits.wip-cap`). |
| `wip_min_cap` | The floor under the computed cap. |
| `held_cap`, `held_alarm_hours` | The held buffer's cap and alarm age. |
| `merged_lane_prs_window`, `merge_rate_per_hour`, `merge_rate_window_hours`, `target_lead_time_hours` | The merge rate and its inputs. |
| `admitted_lane_prs_window`, `admission_cap`, `opened_to_merged_ratio` | Lane PRs opened in the window and their cap. |
| `wip_over`, `held_over`, `admission_over`, `held_alarm` | Which limit is crossed. |
| `alert` | Any of the four. |
| `pause_from`, `paused` | The pause date and whether the lane pauses now. |

## Planning lane work

Size the process to the change:

- A sub-topic of lane work gets a one-page plan.
- Run `/planning:design`, the plan review and `/planning:devils-advocate` only for a change that
  moves a trust boundary.
- Record an ADR only for a trust-boundary or irreversible choice; `/architecture:record-decision`'s
  admission test still applies, and a reversible choice goes in the PR body.
- When the owner pre-approved the recommended options, stop only on the items the owner reserved.

## Changing this config

The config file is a lane-power file: a human merges every change to it, and no lane does. The
same holds for the trusted-actor list and any change to a lane's permissions, tokens or triggers.
Everything downstream of that human merge may propagate on its own.

A pull request that changes a lane and lists a not-verified item that could stop the lane from
running checks that item live before it merges. An item only a merged run can exercise, such as
a changed workflow that runs from the base branch, merges only once a tracked issue names the
check and its owner; a line in the pull request body does not count. Evidence: melodic-software/ci-workflows#755 listed its
intake author gate as "unverified, fails closed", merged, and skipped every intake run here
(melodic-software/ci-workflows#772).

The lanes token broker parses this config with resolve-config code pinned in azure-iac
(`src/lanes-token-broker/resolve-config.pin`, fetched by `scripts/deploy/fetch-resolve-config.sh`).
A pull request that changes a file that script fetches carries the body line
`Broker pin: melodic-software/azure-iac#<n>`, naming the azure-iac pull request that bumps the pin
to its merge commit; `ci-status` fails it otherwise. The path list is the `BROKER_PATHS` value of
`ci-status`'s "Require a broker pin PR for a broker-fetched change" step in
`.github/workflows/pr-require-checks.yml`. Evidence: #8313 changed `resolve.mjs` with no pin bump,
and the broker denied every pr-unblock token request as `config-invalid` until azure-iac#44.

## Outside this repository

The lanes depend on pieces other repositories own. Each row names where that piece is documented;
read it there, since this doc does not restate it. azure-iac, github-iac and architecture are
private. As of 2026-10-12; recheck when a row's owner moves the doc or a new external piece joins
the lanes.

| Piece | Owner and doc |
|---|---|
| Org architecture: why each trust link exists, glossary | `melodic-software/architecture`, `docs/trust-links.md` and `docs/glossary.md` |
| Token broker: the Function app, its Key Vault signing key, identities and roles, deploy | `melodic-software/azure-iac`: `README.md`, ADR 0001 (stack, who can mint), `src/lanes-token-broker/` |
| Broker operations: health check, taking it down, key disable, key rotation, fallback to a runner key | Not yet tracked; [azure-iac#17](https://github.com/melodic-software/azure-iac/issues/17) adds the runbook to azure-iac |
| Lanes App `melodic-automation-lanes`: identity and grant model | architecture `docs/trust-links.md` ("Lanes App"); github-iac ADR 0015 |
| Org variables `CLAUDE_LANES_DISABLED`, `LANES_BROKER_URL`, `LANES_BROKER_AUDIENCE`; repository variable `CLAUDE_LANES_REPO_DISABLED` | github-iac `OrgCiRouting.cs`; README "Claude lane kill-switches" (how to flip either switch); [ADR 0015](https://github.com/melodic-software/github-iac/blob/main/docs/adr/0015-oidc-token-broker-for-pr-pipeline-lane-app-tokens.md) |
| Agent identity (`merge.agent-identity`): the GitHub App the local babysit lane acts as, installed on this repository only, with variables read only | Not yet provisioned; [github-iac#691](https://github.com/melodic-software/github-iac/issues/691) |
| Repository variable `AUTOMATION_LANES_APP_SENDER_ID` | Set by hand on this repository and the sandbox, declared nowhere; [github-iac#677](https://github.com/melodic-software/github-iac/issues/677) |
| `trust-root` ruleset, merge queues, code-owner review settings | github-iac `OrgRulesets.cs`; ADR 0015 Decision 5; [ADR 0007](https://github.com/melodic-software/github-iac/blob/main/docs/adr/0007-no-required-approving-reviews.md). Its rollback is not yet tracked: [github-iac#677](https://github.com/melodic-software/github-iac/issues/677) |
| Test repository | [`melodic-software/pr-pipeline-sandbox`](https://github.com/melodic-software/pr-pipeline-sandbox), whose README states its purpose |
| Trusted actors, runner policy, Actions naming vocabulary | `melodic-software/standards` components [`trusted-actors`](https://github.com/melodic-software/standards/tree/main/components/trusted-actors), [`runner-policy`](https://github.com/melodic-software/standards/tree/main/components/runner-policy) and [`github-actions-conventions`](https://github.com/melodic-software/standards/tree/main/components/github-actions-conventions), synced into `.github/standards/` |
| Review and intake reusable workflows | [`melodic-software/ci-workflows`](https://github.com/melodic-software/ci-workflows) `.github/workflows/pr-review.yml`, `pr-review-security.yml` and `intake-triage.yml`, called by this repository's synced `*-hosted.yml` callers and `intake-triage.yml` |

In this repository, the lane runners and their contract are in [Lanes](#lanes), the config is
`docs/conventions/pr-pipeline.yaml`, and the decisions are ADRs 0049 to 0051, 0053 to 0055 and 0058 in `docs/adr/`.

## Names

Lane and activity names are verb-first and literal; review-engine activity names (`claude`,
`codex`) are the one exception. The allowed workflow stages, function words and engines are owned
by the `github-actions-conventions` component in `melodic-software/standards`
(`components/github-actions-conventions/vocabulary.json`); this doc and its schema never copy that
list. The config reader reads the synced copy from the base SHA's
`.github/standards/github-actions-conventions/vocabulary.json`. Pipeline stage keys (the
[Stages](#stages) table) belong to this convention.

## Not settled yet

- Deferred: the `extends:` grammar for layering a repository file on org defaults. The reader
  rejects any value until a second repository adopts.
- The post-merge failure remedy (revert or fail forward, by change type). Until it is decided, the
  rung drop and `needs-human` issue above apply.

## Versioning

The schema's `version` is the contract major. [`CHANGELOG.md`](CHANGELOG.md) records each change.
A pull request that changes this directory does not edit `CHANGELOG.md`: it adds a changelog
fragment, `scripts/new-changelog-fragment.sh pr-pipeline <major|minor|patch|none>`, and the release
pull request writes the fragments into one `CHANGELOG.md` entry
([ADR 0048](../../adr/0048-release-plugins-from-changelog-fragments-through-a-bot-maintained-release-pr.md)).
A `major` fragment's pull request also raises the schema's `version`.
