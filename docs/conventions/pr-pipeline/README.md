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
- [Review-lane holds](#review-lane-holds)
- [Trust-root paths](#trust-root-paths)
- [The lane sweep](#the-lane-sweep)
- [The monitoring lane](#the-monitoring-lane)
- [Models](#models)
- [Funding](#funding)
- [Loop caps](#loop-caps)
- [Limits](#limits)
- [WIP cap](#wip-cap)
- [Adoption](#adoption)
- [Red main](#red-main)
- [Branch cleanup](#branch-cleanup)
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
| `pr-refine` | a `fix-docs` dispatch from `pr-unblock-dispatch.yml` for each ready PR that changes Markdown and never had `fix-docs`, after a push to the default branch, or a trusted human's dispatch |
| `pr-run-checks` | dispatch from `pr-refine` |
| `pr-review`, `pr-review-security` | dispatch from `pr-refine` |
| `pr-verify` | dispatch from `pr-refine` |
| `pr-explain` | dispatch from `pr-refine`, alongside verify |
| `pr-require-checks` | each verify result |
| `pr-unblock` | a dispatch for each conflicting PR, each unreviewed review-tier Dependabot PR, and each failing lanes App PR after a push to the default branch, a dispatch after a review lane finishes on a lanes App PR with an open reviewer-bot thread, or a trusted human's dispatch |
| `pr-merge` | final check green, or a hold removed |
| `work-unblock` | an issue closing, by a listed human, and an hourly sweep of the issues a listed human or a merge (a merged PR or a commit) closed in the last three hours (catching PR merges a bot ran); labels `agent-ready` on each issue it blocked that is now unblocked, unheld and owner-ratified; the label starts `work-resolve-issue`. The sweep also restarts or re-fires stopped issue runs and relabels a red-main fix issue a repeat failure reopened |
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

In `pr-unblock.yml` no model holds a write token or runs git: `resolve-conflicts-select` (base
code only, read-only token) merges the default branch tip into the head and decides clean,
conflicted or escalate, and posts the `resolve-conflicts` check neutral when no model is needed;
`resolve-conflicts` (a `read` skill in [patch output mode](pr-run-activity.md#patch-output-mode),
on run-claude-cli with the subscription fallback) resolves a conflicted merge from read-only
context files with no shell; and `apply-conflict-patch` (a script, `mutate-branch`) commits the
merge with the head and the pinned base as parents
([`pr-run-activity.md`](pr-run-activity.md#prepare-merge-base)).

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
human-gated label, only one whose answer is a fix request, unless a lane escalation put the label
on: the lanes App added it last, its `work-items:escalation lane=pr-unblock` comment (pr-unblock
or fix-ci) followed within a minute, no other marker is on its comments since, and no review-lane
`claude-lane-hold` names the current head or is open, per
`.github/scripts/pr-unblock/gate-source.mjs`; anything ambiguous keeps the fix-request rule, and
the label stays on, and `clear-escalations.mjs` removes it only while no address-feedback round
record is on the lanes App's comments since it went on; to stop the lane working such a PR, a
person adds `do-not-merge`, since re-adding a label already on records no event), the head has no
`pr-unblock / address-feedback` check run (one that started before the head's newest
`pr-unblock / publish-feedback` check run stops counting when that run skipped `no-model-turn`:
the round handled nothing, and the round cap still bounds the retries; a limit stop keeps its
reset hold and counts toward `limit-stops-per-head`), and no `pr-unblock.yml` run titled
`pr-unblock address-feedback #<n>` is still queued or going (both lanes finishing at once). Then it
runs the base's resolve-config for that PR and head with `address-feedback` selected, so only that
slot's `applies-when` is decided, and dispatches only when the `pr-unblock` lane and its
`address-feedback` and `publish-feedback` slots are enabled and `address-feedback` applies. It records `pr-feedback-dispatched-<upstream id>-<run
id>`, which the gate and the broker read to tie the run to a review of the PR's current head.

It also runs on `workflow_run` `completed` of `pr-verify`. When that run of `pr-verify.yml` on
`main` uploaded a `fail` verdict, its `post-verify-notes` job (a base job with no model, holding
`pull-requests: write`) posts the verdict's summary and notes on the PR as file-level review
comments by `github-actions[bot]`, each starting `<!-- pr-verify:fail-note -->`, on the head the
verdict judged (`.github/scripts/pr-unblock/verify-notes.mjs`). It posts only on an open PR still at
that head, and only the comments that head does not hold yet, by file; on an adopted PR the lanes App did not open, no round starts and
the notes tell its author why the lane refuses it. A note that starts with a path the PR changes goes on
that file; the summary and the other notes go on the first such file, or on the PR's first changed
file. `address-feedback` keeps such a thread as the `verifier`'s finding, as it keeps the reviewer
bot's, when its review is `github-actions[bot]`'s on a head the reviewed-head markers name. The
dispatch job then decides as above, with the newest completed review run at that head as the
upstream it records, except that only `pr-unblock / address-feedback` check runs started after the
`pr-verify` run was created count, and the head's handled record is not read, since the notes are
new work at a head an earlier round may have handled; with none yet, the review run dispatches when it completes. The fix round's
push gives a head the verifier judges again.
In `pr-unblock.yml`, `address-feedback-select` (a base job with no model and a read-only token)
keeps the threads, `address-feedback` (the model job, `read`, on the read runner with a
subscription fallback) answers them and hands on a patch and its replies,
`apply-feedback-patch` (a script job with no model, `mutate-branch`) pushes the patch, and
`publish-feedback` (a script job with no model, `publish-artifact`) posts the replies, naming the
pushed commit ([`pr-run-activity.md`](pr-run-activity.md#prepare-review-threads)).

The reviewer bot is `claude[bot]`, or `github-actions[bot]` on a comment whose last non-blank
line is a review lane's `claude-lane: <lane>` footer, as ci-workflows' `pr-review-cli.yml` posts
its findings; the review holding it must be `github-actions[bot]`'s too.

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
from the GitHub Actions app (the untrusted-trigger skip aside; one that started before the head's
newest `pr-unblock / apply-dependency-verdict` check run stops counting when that run skipped
`no-model-turn`, unless it is a limit stop, and the round cap still bounds the retries). Their run
ids join the same dispatched-runs record. It has no schedule: the broker accepts a dispatcher run
started only by a push or a listed human, so a push to `main` or a hand run wakes it. In `pr-unblock.yml`, no
model holds a write token: `review-dependency-select` (base code only, read-only token) selects
the pull request or posts its check neutral; `review-dependency` (a `read` skill in
[patch output mode](pr-run-activity.md#patch-output-mode), on run-claude-cli with the
subscription fallback) returns its verdict as structured output and leaves a fix as a patch;
`apply-dependency-patch` (a script, `mutate-branch`) pushes that patch only on a scanned `fix`
verdict; and `apply-dependency-verdict` (a script, `publish-artifact`) acts on the verdict and
never merges; the pr-merge lane merges on its `verdict=merge` marker at the current head
([`pr-run-activity.md`](pr-run-activity.md#prepare-dependency-review);
[ADR 0074](../../adr/0074-review-risky-dependabot-updates-in-a-model-job-and-act-in-a-scripted-job.md)).

`pr-unblock`'s `fix-ci` runs in separate jobs of `pr-unblock.yml`, so no model holds a write token:
`fix-ci-context` (base code only, read-only token) writes the failing checks' context or hands
the pull request to a person once `loop.fix-ci-rounds` fixes were pushed; `fix-ci` (a `read`
skill in [patch output mode](pr-run-activity.md#patch-output-mode), on run-claude-cli with the
automations role's API key) runs `source-control:pull-request ci --ci`, which reruns, fixes and
reruns the checks; `fix-ci-subscription` runs the same on the role's OAuth token, only when
`fix-ci-handoff`'s read of this run's jobs shows `fix-ci` posted no check, as a credit stop or an
empty key leaves it
([two calls](pr-run-activity.md#two-calls-on-one-credential-each)); and `apply-patch` (a
`mutate-branch` script, no model, no head code) pushes the patch as one commit without force,
refusing the whole patch on any change `patch-rules.json`'s `ci-context` row refuses: the
universal set, an agent instruction path (`CLAUDE.md`, `AGENTS.md`, `.claude/` or
`.claude-plugin/`, a plugin's `hooks/`, `monitors/` or `bin/`, `.mcp.json`, `.lsp.json`,
`.gitmodules`, `CODEOWNERS`), or more than 300 paths
([`prepare: ci-context`](pr-run-activity.md#prepare-ci-context),
[`prepare: apply-patch`](pr-run-activity.md#prepare-apply-patch)). An empty, invalid or
unappliable patch, or a check the model escalated, goes to `report-escalation`, with one
exception: a run at `model-rung` 0 that changed nothing and escalated only `unfixed` or
`not-reproducible` checks skips `apply-patch` with `rung-up`, and the same `pr-unblock` run
runs `fix-ci` and `apply-patch` once more at `model-rung` 1 (`fix-ci-rung-up`,
`fix-ci-rung-up-subscription`, `apply-patch-rung-up`; [Models](#models)). `report-escalation`
hands the PR to a person unless that retry's patch applied cleanly: the retry's own reason, else
`ci-fix-escalated` (a neutral or failed retry). A cancelled run applies no label: the write
workflow's `run` job has no status function in its `if:`, so it skips on a cancel, nothing
pushes and `ci-status` stays red. `protected-path`, `weaken-required` and `flaky` go to a person
without a retry. The same
`pr-unblock-dispatch.yml` run starts `fix-ci`, after the conflict and Dependabot dispatches: one
GraphQL query per page of 50 open pull requests, its `rateLimit.cost` logged, lists the non-draft,
same-repository ones into `main` that the lanes App opened (by bot id), or that a trusted actor
opened ([`adoption`](#adoption); a person's once idle), with no `do-not-merge`, `needs-human` or tracker
human-gated label,
whose head's `ci-lanes` commit status from `github-actions[bot]` is `failure` or `error`: the lanes'
verdict ci-status records, not ci-status itself, which also fails on a hold, a pending review or the
PR contract, none of which a CI fix mends. It dispatches those whose head has no `pr-unblock / fix-ci` run yet (an
untrusted-trigger skip aside), or only failed ones, at most `limits.fix-ci-restarts` of them,
and no `fix-ci` run for the PR still queued or going, at most `limits.fix-ci-per-run` per run,
lowest number first. Their run ids join the dispatched-runs record. The dispatcher job's
concurrency group cancels a run in progress, so a burst of pushes ends in one listing.

`pr-refine`'s `fix-docs` runs the same way in three jobs of `pr-refine.yml`: `fix-docs` (a
`read` skill in patch output mode with no prepare mode, on run-claude-cli with the automations
role's API key) runs `ai-slop:audit fix` on the PR's changed Markdown files;
`fix-docs-subscription` runs the same on the role's OAuth token, only when `fix-docs-handoff`'s
read of this run's jobs shows the broker allowed `fix-docs` and `fix-docs` posted no check, as a
credit stop or an empty key leaves it; and `apply-docs-patch` runs the `apply-patch` activity on a `written` patch,
pushing it as one commit under `patch-rules.json`'s `default` row, which refuses the universal
set, every agent instruction path and more than 300 paths. No change is the common case, so an
`empty` patch runs no push job. `pr-refine.yml` has no escalation job: a refused or
unappliable patch posts the `pr-refine / apply-patch` check neutral `awaiting-human` and labels
nothing. Every job trusts the default branch tip (`trusted-base: default-tip`). `fix-docs` routes
to the `docs-fix` profile ([Models](#models)).

The same `pr-unblock-dispatch.yml` run dispatches `pr-refine.yml`'s `fix-docs` once per pull
request: one GraphQL query per page of 50 open pull requests, its `rateLimit.cost` logged, lists
the non-draft, same-repository ones into `main`, whoever opened them, lanes App PRs included,
except Dependabot (account 49699333, whose own rebases a lane commit stops), the release App
(337859524) and the standards-sync App (300666570), whose files are generated or synced; an
author with no account id is skipped. It keeps those with no `do-not-merge` or `needs-human`
label, that change at least one `.md` file, and whose head has no `pr-refine / fix-docs` or
`pr-unblock / fix-docs` (the lane `fix-docs` ran in before) check run from the GitHub Actions
app. For each, lowest number first, one
more query reads the check runs on its last 50 commits, and a PR with a `fix-docs` run on any of
them is skipped for good; the dispatch record keeps its head so the next run skips that read. A
run older than 50 commits, or a force-push that dropped its commit, costs one more run. It sends
at most `limits.fix-docs-per-run` per run, none for a PR whose `fix-docs` run is still queued or
going, and the run ids join the dispatched-runs record. A PR that turns ready waits for the next
push to the default branch.

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
  for a script (a `mutate-branch` one), `ci-context`, `review-threads`, `dependency-review` and
  `merge-base` the modes the read runner performs, each on a `read` skill that hands on a patch
  ([`pr-run-activity.md`](pr-run-activity.md#prepare-ci-context)). `merge-base` runs on the read
  runner after the caller's base job merged the base tip into the gated head and found it
  conflicted: it merges the same base again, gives the skill the conflicts as read-only files, and
  hands on its resolutions as a patch, which a `prepare: apply-patch` job commits with the head and
  the base as parents ([`pr-run-activity.md`](pr-run-activity.md#prepare-merge-base)). `review-threads` runs on the
  read runner after the caller's base job kept the PR's unresolved reviewer-bot threads and
  decided skip, escalate or proceed before any model turn: it checks that job's thread file, gives
  the skill the review-thread tool, and hands on its fix as a patch and the replies it records
  (`applied-by.feedback-replies`) for script jobs with no model to push and post
  ([`pr-run-activity.md`](pr-run-activity.md#prepare-review-threads)). A runner performs this
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
  its uncommitted change as a patch when `applied-by.patch` names its applier (`fix-docs`,
  `fix-ci` and `resolve-issue`). Those edit tools and the `changed-paths` filter key on "an effect other than
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
- `permission-mode` (optional, `skill` only): `dontAsk` (the default) or `auto`, the Claude Code
  permission mode of a PR-mode skill on the read runner's launcher; other runners run `dontAsk`.
  The run job fails red unless the CLI reports the mode asked for
  ([`pr-run-activity.md`](pr-run-activity.md#two-calls-on-one-credential-each);
  [ADR 0049](../../adr/0049-run-ci-lanes-on-github-hosted-runners-under-trigger-and-token-hardening.md)).
- `effect`: one of `read`, `mutate-branch`, `mutate-tracker`, `publish-artifact`, `merge`. The
  runner derives ordering from it, takes the token grant from
  [`effect-grants.json`](../../../.github/actions/resolve-config/effect-grants.json), and fails a
  `read` activity that leaves the working tree dirty unless it hands its change on as a patch. An
  activity that runs head code (tests, linters, builds) takes effect `read`, because a
  write-effect activity must not execute head code. To change the branch it hands its change on
  to a `prepare: apply-patch` script with no model and no head code, named in its
  `applied-by.patch`, as fix-docs and fix-ci do with `apply-patch`.
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
  classes, events, `mergeable`, `draft`, `admission`). `mergeable` is `conflicting` or `clean`,
  read from the PR at the gated head SHA only; unknown mergeability never matches. `labels-absent`
  matches only when none of its labels is on the PR. `admission` is an issues lane's
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
| `feedback-protected-path` | the PR changes nothing under `.github/workflows/` |
| `head-moved` (pr-merge's `babysit-merge-verify-escalation`, `babysit-merge-risk` and `babysit-merge-shared-copy-escalation`, with no pr-unblock escalation since the label, and the marked App comment written last before the label is pr-merge's and within a minute of it) | the newest App comment carrying each marker names, as ``at head `<sha>` ``, a 40-hex head other than the current one; pr-merge then judges the new head and escalates again if its refusal still holds |

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
`issue` for a patch that goes to a new issue-lane branch made at the run's base or resume tip.
[`apply-patch.mjs`](../../../.github/scripts/apply-patch/apply-patch.mjs) reads it for fix-ci's,
fix-docs's, resolve-conflicts's, address-feedback's, review-dependency's and resolve-issue's patches ([`prepare: apply-patch`](pr-run-activity.md#prepare-apply-patch)).
[`patch-rules.schema.json`](../../../.github/actions/resolve-config/patch-rules.schema.json) closes
each row to these keys:

| Key | Holds |
|---|---|
| `refuse` | Named refusals; any match refuses the whole patch. |
| `allow` | What every other changed path must also meet: `any`, `kept-threads` (a path in the scope of a thread the select job kept, its `named_paths` included, read from that job's thread file), `dependency-manifests` (an npm or pip manifest or lock file outside `.github/` in a directory the base `.github/dependabot.yml` lists for its ecosystem) or `merge-result` (a path the base merge left conflicted; under a merge row only the patch's own changes, measured from the conflict tree, face the rules, every conflicted path left in the tree must hold no conflict markers, and the merge's base-side changes pass through). |
| `max-files` | The most paths one patch may change, or `null`. |
| `max-blobs` | Merge rows only: the most blobs one merge commit may upload, each one neither the head nor the base holds at its path; over it nothing is written. |
| `requires` | What the producer's output must say before anything applies: `dependency-verdict: fix`, the scanned verdict's field. |
| `content-rule` | Optional; what each changed file's bytes must also meet, on the local blobs before any commit is built, escalating as `protected-path`: `dependency-version-change` (`dependency-review`: modified in place, a regular file, changed only by a version, `fixRefusal` in `dependency-classify.mjs`). |
| `commit` | `parents` (`[head]`, or `[head, base]` for a merge), `message` and `trailer`, with `{ref}`, `{base}`, `{lane}`, `{activity}` and `{issue}` filled in. |
| `reads-report` | The producer report the apply reads (`ci-escalations`: the checks the model escalated), or `null`. |
| `empty-at-push` | Optional; the kind a patch that applies but changes nothing escalates at push time: `empty` (the default), `invalid` (`ci-context`, as the producer said it wrote a change) or `conflict` (`merge-base`: its `unresolved-conflict` reason, since the conflicts stay as git left them). |
| `skip-moved-head` | Optional, default `false`; `true` (`ci-context`, `review-threads`, `dependency-review`, `merge-base`) skips `superseded-sha` on any PR head that moved since the producer ran, where other rows take the moved tip with `--3way` when the moved commits touch no patched path. `default` sets `false`: fix-docs runs once per pull request, so a skipped fix-docs patch would never run again. |
| `script-exec-bit` | Optional, default `false`; `true` (`issue`) makes each new or changed file that ends in `.sh` or starts with `#!` executable after every refusal passes, since the model's tools set no file mode. |
| `escalations` | The escalation reasons the apply may give for the row. |

Every row refuses `.github/workflows/**` in any case and through any `..` segment (the lane
token has no `workflows` permission), `CODEOWNERS` at the root, in `.github/` or in `docs/`,
`.gitmodules`, `**/settings*.json`, a symbolic link, a gitlink, and a rename into any of those.
The rest of `.github/`, `.claude/`, `.mcp.json`, plugin hooks, `.claude-plugin/`, `lib/`,
`scripts/`, `CLAUDE.md`, `AGENTS.md` and an executable bit reach review, and merge on it: the
[HIGH path floor](#merge-authority) holds for a human merge only the takeover set: the
trusted-actor list, the trusted-trigger check, `CODEOWNERS`, `.gitmodules`, and `resolve-config`,
whose code the token broker runs from main. The `ci-context`, `default`, `issue` and `merge-base` rows cap a patch at 300 paths, and the
`merge-base` row a merge commit at 300 new blobs.
`checkPatchRules` in
[`patch-rules.mjs`](../../../.github/actions/resolve-config/patch-rules.mjs) rejects a row without that
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
write lane's mint for a workflow file the PR itself changes), `rung-up` (a fix-ci run's patch is
held back for one retry one model rung up, [Lanes](#lanes)), `no-model-turn` (an address-feedback
round whose model never ran, so the scan uploaded no replies), `clean-merge` (a resolve-conflicts
round whose base merge left no conflict, so no model ran and the push job commits the merge), or, for an issue run under
`models.issue-dimensions`, `research-first` or `probe-first` (its Uncertainty), or
`split-required` (its Size is `split`). Issue mode posts no check, so work-resolve-issue.yml reports those three dimension skips
on the issue instead: `needs-human`, no `agent-ready`, and a comment naming the next step
([Issue mode](pr-run-activity.md#issue-mode)). Silence is not a skip, with three exceptions that
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
- No rung reaches C4 or C5: `merge.rung` stops at `C3`, and C5 always needs a human. The pr-merge
  lane reads no class and merges on the verifier verdict instead ([The pr-merge lane](#the-pr-merge-lane)).
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
that fails counts as a refusal. The `merge:` block and `babysit_loop_merge` are also read at the
default branch head, and each setting takes the stricter of the two values: the lower rung, any
true switch, the union of path lists (each side's `check-inputs` read in a diff of its own), the
smaller cap, the stricter Dependabot mode. Two settings are exceptions: `risk-escalation-minutes`
keeps the base's value, and `max-in-flight` is read at the default branch head alone, so a raised
cap applies at once. So a tightening on the default branch reaches pull requests opened before it,
a loosening waits until a pull request's base includes it, and a pull request still cannot drop its
base's declaration. A different authority, or an identity set on one side only, stops the lane
and its queued entries leave; two different identities, or an unreadable head config, refuse.

- **Authority and identity.** `merge.authority` reads `local-babysit` and `merge.agent-identity`
  names the login the lane acts as. The schema rejects `local-babysit` without an identity. The
  identity must be the `[bot]` login of a GitHub App dedicated to this lane, and the schema rejects
  any other login: a machine user is a GitHub user and would pass every human test, and the shared
  `github-actions[bot]` and `dependabot[bot]` are refused in any letter case. With no `merge:` block,
  or no `authority`, the wrapper merges nothing.
- **Same repository.** The pull request's head is in this repository, never a fork.
- **Risk score.** A diff the risk scorer rates LOW merges, and so does a MEDIUM one whose every
  reason is a class, size or reported-finding reason (`class-contradicted`, `blast-radius-missing`,
  `lines-over`, `files-over`, `no-patch:*`, `findings:claude-review`,
  `findings:claude-security-review`). Every other MEDIUM reason (unbound or missing review
  evidence, an unread file listing, the rung) and every HIGH one refuse.
- **Review flags.** A review flag holds only for a cost increase (`cost-review-required`), a
  trusted-actor widening (`trust-gate:trusted-actors`) or a CRITICAL security finding
  (`security-finding`), owner decisions Q25, Q33 and Q693. Every other open finding, from
  claude-review or a lower security one, is listed in the reasons and does not hold.
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
  With a new record of either kind, the alert files one fix issue per newly failing check, at
  most 5 per run (an overflow line on the record says when more failed), first line
  `<!-- post-merge-fix check=<name> -->`, in fixed text only (the failing job's name, the SHA, the run
  link, the merge range and the record's number, never an annotation title), with no label, locks it,
  and dispatches intake triage for each; a fix issue that could not be filed, locked, reopened
  or sent is named in a comment on the record. A check
  whose fix issue was closed reopens that issue with a comment naming the new range, keeping
  `agent-ready` and sending it to intake triage no second time, so a repeat goes straight back to
  agents (a first failure still waits for the owner's ratification). That reopen starts no run, so
  work-unblock's hourly sweep removes and re-adds `agent-ready` with the lanes App token, once per
  recurrence comment, unless the issue is held or has an open lane PR or a lane run in flight; one closed
  as not planned or duplicate stays closed and mutes the check. Closing a fix issue releases
  nothing on the record.
- **Opt-in label.** `merge: agent-allowed` makes a pull request eligible; it does not make it safe,
  and the diff risk score still decides. It counts only when a human added it last and the pull
  request body was not edited afterwards.
- **HIGH path floor.** A fixed set of paths in the wrapper's code, joined with
  `merge.diff-check.denied-paths` and matched case-insensitively. It holds only the takeover set
  (owner direction 2026-10-23): `.github/standards/trusted-actors/**`,
  `.github/actions/check-trusted-trigger/**`, `CODEOWNERS`, `.gitmodules`, and
  `.github/actions/resolve-config/**`, whose code the token broker runs from main in its signer
  process. Agent permission config, package manifests and workflows merge on the review lanes. A
  diff that touches a floor path scores HIGH and is never merged unattended. A
  `plugins/<plugin>/.claude-plugin/plugin.json` or the top-level
  `.claude-plugin/marketplace.json` change scores HIGH as `manifest-review-required` when it
  installs or runs something new: a differing `hooks`, `mcpServers`, `lspServers`, `monitors` or
  `experimental.monitors` value, or a marketplace plugin added, removed, renamed or re-sourced, or
  the marketplace renamed. A removed, renamed or copied manifest, and a side that cannot be read,
  does not parse or repeats a key, holds. That reason waits for a human like any other HIGH one.
- **Trusted-actor widening.** A change that adds or widens an entry in
  `.github/standards/trusted-actors/trusted-actors.json` scores HIGH as
  `trust-gate:trusted-actors` in both lanes and waits for the owner, whatever `high-path-floor`
  says and whatever an adopted author's own paths leave off the floor. The gate compares the
  base and head entries: a change that only removes entries merges; an added or changed entry,
  any other key changed, a side that cannot be read or parsed or repeats a key, and an added,
  removed, renamed or copied list hold. An owner cost decision does not clear it.
- **Security findings.** The security lane flags; only a CRITICAL finding, its top tier, holds the
  merge, as `security-finding`. Its inline comments and summary carry the severity lines
  `/review:security-review` defines, and a finding whose severity the gate cannot read counts as
  CRITICAL. Its other open findings are reported as `findings:claude-security-review`.
- **Cost hold.** A change that could add or raise a charge needs the owner (owner rule,
  2026-10-22). It scores HIGH as `cost-review-required` in both lanes, whatever `high-path-floor`
  says and whatever an adopted author's own paths leave off the floor, and waits for a human like
  any other HIGH reason. It catches:
  - any changed `Pulumi.yaml`, `Pulumi.*.yaml`, `*.tf`, `*.tfvars`, `*.bicep` or `*.bicepparam`
    file, `plugins/multi-agent/reference/defaults.yaml` (the model and effort per role), and any
    file under a directory that holds a `Pulumi.yaml` at the base. A base tree the gate cannot
    list whole holds every file;
  - a file renamed or copied into `.github/workflows/` or a `pr-pipeline.yaml` path from outside;
  - a workflow patch that adds a `cron:` key in any YAML or JSON spelling (a schedule can spend
    model credits) or a `--model` or `--max-turns` flag; or that gains any `secrets` reference
    (`secrets.NAME`, `secrets['NAME']`, `toJSON(secrets)`, `secrets: inherit`), a `uses:` of
    `run-claude-cli` or any `claude-code*` action or image (matched ignoring case), or a run line
    invoking `@anthropic-ai/claude-code`, each counted against the lines it removes so a moved
    line or a repin is not new;
  - a `timeout-minutes` or `leg-timeout-minutes` the patch adds above every one it removes, in a
    workflow whose head text uses one of those actions or could not be read;
  - a runner value the workflow's head text gains over its base text, or an added inline
    `runs-on:` value: on a public repository only one that is not a free literal (GitHub's
    standard `ubuntu-*`, `windows-*` and `macos-*` labels, the self-hosted managed labels, or a
    list holding `self-hosted`), so an expression, a `group:` and a larger runner hold, since
    [GitHub bills larger runners even on public repositories](https://docs.github.com/en/billing/concepts/product-billing/github-actions);
    on any other repository every one, and any added `windows` or `macos` line;
  - any `pr-pipeline.yaml` change except one whose added and removed lines are all blank,
    comment-only, or a `description:` or `title:` value, or that only edits trailing comments
    on the same lines in place.
    Flow style, quoted keys and new list items hold;
  - a workflow or pipeline file with no patch.

  The hold clears only when the pull request body links an owner decision that covers it: a
  comment on the pull request's closing issue or on the pull request itself, in this repository,
  whose first line starts `**Decision recorded.** Cost:`, written by a User with admin permission
  who is not the agent identity or one of the gate's own logins, not posted through an App, and
  never edited; one on the closing issue must also be created after the pull request was. A link
  inside an HTML comment in the body counts for nothing. A push after the decision is an accepted
  residual: the decision is not bound to a head. The gate reads the linked comments only for a
  pull request the hold catches, and a failed read leaves the hold. A decision
  clears only this reason: a change that is also on the HIGH path floor still waits for a person
  to merge it. Cite the decision before the
  human-gated label lands; a body edit does not remove that label (only a new head or a person
  does). Not detected: budgets, billing settings and new paid services outside these files, and
  the shapes [#9241](https://github.com/melodic-software/claude-code-plugins/issues/9241) lists.
  azure-iac's Pulumi program is C#, and its deploy gate
  ([azure-iac#75](https://github.com/melodic-software/azure-iac/issues/75)) stops any Azure change
  for the owner at deploy time. The review lanes and the verifier judge the rest. Dependabot pull
  requests are not scored, so the hold does not apply to them.
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
- **Quarantined suites.** A red full run on the default branch demotes only for a newly failing
  suite (a test file) in the affected set of the merges since the branch's last green full run:
  `scripts/plan-test-lanes.sh`, the pull request runs' selector, over the paths changed since that
  run's SHA, run from a worktree of that green SHA with no token in its environment, so no merge
  judged can narrow its own set. A window that changes the selector's own files, or a plan that
  picks no suite, has no set. A suite is named from its test leg's log; a failed job whose
  suites cannot be named, a set that cannot be computed, and the merge gate's own suites
  (`GATE_SUITE_PREFIXES` in `babysit_postmerge.py`) demote as before. A suite outside the set
  demotes nothing, the window counts as verified (its `max-in-flight` slots free), and the suite
  is quarantined: an issue marked `<!-- post-merge-quarantine suite=<path> -->`, labeled
  needs-human and assigned to the suite's CODEOWNERS user when a rule names one, filed by the
  agent identity's `--remediate` or by post-merge-demotion-alert.yml. While that issue is open
  and younger than `merge.quarantine-days` (default 7, at most 30), the suite's out-of-set failures
  demote nothing; after that they demote again, even when the suite was already failing before the
  merge. A failure inside the set demotes whether or not the suite
  is quarantined, and an excused run gets no red-main report. Quarantine never changes a pull request's `ci-status` and starts no
  re-run.
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
  cleanly whatever the base registered; every other listed path counts for every pull request.
  With the registry listed, a canonical the pull request carries (its canonical or a copy touched,
  or a copy newly registered) that the base changed is refused as `shared-copy-sources-changed:`
  instead of updated: an update leaves the copies the pull request generated from its own
  canonical, so the fix is merging the base and running `scripts/sync-shared-copies.sh`. No lane
  acts on that refusal, so the wrapper escalates it: one `<!-- babysit-merge-shared-copy-escalation -->`
  comment naming the canonicals, the head and the fix, then the human-gated role label, both
  unchanged by a rerun at the same head; the `head-moved` clear removes the label once the head moves. Any
  doubt, an update the API refused with a 4xx (its status and message recorded as `updateError`),
  or a Dependabot head enqueues as before. An update with no answer (a timeout, no status, a server
  error) may have landed, so it holds the old head instead. Empty or absent updates nothing.
- **Dependabot.** A dependency-manager author is never eligible for a local unattended merge. The
  pr-merge lane owns Dependabot pull requests (below).

A human here is a GitHub user, not the agent identity and not an automation login, with write or
admin permission on the repository.

### The pr-merge lane

The same wrapper run with `--unattended --authority pr-merge` is the pr-merge lane's gate. It needs
`merge.authority: pr-merge` and `merge.agent-identity` at the base and at the default branch
head, and keeps every read above
except six:

- **Eligibility.** Not a fork or a dependency manager's pull request, opened by
  `merge.agent-identity` (the lanes App) or adopted, exactly one closing issue
  (`closingIssuesReferences`) in this repository, and a diff where no path, either side of a
  rename, matches `merge.diff-check.denied-paths`. Such a pull request is class C2, as a
  Dependabot pull request is: no `work-class:` label is read, on the issue or the pull request,
  and the diff-derived C2 checks of the risk score still apply. No opt-in label or lane claim is
  read. No closing issue, or more than one, refuses (`linked-issues:<n>`); right before the
  enqueue the closing issue is read again and a different one refuses
  (`closing-issue-changed:<was>><now>`). A pull request into any branch but the default refuses
  `base-not-default:<ref>`, read at eligibility and again before the enqueue; any read that fails
  refuses. An adopted pull request (owner decisions Q22 and 2026-10-22, [Adoption](#adoption)) is
  one a `User` or `Bot` on the trusted-actor list opened, matched by account id, never by
  login, that is not a draft, and, for a `User`, whose `updatedAt` and head commit committer date
  are both at least `adoption.idle-hours` old (absent adopts nothing; an unreadable date is not
  idle; a value that is not a whole number from 1 to 720 adopts nothing), the setting and the
  list read at the default branch head,
  and that no hold applies to: the `do-not-merge` label, the
  tracker's human-gated role label as `.work-item-tracker.json` resolves it, or a hold line in
  the body. While the lane's own merge-queue entry holds it at the current head (the lanes App
  enqueued it, its newest unedited pin comment names that head, and no other author has commented
  or submitted the newest review since that pin), a recent `updatedAt` does not refuse, since the
  pin comment and the enqueue refresh it; any other comment or review, such as a request to
  wait, refuses again, as does an unreadable one. The head commit test and every hold still
  apply. The decision records it as `eligibility.adoption` (`idle-owner:<hours>h`);
  every other gate applies unchanged. Any other author refuses `not-lane-authored`, and an owner pull
  request that is not adopted refuses `not-adopted:<reason>`. The candidate listing adds each
  trusted actor's open pull requests by its login on the list.
- **Verdict criterion.** No promotion evidence is read. The merge criterion is the pr-verify
  verdict at the head ([Verifier verdict](#verifier-verdict)), which binds to that one closing
  issue and its trusted spec, so with a rung above off the gate refuses
  `verifier-verdict-not-required` unless `merge.require-verifier-verdict` is true, and the schema
  rejects such a config. The lane starts with `merge.report-only: true`; the owner reads its
  reports and sets `false` to let it merge.
- **Risk switches.** Each check below is a `merge.diff-check` setting that is off when absent:
  `denied-paths` (an empty list denies no path; a listed path makes the pull request ineligible),
  `high-path-floor` (true scores the scorer's fixed HIGH path set and the manifest review HIGH),
  `c2-contradictions` (true
  scores a removed, renamed or copied file, a schema change or more than one plugin MED),
  `max-changed-files` and `max-changed-lines` (absent is no cap). This repository sets
  `high-path-floor: true`, so a lane pull request on the floor waits for a human; the non-author verifier
  verdict, both AI review lanes, `ci-status` and the post-merge revert breaker gate the rest. It
  leaves the rest off (owner decision,
  2026-10-17). The local babysit lane ignores these switches and keeps the fixed floor, both
  caps and the C2 contradictions. The review evidence, the security lane's CRITICAL findings, the
  cost hold and the trusted-actor widening hold still count.

  What is left with every switch off: a lane pull request may change the merge gate, the
  workflows and their tokens, these lane rules, skills, hooks, agent instructions and CI checks,
  at any size; a trusted-actor widening still waits for the owner.
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

Before it enqueues, the lane reads every person's comments on the pull request: issue comments,
review summaries and inline review comments. When the newest one from an OWNER, MEMBER or
COLLABORATOR says "do not merge" (`HUMAN_MERGE_VETO_RE`), the pull request is held (`human merge
veto from <logins>`). That person lifts the hold with any later comment that does not say it, such
as "go ahead", or by editing the veto away. Another person's comment does not lift it, and neither
does an item with no text, such as an Approve with no comment or the empty summary of an inline-only
review. Comments from a bot or from `merge.agent-identity` hold nothing and neither do comments from
anyone else, so an outside commenter cannot hold a lane pull request. A bare "wait" is not a veto,
and neither are blocking words such as "regression" (the autopilot tier's wider scan).

An eligible pull request its score holds gets one `<!-- babysit-merge-risk -->` reasons comment
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
alone, reports no finding. A finding any review of a head reported, whole or incremental, clears
only by a new head (a fix) or a human resolution (owner decision, #8554): a later clean review of
the same head never clears it. So for each head on the covering chain the gate counts the most
summary findings, and the most inline findings left without a thread, that any review of that head
reported, closes a resolved thread only when no completed review of such a head reported a finding,
and re-running a review until it comes back clean closes nothing. An incremental review reads only what changed since the last review, so it never closes an
unchanged thread: a lane that resolved an unfixed finding and pushed an unrelated commit leaves it
open. A resolved thread also closes when a human resolved it, or when it is
outdated with none of its flagged lines left at the head; an unresolved thread stays open.

Whole-review request (`babysit_whole_review.py`): when a lane pull request passes every other gate
and its only risk reasons are open findings a clean whole review of the head would close (no review
of that head reported a finding or was whole, and no lane thread is unresolved), the gate writes a
`Whole review requested at head` line into its reasons comment, then converts the pull request to a
draft and marks it ready with the lane token, so `ready_for_review` runs both review lanes whole.
That event also re-runs `pr-require-checks.yml`, `pr-test-windows.yml` and pr-merge itself. The
line, stamped with the time it was written, is kept on every rewrite, so a head is toggled once. A pull
request is toggled at most twice, counted from those lines and from the lane token's conversions to draft on
its timeline, which the lane token cannot delete as it can edit the comment; past that, or with the timeline
unread, it waits for a person. A run toggles at most one
pull request, and only while fewer than 35 jobs are running or queued and the lane token and the job token
each have 30% of every rate-limit bucket's hourly limit left; an escalated comment is not toggled. Each toggle logs
`::notice::pr-merge whole-review-toggle pr=<n> head=<sha>`. A draft a run left between the two
writes is marked ready by the next run, only when the lane token made its newest conversion to draft within ten minutes after a record's time;
a draft a person made stays one.

While `merge.report-only` is true and `merge.dependabot.mode` is not `enforce`, the workflow starts
no full CI run either; its summary says whether it would have.

The workflow's gate loop starts no further candidate once it has run `merge.gate-budget-minutes`
(absent: no budget); the candidate in progress finishes first, so the budget never stops a gate
between its check and its enqueue. One candidate's gate reads for at most
`merge.gate-candidate-minutes` (absent: no limit): past it the gate starts no further read and the
candidate is reported `unknown:candidate-deadline`, never ready, while a write already started
finishes; the loop goes on to the next candidate. The first candidate a run stops so is recorded in
the cursor as deferred, and the next run gates it first under the longer
`merge.gate-deferred-minutes` (absent: no limit), so a pull request whose gate always runs past the
limit still gets a longer gate. One stopped at that ceiling too gets a warning annotation naming it
and goes back to the capped rotation, never deferred again. Each run starts after the last candidate the previous loop
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
the `verify:` refusals `fail`, `earlier-fail`, `repeated-fail`, `missing`, `too-old`,
`spec-changed` and `untrusted-spec` are skipped. A refusal whose gate process failed a write or has a review re-run due
is not. Neither is a pull request in the merge queue, nor `verify:missing` or `verify:earlier-fail`
while a PASS artifact names the head. `merge.skip-unchanged` bounds each skip: `max-minutes` (default 60) after the
refusal was judged, or `max-skips` (default 3) runs in a row, the candidate is gated again. `0` in
either turns skipping off. When every candidate would be skipped, the first is gated, and any read
that fails or comes back incomplete gates the candidate (`babysit_merge_skip.py`). The refusals live
in the same `actions/cache` entry as the carried verdict reads, so a forged entry can only repeat a
refusal, for at most `max-minutes` from the judgment time it names. A change the key does not cover,
such as a demotion record, a ruleset, an edit to a comment older than the newest 50 or a gate import
outside the keyed paths, delays re-gating by at most those limits; a skip never merges, enqueues or
drops an escalation.

#### Native auto-merge

The lane's `enable-auto-merge` activity, the `enable-auto-merge` job of `pr-merge.yml` with its
own lanes App token (`.github/scripts/pr-merge/enable-auto-merge.mjs`, no model), turns on GitHub's
native auto-merge (`enablePullRequestAutoMerge`, squash, `expectedHeadOid` the head it read) for
each open lanes App pull request into main from a branch of this repository that is not a draft,
opens with `Closes #<issue>`, and carries no hold: no `Hold:` line or "do not merge" in its body
(the gate's own rule), no `do-not-merge` or human-gated label, and no member (owner, member or
collaborator) whose newest comment, review or inline comment with text says "do not merge" (the
gate's veto rule; a later comment lifts it), and whose head changes no path in the lane's
`merge.diff-check.denied-paths`, read on the files the head changes at each run. It turns auto-merge off on an armed one that now fails
any of those, and does not turn it back on once a person has turned it off. GitHub then merges the pull request through the merge queue
once `ci-status` passes. The issue lane finishing (`workflow_run`) wakes it, so a pull request is
armed right after report-outcome opens it; a listed human's edit, unlabel or ready wakes it too, so
adding a `Hold:` line disarms at once; and the 15-minute schedule arms or disarms what the events
missed. The token broker mints `merge` only for `pr-merge.yml`, and outside the schedule only for a
listed human's run, so an issue run the lanes App started is armed by the next scheduled run. While
`merge.report-only` is true it reports each decision and writes nothing.

`ci-status` enforces the same holds on every lanes App pull request, the two text holds and the
hold paths, so one added after arming stops the merge without waiting for this job: its step
`Fail a lanes App pull request its body or a member holds` runs
`.github/scripts/pr-merge/merge-holds.mjs` as main has it, the module `enable-auto-merge.mjs` arms
by, over the live body, discussion and changed files (renamed-from paths included) against main's
`merge.diff-check.denied-paths` plus the paths resolve-config always adds and the rest of the merge
gate's HIGH floor (`CODEOWNERS`, `.gitmodules`, every plugin manifest), on each pull request
event and in the merge queue, where a red group removes the pull request. A push that adds a hold
path fails `ci-status` on its own head. A person on the trusted-actor list (as main has it) lifts a
hold path by approving that head: their newest review of it that approves, requests changes or was
dismissed must approve. Then re-run `ci-status`, since a review does not. The approval lifts no
body hold or veto, and arming still skips the pull request, so that person merges it. The module is read at the pull request's base commit, so a lanes App pull
request whose base predates the module fails `ci-status` closed until it is updated with main.
Its own changes are held: `merge-holds.mjs` and this workflow sit under `.github/**`, a path
resolve-config always denies, so a lanes App pull request cannot weaken the rule and merge itself. A body edit re-runs
`ci-status` at once. A comment does not, so a veto posted while armed takes effect when the queue
builds the group, and after a person lifts one with a later comment, `ci-status` needs a re-run.

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
  names the current head with `verdict=merge`. A marker from any other author is ignored. The
  review's verdict job posts no merge marker on a pull request that changes a workflow or action
  file (`dependency-workflow-held`), so a person merges those. A `fix` verdict lands only when
  its commits change nothing but npm or pip manifest and lock files outside `.github/`, in a
  directory `.github/dependabot.yml` lists for that ecosystem, each modified in place as a regular
  `100644` file and changed only by a version (the **fix rule**: in `package.json` only an
  existing dependency entry's plain, bounded semver range (no `*` or lower bound alone); in a
  lock the same package keys as the Dependabot commit's lock, each entry's `resolved` exactly
  `https://registry.npmjs.org/<name>/-/<unscoped name>-<version>.tgz` for its own name (or
  alias `name`, which must be the Dependabot commit's) and version with a `sha512-` integrity, and no install-script change; in
  requirements only added `name==version` pins of projects the fix also unpins, and
  `--hash=sha256:` continuations); anything else keeps the fix off the
  branch and hands the pull request to a person. The verdict job posts no merge marker unless
  every commit is Dependabot's own, the version-bump commit, or a commit that passes the fix rule
  (`dependency-fix-refused`) ([pr-run-activity, "review-dependency"](pr-run-activity.md)).
- **Commits.** Every commit is a GitHub-verified Dependabot commit, or the repository's
  `[dependabot skip]` version-bump commit (authored by `github-actions[bot]`, verified, touching
  only a plugin's `plugin.json` or `CHANGELOG.md`, each modified in place as a regular file, the
  `plugin.json` changing only its `version`; else `dependabot-bump-content:<why>`). On a reviewed pull request the lanes App's
  verified `[dependabot skip]` fix commits count too, each only after it passes the fix rule. The commits listing must hold the pull
  request's whole commit count, else the reason is `commits-listed:<listed>-of:<total>` (the
  listing stops at 250). A lanes App commit must pass the fix rule against its one parent, read
  from the commit's files, tree modes and both sides' text, else the reason is
  `dependabot-fix-content:<why>`. A commit's author is text whoever creates it
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
    commit touched counts as checked; a fix commit may touch only npm or pip manifest and lock files
    outside `.github/` in a listed directory (the pr-unblock lane enforces this before the fix
    lands), and one whose file
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
review-dependency select job writes a `::warning::classifier gap` naming those reasons, so a
parse bug shows in the run log instead of quietly spending AI reviews; fix the classifier.

### Verifier verdict

`.github/workflows/pr-verify.yml` runs on main after each successful `pr-require-checks` run of a
same-repository, non-draft pull request into main. It never runs the pull request's code: a model
(the `verify-pr` route of [Models](#models)) reads the diff, the trusted pull request text and its linked issues as
data, and judges whether the diff delivers the issue's intent correctly and safely. The model runs
on ci-workflows' `run-claude-cli` as the `automations` role ([Funding](#funding)), with the Read
tool alone, allowed only on the data files in the working directory's `pr-verify-data`. The run
uploads one artifact, `pr-verify-<pr>-<head-sha>-<pass|pass-notes|fail>`, holding the verdict JSON. Every
reader also accepts that name followed by `-<ref-digest>`, the first 16 hex digits of the SHA-256
of the `head_ref` the JSON records (`HEAD_REF_DIGEST_HEX` in `write-verdict.mjs`), which the
writer moves to once the readers have run on main. The JSON holds `pr`, `head_sha`, `base_sha`, `head_ref`, `linked_issues` with each issue's author login, id and
account type, `verdict`, `summary`, `notes` and `run_id`. The head SHA is the one `pr-require-checks`
ran on, never the pull request's live head. A model error, an output that fails the schema, a
summary or note matching a shared credential pattern (`findSecret` in `lib/publish-gate.mjs`), or a run with any permission denial
uploads nothing, and the run fails. A head that already has a counted verdict from a completed run (a `fail` under any
pull request number) is not judged again. Runs share one concurrency group per pull request and
head and never cancel a running judgment.

`merge.verify-authors` decides whose pull requests are judged. Under `lane`, the default, only one
the lanes App opened is: a `Bot` account whose login is `merge.agent-identity`, compared as the
pr-merge lane decides lane authorship. Any other author's is skipped before the model runs, with
the reason `author-not-lane` and the step summary line `skipped: author not the lanes App`, since
only lane-authored pull requests reach the pr-merge lane. `lane-or-owner` also judges every
trusted actor's: a `User` or `Bot` whose account id is on the trusted-actor list (never matched
by login), whose pull requests the pr-merge lane adopts (Eligibility, above); any other author's
is skipped with `author-not-lane-or-owner`. pr-verify runs when `pr-require-checks` passes, so it
judges a person's pull request at each ready head, before it is idle. A pull request closing no
issue is judged against its own title and body only as [Adoption](#adoption) says. Work the spec
does not ask for passes with a note (`pass-notes`) unless it is also a correctness or safety
problem, changes what the code is for, or touches a hold the owner keeps; then it fails the
verdict. `any` judges every author's. Any other
value judges none (`verify-authors-invalid`). The trusted-spec rule below does not depend on who
opened the pull request: a spec written by a trusted human counts, so an adopted owner pull
request whose closing issue the owner wrote is judged against that issue as its spec. A spec the
lanes App or any other Bot or App wrote, or one an untrusted account wrote or last edited, still
reads `verify:untrusted-spec`, so a lane pull request never supplies its own spec.

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
- counted `fail` verdicts at `merge.max-verify-fails` (default 3) or more distinct heads of the pull
  request, tied as in the item after next, refuse (`verify:repeated-fail`) whatever a later pass
  says, a `fail` at the head included. A value that is not a count of 1 or more, an empty or
  non-scalar one included, is 1, so any earlier `fail` holds. Before a `fail` at the head or a
  pass decides, the counted `fail` verdicts of every other pull
  request in this repository, open or closed, that closes one of its closing issues count too, at
  their own heads, so a new pull request for the same issue does not reset the count; such a
  `fail` whose run cannot be read refuses `verify:unreadable`, and a cut list of those pull
  requests refuses the same way. This cap is what bounds pushing until the verifier passes once:
  the carry-forward below stops only a head that changes nothing of its own, and a one-line edit
  gives a new change. A pull request that names the issue without closing it, or whose closing
  reference was removed, is not counted. Closing a newly filed duplicate issue instead starts the
  count of other pull requests again; a pass then needs that issue written by a trusted human,
  as below. More than 50 pull requests that claim to close one issue make
  every pull request for that issue refuse `verify:unreadable`: a hold, not a way past the cap;
- a counted `fail` at the head, under any pull request number, refuses (`verify:fail`);
- a counted `fail` at another head of the pull request (its number, one of its commits, or a
  verdict recording its head branch, read from the name's digest, or for a name without one from
  the head-ref map below, else the verdict JSON) refuses (`verify:earlier-fail`). The name is trusted only from a run of
  verifier origin, as the JSON is, and equal branches always give equal digests, so a collision
  can only tie a `fail`, never untie one. A digest-named `fail` is decided by its name even when
  its JSON cannot be read, where a name without the digest refuses `verify:unreadable` then. Counted `pass` or
  `pass-notes` verdicts at the head whose runs were all created after every such `fail`'s run
  clear it, each `created_at` read fresh from GitHub (a missing one keeps the refusal; a
  re-attempt keeps its run's `created_at` and moves `run_started_at` later, so a re-run of an
  earlier pass never clears a later `fail`), when the pull request's own change at the head
  differs from its change at every `fail`ed head, and those passes decide as below. A change is
  a sha256 digest of the changed lines in the compare diff from its merge base with the branch:
  per file its path, a rename's old and new paths, mode lines, the binary-change line and the `-`
  and `+` lines with whitespace removed and the marker kept (blank ones and trailing carriage
  returns dropped), lines and files sorted. A head that only adds blank lines holds. Context lines,
  line numbers and hunk order do not count, so a head that only merges the branch, even one that
  edits a line next to the fix, or adds an empty commit keeps the refusal, as does a diff that
  holds no change or a compare GitHub answers with 404 (a head garbage-collected or force-pushed
  away). Removing whitespace also keeps the refusal for a change that only re-indents, which can
  matter in Python: it holds more than it must, never less. A pass judged before a later `fail`
  never clears it. Any other failed read of a run time or a diff refuses as the next item does;
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
  edited if ever, by a `User` on the trusted-actor list's humans, the pull request's author
  included) are the ones it recorded by id and update time, none added, edited or deleted; a partial
  comment read refuses `verify:unreadable`. It then allows the merge only when every linked
  issue it records was written, and its body last edited if ever, by a `User` on the trusted-actor
  list's humans, the pull request's author included (otherwise `verify:untrusted-spec`); a Bot or
  App, the lanes App among them, never counts. The model's spec text holds only what such
  accounts wrote;
- no counted verdict refuses (`verify:missing`).

The trusted-spec rule trusts an account, not a person. An agent session that uses an owner's `gh`
login posts as that owner, so until agent sessions have their own GitHub identity, an issue or an
`agent-ready` label from a trusted account counts as the owner's authority, including when an agent
acting as that account wrote it. Since the pull request's author counts (owner decision,
2026-10-22), that includes a session that opens both the issue and the pull request as the owner:
once the pull request is idle for `adoption.idle-hours`, the lane can merge it against that spec. The
owner accepts that risk: unattended merge is on (`merge.report-only: false`) before that identity
exists (#7711).

`verify:fail` and `verify:earlier-fail` only wait: the fail's notes go to an `address-feedback`
round (`pr-feedback-dispatch.yml`, above), whose push the verifier judges again.
`verify:too-old`, `verify:repeated-fail`, `verify:spec-changed` and `verify:untrusted-spec` need a
human. While `merge.report-only` is false the lane escalates such a
refusal on the pull request ([loop-lane §2](../loop-lane/README.md#2-escalation-contract)): it
keeps one `<!-- babysit-merge-verify-escalation -->` comment naming the refusal and the head, and
for `verify:repeated-fail` with a `fail` at the head quoting as data the first 1500 characters of
the `summary` in the newest head `fail` verdict when its record can be read and names this pull
request. The comment is rewritten only when any of these changes. A `verify:repeated-fail` with no
summary to quote keeps the summary the lane's last such comment quoted, under the head it was given
at, so a failed read rewrites nothing and the reason outlives a push. Then the lane adds the tracker's human-gated role label (`needs-human` unless
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
records, the download of a verdict.json (by the listed artifact's id, one request where `gh run
download` lists the run's artifacts first) and the compare of a run's head to main (a `contents: read` call). The gate's
review-evidence reads use it too: the timeline, the comments, and the lane runs with their attempts,
jobs and annotations. Two things send them back to the lane token, as before; both tokens read
the same data, so neither changes a gate decision. First, `GITHUB_TOKEN` must have at least
`merge.read-token-floor` of its core limit left by `GET /rate_limit` (default 0.3, read at the
default branch head; an unreadable limit counts as short). That is only an early switch: in the
05:26Z outage on 2026-10-23, `/rate_limit` showed 3,934 of 5,000 left while `GITHUB_TOKEN` was
already refused with "API rate limit exceeded for installation". Second, when any of those reads
is refused with a 429, or a 403 whose message names a rate limit, the gate reads all of that
candidate's evidence again with the lane token (they are all GETs). It records the refusal in
`BABYSIT_RUN_CACHE`, so later candidates in the run skip `GITHUB_TOKEN`. Any other refusal is not
retried. The verdict downloads, the listing, the run records and the compares
stay on `GITHUB_TOKEN`: the lane token holds no Actions permission. An untied FAIL whose record
cannot be read refuses the run's later candidates through `BABYSIT_RUN_CACHE` without another
download; the next run reads it again. `GITHUB_TOKEN`'s pool is shared with the full-run dispatch and the post-merge checks. Every other call, every write
included, keeps the lane token. That job checks out only main and runs no pull request code.

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
read by each gate process, because a re-run can undo a completed success. An untied FAIL whose
name carries no head-ref digest has its recorded head ref shared for the run under the artifact's id, since the contents an id names
never change (an overwrite uploads a new id). Those head refs, by artifact id, also carry to the
next run as the `pr-merge-head-refs` artifact (`.github/scripts/pr-merge/head-ref-map.mjs`): each
scheduled or hand-started run uploads the map it read plus its own downloads, kept while the
artifact listing still lists the id, and the next run reads it from the newest such run, found the
way the gate cursor is. Only a run's own steps can upload its artifacts, so the map was written by
the default branch's `pr-merge.yml`; it never passes through `actions/cache`. An id the map holds
ties or unties its FAIL as its downloaded record would, with no download; any other id is
downloaded, and a missing, expired or malformed map leaves every one to download. The map holds
no verdict. On the `--unattended` path only, the default branch
and the base's rules are reused for two minutes, and a failed read is never shared; before an
enqueue, a default branch or rules a gate took from the file are read again for the branch read,
and any change holds. An attended gate run reads both fresh. Without the variable nothing is shared.

## Review-lane holds

Both review callers (`pr-review-hosted.yml`, `pr-review-security-hosted.yml`) pass
`hold-label: needs-human` and the same `hold-paths` to ci-workflows' `pr-review-cli.yml`. Their
status job adds the label and a `<!-- claude-lane-hold lane=<lane> sha=<head> criteria=<list> -->`
comment when the review returns a hold, or when a changed file (or a renamed file's old path)
matches a hold path, which holds as `trust-gate` whatever the review says:

- `.github/standards/trusted-actors/**`
- `.github/actions/check-trusted-trigger/**`
- `**/CODEOWNERS`
- `**/.gitmodules`

No ruleset requires a review check (github-iac ADR 0017); ci-status, the one required check, enforces
them on every `pull_request` run, contract-only runs included:

- **The label holds.** ci-status fails while the PR carries the human-gated label (`needs-human`
  unless the base's `.work-item-tracker.json` names another). Removing it approves.
- **Only a trusted person lifts a review-lane hold.** A hold is the newest hold comment or the
  newest `labeled` event of the label by `github-actions[bot]` or `claude[bot]`, whichever is later,
  so deleting the comment does not lift it. The first removal of the label after it must be by a `human` of the base's
  trusted-actor list; a later removal is of a later label, such as an escalation
  `clear-escalations` lifts. A bot's or anyone else's lift, or none recorded, fails. To recover, a
  trusted person adds the label back, which starts a new hold, and a trusted person removes it.
- **Both lanes review the head.** On a ready PR, the newest `pull_request` run of each caller on the
  head must have a successful status job (`pr-review / claude-review-status`,
  `pr-review-security / security-review`) whose `Apply the hold` step ran. A summary-mode run or
  one with no hold label does not count. A pending, failed, cancelled or skipped review fails with
  the cause named. A lane the kill switch stopped passes (no merge freeze), but a kill-switch job
  that failed does not. A review skips a fork and a bot outside the caller's
  `allowed-bot-sender-ids`, so their PRs stay red until a person on the trusted-actor list pushes a
  commit to the head. Dependabot, the release App and the standards-sync App are exempt by numeric
  author id, except that their PR fails when a changed file (or a renamed file's old path) matches
  a hold path, since no lane reviews it to hold it; a person merges it. A draft is exempt.

A review usually finishes after ci-status has read it, so `pr-feedback-dispatch.yml`'s
`rerun-ci-status` job re-runs the ci-status job of the newest `pr-require-checks` run on the head
whenever either review caller completes (not when GitHub skipped it) on an open same-repository PR
still at that head. A ci-status not started yet is left to read the reviews itself; one in progress
is polled every 60 seconds for at most 10 minutes first. The merge-group run re-checks the labels.
`fix-ci` keys on `ci-lanes`, so a hold or a pending review never summons it.

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
- a skill's `Bash` grant can be wider than its job: a skill that allows `Bash(git:*)` with no
  subcommand bound (`ai-slop:audit` does; `fix-docs` now runs it on the read runner, with no write
  token), in a write lane, where claude-code-action puts the token in the origin URL. A run,
  including one steered by untrusted text it reads, can then push to any branch
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
passing verdict like any other (see the switches above), unless it widens the trusted-actor
list ([Trusted-actor widening](#the-local-babysit-lane)).

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
  never count. It lists the window workflow by workflow: one `per_page=1` call reads each workflow's
  run count, and a range at the listing's 1,000-run cap is halved until each part fits, so every run
  of the 24 hours is read. It stops at 350 REST calls, keeping 170 of them for the units, and says
  so: a workflow it read only part of is named in a warning, and its unit carries `window_complete:
  false`.
- **judge**, one model leg per unit, holds read permissions only, runs with `--setting-sources
  user` and `--permission-mode dontAsk`, and has Read, Grep and Glob over its data and the main
  checkout and no shell. It takes the `triage-issue` route's profile. CI logs and titles reach it
  as data. It returns at most three findings, each citing at least one `path`, `line` and exact
  `quote` from main.
- **file**, a script with no model and `issues: write`, drops a finding when any quote is not on its
  line in the run's main commit, then de-duplicates it by fingerprint: a hash of the slice, workflow,
  job and the error signature with numbers, SHAs and times removed, kept as the last line of the
  issue body. An open match gets a "seen again" comment; a match closed as not planned or duplicate
  is skipped; any other closed match, whatever its age, is reopened with a comment carrying the
  checked claims. A finding whose
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
priority or work-class label. The `needs-triage` floor label is not a triage label: it lands on open
whether or not intake runs, so an issue whose intake run failed is still selected; one the sweep
already filed a hand-off issue for, found by one search of those issues, is skipped unread. Issues from
`github-actions[bot]`, the lane sweep's own included, are left out. For each it re-dispatches `intake-triage.yml`, at most 5 a pass, and records the runs in
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
| 9 lane stop | a comment by `merge.agent-identity` created in the window starts with a `<!-- work-resolve-issue outcome=funding\|limited\|turn-cap ... -->` marker, one issue per outcome listing each stopped issue | `lane-stop:funding`, `lane-stop:limited`, `lane-stop:turn-cap` |

An issue's first body line is `<!-- factory-monitor key=<key> fp=<fingerprint> -->`; the body names
the signal, the owning area and the key, and carries the evidence inside a text fence as inert lines.
The fingerprint changes only when the evidence does: the failure text, the run, PR or stop-comment set, the newest
failed merge group, the incident status, the last merge, or the day for a ceiling. The newest issue for a key
decides: open with the same fingerprint, nothing is written; open with a new one, a comment carries
the evidence and the marker records it; closed as not planned or duplicate, the key is muted; closed
otherwise, the issue is reopened with a comment carrying the evidence only on new evidence, or for
`main-red` on a failed run that started after the close. Issues of every age are read, page by page until a short page, so a quiet key stays open or muted; a run that spends its call budget there stops before writing. It files at most 8 issues a run,
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
- `escalate-to` (optional): the profile one model rung up. A run resolved at `model-rung` 1
  (resolve-config's `model-rung` input) takes it in place of this one; at most one rung, so the
  target's own `escalate-to` is never followed, and a profile with none refuses `model-rung` 1
  (`no-rung-up`). Only the selected slot climbs, and only fix-ci's retry passes `model-rung` 1.

A role profile names a multi-agent role in place of `model`, and never both: `role`, `workload`
and `effort-role`, plus `max-turns`. It has no `model` or `effort` key, so it can name neither
`default` nor a model ID. `resolve-config` reads its model and effort from the role map,
`plugins/multi-agent/reference/defaults.yaml` in the base checkout. The model is `opus` when the
role map gives `inherit`, no alias, or an alias other than `haiku`, `sonnet` or `opus`, and when
the role map is absent or unreadable, so a route never resolves to an empty model, `default`, a
model ID or the frontier tier. `resolve-config` also writes an `applied-by-patch` output, set
only when the selected activity sets `applied-by.patch`.

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

This repository's profiles, and the route each run takes, are set in
[`pr-pipeline.yaml`](../pr-pipeline.yaml) (`models.profiles` and `models.routes`).

`models.issue-dimensions` budgets a skill activity with input `issue` from its issue's Size,
Complexity and Uncertainty org issue fields. `fields` maps each field id and its single-select
option ids to the keys of `sizes`, `complexity` and `uncertainty`; ids, not names, so a renamed
option keeps its meaning. A field with no value, or whose latest setter (from the GraphQL field
events) is neither a listed human on the trusted-actor list nor the lanes App, reads as Size
`small`, Complexity `medium` or Uncertainty `known`, so the run goes ahead; the config must define
those keys, and `small` must run. An option no entry maps fails the resolve with
`unmapped-dimension`. Before any model turn the activity skips with its Uncertainty's
mode when that is not `run` (`research-first` or `probe-first`), then with `split-required` when
its Size is `split`. Otherwise its `max-turns` is the size's `base-turns` times the complexity
factor, rounded up, replacing the profile's, and the size's `timeout-minutes` is the run job's
timeout; a skip takes the shortest size timeout. resolve-config outputs `issue-dimensions`
(`<size>/<complexity>/<uncertainty>`) and `timeout-minutes`;
work-resolve-issue.yml resolves them before its run job starts, since a job's timeout is fixed
then, and passes the dimensions on (`issue-dimensions`), so a field set while the run waits for
its slot cannot give it more turns than its timeout allows; without `issue-dimensions` the
timeout is 25 minutes. This repository's budgets are owner-approved starting values, tuned in
[`pr-pipeline.yaml`](../pr-pipeline.yaml) (`models.issue-dimensions`) from per-run measures. Large
is `split`, and Uncertainty Known and Knowable map to `run` and Unknown to `probe-first`. `complexity-profiles` (optional) maps a complexity to the profile the run starts on,
in place of its route's; the dimensions' turn cap still replaces that profile's `max-turns`. A
complexity with no entry keeps the route's profile. The config
reader rejects a key that is not a complexity and a value that is not a profile.

Lanes choose the model by difficulty along one ladder: Sonnet for mechanical work (the review,
triage and summary profiles), Opus at effort high for code (`code-fix`), Opus at effort xhigh
(`code-xhigh`) for a high-Complexity issue and fix-ci's one retry, and Fable above it. The Fable
rung is off: no profile names `fable` or `best`, so no route, rung or Complexity reaches it; it
waits on an owner decision and a per-week Fable allowance for the lanes.

## Funding

Each Claude lane's runs are paid by one funding role. There are six: `reviews` for both review
lanes, `issue-lane`, `intake`, `pr-unblock`, `pr-verify`, and `automations` for the lanes outside
the pipeline. A role's secrets are `<ROLE>_CLAUDE_API_KEY` and
`<ROLE>_CLAUDE_CODE_OAUTH_TOKEN`, the role upper-snake, so `issue-lane` gives `ISSUE_LANE_`.

[`.github/lane-funding.json`](../../../.github/lane-funding.json) is the source of truth: each
role's secrets, whether it is keyed, and each lane's workflow, job, launcher, triggers, gate, and
the secrets its job reads today, which can still be another role's or the bare
`CLAUDE_CODE_OAUTH_TOKEN` until its wiring moves. `callers.test.mjs` in
`.github/actions/resolve-config/` fails when a job that reads a Claude secret is missing from the
catalog, or reads secrets other than those listed, and when a job that holds one under
`pull_request_target`, `issues` or `workflow_run` shows no author gate (check-trusted-trigger in a
job it needs, or the intake reusable's `allowed-author-ids`) or same-repo gate.

Only a lane on ci-workflows' `run-claude-cli` action gets an API key, so only a role with such a
lane is keyed; claude-code-action runs take the OAuth token alone, since they are not paid from
API credits. On `run-claude-cli` the key runs first and the subscription token only after the key
leg hands off (`run-claude-cli`'s `handoff` output: a credit stop, or class `auth` with API status
401 or 402; a 403 hands nothing off). `pr-verify` holds one credential per job: `check-intent`
runs on the key, and `check-intent-subscription` runs on the token, on a new runner, only after
`check-intent`'s handoff with no permission denial or when the key is empty; its lane record is
`pr-verify` with `fallback-reason` `credit-stop`, `auth` or `no-key`. Each lane's workflow names
its role as a literal, and the runner policy admits it. A lane on pr-run-activity-write.yml passes
its role as the `role` input, and the lane record names that role's token as the run's credential.

## Loop caps

One counter per PR, in the findings store, is shared by every lane. After `loop.review-rounds`
full review rounds, one more high-severity-only pass runs; if it still has findings, the PR
escalates. The address-feedback activity hands a PR to a person once `loop.review-rounds` of its
rounds have run, unless a write-access trusted person asked for a fix on a thread after the
newest round: that runs one more round, on the requested threads only. The default is 2; this
repository's value is in `docs/conventions/pr-pipeline.yaml` `loop`. Separately, after `loop.no-progress` lane runs in a row that change nothing, the PR
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
| `fix-docs-per-run` | 2 | fix-docs dispatches one pr-unblock-dispatch run sends; at most 20. |
| `admission-factor` | 0.8 | Share of the lane's hourly merge rate admitted per hour for the queued cap ([WIP cap](#wip-cap)); greater than 0, at most 1. |
| `admission-min-per-hour` | 1 | Admissions per hour the queued cap never falls below, so a day with no lane merges cannot hold admissions shut; 0 to 100, and 0 removes the floor. |

report-outcome and the work-unblock sweep read them from resolve-config's output;
pr-feedback-dispatch, pr-unblock-dispatch and work-resolve-issue's WIP cap check resolve the base
config themselves. A config the resolver refuses fails the two dispatchers before any dispatch;
the WIP cap check keeps the last known pause ([WIP cap](#wip-cap)). This repository's values are in
[`pr-pipeline.yaml`](../pr-pipeline.yaml) (`limits` and `wip`).

## WIP cap

The optional `wip` block sizes the issue lane's work in progress from the lane merge rate. The WIP
cap check (`.github/actions/check-wip-cap`) runs before work-resolve-issue takes a slot, and
work-unblock runs it before a re-fire and before adding `agent-ready`. It reads, one request at a
time and none once `x-ratelimit-remaining` reaches 0, the lanes App's open pull requests, those
merged in the window, those opened in it, and the open `agent-ready` issues that carry no hold
label (`needs-human`, `needs-owner-decision`, `status: needs-decision`, `status: needs-info`).

| Key | Default | What it sets |
|---|---|---|
| `target-lead-time-hours` | 2 | Target open-to-merge hours. The WIP cap is merged lane PRs per hour times this, rounded up, at least `min-cap`. |
| `min-cap` | 1 | Floor under the computed WIP cap, so a day with few merges cannot shrink the cap until the lane stalls. This repository's value is in `docs/conventions/pr-pipeline.yaml` `wip`. |
| `merge-rate-window-hours` | 24 | Rolling window for the merged and opened counts. |
| `opened-to-merged-ratio` | 0.8 | Lane PRs opened in the window may be at most this share of those merged in it. Not `limits.admission-factor`, which sizes the queued cap. |
| `held-cap` | 60 | Held lane PRs at or above which the held buffer is over its cap; on or after `pause-from` the lane pauses there. This repository sets 10. |
| `held-alarm-hours` | 24 | Age past which a held lane PR raises the alarm. |
| `pause-from` | empty | UTC date or date-time from which runs pause over the WIP cap or the held cap, and new admissions over the queued cap; empty never pauses. This repository sets 2026-10-22. |

A held lane PR carries `needs-human` or `do-not-merge`, or has a body line exactly
`Hold: a human merges this`. Held PRs never count against the WIP cap; countable PRs are the open
lane PRs that are not held. Over the WIP cap (countable at or above it), over the held cap, over
the admission share, at or over the queued cap, or with a held PR past the alarm age, the check
writes a warning annotation. Over the WIP cap or the held cap on or after `pause-from` it pauses runs: work-resolve-issue
starts no run, work-unblock re-fires none, and the log and step summary carry one line
`admission paused: reason=<wip|held-cap|wip,held-cap> countable=<n> wip_cap=<n> held=<n> held_cap=<n>`
(a `::notice` annotation titled `admission paused`). When the open listing or the base config
cannot be read, the lane keeps the last known pause: the status work-unblock's hourly sweep last
saved to the Actions cache (key prefix `check-wip-cap-state-`) from reads that succeeded. Only a
trusted trigger such as `schedule` can save a default-branch cache, so work-resolve-issue's
pick-slot (`cache-mode: read`) only restores it. A kept pause names only `wip`, `held-cap` or
`wip,held-cap`; any other saved reason counts as no saved state. A kept pause logs
`admission paused: reason=<reason> (read-error, kept last state)`, unless a config that was read no
longer pauses (`pause-from` cleared or in the future); with no saved state (none yet,
or the cache evicted it), the check fails open and the run starts. Without a merged count the
cap is `limits.wip-cap`. A held PR's age runs from when it opened.

Queued work is the open `agent-ready` issues no open lane PR names, plus the held lane PRs. A lane
PR names its issue on its first body line (`Closes #<n>` or `Refs: #<n>`, as report-outcome writes
it), or else by its head branch `work-resolve-issue/issue-<n>-<run>-<attempt>`: the search answer
carries no head ref, so each open lane PR whose first line names no issue (a person edited it) costs
one pull request read, and one that fails leaves the PR unmatched. A dimension-skipped issue
whose report-skip failed keeps `agent-ready` with no run; work-unblock's sweep re-fires that failed
run like any other, and the fresh run's report-skip hands the issue back. The queued cap is
`max(limits.admission-factor × lane merges per hour, limits.admission-min-per-hour) ×
merge-rate-window-hours`, with the floor alone when the merged count cannot be read. At or over it,
on or after `pause-from`, new admissions pause: the step output `admission-open` is `false`, and
the log and step summary carry one line
`admission paused: reason=queued queued=<issues> held=<held PRs> cap=<cap>` (a `::notice`
annotation titled `admission paused`). Under it, `admission_room` is how many more issues may be
admitted now. The queued cap gates only new `agent-ready` labels, never a run: a queued issue
leaves the count only by running, so pausing runs on it would hold the count shut. A queued read
that fails leaves admissions open (`admission_basis: fail-open`) and changes no run pause. A
search that answers `incomplete_results: true` (a degraded search can answer a false empty) is
unknown, not failed: admissions pause whether or not `pause-from` is set or reached
(`admission_basis` and `admission_reason` `search-incomplete`), with a `check-wip-cap` warning,
and work-unblock's deferral log names that reason. The queued cap itself still pauses only on or
after `pause-from`, and no run pause changes.
The search lists at most 1,000 issues: past that, the issues it counted but did not list count as
queued, and admissions pause (`queued_truncated: true`).

work-unblock is the one lane that adds `agent-ready` to a new issue. Past the room it labels a
ready issue `admission-deferred` instead, and each hourly sweep revisits the open
`admission-deferred` issues oldest first, before the issues closed in its window. Only an issue
whose newest `admission-deferred` was added by the lanes App or a listed human (by id) is
revisited; any other is left as is with a warning annotation, since re-admitting it adds the App's
`agent-ready`. Of those, one still ready gets `agent-ready` within the room and loses
`admission-deferred`, a held one stays deferred, and any other loses it. Restarts, re-fires and relabels re-run issues already admitted and are never
paced. This queued cap replaces the admission window (`limits.admission-window-hours`) and owner
decisions Q2, Q17 and Q22 of the 2026-10-21 lane-flow interview.

work-unblock's `label-unblocked` job runs one at a time across the repository (one `concurrency:`
group, queued, never cancelled), so a burst of closes or a close run beside the hourly sweep cannot
each admit the full room. The search index can still lag an `agent-ready` label added moments
before, so a run right after another may read the room as one admission too wide.

The queued cap paces only work-unblock's new `agent-ready` labels. Every other writer is exempt by
design (owner decision 2026-10-22, #8966), and the issues it labels still count as queued work:

| Writer | Paced |
|---|---|
| work-unblock adding `agent-ready` to an unblocked or deferred issue | Yes |
| work-unblock's restarts, re-fires and relabels (remove and re-add on an admitted issue) | No: they re-run work already admitted |
| A person adding the label by hand | No |
| A person-run skill: `/work-items:triage`, `/work-items:decompose`, `/work-items:attend-queue`, `/work-items:track` | No: a person's account, their call |
| `post-merge-demotion-alert.yml` red-main fix issues | No: it files them unlabeled and reopens one on a repeat failure keeping the `agent-ready` a person gave it, which work-unblock relabels; guardrail work |

The check publishes its status as one flat JSON object: the step output `wip`, the step summary
and the log line `check-wip-cap: <json>`. `capped` is `true` only while runs pause;
`admission-open` is `false` only while new admissions pause.

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
| `queued_issues`, `queued_total` | Queued issues with no open lane PR, and those plus the held lane PRs; null when a read failed. |
| `queued_truncated` | `true` when the search counted more queued issues than it lists; admissions then pause. |
| `queued_cap`, `admission_factor`, `admission_min_per_hour` | The queued cap and its inputs. |
| `wip_over`, `held_over`, `admission_over`, `queued_over`, `held_alarm` | Which limit is crossed. |
| `alert` | Any of the five. |
| `pause_from`, `paused` | The pause date and whether the lane pauses now. |
| `pause_reason` | `wip`, `held-cap` or `wip,held-cap` while paused; null otherwise. |
| `pause_basis` | `read` from this run's reads; on a failed read `last-state` (the last known pause) or `fail-open` (none saved). |
| `admission_open`, `admission_reason`, `admission_room` | Whether new admissions are open; `queued` or `search-incomplete` while paused, null otherwise; admissions left before the cap, null when nothing gates them. |
| `admission_basis` | `read`; `fail-open` when the queued count could not be read; `search-incomplete` when a search answered `incomplete_results: true`. |

## Adoption

With an `adoption` section, the lanes take over every trusted actor's pull request (owner
decisions Q22 and 2026-10-22): one rule for the lanes App, Dependabot, the release App, the owner
and anyone later added to `.github/standards/trusted-actors/trusted-actors.json`. When it is red
or needs a fix, a lane fixes it and it merges without a person, unless the fix changes behavior or
intent, which the verifier fails and escalates. This grants the lanes unattended power over PRs a
person opened. A PR is adopted when all of these hold:

- an account on the trusted-actor list opened it, a person or an App, matched by numeric id;
- it is not a draft, it is a same-repository PR into `main`, and it carries no `do-not-merge`,
  `needs-human` or human-gated label (`config.role_labels["human-gated"]` in the base
  `.work-item-tracker.json`, as pr-merge resolves it; a tracker file that is not JSON holds every
  owner PR for the run and fails the dispatcher run, while lanes App PRs proceed under the other
  two labels);
- no body line starts with `Hold:`, read as babysit reads it: any case, after any non-newline
  whitespace (NBSP included), with a bare CR also ending a line;
- for a person's PR, its last update (`updatedAt`) and its head commit's committer date are both
  at least `idle-hours` old. Neither one alone is enough. An App's PR does not wait.

An adopted PR that closes no issue in this repository is judged against its own title and body
when a person (a `kind: human` id on the trusted list, not merely a GitHub `User`) opened it or
an App in `spec-from-body-apps` did (an App whose bodies a script writes): resolve-pr gives the verifier that text as the spec, the verdict records `intent:
pull-request`, and the pr-merge gate accepts it with no closing issue. Any other App, the lanes
App included, still needs a closing issue a trusted person wrote: a model that wrote the diff
would also have written the spec it is graded against.

The body counts only if it was never edited, or was last edited by its author or a trusted person;
the verdict records its sha256 (`intent_sha256`), and the gate refuses the pass
(`verify:spec-changed`) once the live title and body differ.

In the pr-merge lane, for an adopted PR a person or a `spec-from-body-apps` App opened, the
denied paths and the manifest review score only the PR's changed paths that a commit not its
author's own touched (a lane's fix among them): that author's own lines need no person. Any other
App's PR (claude[bot], cursor[bot], cursoragent, melodic-ai[bot]) gets that exemption only for its
own lines under `plugins/*/scripts/` (owner decision Q14 (c)); its other paths score whole, like
the lanes App's, while it stays adoptable for fix-and-merge. The HIGH path floor always scores,
whoever wrote it. Paths match
case-insensitively. The lanes App and
Dependabot are never adopted. A commit is the author's own
only when GitHub verified its signature and its author account is the PR's author, and, for a
person, its committer account too; the author account alone comes from the git author email,
which anyone can set. An App's commits go through the API and GitHub's web-flow commits them, so
an App's own commit needs the signature, its author account, and a committer that is the App or
web-flow, the weaker case. A merge
commit not the author's own scores its files that the PR also changed, so a conflict a lane
resolves inside a PR-changed file holds while main's other incoming files score nothing. The lanes
App's own PRs are never adopted and stay scored whole. A commit list or commit that cannot be read
whole scores every path. The trusted list is read at the default branch head. The capability
check, the security-review lane's findings and every other gate still apply. Dependabot keeps its own paths, `review-dependency` for a red PR and
its own tier in pr-merge ([Dependabot pull requests](#dependabot-pull-requests)), and is never
dispatched `fix-ci`.

An adopted PR whose lanes failed (`ci-lanes`) is dispatched `fix-ci` like a lanes App PR, under the same
`limits.fix-ci-per-run`, `limits.fix-ci-restarts` and `loop.fix-ci-rounds`. The run still needs
the author on the trusted-actor list, as every pr-unblock run does. A pushed fix commit updates the
PR and its head, so the next fix waits another `idle-hours`: a person's PR gets at most one fix
round per idle window. A lanes App PR waits for no idle window, and its
`Hold: a human merges this` line holds the merge, not a CI fix. With an `adoption` section the
human-gated label holds a lanes App PR from `fix-ci` too; without one the tracker file and the
trusted-actor list are not read, nothing is adopted, and only `do-not-merge` and `needs-human`
hold.

| Key | Default | Meaning |
|---|---|---|
| `idle-hours` | none | Hours both a person's PR and its head commit must be unchanged; 1 to 720. Absent: nothing is adopted. |
| `spec-from-body-apps` | `[]` | App ids whose PR bodies a script writes; such a PR closing no issue is judged against its title and body. |

## Red main

When a full `pr-require-checks` run on `main` (scheduled or dispatched) fails, the
`report-red-main` job of
[`post-merge-demotion-alert.yml`](../../../.github/workflows/post-merge-demotion-alert.yml) applies
this rule after the alert job has filed its post-merge record. It runs no model; its scripts and
tests are in
[`.github/scripts/post-merge-demotion-alert/`](../../../.github/scripts/post-merge-demotion-alert/).

The full run pr-merge starts after each merge uses `GITHUB_TOKEN`, so its completion raises no
`workflow_run` event. When that run ends red, pr-merge's `dispatch-full-run` job sends its run id to
the alert workflow through `workflow_dispatch`. The alert accepts the id only from
`github-actions[bot]` or a listed human (`trusted-actors.json` on `main`), never the lanes App,
and only for attempt 1 of a red `pr-require-checks.yml` run on this repository's `main` that
`github-actions[bot]` dispatched. Red is any conclusion `babysit_postmerge.py` counts as failed:
`failure`, `timed_out`, `cancelled`, `startup_failure` or `action_required`, so a run cancelled
on a time-budget overrun files its record and fix issues too; only a `failure` reaches this
report (rule 1). A red run gets its one re-run from pr-merge's `post-merge-dispatch` job when it
is inside a lane merge's attribution window, or was created within `confirm-wait-minutes` plus
50 minutes (90 by default) and demotes by the affected-set rule; any other red run gets none. Both jobs
wait for a re-run for up to `confirm-wait-minutes`, so the record, its fix issues and this report
follow the merge instead of the next scheduled run. A dispatched red, whether its re-run failed or
never finished within that wait, files nothing once a newer `pr-require-checks` run on this
repository's `main` has succeeded: `main` already recovered, and the alert logs so and files no
record, fix issue or report. A failed lookup files as before. The dispatch also names the run's
head SHA, which the alert checks against the run, so a dispatch and a `workflow_run` event of the
same run share one concurrency group by signal and SHA. Records, fix issues and report comments
dedupe as they do for any run: records by signal and SHA or by failing run, fix issues by check,
and reports by run and attempt.

1. **Confirmed red.** Attempt 1 concluded `failure`, the one re-run of its failed jobs finished
   and concluded `failure`, and one check failed in both, a check being a job that concluded
   `failure` or a gate the hygiene aggregator titles (never the all-branches gitleaks gate). A
   cancelled, timed-out or not-started run, a re-run that passes or never finishes within
   `confirm-wait-minutes`, and the canary never trigger it. The job waits for the re-run because
   pr-merge starts the one for a run it dispatched, and that re-run raises no event of its own.
2. **Culprit.** The range is the first-parent merges since `main`'s last green full run. A
   merge is red when its own full run is a confirmed red in a check the head also fails, and
   green when it passed. The culprit is the one merge that is red while its parent is green (the
   last green run for the oldest). A range of one merge always pins it. Two such merges, or none
   (a merge with no full run of its own breaks the chain), pin no culprit: the report names the
   untested merges, and a person picks from the post-merge record.
3. **Who reverts.** The bot may revert the culprit only when every guard holds; otherwise a
   person gets a draft revert pull request, labeled `needs-human`. The guards: the lanes App
   (`merge.agent-identity`) put it in the merge queue, so an owner or other human merge never
   auto-reverts while a lane merge pinned inside a mixed range may; it merged under
   `max-culprit-age-hours` ago; it is no revert itself (a `revert` subject, a `This reverts
   commit` line or the `auto-revert` label); no auto-revert of it was decided before; fewer than
   `daily-cap` were decided in the last 24 hours, dry-run decisions included; no open canary
   record names a merge in the range; and `git merge-tree` applies the revert to `main`'s tip.
4. **The revert.** `git revert --no-edit <culprit>` on branch `red-main-revert/<sha12>`, titled
   `revert: <the culprit's subject>`, labeled `auto-revert`, its body carrying
   `<!-- red-main-revert culprit=<sha> -->` and linking the culprit, the failing run and the
   evidence runs. The bot also files a reinstate issue and comments on the culprit's pull request,
   and its own revert merges through the merge queue.

| Key | Default | What it sets |
|---|---|---|
| `dry-run` | `true` | Report only: the step summary and one comment per confirmed red on the log issue (first body line `<!-- red-main-revert-log -->`), each starting `<!-- red-main-report run=<id> attempt=<n> culprit=<sha or none> decision=<auto-revert, human or none> -->`. Nothing is pushed, opened or merged. This version has no revert path, so `false` reports too. |
| `daily-cap` | 3 | Auto-reverts decided in any 24 hours; 0 to 10, and 0 sends every culprit to a person. |
| `max-culprit-age-hours` | 24 | Hours since the culprit merged past which a person decides; 1 to 168. |
| `confirm-wait-minutes` | 40 | Minutes the job waits for the re-run to finish; 0 to 45. |
| `remedy` | `rollback` | `rollback` applies rules 3 and 4. `fail-forward` plans no revert: the report's decision is `human`, it names the remedy as the reason, and a person or a fix pull request repairs `main`. |

The job reads the leaf through the base checkout's resolve-config (`redMainFromBase`), so a config
the resolver refuses fails it. It holds the job's own `GITHUB_TOKEN` (`actions`, `checks`,
`contents` and `pull-requests` read, `issues: write`), reads REST only, 300 ms apart and within 300
calls, and stops on any failed read. A range of more than 25 merges pins no culprit. The kill switch stops it, and it skips an event the lanes App
sent. Reports run one at a time in one repository-wide concurrency group, which keeps one pending
report and cancels the one before it. The next report names every red full run since the last
green one that has no report on the log, and its range covers their merges, so a cancelled report
re-decides there instead of dropping. The log is the oldest `github-actions[bot]` issue (user id
41898282) carrying the log marker, and only that account's comments on it count toward the cap and
the dedupe. Any workflow's `GITHUB_TOKEN` posts as that account, so a comment there can still use
up the cap, which only sends a culprit to a person. Owner decision 2026-10-20: `dry-run` stays true for 3 days of reports with no wrong blame
before any revert merges.

## Branch cleanup

A branch lives as long as its issue is open and is deleted once the issue closes (owner decisions
W-7, 2026-10-21, and #8958). No dates are involved.
[`maintenance-delete-stale-branches.yml`](../../../.github/workflows/maintenance-delete-stale-branches.yml)
runs daily and sorts every branch; its rules and tests are in
[`.github/scripts/branch-cleanup/`](../../../.github/scripts/branch-cleanup/). It runs no model.

1. **Never touched.** The default branch, `release/*`, `dependabot/*` and `gh-readonly-queue/*`.
2. **Kept.** A protected branch or one a ruleset applies to; one with an open pull request; a lane
   branch (`work-resolve-issue/issue-<n>-...`) while issue `n` is open; any other branch while an
   issue its newest pull request's body links with `Closes`, `Fixes`, `Resolves` or `Refs` is
   open.
3. **Never deleted, reported.** A branch that never had a pull request (a lane branch excepted), a
   merged branch with commits ahead of the default branch after its tip moved, a closed-unmerged
   branch whose tip moved, and any branch a read failed on. The step summary lists them for a
   person.
4. **Deleted.** The newest pull request closed unmerged or merged at the branch tip, or merged
   with the tip moved and 0 commits ahead of the default branch, and every linked issue closed;
   or a lane branch with no pull request whose issue closed. A lane run's stop or resume marker
   on the issue does not keep the branch once the issue is closed.

The job prints how many it will delete, then deletes at most `max-deletes-per-run`, in listing
order. It reserves four calls per planned delete from its call budget before evaluating, and stops
evaluating once it has found `max-deletes-per-run` deletable branches or spent the rest of the
budget. Each run starts at a different point in the listing, moved by the run number and wrapping
around, so branches kept early in the listing do not hide the later ones from every run. Before each delete it re-reads the tip and the open pull requests from and into the branch,
skips it when the tip moved or one opened, and appends `{repo, branch, sha, rule, issue, pr,
deletedAt}` to the step summary and the run's `branch-cleanup-ledger-<run>-<attempt>` artifact. The
delete is `DELETE git/refs/heads/<branch>` with the job's own `GITHUB_TOKEN` (`contents: write`,
`issues` and `pull-requests` read); the API takes no expected SHA, so the delete also removes a push that lands between the re-read
and the delete; the pusher's own copy restores it. The ledger SHA restores the deleted tip:
`git push origin <sha>:refs/heads/<branch>`. A scheduled run
deletes; a manual run is a dry-run unless `dry-run` is set to false, and in dry-run the client
refuses every request but `GET`. The kill switch stops it.

| Key | Default | What it sets |
|---|---|---|
| `max-deletes-per-run` | 25 | Deletes per run at most; 0 to 100, and 0 deletes none. |

## Planning lane work

Size the process to the change:

- A sub-topic of lane work gets a one-page plan.
- Run `/planning:design`, the plan review and `/planning:devils-advocate` only for a change that
  moves a trust boundary.
- Record an ADR only for a trust-boundary or irreversible choice; `/architecture:record-decision`'s
  admission test still applies, and a reversible choice goes in the PR body.
- When the owner pre-approved the recommended options, stop only on the items the owner reserved.

## Changing this config

The config file is a lane-power file, like the trusted-actor list and any change to a lane's
permissions, tokens or triggers. A change to it goes through review and `ci-status`, and the
merge lane's cost hold (an edit to more than comments, a `description` or a `title` waits for a
cited owner decision); no rule requires a human to merge it.

A pull request that changes a lane and lists a not-verified item that could stop the lane from
running checks that item live before it merges. An item only a merged run can exercise, such as
a changed workflow that runs from the base branch, merges only once a tracked issue names the
check and its owner; a line in the pull request body does not count. Evidence: melodic-software/ci-workflows#755 listed its
intake author gate as "unverified, fails closed", merged, and skipped every intake run here
(melodic-software/ci-workflows#772).

The lanes token broker in azure-iac parses each caller's config with the resolve-config modules it
loads from claude-code-plugins' `main`, whichever repository calls, so a change to `resolve.mjs` or
a module it imports needs no azure-iac change. These still pair with an azure-iac deploy:

- resolve-config's `package.json` or `package-lock.json`: the broker imports `ajv` and `yaml` from
  its own deployment and denies every token as `config-invalid` while `main`'s two files differ
  from the deployed ones. The pull request carries the body line
  `Broker deploy: melodic-software/azure-iac#<n>`, naming the azure-iac pull request that moves the
  broker to them; `ci-status` fails it otherwise (the `BROKER_PATHS` value of `ci-status`'s
  "Require a broker deploy PR for a resolve-config dependency change" step in
  `.github/workflows/pr-require-checks.yml`).
- A file `loadConfig` comes to need, a new export the broker calls, a module outside
  `.github/actions/resolve-config`, or an import form the broker's loader does not walk:
  [`broker-vendoring.test.mjs`](../../../.github/actions/resolve-config/broker-vendoring.test.mjs)
  fails on each against its copy of the broker's lists.

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
| Review and intake reusable workflows | [`melodic-software/ci-workflows`](https://github.com/melodic-software/ci-workflows) `.github/workflows/pr-review-cli.yml` (both review lanes) and `intake-triage.yml`, called by this repository's `*-hosted.yml` review callers and `intake-triage.yml` |

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
- The post-merge failure remedy, revert or fail forward, is the per-repository `red-main.remedy`
  key ([Red main](#red-main)), not a choice by change type.

## Versioning

The schema's `version` is the contract major. [`CHANGELOG.md`](CHANGELOG.md) records each change.
A pull request that changes this directory does not edit `CHANGELOG.md`: it adds a changelog
fragment, `scripts/new-changelog-fragment.sh pr-pipeline <major|minor|patch|none>`, and the release
pull request writes the fragments into one `CHANGELOG.md` entry
([ADR 0048](../../adr/0048-release-plugins-from-changelog-fragments-through-a-bot-maintained-release-pr.md)).
A `major` fragment's pull request also raises the schema's `version`.
