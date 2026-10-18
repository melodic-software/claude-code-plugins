# PR pipeline convention

## Contents

- [Files](#files)
- [Stages](#stages)
- [Lanes](#lanes)
- [Activities](#activities)
- [Slots and order](#slots-and-order)
- [Concurrency](#concurrency)
- [Outputs and skips](#outputs-and-skips)
- [Merge authority](#merge-authority)
- [Trust-root paths](#trust-root-paths)
- [The lane sweep](#the-lane-sweep)
- [Models](#models)
- [Loop caps](#loop-caps)
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
| `CHANGELOG.md` | Contract versions. |

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
| `pr-refine` | ready |
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

`pr-unblock`'s `address-feedback` dispatches come from `pr-feedback-dispatch.yml`, also scripted,
on `workflow_run` `completed` of `pr-review-hosted` and `pr-review-security-hosted`. It takes only
the upstream run id from the event and reads the rest back. It dispatches `pr-unblock.yml` with
`activity: address-feedback` when the upstream is a `pull_request` run of one of those two paths in
this repository, exactly one open non-draft PR into `main` has its head, the lanes App opened that
PR, it carries neither `do-not-merge` nor `needs-human`, both lanes' newest reviewed-head markers
name the head, an unresolved thread exists that `address-feedback` would keep (left only by the
reviewer bot, or answered by a trusted human after the lane escalated it), the head has no
`pr-unblock / address-feedback` check run, and no `pr-unblock.yml` run titled
`pr-unblock address-feedback #<n>` is still queued or going (both lanes finishing at once). Then it
runs the base's resolve-config for that PR and head with `address-feedback` selected, so only that
slot's `applies-when` is decided, and dispatches only when the `pr-unblock` lane and its
`address-feedback` and `publish-feedback` slots are enabled and `address-feedback` applies. It records `pr-feedback-dispatched-<upstream id>-<run
id>`, which the gate and the broker read to tie the run to a review of the PR's current head.
In `pr-unblock.yml`, `address-feedback` (the model job, `mutate-branch`) is followed by
`publish-feedback` (a script job with no model, `publish-artifact`), which posts the replies the
model job recorded ([`pr-run-activity.md`](pr-run-activity.md#prepare-review-threads)).

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
- `prepare` (optional, `skill` only, effect other than `read`): what the write runner does around
  the skill. `merge-base` merges the base tip into the gated head without committing before the
  skill runs, and commits the result with both as parents after it. `review-threads` keeps the
  PR's unresolved reviewer-bot threads and decides skip, escalate or proceed before any model
  turn, gives the skill the review-thread tool, and uploads the replies it records for a reply job
  with no model to post ([`pr-run-activity.md`](pr-run-activity.md#prepare-review-threads)). A write runner performs this
  only where it declares support by passing `prepare-supported: true` to `resolve-config`; anywhere
  else an applying leaf that sets `prepare` fails red rather than running without it.
- `checks` (optional, `skill` only): repository check scripts, each `scripts/<name>.sh` with its
  flags fixed, that a skill with an effect other than `read` may run. The write runner runs each
  from the base copy against the checkout, so no head code runs
  ([`pr-run-activity.md`](pr-run-activity.md#skill-activities)).
- `verify-scripts` (optional, `skill` only): exact repository-relative paths of scripts, each `scripts/<name>.sh`, `plugins/<plugin>/scripts/<name>.sh` or
  `plugins/<plugin>/skills/<skill>/scripts/<name>.sh`, that a skill with an effect other than
  `read` may run with any arguments but a path outside the checkout; a `read` leaf cannot set it.
  The write runner runs each from a read-only base copy of its plugin (or of `scripts/`) against
  the checkout, without `GH_TOKEN` or `GITHUB_TOKEN`
  ([`pr-run-activity.md`](pr-run-activity.md#skill-activities)). The arguments are the model's, so
  a script that changes files, runs code from the checkout or reaches the network hands the run
  that power: list one only when it limits itself, as `scripts/run-test-file.sh` (one test file
  inside the checkout) and `scripts/git-mv-rm.sh` (`git mv` and `git rm` inside the checkout) do,
  or when the run may hold that power, as `plugins/skill-quality/scripts/check-skill.sh` (each
  checked skill's `scripts/*.test.sh` and the checkout's markdownlint) does.
- `web-access` (optional, `skill` only, off when absent): `enabled` and `domains`, either `any` or
  a list of host names (`*.` allowed as a prefix). When on, a skill with an effect other than
  `read` may search the web, fetch those domains, and run the research skills
  ([`pr-run-activity.md`](pr-run-activity.md#skill-activities)). An activity that turns it on must
  set `reads-untrusted: true` and an effect other than `read`.
- `effect`: one of `read`, `mutate-branch`, `mutate-tracker`, `publish-artifact`, `merge`. The
  runner derives ordering from it, takes the token grant from
  [`effect-grants.json`](../../../.github/actions/resolve-config/effect-grants.json), and fails a
  `read` activity that leaves the working tree dirty. An activity that runs head code (tests,
  linters, builds) takes effect `read`, because a write-effect activity must not execute head
  code; a fix-and-push lane waits on a split design (a read-only run, then a separate
  signed-commit step).
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
  activity is asked to work on, not what it can touch; for a write effect it leaves out
  instruction surfaces and paths `.github/CODEOWNERS` lists
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
- `prepare` on a leaf whose effect is `read`;
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
PR), `superseded-sha`, `disabled-by-config` or `untrusted-trigger` (a fork, no same-repository PR, or an
actor or author not on the trusted-actor list). Silence is not a skip, with three exceptions that
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
  removing the marker or the label does not clear one.
- **Opt-in label.** `merge: agent-allowed` makes a pull request eligible; it does not make it safe,
  and the diff risk score still decides. It counts only when a human added it last and the pull
  request body was not edited afterwards.
- **HIGH path floor.** A fixed set of paths in the wrapper's code, joined with
  `merge.diff-check.denied-paths` and matched case-insensitively. A diff that touches any of them
  scores HIGH and is never merged unattended.
- **Merge queue.** The wrapper enqueues with `--match-head-commit`, never `--auto`, and only when
  every required check is green. An armed auto-merge request on the pull request is a refusal, and
  the wrapper disarms it.
- **One merge in flight.** The wrapper refuses while the identity has an entry in the merge queue,
  or while an earlier unattended merge has not passed its post-merge check.
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
- **Risk switches.** Each check below is a `merge.diff-check` setting that is off when absent, and
  this repository leaves every one off (owner decision, 2026-10-17): `denied-paths` (an empty
  list denies no path), `high-path-floor` (true scores the scorer's fixed HIGH path set HIGH),
  `c2-contradictions` (true scores a removed, renamed or copied file, a schema change or more
  than one plugin MED), `max-changed-files` and `max-changed-lines` (absent is no cap). The local
  babysit lane ignores these switches and keeps every check. The review evidence and the
  security lane's findings still count.

  What is left with them off: a lane pull request may change the merge gate, the workflows and
  their tokens, these lane rules, skills, hooks, agent instructions and CI checks, at any size.
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
- **Post-merge check and one merge in flight.** Only merges the agent identity enqueued count. A
  merge by a person or by another App, such as a release pull request, is not the lane's.

While `merge.report-only` is true and `merge.dependabot.mode` is not `enforce`, the workflow starts
no full CI run either; its summary says whether it would have.

### Dependabot pull requests

No Dependabot pull request waits on a human
([ADR 0073](../../adr/0073-merge-dependabot-pull-requests-in-the-pr-merge-lane.md)). The pr-merge
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
  one merge in flight. No closing issue, denied-path rule or diff risk score applies: `ci-status`
  (and, for tier `review`, the review verdict) is the gate, and a workflow pin bump touches
  `.github/**` by definition.
- **Switch.** `merge.dependabot.mode` decides it, not `merge.report-only`: `enforce` merges,
  `report` reports and writes nothing, and `off` (the default) refuses every Dependabot pull
  request and leaves them unlisted.

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
data, and judges whether the diff delivers the issue's intent correctly and safely. The run
uploads one artifact, `pr-verify-<pr>-<head-sha>-<pass|pass-notes|fail>`, holding the verdict JSON
(`pr`, `head_sha`, `base_sha`, `head_ref`, `linked_issues` with each issue's author login, id and
account type, `verdict`, `summary`, `notes`, `run_id`). The head SHA is the one `pr-require-checks`
ran on, never the pull request's live head. A model error or an output that fails the schema
uploads nothing. A head that already has a counted verdict from a completed run (a `fail` under any
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

`verify:too-old`, `verify:earlier-fail`, `verify:spec-changed` and `verify:untrusted-spec` need a
human. While `merge.report-only` is false the lane escalates such a refusal on the pull request
([loop-lane §2](../loop-lane/README.md#2-escalation-contract)): it keeps one
`<!-- babysit-merge-verify-escalation -->` comment naming the refusal and the head, rewritten only
when either changes, then adds the tracker's human-gated role label (`needs-human` unless
`.work-item-tracker.json` maps it) when no label matches it ignoring case. The comment goes first,
so a label never stands unexplained, and a failed label is added by the next run; a rerun that
finds both writes nothing. While it is true the refusal is only reported. The
lane token's `issues: write` and `pull-requests: write` cover both writes. A human clears them
by merging in person: the verdict is not a check run and stays out of `ci-status` and the required
checks (github-iac ADR 0011), so a human merge needs `ci-status` alone. A queued entry without an
allowing verdict at its live head leaves the queue. A dependency manager's pull request (a `Bot`
account with a dependency manager's login; a `User` named like one is judged) needs no verdict: the lane decides it in its Dependabot class before the verdict is read, or refuses it, and
its queued entry is not held for one. The gate lists every repository artifact once per
candidate run, since pr-merge.yml runs the gate once per candidate. A listing that got a 5xx or a fast
network error is read again, three reads in all with backoff, all inside the one gh timeout a single
read would get; any other failure, a timeout, a 429 or a rate-limit 403 included, is not. A failed listing is kept for
that run as well: the pull request and every queued entry refuse `verify:unreadable` without the
listing being paged again, so a listing outage holds the whole queue rather than merging blind.
The lane token holds no Actions permission, so pr-merge.yml grants its job `actions: read` and passes the job's `GITHUB_TOKEN` as
`BABYSIT_VERIFY_GH_TOKEN`; the reader uses it as `GH_TOKEN` for the artifact listing, the run
records and the download alone, and every other call keeps the lane token. That job checks out only
main and runs no pull request code.

## Trust-root paths

A lane's token grant and the rules it is judged by come from these default-branch paths, so a
change to any of them is a change to every lane's powers:

- `docs/conventions/pr-pipeline.yaml` and `docs/conventions/pr-pipeline/**` (config and schema);
- `.github/actions/**`, which holds `resolve-config/effect-grants.json`,
  `resolve-config/lane-rules.json`, `resolve-config/activity-rules.json` and every action a lane
  job runs from its base checkout;
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
  holds `workflows`, so no lane can push `.github/workflows/`;
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
`claude-args` and `settings-json` outputs, which the runners pass to claude-code-action as
`claude_args` and `settings`; the values come only from this file on the base, never from text the
run reads.

This repository's block has five profiles: `standard` (model `default`, 75 turns, no effort),
every skill activity's; `review` (`opus`, 60 turns, no effort), the verifier's; `pr-review`
(`sonnet`, effort `high`, 75 turns), both review lanes'; `triage` (`sonnet`, effort `medium`,
30 turns), intake triage's and the [lane sweep](#the-lane-sweep)'s; and `summary` (`sonnet`, effort `medium`, 10 turns), the reuse
summary pass's.

## Loop caps

One counter per PR, in the findings store, is shared by every lane. After `loop.review-rounds`
full review rounds, one more high-severity-only pass runs; if it still has findings, the PR
escalates. The address-feedback activity hands a PR to a person once `loop.review-rounds` of its
rounds have run. The default is 2; this repository sets 3. Separately, after `loop.no-progress` lane runs in a row that change nothing, the PR
escalates.

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
