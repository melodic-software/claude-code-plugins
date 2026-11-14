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
- [Claude Code CLI releases](#claude-code-cli-releases)
- [The lane sweep](#the-lane-sweep)
- [The monitoring lane](#the-monitoring-lane)
- [Write identities](#write-identities)
- [Models](#models)
- [Funding](#funding)
- [Loop caps](#loop-caps)
- [Limits](#limits)
- [WIP cap](#wip-cap)
- [Adoption](#adoption)
- [Review threads](#review-threads)
- [Red main](#red-main)
- [Attended work](#attended-work)
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

The loop-lane convention ([`loop-lane`](../../contracts/loop-lane/README.md)) governs local loop sessions; this
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

An answered issue re-enters `intake` through [`intake-reenter.yml`](../../../.github/workflows/intake-reenter.yml), a scripted workflow with no
model. On a new comment on an open issue, not a pull request, it acts on a `needs-owner-decision`
issue whose comment is a decision (first line `**Decision recorded.**`, by a human on the
trusted-actors list, not posted through an App, unedited or last edited by a listed human) or a
`status: confirmed` issue with no other `status:` label and no `agent-ready` whose comment is such
a decision, whether admission parked it there or a person confirmed it, or on a
`needs-reporter-info` issue whose comment is by the issue's author or a listed human. It removes that
status label and adds `needs-triage`. A decision on an issue that carries `needs-human` changes
nothing; a listed human's removal of `needs-human` re-enters an issue with no `status:` label or
at `needs-owner-decision`, removing that label the same way. A listed human's change of the Work
status field from a hold state to none or `needs-triage`, on an issue with no status label but
`needs-triage`, re-enters it too, writing no label: the claim is a comment marked with the field
event that left the hold, which a re-run of that release finds, and the field is set to
`needs-triage` before the dispatch when the release left it empty. It dispatches
`intake-triage.yml` once only when the issue's author is one intake admits on open (a listed human
or the lanes App); any other issue waits in `needs-triage` for a person, so an outside author
cannot start a model run with each reply. A dispatch skips the born-triaged check. Removing the status label is the
claim, so a second answer dispatches nothing. A blocker stops blocking once it is a pull request
merged in this repository, or an issue closed, for any reason, by a listed human or, in this
repository only, a merge (owner decision Q95, `blockerDone` in `.github/scripts/intake-triage/admit.mjs`):
the lanes follow that rule, not the work-items tracker's `blocked_by_count`, which still counts a
won't-do close. When a blocker of an issue admission parked at
`status: confirmed` closes after it parked, `work-unblock` removes that label with the lanes App's
token instead of admitting the issue, and that removal starts this workflow, which adds
`needs-triage` and dispatches on the same author rule. It acts only when the newest removal is the
App's and the issue carries no `status:` label, `agent-ready`, `needs-human`, `needs-triage` or
`admission-deferred`, which leaves out every other App removal; `needs-triage` is the claim there,
and a failed dispatch leaves the issue with no `status:` label for a re-run or the triage sweep. A
milestone in `admission-rules.json`'s `cordoned-milestones` keeps an issue parked. It never adds `agent-ready`, and it holds the job's own `GITHUB_TOKEN` (`actions: write`, `contents: read`, `issues: write`), never a lanes App token.

Anyone outside the organization who writes on an issue or pull request is flagged for a person by
[`security-outside-actor.yml`](../../../.github/workflows/security-outside-actor.yml), a scripted
workflow with no model, secret or kill switch. It runs on an issue or pull request opened, edited
or reopened, a pull request synchronized (`pull_request_target` for a pull request), on a
comment, review or diff comment created, submitted or edited, and on `security: outside-actor`
removed from an issue or pull request. A flag job starts only when the sender is not a Bot (an App
installed here), or the event is on a pull request whose head is a fork (an App on the fork can act
there), and either the content's author is neither `OWNER` nor `MEMBER` or the event is an edit,
push or reopen by someone other than the author, which judges the sender. The run then trusts the
actor only by numeric id on the default branch's trusted-actor list, and an unreadable list flags.
An outside actor's item always gets `security: outside-actor` and `needs-human` written, and one
comment per actor names the login, without a mention, and the event, quoting none of their text.
`security: outside-actor` is a hold of its own (`merge-holds.mjs` `OUTSIDE_ACTOR_LABEL`): the merge
queue, auto-merge arming, the babysit merge gate, ci-status, intake triage, the work-unblock sweep
and every pull request activity (its `labels-absent`, which the write runner holds too) skip it,
and `clear-escalations.mjs` keeps `needs-human` on an item carrying it. Only a person on the
trusted list removes it: when anyone else removes it (any letter case of the name), the run puts
both labels back and posts one comment naming the remover, without a mention. The job holds the
job's own `GITHUB_TOKEN` (`contents: read`, `issues: write`, `pull-requests: write`). A review or
diff comment on a fork pull request gets a read-only token and is not flagged; the fork pull
request itself is flagged when it opens.

Pipeline lanes skip draft PRs; `ci-status` still reports on them, and passes the skipped lanes.
The `ready_for_review` run tests the head, and the merge queue re-runs every lane before a merge.
Converting a PR back to draft
cancels every running pipeline lane for it.

### Refine before review

A PR's path, in order: build, refine, review, fix, verify, merge. Build is `work` or `pre-ready`;
review is the AI review lanes; fix is `unblock` (fixing CI, addressing review feedback); verify and
merge are their stages.

`pr-refine.yml` runs the Refine passes. Its `plan` job lists the PR's changed files and picks each
activity with `stage: refine` whose `applies-when` `paths` match a changed file that no
`paths-ignore` glob matches, so a changelog fragment alone (`.changes/**`) starts no `fix-docs`.
Adding a pass is an activity entry with `stage: refine`, its globs, an `order` and a `group`, and
its jobs in `pr-refine.yml`. The plan also outputs `batches`: in `order`, a pass joins the batch
before it when it is not `serial`, shares that batch's `group`, and matched none of the batch's
files; otherwise it starts a new batch. No job reads `batches` yet, so every planned pass starts at
once; a second pass's first job must also wait on the batch before it. A PR that matches no pass ends the run
at the plan, every later job skipped and no model turn. The plan reads the lane's slots as the
runner's config reader expands them, so a disabled slot or a slot's own `applies-when` counts, and
a pass taking `changed-paths` needs a file left after instruction surfaces and owned paths are
dropped. A changed-files list the plan cannot read holds: no pass runs and `fix-docs-head-held`
logs a `PR head hold` notice; a plan that fails logs `refine-failed` for `pass=plan`. Each job has
a `timeout-minutes`, its own or its reusable workflow's input.

#### Signals

| Signal | Means |
|---|---|
| A push to a branch | Work in progress. |
| A non-draft PR | The author is done. |
| A `refine-pass` notice per pass in `pr-refine`'s `record-passes` job: `pass=<name> files=<n> outcome=<pushed\|none\|superseded\|failed> seconds=<n>` | What each pass did, and how long since the plan started. A failed pass also logs a `refine-failed` warning, which [signal 13](#the-monitoring-lane) counts as a `pr-refine` hold. |
| Refine complete | The signal review starts on. Each hosted review run's `wait-refine` job (`.github/scripts/pr-review/wait-refine.mjs`) waits up to 40 minutes for the `pr-refine` run that this head's `pr-unblock-dispatch.yml` `refine` job dispatched, inside the review's own `pull_request` run, since ci-status reads only those. A head that moved meanwhile, by Refine's push or another, is not reviewed: that push starts the new head's review. Any other outcome reviews: no dispatch, a Refine that failed or ran past the cap, or a read that failed. |

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
| `pr-refine` | a `fix-docs` dispatch from `pr-unblock-dispatch.yml`'s `refine` job, on the PR's own `pull_request_target` event (opened, reopened, ready for review or pushed), for each ready PR that changes Markdown, never had `fix-docs` and is not a `work-resolve-issue` PR tidied in its own run (within the tidy cutoffs), or a trusted human's dispatch; a push to the default branch or the dispatcher's half-hourly tick starts none, and `limits.fix-docs-per-run: 0` turns the dispatches off; on a listed human's event (never the lanes App's) the same job also dispatches each activity `refine-dispatch.activities` lists, from the allowlist in `refine-event-dispatch.mjs` (`fix-marker`), empty by default |
| `pr-run-checks` | dispatch from `pr-refine` |
| `pr-review`, `pr-review-security` | dispatch from `pr-refine` |
| `pr-verify` | dispatch from `pr-refine` |
| `pr-explain` | dispatch from `pr-refine`, alongside verify |
| `pr-require-checks` | each verify result |
| `pr-unblock` | a dispatch for each conflicting PR but a Dependabot head (Dependabot rebases its own), each unreviewed review-tier Dependabot PR, and each failing lanes App PR after a push to the default branch or at the dispatcher's half-hourly tick, a dispatch after a review lane finishes on a lanes App PR with an open reviewer-bot thread, a dispatch at the half-hourly tick for a fix request on such a thread, or a trusted human's dispatch |
| `pr-merge` | final check green, or a hold removed |
| `work-unblock` | an issue closing, by a listed human, and an hourly sweep of the issues a listed human or a merge (a merged PR or a commit) closed in the last three hours (catching PR merges a bot ran; a sweep whose closed-issue listing fails holds green, and the next one reads back past it), which each finished `work-resolve-issue` run that ran a job also starts, so a freed slot admits the next deferred issue at once; labels `agent-ready` on each issue it blocked that is now unblocked, unheld and owner-ratified; the label starts `work-resolve-issue`. The sweep also restarts or re-fires stopped issue runs (one a merged `Refs:` pull request names after its newest decision comment goes to triage instead) and relabels a red-main fix issue a repeat failure reopened |
| `post-merge-verify` | push to the default branch |
| `post-merge-sweep-comments` | push to the default branch |

`pr-unblock`'s dispatches come from `pr-unblock-dispatch.yml`, a scripted workflow with no model
that runs on a push to `main`, half-hourly five minutes after each lost-run reconciler tick, and on
a trusted human's `workflow_dispatch`:

- It lists open, non-draft, same-repository PRs into `main` that GitHub reports as `CONFLICTING`,
  re-querying an `UNKNOWN` PR up to 5 times, 10 s apart.
- It skips a held PR without recording it: `do-not-merge`, or the human-gated label unless
  another lane's escalation put it on (below). The next run after the hold comes off picks it up.
- It skips a PR whose head already has a `pr-unblock / resolve-conflicts` check run from the
  GitHub Actions app, unless that run is a neutral `Skipped: untrusted-trigger`, or a
  `Skipped: awaiting-human` (a skip while held), a limit stop past its reset or a failure, until
  `limits.limit-stops-per-head` of those last three stand on the head. A limit stop is a run whose
  lane-outcome record's `class` is `rate-limit` or `auth` (a refused credential); until it resets the
  dispatcher logs a notice naming the class and the reset time.
- It dispatches `pr-unblock.yml` on `refs/heads/main` for at most 3 PRs per run, lowest number
  first, passing `pr-number` and `dispatcher-run-id`.
- A read that fails holds, whatever GitHub answered. A listing it cannot read dispatches nothing,
  and a PR whose holds or check runs it cannot read is skipped, each with a warning, and the next
  tick reads them again. This holds for every dispatch the run sends, the ones below included,
  with one exception kept from before: `fix-ci` still dispatches under its caps when it cannot
  read its required run or the head's check runs for a reason other than a `5xx` or a rate limit,
  or when the verifier reader fails. A failed read does not fail the run. A dispatch that failed
  or named no run id, config the run cannot read, or a rate limit (the shared rate guard fails
  the step) still does.
- A hand run or a re-run must be started by a listed human (`check-trusted-trigger` with
  `require-pr: false` and `require-kind: human`). That mode handles no `schedule` event, so a
  re-run of a scheduled run fails; the next tick replaces it.
- With the kill switch on, the run ends green with a notice and dispatches nothing.

In `pr-unblock.yml` no model holds a write token or runs git: `resolve-conflicts-select` (base
code only, read-only token) merges the default branch tip into the head and decides clean,
conflicted or escalate, and posts the `resolve-conflicts` check neutral when no model is needed;
`resolve-conflicts` (a `read` skill in [patch output mode](pr-run-activity.md#patch-output-mode),
on run-claude-cli with the subscription fallback) resolves a conflicted merge from read-only
context files with no shell; and `apply-conflict-patch` (a script, `mutate-branch`) commits the
merge with the head and the pinned base as parents
([`pr-run-activity.md`](pr-run-activity.md#prepare-merge-base)).

A trusted human may also dispatch `resolve-conflicts` for a PR GitHub reports as mergeable, to merge
the default branch into a head whose stale base breaks a required check. The select job merges it
the same way when the head is behind, and skips one that already holds the default branch tip,
posting no check, so the dispatcher can still take that head if it later conflicts. The dispatcher
itself still sends only `CONFLICTING` PRs. A PR whose base is not the default branch (a stacked
layer) skips `not-applicable`, clean or conflicting, since every job merges the default branch tip.

GitHub starts no `pull_request` workflow on a PR with a merge conflict, so a conflicted head gets
no CI. When `resolve-conflicts` stops on a reason routed to a failing status (below),
`pr-unblock.yml`'s `report-stop-status` job (a script job with no model, the lane's only
`statuses: write`, on its own `GITHUB_TOKEN`) posts a `failure` commit status with context
`pr-unblock/conflict` on that head; for `unresolved-conflict` it says CI does not run until the
conflicts are resolved. A push that resolves them is a new head, which the status does not reach.
A conflict that clears with the head unchanged (main moved again) leaves the failing status on it
until a push or a person replaces it. An `address-feedback` or `fix-ci` failing status stays too
when a person resolves the threads or gets the checks green on that head: a `pr-unblock` dispatch
of that activity then finds the cause gone and clears it. On a lanes App pull request the
dispatchers start that run themselves, once per stop: `pr-feedback-dispatch.yml`'s sweep for an
`address-feedback` stop with no unresolved thread left (`sweepStale`), and `pr-unblock-dispatch.yml`
for a `fix-ci` stop whose head's checks all pass (`staleStop`). On any other pull request a person
dispatches it.

`pr-unblock`'s `address-feedback` dispatches come from `pr-feedback-dispatch.yml`, also scripted,
on `workflow_run` `completed` of `pr-review-hosted` and `pr-review-security-hosted`. It takes only
the upstream run id from the event and reads the rest back. It dispatches `pr-unblock.yml` with
`activity: address-feedback` when the upstream is a `pull_request` run of one of those two paths in
this repository, exactly one open non-draft PR into `main` has its head, the lanes App or an
[adopted owner](#owner-pull-requests) opened that PR, it carries no `do-not-merge`, both lanes' newest reviewed-head markers
name the head, an unresolved thread exists that `address-feedback` would keep (left only by the
reviewer bot, one the lane never answered where a fix request, below, follows the reviewer bot's
finding or sits in a thread a trusted person opened, or answered by a trusted human after the lane escalated it; on a PR carrying the
human-gated label, only one whose answer is a fix request, unless a lane escalation put the label
on: the lanes App added it last, its `work-items:escalation lane=pr-unblock` comment (pr-unblock
or fix-ci) followed within a minute, no other marker is on its comments since, no review-lane
`claude-lane-hold` names the current head or is open, and no `check-signed-commits` hold is open,
per
`.github/scripts/pr-unblock/gate-source.mjs`; anything ambiguous keeps the fix-request rule, and
the label stays on, and `clear-escalations.mjs` removes it only while no address-feedback round
record is on the lanes App's comments since it went on; to stop the lane working such a PR, a
person adds `do-not-merge`, since re-adding a label already on records no event), the head has no
`pr-unblock / address-feedback` check run (one that started before the head's newest
`pr-unblock / publish-feedback` check run stops counting when that run skipped `no-model-turn`
(the round handled nothing) or `finding-stands` (it left a finding standing at that head), and
the round cap still bounds the retries; a limit stop keeps its
reset hold and counts toward `limit-stops-per-head`; since such a head may see no later review,
each scheduled `pr-unblock-dispatch.yml` run's completion also starts a sweep that decides each
such head as for its newest completed review run, under three such skips at that head, and
sends up to five rounds a tick (`SWEEP_TICK_CAP`) once every decision is made, each PR at most
once), and no `pr-unblock.yml` run titled
`pr-unblock address-feedback #<n>` is still queued or going (both lanes finishing at once). Then it
runs the base's resolve-config for that PR and head with `address-feedback` selected, so only that
slot's `applies-when` is decided, and dispatches only when the `pr-unblock` lane and its
`address-feedback` and `publish-feedback` slots are enabled and `address-feedback` applies. It records `pr-feedback-dispatched-<upstream id>-<run
id>`, which the gate and the broker read to tie the run to a review of the PR's current head.

It also runs on `workflow_run` `completed` of `pr-review-comment-relay`, which a person's new
review comment on a lane branch starts (`pull_request_review_comment` `created`, no permission,
no checkout, no secret). It reads the relay run back and dispatches as above, with the relay run
as the upstream the record names, only when the run succeeded, its actor and re-runner are both
listed humans (never the lanes App), its `pull_requests` name the PR, and an unresolved thread
the lane escalated was answered by a listed human (a fix request alone keeps the tick's sweep); only check runs started after the relay run count. The gate and
the broker accept that upstream by path, event and actor id
([ADR 0088](../../adr/0088-relay-a-listed-humans-review-comment-to-the-feedback-dispatcher.md)).
GitHub starts no such run on a conflicted PR; that reply is picked up by the review run after
`resolve-conflicts` pushes.

It also runs on `workflow_run` `completed` of `pr-verify`. When that run of `pr-verify.yml` on
`main` uploaded a `fail` verdict, its `post-verify-notes` job (a base job with no model, holding
`pull-requests: write`) posts the verdict's summary and notes on a lanes App PR as file-level review
comments by `github-actions[bot]`, each starting `<!-- pr-verify:fail-note -->`, on the head the
verdict judged (`.github/scripts/pr-unblock/verify-notes.mjs`). It posts only on an open PR still at
that head, and only the comments that head does not hold yet, by file; a note in a resolved thread
does not count, so a FAIL after a pass that superseded an earlier one at the same head opens a thread
again. A PR a person opened gets no
review comment: GitHub lets only a PR's author or a writer resolve a thread, the lanes App is
neither, and every conversation must be resolved to merge. It gets one PR comment instead, starting
with the same marker and edited in place on a later fail, and the `pr-verify-failed` label, which
`ci-status` holds in the merge queue. No round starts there. A withheld fail (a verdict whose text
is shaped like a credential, or whose step stopped on the credential scan, which `write-verdict.mjs`
alone records as `withheld: true`) also holds for a person, and no fix round works past it, since a later clean commit rotates nothing: at
whatever head the PR has moved to, and in any state, so a closed PR that reopens stays held, it takes
the human-gated label and, once per head, a comment with a `security` stop reason, and an open PR
leaves the merge queue. That
comment keeps the label through every clear path (`clear-escalations`, `enable-auto-merge`'s lift,
`ci-status`'s cost-hold clear) until a person removes the label. A failure in the hold still posts
the notes, then fails the job. A note that starts with a path the PR changes goes on
that file; the summary and the other notes go on the first such file, or on the PR's first changed
file. `address-feedback` keeps such a thread as the `verifier`'s finding, as it keeps the reviewer
bot's, when its review is `github-actions[bot]`'s on a head the reviewed-head markers name. The
dispatch job then decides as above, with the newest completed review run at that head as the
upstream it records, except that only `pr-unblock / address-feedback` check runs started after the
`pr-verify` run was created count, and the head's handled record is not read, since the notes are
new work at a head an earlier round may have handled; with none yet, the review run dispatches when it completes. The fix round's
push gives a head the verifier judges again.
When the run uploaded a `pass` or `pass-notes` verdict instead, on an open PR still at that head
`post-verify-notes` removes `pr-verify-failed` from a PR a person opened, if it is there, and
dispatches nothing. On a lanes App PR it posts and resolves nothing: it reads the review threads, and when an
unresolved fail-note thread is open (`address-feedback.mjs` `staleVerifyNotes`,
by the first comment's original commit) it names the head in `pass-head-sha`. The dispatch job then
sends a pass-only round (input `verify-pass-head`), needing no workable thread, review marker or
check-run room, and not held by a round for the PR in progress: `pr-unblock.yml`'s per-PR
concurrency group queues it behind that round. A round waiting to start still holds it, since the
group keeps one waiting run and sending would cancel that round. When the merge gate's reader, in the dispatch job's FAIL-cap read, reports the FAIL
at that head superseded (`babysit_verify_evidence.py` `supersededAtHead`, the gate's own
`_superseded` judgment), the dispatch also names the head in `verify-superseded-head`.
`address-feedback-select` lists in `run.json`'s `stale_notes` the threads from another head, and
those at the passing head only with `verify-superseded-head` at it (then naming it in
`superseded_head`); a failed or missing read leaves those open. No model
job or neutral check runs, and `publish-feedback` resolves each one still open and stale while the
PR head is the passing one, as the lanes App, with no reply and no round marker, and skips
`pass-only`, which the dispatcher's release reads pass over. A pass-only round goes only to lanes
App PRs; other address-feedback rounds also go to adopted owner PRs
([Owner pull requests](#owner-pull-requests)). Resolving a thread
takes more than the `post-verify-notes` token holds, so that job never resolves one.
When the gate's reader refuses a lanes App PR's head `verify:earlier-fail` (a FAIL at another head
of the same change), its report's `earlierFails` names the FAILed heads, and the dispatcher sends a
model round with them in `verify-earlier-fail-heads`, even with no unresolved thread. When no
thread is left to work, `address-feedback-select` (with `actions: read`) reads those FAILs' notes
from their verdict artifacts (`earlier-fail-notes.mjs`: the head's FAIL index, a run the gate
counts, `verify-notes.mjs` `readVerdict` and `noteComments`) into `threads.json`'s
`verify_notes`; a read that fails stops `feedback-verdict-unreadable`. The model fixes each note
or reports it `already-addressed`; `publish-feedback` posts nothing for them. A push fixing a
named note ends as any fix round; no push with every note already addressed stops
`feedback-already-addressed` for a session builder.
In `pr-unblock.yml`, `address-feedback-select` (a base job with no model and a read-only token)
keeps the threads, `address-feedback` (the model job, `read`, on the read runner with a
subscription fallback) answers them and hands on a patch and its replies,
`apply-feedback-patch` (a script job with no model, `mutate-branch`) pushes the patch, and
`publish-feedback` (a script job with no model, `publish-artifact`) posts the replies, naming the
pushed commit ([`pr-run-activity.md`](pr-run-activity.md#prepare-review-threads)). It re-reads each
thread against the reviewed heads the select job recorded in `run.json`, since a review lane edits
its one marker in place when it reviews the pushed fix. `publish-feedback` also brings the body
sections a landed fix made stale up to date, unless the base's `pr_body_refresh` is `false`: the
select job offers the `##` sections the base's `pr_body_required_sections` lists (every one when it
lists none) whose text holds no gate-read line, never `## Follow-ups` or the body's last section,
and pins each by SHA-256 in `run.json`; the model job records replacement text with the
review-thread tool; and `publish-feedback` puts it in place of an offered section still unchanged,
leaving every other byte, or drops the refresh alone, naming why in its log and round marker, when
any text holds a line a gate reads or the body's gate-read lines would change. Its body writes are
those sections and its `## Follow-ups` entries. `fix-ci` rewrites no body section; an attended
session does ([`monitor.md`](../../../plugins/source-control/skills/pull-request/reference/monitor.md)
§3.3.2 step 5).

### Outage posture

Every lane pauses and resumes through an outage by these six elements (#9205, owner decision
Q677). [The outage posture audit](../../outage-posture-audit.md) records each lane's verdicts.

1. **Retries.** Scripts retry and the model never does. Each call gets at most 3 attempts. A
   script waits for `retry-after` when the header is present. For a primary rate limit it waits
   until `x-ratelimit-reset`, and for a secondary limit at least 60 s. Otherwise it uses capped
   exponential backoff with full jitter. A wait longer than a small per-step budget counts as
   unknown under element 2 instead of a sleep. Non-idempotent writes are never retried.
2. **Unknown holds.** A failed read, or a 200 whose completeness check fails, makes the verdict
   unknown. The lane then holds, files nothing, merges nothing, and exits green with a notice.
3. **Next tick probes.** The next existing cron tick is the probe. There is no stored breaker, no
   re-arm and no status-page trigger (element 5).
4. **Positive evidence.** A lane demotes or files a failure only on positive evidence from a
   complete read. When a later complete read contradicts a record the lane filed, the lane closes
   it.
5. **Status page.** The GitHub status page may stop work but never starts it. A lane may idle while
   the page lists an Actions outage, and it resumes only when the page is green and its own reads
   succeed. The page never opens or closes a record, and a hold notice may quote it as context
   (owner decision, #12292).
6. **No extra load.** Reads are serial and repeated polls send conditional requests (`etag`).
   Scheduled lanes keep the default single-pending concurrency. Optional work is skipped while the
   state is unknown, and other lanes stay off minute 0.

### Owner pull requests

Agent sessions answer review threads under the owner's login, so on a PR the owner opened a lane
answer cannot be told apart from the person's, and the babysit worker tier, which resolves only
threads a lane login answered, resolves none of them (#10763). `address-feedback` therefore also
serves an adopted owner PR, posting its replies as the lanes App:

- Who: a PR whose author is a `kind: human` id on the base's trusted-actors list, typed `User`,
  under an [`adoption`](#adoption) section (`feedback-dispatch.mjs` `ownerAuthored`). Without that
  section, or for anyone else, nothing changes: the dispatch skips the PR.
- When: as fix-ci adopts one, no body line starts `Hold:`, and both the PR's last update and its head
  commit's committer date are at least `adoption.idle-hours` old (`ownerSkip`), so the lane never
  pushes onto a branch a session is still working on. A review usually finishes while the session
  is active, so that dispatch skips; each scheduled tick's sweep then sends each idle owner PR, within its cap, whose
  reviewed head has no `pr-unblock / address-feedback` check run (`sweepIdleOwner`), deciding it
  as for its newest completed review run. It decides such a head only within
  `IDLE_OWNER_WINDOW_HOURS` of the PR turning idle, so a head with nothing for the lane is not
  re-read every tick; any new update opens the window again. A head whose round stopped with a
  failing `pr-unblock/address-feedback` status, and no thread left, is dispatched to clear it, as
  for a lanes App PR, under the same `Hold:` and idle gates. The select job reads the body again
  when the round starts and skips `awaiting-human` on a `Hold:` line added after dispatch.
- Human gate: a lane escalation's human-gated label lets the round work only as it lets fix-ci
  work the PR (`gate-source.mjs` `prHold`): not after an `address-feedback` escalation, and not
  once a person commented or reviewed after the label went on. Held, the round works only a thread
  a trusted person with write access asked the lane to fix. On a lanes App PR a lane escalation's
  label still lets the round work, as before.
- What: the round is the App PR round, unchanged: the same threads (only the reviewer bot's, a
  listed review bot's, or a lane's, under the same trusted-person rules), the same CRITICAL and
  security holds, the same `apply-feedback-patch` push under the same patch rules, and no merge.
  A thread a person wrote without a fix request, answered without one, or directed still goes to that person;
  on an owner PR such a thread starts no round, and the select job skips it with no stop instead of
  escalating `feedback-untaken-threads`.
- Resolve: GitHub lets only a PR's author or a writer resolve its threads, so `publish-feedback`
  (`publish-artifact`, no writer) posts each answer and leaves the thread open, logging it. The
  `resolve-feedback-threads` job after it, a script with no model and `checkout: base` (no PR head
  checkout), holds `mutate-branch` (`contents: write`, which makes it a writer) and resolves, on a
  PR a person on the trusted-actors list opened, each thread whose comments are all a review bot's
  or the lanes App's, whose finding no reviewer comment rates CRITICAL and an adjudicator could
  judge (`adjudicable`: no person-decided security finding), and that is answered (the lane's
  VALID reply or a `finding-answered` adjudication is its last comment) or outdated with no lane
  reply that left it open (`resolve-threads.mjs`). It reads the threads from GitHub, never from
  another job, judges each again on its re-read comments just before resolving, and escalates
  nothing. It runs after an acted round and after the reply script's own stops (an escalation,
  `finding-stands`, `no-model-turn`), never after a kill-switch or gate skip, and starts no job
  (so asks the broker for no token) on a PR no listed person opened (the select job's
  `person-opened`) or on a round whose upstream is a relayed person's reply (the dispatch's
  `upstream-relay`), where it has no thread to resolve. A CRITICAL finding
  and any thread a person wrote or joined stay open for the person.
- No pass-only round goes to an owner PR: a person-opened PR gets no fail-note threads
  (`verify-notes.mjs`).

The push is the power fix-ci already holds on an adopted PR, under the same idle rule; the one
grant the lane gains is `resolve-feedback-threads`' `mutate-branch`, used only to resolve.

The reviewer bot is `claude[bot]`, a review bot listed in [`review-threads`](#review-threads), or
`github-actions[bot]` on a comment whose last non-blank line is a review lane's
`claude-lane: <lane>` footer, as ci-workflows' `pr-review-cli.yml` posts its findings; the review
holding the thread's first comment must be that comment's author's own.

A fix request is a reply by a person on the trusted-actor list who holds write or admin
permission on the repository, never edited, or last edited by a person on that list, with a line that starts with
`PR-fix lane: please fix this finding`, in any letter case, outside a fenced code block (a quoted
`>` line never matches). On a thread the lanes App never commented on, one fix request after the
reviewer bot's finding makes the thread one `address-feedback` works, as long as every other
comment is the reviewer bot's or a trusted person's; their comments from the first fix request on
are direction. A thread such a person opened is worked the same way: their own fix request in it,
first comment or a later one, asks the lane to fix what it names (a failing check, say, on a PR
no review bot commented on), so the lane no longer stops on it with `feedback-untaken-threads`.
A thread anyone else opened, or one without a fix request, is left alone as before. Such a
thread, and one a trusted person answered after the lane escalated it, is
worked even when its review is on an earlier head than the one the reviewed-head markers name.
On a lanes App PR, the next half-hourly tick picks up a fix request on an unresolved thread the
reviewer bot opened: each scheduled `pr-unblock-dispatch.yml` run's completion starts
`pr-feedback-dispatch.yml`, whose sweep decides each such head ahead of the heads it retries, within its cap of five a tick.
The request must be newer than the head's newest `pr-unblock / address-feedback` check run; check
runs that started before it stop counting for that dispatch, except a limit stop, which keeps its
reset hold. Each request is sent once, a head with three rounds or releasing skips is not sent, and
`dispatchFeedback` re-checks every other condition. This sweep does not take a fix request in a
thread a trusted person opened or on an owner PR. To start a round at once, an account on the
trusted-actor list dispatches the lane directly:

```bash
gh workflow run pr-unblock.yml -R melodic-software/claude-code-plugins -f pr-number=<n> -f activity=address-feedback
```

That run names no dispatcher run, so the gate checks that account as the actor, and the select
step judges the threads as above.

A lane escalation's human-gated label does not stop the other fixers that could clear its cause.
`resolve-conflicts`, `fix-ci` and `fix-docs` work a PR carrying the label when `gate-source.mjs`
reads it as a lane escalation (the conditions below), no person has commented, reviewed or replied
in a review thread since the label went on (they may want the lanes to wait; GitHub's timeline
shows no reply inside an existing review thread, so the PR's review comments and reviews are read
too, and a failed read holds it), and no escalation since then names a reason of the activity's
own, read from the `- Reason:` line `report-escalation.sh` writes (`ci-fix-*` is `fix-ci`'s,
`feedback-*` `address-feedback`'s, `dependency-*` `review-dependency`'s, any other
`resolve-conflicts`'s). Their dispatchers and base-code jobs (`resolve-conflicts-select` and
`pr-refine.yml`'s `fix-docs-head` through `lane-hold.mjs`, `fix-ci-context`) read it; anything
else, a person's label included, holds the PR as `awaiting-human`, and `do-not-merge` holds it in
their `labels-absent`. `check-signed-commits`' escalation holds the PR too, even under a lane
escalation: a `github-actions[bot]` comment whose first line is `<!-- check-signed-commits hold -->`,
written or edited since the label was last removed, holds `resolve-conflicts`, `fix-ci` and
`fix-docs`, leaves `address-feedback` to the fix-request rule above, and keeps
`clear-escalations.mjs` from removing the label; the same marker from any other account is not
read. When they work past the label, the write runner lifts only the human-gated hold for that
push. That verdict is read once,
before the model turn: a person who comments, or a hold that lands, while the run works does not
stop that run's push (the next dispatch reads it), and `do-not-merge` still does. The label stays on, and
`pr-merge` refuses the PR until it comes off.

On a PR carrying the human-gated role label (`needs-human` unless the base's tracker binding in
`docs/conventions/work-items.yaml` names another), `address-feedback` works a thread only when it carries
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
ids join the same dispatched-runs record. A push to `main`, the half-hourly tick or a hand run
wakes it. In `pr-unblock.yml`, no
model holds a write token: `review-dependency-select` (base code only, read-only token) selects
the pull request or posts its check neutral; `review-dependency` (a `read` skill in
[patch output mode](pr-run-activity.md#patch-output-mode), on run-claude-cli with the
subscription fallback) returns its verdict as structured output and leaves a fix as a patch;
`apply-dependency-patch` (a script, `mutate-branch`) pushes that patch only on a scanned `fix`
verdict; and `apply-dependency-verdict` (a script, `publish-artifact`) acts on the verdict and
never merges; the pr-merge lane merges on its `verdict=merge` marker at the current head
([`pr-run-activity.md`](pr-run-activity.md#prepare-dependency-review);
[ADR 0074](../../adr/0074-review-risky-dependabot-updates-in-a-model-job-and-act-in-a-scripted-job.md)).
When the head's `package.json` approves the `@anthropic-ai/claude-code` install script
(`allowScripts`) for a version other than the one its `package-lock.json` installs,
`review-dependency-select` writes the patch that moves that one pin to the lockfile's version,
when it is also the exact version the manifest pins, instead of a model turn
([`install-script-pin.mjs`](../../../.github/scripts/pr-unblock/install-script-pin.mjs)), and
`apply-dependency-pin` pushes it with `apply-dependency-patch`'s grant under the
`install-script-pin` row, which checks the pin against the manifest's version as Dependabot set
it, not the lockfile; it posts no round marker, and the new head is reviewed as any other.
`check-catalog` fails `ci-status` while the pin and the lockfile disagree, so a Dependabot bump
of the CLI sorts `review` and reaches this step.

`pr-unblock`'s `fix-ci` runs in separate jobs of `pr-unblock.yml`, so no model holds a write token:
`fix-ci-context` (base code only, read-only token) writes the failing checks' context or hands
the pull request to a person once `loop.fix-ci-rounds` fixes were pushed; `fix-ci` (a `read`
skill in [patch output mode](pr-run-activity.md#patch-output-mode), on run-claude-cli with the
pr-unblock role's API key) runs `source-control:pull-request ci --ci`, which reruns, fixes and
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
unappliable patch goes to `report-escalation`, as does a run that changed nothing and escalated a
check. A patch that pushed escalates nothing, whatever the model escalated beside it: the new
head's CI decides, and a red new head gets its own run. The one exception: a run at
`model-rung` 0 that changed nothing and escalated only `unfixed` or `not-reproducible` checks skips `apply-patch` with `rung-up`, and the same `pr-unblock` run
runs `fix-ci` and `apply-patch` once more at `model-rung` 1 (`fix-ci-rung-up`,
`fix-ci-rung-up-subscription`, `apply-patch-rung-up`; [Models](#models)). The retry posts its own
`pr-unblock / fix-ci` check, which the dispatcher counts toward fix-ci's per-head cap (`maxRunsPerHead`) like
any other run, so that cap bounds rung-ups on a head too. `report-escalation`
ends the run unless that retry's patch applied cleanly: the retry's own reason, else
`ci-fix-escalated` (a neutral or failed retry), each routed to a failing `pr-unblock/fix-ci`
status; `ci-fix-escalated`, `ci-fix-protected-path` and `ci-fix-weaken-required` (a check the
rung-up retry could not fix, or one the model could fix only through a path the lane token may not
push or by weakening a required check) also queue the PR with `needs-session` for a session
builder, while the dispatcher's same-head retry still runs: the session that finds the head green
or lands the fix removes the label; no lane removes it. A cancelled run applies no label: the write
workflow's `run` job has no status function in its `if:`, so it skips on a cancel, nothing
pushes and `ci-status` stays red. In a run that changed nothing, `protected-path` goes to the
`needs-session` queue (a failing status and the label) and `flaky` to a failing status, both
without a rung-up. `weaken-required` on the head's first
fix-ci attempt stops `ci-fix-weaken-retry` instead, a failing status: the dispatcher retries the
head once at `model-rung` 1, a fresh fixer round whose context carries a fixed brief (fix the
code under test and keep every test's assertions and expected values). A
`weaken-required` in that round, or after any earlier attempt on the head, stops
`ci-fix-weaken-required` for a session builder; the guard itself is unchanged. Beside a pushed
patch, the new head's
CI decides for all of them. The same
`pr-unblock-dispatch.yml` run starts `fix-ci`, after the conflict and Dependabot dispatches: one
GraphQL query per page of 50 open pull requests, its `rateLimit.cost` logged, lists the non-draft,
same-repository ones into `main` that the lanes App opened (by bot id), or that a trusted actor
opened ([`adoption`](#adoption); a person's once idle), with no `do-not-merge`, `needs-human` or tracker
human-gated label (one another lane's escalation put on aside, as above),
whose head's `ci-lanes` commit status from `github-actions[bot]` is `failure` or `error`: the lanes'
verdict ci-status records, not ci-status itself, which also fails on a hold, a pending review or the
PR contract, none of which a CI fix mends. It dispatches those whose head has no `pr-unblock / fix-ci` run yet (an
untrusted-trigger skip or a skip while held aside), or only failed ones and `Skipped: not-applicable`
or `Skipped: stop-resolved` ones (no failing check found), fewer than `limits.limit-stops-per-head`
of them, and since the base tip was committed (the same query reads it) no such skip and at most
`limits.fix-ci-restarts` failed ones; a new head starts with none. No `fix-ci` run for the PR may
still be queued or going, and it sends at most `limits.fix-ci-per-run` per run,
lowest number first. Their run ids join the dispatched-runs record. The dispatcher job's
concurrency group cancels a run in progress, so a burst of pushes ends in one listing.

`pr-refine`'s `fix-docs` runs the same way in three jobs of `pr-refine.yml`: `fix-docs` (a
`read` skill in patch output mode with no prepare mode, on run-claude-cli with the pr-unblock
role's API key) runs `ai-slop:audit fix` on the PR's changed Markdown files;
`fix-docs-subscription` runs the same on the role's OAuth token, only when `fix-docs-handoff`'s
read of this run's jobs shows the broker allowed `fix-docs` and `fix-docs` posted no check, as a
credit stop or an empty key leaves it; and `apply-docs-patch` runs the `apply-patch` activity on a `written` patch,
pushing it as one commit under `patch-rules.json`'s `docs` row (`patch-prepare: docs`), which
admits only markdown and refuses the universal set, any path under a `skills/` directory, any
`SKILL.md` and more than 300 paths. No change is the common case, so an
`empty` patch runs no push job. `pr-refine.yml` has no escalation job: a refused or
unappliable patch posts the `pr-refine / apply-patch` check neutral `awaiting-human` and labels
nothing. Every job trusts the default branch tip (`trusted-base: default-tip`). `fix-docs` routes
to the `docs-fix` profile ([Models](#models)).

CI `fix-docs` runs on every pull request not tidied in its own run
([ADR 0089](../../adr/0089-narrow-d100-to-pull-requests-tidied-in-their-own-run.md)). The skip
reads the base config's tidy cutoffs when it dispatches, not the ones the lane run used.
`limits.fix-docs-per-run` is `2` here; each event offers one pull request, so any value from `1`
up turns its dispatch on. At `0` the dispatcher logs
`fix-docs is off (fix-docs-per-run: 0)`, sends nothing and makes no GitHub call for it.

Only `pr-unblock-dispatch.yml`'s `refine` job dispatches `pr-refine.yml`'s `fix-docs`, on the
pull request's own `pull_request_target` event (`refine-event-dispatch.mjs`); a push to the
default branch, the half-hourly tick and a hand run of the dispatcher start none. It dispatches
once per pull request: one GraphQL query, its `rateLimit.cost` logged, reads that pull request,
and it keeps it when it is a non-draft, same-repository one into `main` whose event the lanes App or a listed human
sent (a pull request whose events come only from other senders gets no fix-docs), except Dependabot (account
49699333, whose own rebases a lane commit stops), the release App (337859524) and the
standards-sync App (300666570), whose files are generated or synced, and `work-resolve-issue`
PRs tidied in their own run (within the tidy cutoffs): the lanes App's on a lane branch
(`work-resolve-issue/issue-<n>-<run>-<attempt>`) whose one commit is the App's API
commit (a valid signature, the App as author, GitHub as committer), and whose change is within
`resolve-issue`'s `tidy.cutoffs` in the base config, read from the PR's file count, added plus
removed lines, changed paths and their areas as the [`tidy` entry](#activities) defines them. A
lane PR with any other commit (a later push its tidy never saw), over any cutoff, or whose file
list is cut off, was not tidied and is kept, and so are the lanes
App's other PRs and a person's PR on a branch with a lane name. An author with no account id is
skipped. It keeps
one with no `do-not-merge` or `needs-human`
label (a lane escalation's aside, as above), that changes at least one `.md` file, and whose head has no `pr-refine / fix-docs` or
`pr-unblock / fix-docs` (the lane `fix-docs` ran in before) check run from the GitHub Actions
app. One
more query reads the check runs on its last 50 commits, and a PR with a `fix-docs` run on any of
them is skipped for good. A
run older than 50 commits, or a force-push that dropped its commit, costs one more run. It sends
none for a PR whose `fix-docs` run is still queued or going, and the run id joins the
dispatched-run record. A PR this run skips (a read that failed, a sender neither the lanes App
nor a listed human, a re-run) waits for its next event.

A `fix-docs` run whose run job emits an empty head posts no check (`post-decline: false`). The
event dispatcher reads and saves no dispatch record, so the per-head cap of
`limits.limit-stops-per-head` broker-allowed runs that posted no check holds only within one
run, where it never binds: each event starts at most one run, and a new head arrives as a new
event.

A completed `fix-docs` run ends the PR too, check or not, unless it says nothing about the PR. One
lost run gets another dispatch. So do fewer than `limits.limit-stops-per-head` runs that went red or
held on a failed `handoff-evidence.sh` read or an unread PR head, the PR's next event being the probe: red
alone cannot tell a read that failed from a broker that refused, so the count is what ends a
refusal, and an outage past that many runs still ends the PR. A held run ends green, so the
dispatcher reads the jobs of each green run it finds for a candidate: a leg that handed off, whose
handoff job succeeded, with no next leg started, is a held run, and so is a run whose
`fix-docs-head-held` job succeeded, which runs only when `fix-docs-head` could not read the head
or the human-gated hold, or the plan could not read the changed files. A
run whose jobs cannot be read holds the PR for its next event.

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
- Runs Claude Code with `--permission-mode dontAsk` and the tools its skill needs to do its job,
  always in the read runner with no GitHub token: a skill's effect is `read`, and the config
  reader refuses any other. Its change reaches the branch only through a script activity
  ([`pr-run-activity.md`](pr-run-activity.md#skill-activities)), which gets the write access its
  job needs through a short-lived, job-scoped App token, revoked when the job ends. Local lanes keep
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
  ([loop-lane](../../contracts/loop-lane/README.md#cross-lane-pr-hold)), and the merge rule in AGENTS.md. A lane
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
  flags fixed, that the skill may run. The read runner gives a skill that hands on a patch its edit
  tools and runs each from the base copy
  against the checkout, so no head code runs, and tells the skill to fix what
  a check reports before it reports done
  ([`pr-run-activity.md`](pr-run-activity.md#skill-activities)). The schema refuses `checks`,
  `self-checks`, `verify-scripts` and `web-access` turned on for any other skill (one
  without `applied-by.patch`, or with `prepare: ci-context`), where they would do nothing, except
  `verify-scripts` under `prepare: ci-context`, which the read runner stages as a base copy the
  skill is told to run in place of the checkout's; its Bash, Edit and Write stay open, so review
  of the patch is the control.
- `self-checks` (optional, `skill` only): the same shape as `checks`, run and fixed by the skill
  through the same wrapper before it commits or hands its change on. Advisory: unlike `checks`, no
  runner job reruns them, so a failure the skill cannot fix still opens the PR and is named in its
  report. A script in both lists fails red.
- `verify-scripts` (optional, `skill` only): exact repository-relative paths of scripts, each `scripts/<name>.sh`, `plugins/<plugin>/scripts/<name>.sh` or
  `plugins/<plugin>/skills/<skill>/scripts/<name>.sh`, that the skill may run with any arguments
  but a path outside the checkout. The runner that gives the skill its edit tools runs each from a read-only base copy of its plugin (or of `scripts/`) against
  the checkout, with `GH_TOKEN` and `GITHUB_TOKEN` unset. No Bash process above it holds
  the token either: the read runner's run-claude-cli steps set neither token ([`pr-run-activity.md`](pr-run-activity.md#skill-activities)). The arguments are the model's, so
  a script that changes files, runs code from the checkout or reaches the network hands the run
  that power: list one only when it limits itself, as `scripts/run-test-file.sh` (one test file
  inside the checkout), `scripts/git-mv-rm.sh` (`git mv` and `git rm` inside the checkout) and
  `scripts/new-changelog-fragment.sh` (new files under the checkout's `.changes/` only) do,
  or when the run may hold that power, as `plugins/skill-quality/scripts/check-skill.sh` (each
  checked skill's `scripts/*.test.sh` and the checkout's markdownlint) does. Those two run checkout
  code, which the read runner's run job may, since it holds neither the lane token nor
  `id-token: write`.
- `web-access` (optional, `skill` only, off when absent): `enabled` and `domains`, either `any` or
  a list of host names (`*.` allowed as a prefix). When on, the skill may search the web, fetch
  those domains, and run the research skills, wherever the runner gives it its edit tools
  ([`pr-run-activity.md`](pr-run-activity.md#skill-activities)). An activity that turns it on must
  set `reads-untrusted: true`.
- `tidy` (optional, `skill` only, off when absent): the run tidies its own change before its last
  check run. `entry` is the diff-scoped tidy skill, `passes` the other quality skills it may call,
  `turn-share` the percent of the run's turn cap tidy may spend (at the cap the passes left are
  skipped and the change is handed on; tidy never fails the run), and `cutoffs` the one named
  value that decides whether a change is small and single-area enough to tidy in the run:
  `max-files`, `max-lines` (added plus removed), `max-areas` (`plugins/<name>` with its
  `.changes/<name>`, `docs/<dir>`, else the top-level segment) and `shared-paths` (a directory
  ends in `/`). The runner allows the entry and the passes and no other skill. The schema takes
  it only on a `read` skill whose `applied-by` sets `patch` with no `prepare`, and the launcher
  stage only for an issue lane ([`pr-run-activity.md`](pr-run-activity.md#issue-mode)).
- `permission-mode` (optional, `skill` only): `dontAsk` (the default) or `auto`, the Claude Code
  permission mode of a PR-mode skill on the read runner's launcher; other runners run `dontAsk`.
  The run job fails red unless the CLI reports the mode asked for
  ([`pr-run-activity.md`](pr-run-activity.md#two-calls-on-one-credential-each);
  [ADR 0049](../../adr/0049-run-ci-lanes-on-github-hosted-runners-under-trigger-and-token-hardening.md)).
- `effect`: one of `read`, `mutate-branch`, `mutate-tracker`, `mutate-variable`,
  `publish-artifact`, `merge`. `mutate-variable` reads every scope and writes only what its
  lane's `activity-grants` row in `lane-rules.json` adds: repository Variables write, which the
  token broker grants to work-unblock's `publish-lane-level` alone (owner decision Q113 (a)). The
  runner derives ordering from it, takes the token grant from
  [`effect-grants.json`](../../../.github/actions/resolve-config/effect-grants.json), and fails a
  `read` activity that leaves the working tree dirty unless it hands its change on as a patch. A
  skill's effect is always `read`: the schema and the config reader refuse any other, so no model
  runs beside the lane token. An activity that runs head code (tests, linters, builds) takes effect
  `read`, because a write-effect activity must not execute head code. To change the branch it hands its change on
  to a `prepare: apply-patch` script with no model and no head code, named in its
  `applied-by.patch`, as fix-docs and fix-ci do with `apply-patch`.
- `gating`: `gate` feeds `ci-status`; `advisory` is reported only. `ci-status` stays the only
  required check. Tests, linters and builds that gate run as a `script` activity or under a
  separate design.
- `reads-untrusted`: whether it reads issue, PR, comment, web or CI-log text, or PR head files,
  which can quote such text. Ingested text is data, never instructions
  ([`untrusted-content`](../../contracts/untrusted-content/README.md)).
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
- `scope` (`diff`, `tree`, `target`) and `applies-when` (paths, labels, `labels-absent`, events,
  `mergeable`, `draft`). `mergeable` is `conflicting` or `clean`, read from the PR at the gated
  head SHA only; unknown mergeability never matches. `labels-absent` matches only when none of its
  labels is on the PR. No predicate reads a work class: on an issues lane the triggering label
  alone admits the issue, so `agent-ready` added by a listed human or the lanes App admits, and
  resolve-issue's `labels-absent` holds keep an issue a person must decide.

An activity is idempotent: a rerun on the same commit gives the same verdict or reuses it, a
mutating activity with nothing to change makes no commit, and each commit it makes names the
activity in a trailer. A verdict is bound to the commit it judged and is not reused for any other commit.

A `pr-unblock` run that stops ends on the route
[`escalation-routes.json`](../../../.github/scripts/pr-unblock/escalation-routes.json), the one
routing table, gives its reason; `report-escalation.sh` reads it. Route `hold` is only for the
owner's three reasons
([When work stops for the owner](../loop-lane/README.md#when-work-stops-for-the-owner)): an intent
or design question the work item contract does not settle, a person's own thread or hold, a CRITICAL security risk (a security
question, a finding no adjudicator may judge: a CRITICAL one, or a security-review one with no
rating it reads; a security-review `IMPORTANT` or `SUGGESTION` is adjudicated like a code-review
finding, owner decision on [#11020](https://github.com/melodic-software/claude-code-plugins/issues/11020#issuecomment-6534933426); a Dependabot security update the review would close, a risk the dependency
review raised, or a commit on a Dependabot branch from anyone but Dependabot). A reason the table
does not list holds too, with no activity to resume. The adjudicator settles an intent or design
question for the reviewer itself when it quotes a line of the linked issues' spec text, the text
pr-verify reads (`resolve-pr.mjs` `linkedIssues`), staged as `contract.json`: the script keeps the
quote only when it is an exact substring of that text, at least 20 characters, and the reply
quotes it with the issue's URL; the finding stands and the next round fixes it. A quote shows the
text exists, not that it bears on the finding, so it never dismisses one: a `lane` verdict on an
intent or design question goes to a person. A quote that fails the check, or no spec text, leaves
the question a person's; a
security question, a CRITICAL finding and an unrated security-review one never
settle by quote. Every other reason routes `fail`. A `fail`
entry that names `"label": "needs-session"` is a change the lane cannot make: a path its token may
not push, a fix that weakens a required check after its fresh fixer round, a failing check the
`fix-ci` rung-up retry could not fix, or a dependency update
the review could not finish (its cap, an unlanded fix, an unreadable config, a cut-short listing,
an uncited control, a workflow change beyond a pin swap), or a review thread the lane left open
that no lane or verdict will settle (`feedback-untaken-threads`, `feedback-unadjudicated`; while
that stop stands on the head, `address-feedback`'s select job skips `awaiting-session` instead of
escalating again). `review-dependency` and
`apply-dependency-patch` do not apply while `needs-session` is on (their `labels-absent` in
`pr-pipeline.yaml`), so such a stop gets no same-head model re-run and no fresh round budget on a
rebased head until a session removes the label, or `clear-escalations.mjs` does: once a same-head
retry cleared the stop's failing status, or once the head moved off every such stop's head and the
new head carries no failing status for their activities and passes its checks (`ci-status` aside,
which the label keeps red). A `dependency-workflow-unpinned` stop is lifted only on its own head,
since green checks do not judge a workflow change. If the cause holds, the lane stops again on the
new head and labels it again. It also puts the PR in the
session-builder queue with that label, which no merge gate reads, so a session builder makes the
change instead of a person; a person arms it only where the merge gate already asks for one. Every
other reason is a defect the lane's bounded retries (the
`fix-ci` rung-up, the adjudicator, the round, repeat and per-head caps) did not mend, routed `fail`:
no human-gated label (an entry naming `"label": "needs-session"` adds that label first, the
session-builder queue, which no merge gate reads), a failing commit status on the head the activity gated (`pr-unblock/conflict` for
`resolve-conflicts`, `pr-unblock/<activity>` otherwise; `report-stop-status` posts it, except for a
`feedback-publish-failed` whose lane token was refused as workflow-modified, which the feedback
sweep sends again; a transient broker refusal still posts it, since pr-merge's re-fire skips some
PRs), and one
lanes App comment per activity (marked `<!-- pr-unblock:lane-stopped activity=<activity> -->`,
naming the run) that the next stop edits in place; when `report-stop-status` withholds the status,
`report-escalation` posts no comment either. The stopping job's check skips `lane-stopped`.
`workflow-staged` routes `fail` as a capability limit: the merge carries the PR's own
`.github/workflows/` changes together with the base's, which the lane token cannot push, and
nothing in it is a person's decision, so a session merges main by hand.
A select job's stop (a cap, or a conflict no model can resolve) is final for its head. A stop
after a model turn (the push, reply or verdict job's) is retried on the same head by the
activity's dispatcher, under the cap it already keeps: `limit-stops-per-head` for
`resolve-conflicts`, `fix-ci-restarts` and the per-head cap for `fix-ci`,
`SWEEP_HEAD_CAP` for `address-feedback`. A `fix-ci` or `address-feedback` retry runs one model
rung up (`escalate-to`), read in the run from the head's own stop record, never from a dispatch
input; the others retry as a fresh session. A retry that acts and does not stop posts success over the
failing status (`report-escalation.sh clear`); one that ends on a skip, such as a reply job with no
model turn, leaves it. A select job that finds the stop gone on its head also posts success
and skips `stop-resolved`: `address-feedback` once no hold and no unresolved review thread is left,
`fix-ci` once a whole listing of the head's checks, every one completed, has none failing (round
cap included). So a thread resolved by hand, or CI fixed by hand or re-run green, frees the same
head at the next dispatch of that activity (the one the lane-stopped comment gives); on a lanes App
pull request the dispatchers above start it once per stop, on any other a person does, and a `ci-status` that already failed stays failed until something
re-runs it (the next review lane's `rerun-ci-status`, or a person). Once the retries are spent, and
until a `stop-resolved` skip ends the stop, the monitoring lane's
`stalled lane stop` signal names the PR. A new head carries no status, so the lane's next run
there starts clean.

When an activity needs a human, it escalates with a resume key and exits instead of blocking. An
activity whose `labels-absent` lists `needs-human` or `do-not-merge` skips with `awaiting-human`
while that label is on the PR; a human removes the label, then dispatches the lane, to resume it
(the `pr-unblock-dispatch.yml` dispatchers pick a held `resolve-conflicts` or `fix-ci` PR up
themselves once the label is off; a held `fix-docs` PR waits for its next push, reopen or ready
flip, the events its `refine` job runs on).
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
| `workflow-staged` (a label set before it routed `fail`) | main changes nothing under `.github/workflows/` since its merge base with the head; or a trusted move (below) took the head off the resume key and the head contains main as it was when the lane escalated |
| `unresolved-conflict`, `protected-path-conflict` | GitHub reports the PR mergeable |
| `ci-fix-round-cap`, `ci-fix-empty`, `ci-fix-invalid`, `ci-fix-not-applied`, `ci-fix-escalated` | a trusted move took the head off the resume key, and at the new head no check other than `ci-status` (which the label itself fails) fails, runs or was cancelled, the latest run of each ended `success`, `neutral` or `skipped`, and one passed |
| `feedback-protected-path` | the PR changes nothing under `.github/workflows/` |
| `feedback-not-landed` | the head is none of its escalations' resume keys, and no unresolved review thread carries a lanes App comment; a thread listing that may be cut short keeps the label (owner decision 2026-10-25). Then either a trusted move (below) took the head there, or, after a push no trusted person made (the lanes App's own included), at the current head both review lanes (`claude-review` and `claude-security-review`) have a newest run that completed successfully with a review-complete record for this head, the security review is a whole review whose summary reports `critical-findings: 0`, and no unresolved review thread carries a CRITICAL or unreadable severity (an `IMPORTANT` one is reported, not held). A lanes App push alone never clears it |
| a reason `escalation-routes.json` routes `fail`, on a label set before it did | a `ci-fix-*` reason once a lane check of a `pr-require-checks.yml` run on the current head reads failed (`ci-status` itself fails on the label, so it is not read, and an advisory lane such as `pr-test-platforms` does not count; green, missing or unreadable keeps the label). Any other fail-routed reason but `feedback-not-landed` stays for a person: a lane posts a `pr-unblock/*` status on a head only when it stops there or clears its own failure, so a new head carries nothing that shows the cause gone or fails that head in the label's place |
| `head-moved` (pr-merge's `babysit-merge-verify-escalation`, `babysit-merge-risk` and `babysit-merge-shared-copy-escalation`, with no pr-unblock escalation since the label, and the marked App comment written last before the label is pr-merge's and within a minute of it) | the newest App comment carrying each marker names, as ``at head `<sha>` ``, a 40-hex head other than the current one; pr-merge then judges the new head and escalates again if its refusal still holds |
| `refusal-cleared` (under `merge.lane-prs: native`, `enable-auto-merge`'s own unedited person refusal comment on a lanes App pull request, naming the current head, whose recorded verifier or risk cause is one the lanes clear: every code on `LANE_CAUSES`) | the gate's reader at that head finds nothing refusing, or only causes the lanes clear, read at least as far as the recorded one. A recorded cause a person clears (an issue link, a security finding, a trust-gate widening, a cost hold, an untrusted spec, any code off that list) is never read or lifted at its head (owner decision Q-CLEAR B): a person removes the label, or the `head-moved` clear does once the head moves. At most three reader runs a run |
| `stale-review-hold` (a label a review lane added, every hold comment since it was last removed naming an earlier head) | a trusted move took the branch off the newest held head, and one of the pull request's own commits since each held head (not reachable from `main`, so an `Update branch` brings in none) is not a merge; both review lanes passed on the current head with a whole review each (status job succeeded, review-complete notice and no hold notice for it, and the head changes neither review caller); no lane leaves a CRITICAL finding (`critical-findings: 0` from the security lane, every finding inline for the security lane and any lane a hold names, no unresolved lane thread at `CRITICAL`, nor one with no one readable severity from those strict lanes; an `IMPORTANT` thread is reported and keeps nothing); and a `critical-security` hold's lane left at least one `CRITICAL` inline finding at the held head, each in a file one of those commits changed (a finding only the summary carried stays for a person). The head and the hold comments are read again just before the removal. A lane that still finds the cause holds the new head again. `ci-status` counts the lanes App's removal only after its own newest `stale-review-hold` comment names a head no hold comment names, while none names the event's head (hold comments counted from the label's last removal before it went on), and only when the base commit's `recheckStaleHold` (the same predicate) passes again with the job's own token at the head the comment names, as it was when the App removed the label, including the check-signed-commits hold, other lanes App markers and a person speaking up to the removal; a later head is judged by its own review lanes, as after a person's lift |

It removes only a label whose newest `labeled` event has the lanes App, or for `stale-review-hold` a
review lane, as its actor, and keeps it
when a person commented, reviewed or left a review comment since that event (a bot account, such
as an AI review or another lane, does not count), or when an App comment
written or edited since then carries any marker other than the escalation being judged (another
`babysit-merge-*` marker, another lane's). A trusted move is read with the job's own token, never
from comment text: the PR head is in this repository, every push on its branch since the label went
on is by a `human` of the base `trusted-actors.json` (matched by id; never the lanes App, so its
own push never lifts its own stop), the newest one landed the current head, and the head is none of the recorded resume keys. A
read that fails keeps the label. Every other reason waits for a person: the security, intent and
decision stops (`feedback-uncertain`, `feedback-disputed`, `feedback-unadjudicated`,
`feedback-question-*`, `feedback-round-cap`, `feedback-not-converging`, `dependency-security-close`,
`dependency-escalate` and `dependency-escalate-<owner reason>`), the protected-path and own-patch stops (`ci-fix-protected-path`,
`unexpected-path-staged`, `conflict-patch-*`), and those with no cause-gone evidence yet (`repeat-cap`,
`feedback-invalid`, `feedback-partial`, `feedback-incomplete`, and the other
`dependency-*` stops). Removing the label this way approves nothing: `ci-status` still fails a
review-lane hold the lanes App unlabeled, and hold paths still need a trusted person's approving
review. Rules: `.github/scripts/pr-merge/clear-escalations.mjs`.

Accepted risk: a person's request relayed through an App posts as a Bot account (`claude[bot]`
replying to an `@claude` mention that asks to wait), and so does a third-party App writing "needs
a human"; neither keeps the label. A person who wants the hold comments themselves or adds the
label back.

## Patch rules

[`patch-rules.json`](../../../.github/actions/resolve-config/patch-rules.json) is the registry
of what one `prepare: apply-patch` script is to admit from a producer's patch, read from the
trusted base: one row per prepare mode a patch-producing skill uses (`ci-context`,
`review-threads`, `dependency-review`, `merge-base`), `install-script-pin` for the pin patch
`review-dependency-select` writes with no model, `docs` for a push job that passes
`patch-prepare: docs` to hold a patch to markdown (fix-docs's `apply-docs-patch`), `default` for
one with no prepare mode, and
`issue` for a patch that goes to a new issue-lane branch made at the run's base or resume tip.
[`apply-patch.mjs`](../../../.github/scripts/apply-patch/apply-patch.mjs) reads it for fix-ci's,
fix-docs's, resolve-conflicts's, address-feedback's, review-dependency's and resolve-issue's patches ([`prepare: apply-patch`](pr-run-activity.md#prepare-apply-patch)).
[`patch-rules.schema.json`](../../../.github/actions/resolve-config/patch-rules.schema.json) closes
each row to these keys:

| Key | Holds |
|---|---|
| `refuse` | Named refusals; any match refuses the whole patch. |
| `allow` | What every other changed path must also meet: `any`, `markdown` (a path ending in `.md`, in that case), `kept-threads` (a path in the scope of a thread the select job kept, its `named_paths` included, a file the pull request already changes or a shared copy of a canonical it changes that the patch does not add, its `pr_paths` and `copy_paths`, read from that job's thread file, or any non-instruction file under a plugin's or skill's `evals/` or in a plugin a kept thread or `pr_paths` file sits in), `dependency-manifests` (an npm or pip manifest or lock file outside `.github/` in a directory the base `.github/dependabot.yml` lists for its ecosystem) or `merge-result` (a path the base merge left conflicted; under a merge row only the patch's own changes, measured from the conflict tree, face the rules, every conflicted path left in the tree must hold no conflict markers, and the merge's base-side changes pass through). |
| `max-files` | The most paths one patch may change, or `null`. |
| `max-blobs` | Merge rows only: the most blobs one merge commit may upload, each one neither the head nor the base holds at its path; over it nothing is written. |
| `requires` | What the producer's output must say before anything applies: `dependency-verdict: fix`, the scanned verdict's field. |
| `content-rule` | Optional; what each changed file's bytes must also meet, on the local blobs before any commit is built, escalating as `protected-path`: `dependency-version-change` (`dependency-review`: modified in place, a regular file, changed only by a version, `fixRefusal` in `dependency-classify.mjs`), `install-script-pin` (`install-script-pin`: the root `package.json` alone, under `dependency-version-change`, with one `allowScripts` install-script pin moved to the exact version the manifest pins, unchanged from the commit before the patch, and nothing else, `installScriptPinRefusal`) or `pr-mode-revert` (`review-threads`: a file whose mode changes between `100644` and `100755` takes the mode its path has at the merge base of the PR head and its base, read through the GitHub API, so the lane can only revert a mode the pull request introduced). `protected-content` (`docs`) refuses nothing and leaves content out instead, after every other check passes on the whole patch: see the `docs` row below. |
| `commit` | `parents` (`[head]`, or `[head, base]` for a merge), `message` and `trailer`, with `{ref}`, `{base}`, `{lane}`, `{activity}` and `{issue}` filled in. |
| `thread-trailer` | Optional; `true` (`review-threads`, a `kept-threads` row only) adds after the trailer a `Lane-Thread: <thread id>` line for each kept thread a `VALID` reply in the model job's scanned replies names, the binding `publish-feedback.mjs` requires before it credits the commit to a thread; with no replies read, nothing is committed. |
| `reads-report` | The producer report the apply reads (`ci-escalations`: the checks the model escalated), or `null`. |
| `empty-at-push` | Optional; the kind a patch that applies but changes nothing escalates at push time: `empty` (the default), `invalid` (`ci-context`, as the producer said it wrote a change) or `conflict` (`merge-base`: its `unresolved-conflict` reason, since the conflicts stay as git left them). |
| `skip-moved-head` | Optional, default `false`; `true` (`ci-context`, `review-threads`, `dependency-review`, `merge-base`) skips `superseded-sha` on any PR head that moved since the producer ran, where other rows take the moved tip with `--3way` when the moved commits touch no patched path. `default` and `docs` set `false`: fix-docs runs once per pull request, so a skipped fix-docs patch would never run again. |
| `script-exec-bit` | Optional, default `false`; `true` (`issue`) makes each new or changed file that ends in `.sh` or starts with `#!` executable after every refusal passes, since the model's tools set no file mode. |
| `escalations` | The escalation reasons the apply may give for the row. |

Every row refuses `.github/workflows/**` in any case and through any `..` segment (the lane
token has no `workflows` permission), `CODEOWNERS` at the root, in `.github/` or in `docs/`,
`.gitmodules`, `**/settings*.json`, the central lane grant file
([`lane-grants.json`](../../../.github/actions/resolve-config/lane-grants.json)) and the
trusted-actor list (`.github/standards/trusted-actors/trusted-actors.json`) in any case and through
any `..` segment (`lane-grants`: they decide what every admitted repository's lanes may mint and
who may start them, [ADR 0085](../../adr/0085-run-org-lanes-from-ci-workflows-under-one-lanes-app-with-central-grants.md)
Decision 6), a symbolic link, a gitlink, and a rename into any of those.
The rest of `.github/`, `.claude/` and `.mcp.json` (outside the `issue` row, below), plugin hooks,
`.claude-plugin/`, `lib/`, `scripts/`, `CLAUDE.md`, `AGENTS.md` and an executable bit reach review,
and merge on it: only the
narrow [path floor](#merge-authority) (`resolve-config`, whose code the token broker runs from
main, `request-lane-token`, the trusted-trigger check, `check-kill-switch`, the rate guard,
`CODEOWNERS`, `.gitmodules` and the merge gate's own code; the other files that enforce the floor
wait for a clean security review instead) waits for a person, and the
security lane judges the rest. The `docs` row also refuses, in any case and through
any `..` segment, a path under a `skills/` directory at any depth (`skills`) and a `SKILL.md`
anywhere (`skill-md`), and allows only `markdown`, so a non-markdown path escalates
`patch-protected-path`. Its `protected-content` content rule keeps fix-docs out of content a
generator or the release tooling owns, and because fix-docs runs once per pull request it drops
that content rather than refusing the patch. It reads git's own `-U0` hunks of each file and
leaves out every hunk whose head lines meet a generated region (a standalone
`<!-- BEGIN GENERATED: ... -->` line through its `<!-- END GENERATED: ... -->` line, the marker
lines included), that inserts lines between a BEGIN and its END, or that writes a marker line; an
insertion right before a BEGIN line or right after an END line is outside the region and kept, as
is every other hunk. The whole change to a file, its mode included, is left out when the file sits
in the `released` or `historical` tier of [`docs-naming.yaml`](../docs-naming.yaml)
(`**/CHANGELOG.md`; `docs/adr/**`, `docs/upstream/**`, `.claude/unhobble/**`), when the patch
deletes a file whose head holds a region (a rename, read as a deletion and an addition, so leaves
the file at its old path), when its markers do not pair in the head or the patched blob, or when
the kept or rebuilt blob's regions would not be the head's byte for byte; a mode change to any
other file is kept. Each dropped hunk or file prints a
`::warning` naming the file and, for a hunk, the generator its region's BEGIN line names, so the
fix goes to the generator's inputs. A patch left with no change pushes nothing, escalates nothing
and skips `not-applicable`. The row otherwise matches `default`. No other row names those two refusals or that
rule, and none has to. The `review-threads` row alone also refuses a new file at mode `100755` or a
change to that mode (`new-exec-bit`), so address-feedback can drop an executable bit but never
add one; `ci-context` and `issue` keep setting script bits. The `ci-context` and `review-threads`
rows also refuse, in any case and through any `..` segment, a `.gitattributes` file at any depth
(`gitattributes`), a path whose first segment is `.husky` (`husky`) and every file lefthook reads
its config or hook scripts from (`lefthook`): at the root, `lefthook`, `.lefthook`, `lefthook-local`
and `.lefthook-local` with `.yml`, `.yaml`, `.toml`, `.json` or `.jsonc`; under a root `.config/`,
`lefthook` and `lefthook-local` with those extensions; and a path whose first segment is `.lefthook`
or `.lefthook-local`. Each changes what git, or a hook it runs, does on the next checkout or commit,
so fix-ci and address-feedback cannot change them. No other row names these three.
The `issue` row alone also refuses (`claude-protected`), at any depth, every path Claude Code
denies writes to under the lanes' `dontAsk` permission mode
([protected paths](https://code.claude.com/docs/en/permission-modes#protected-paths)) except
`.gitmodules`, which has its own refusal (`gitmodules`): its run can never write one, so a run
whose change needs one stops with `patch-protected-path`. No other row names `claude-protected`,
and a rename into such a path is not `rename-into-refused`.
The `ci-context`, `docs`, `default`, `issue` and `merge-base` rows cap a patch at 300 paths, and the
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

`refine`'s plan groups its passes into batches by `order` and `group`
([Refine before review](#refine-before-review)); a format pass takes the highest `order` and
`group: serial`, because earlier passes change whitespace, and its first job waits on the earlier
batches.
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

The reader adds no path to `merge.diff-check.denied-paths`: it resolves the config's own list,
each entry once.

## Concurrency

| Scope | Rule | Set by |
|---|---|---|
| Triggers of one PR's `pr-unblock` activity | A newer dispatch replaces one still waiting; a running one finishes | workflow group `pr-unblock-<activity>-<n>`, `cancel-in-progress: false` |
| Within one run | Leaves run in slot order: `publish-feedback` after `address-feedback` once its skill ran; `report-escalation` after the others, and only when one escalated | the caller's `needs:` |
| Across PRs | Unbounded: every group is per PR | group names |
| Within one PR, across write lanes | One queue: a write job waits for the one ahead and never cancels it | job group `pr-pipeline-write-<n>`, `queue: max`, on every write caller job |
| `pr-unblock-dispatch` | One run at a time; a push cancels the run going, and a tick or hand run waits behind it; any newer run replaces one still waiting | workflow group `pr-unblock-dispatch`, `cancel-in-progress: ${{ github.event_name == 'push' }}` |
| `pr-feedback-dispatch` | One run per group at a time: one per pr-verify run, one for all sweeps, and one per reviewed head otherwise; waiting runs queue and none is replaced | workflow group `pr-feedback-dispatch-verify-<run id>`, `-sweep` or `-<head SHA>`, `queue: max` |
| `pr-merge` `enable-auto-merge`, across PRs | One run at a time, sweeps and verdict wakes alike, since the lane-room check is not re-read after arming; none is cancelled, and a waiting sweep, or a newer wake for the same PR, does a wake's work. At the measured peak of 31 `pr-verify` completions in 15 minutes, all of them wakes, the job's 44-minute ceiling queues about 91, under GitHub's cap of 100; a run past the cap leaves its PR to the next scheduled run | job group `pr-merge-enable-auto-merge`, `queue: max` |

The write group sits on each caller job, behind an `if:` that leaves out the lanes App's own
`pull_request` events, so a lane's push never queues a job in it.

## Outputs and skips

Each leaf reports:

- A verdict: `pass`, `fail`, `neutral` or `skipped`.
- Findings in the detector-findings shape ([`detector-findings`](../../contracts/detector-findings/README.md)),
  for the commit the leaf judged. A new commit gets a new verdict, even when its content is
  unchanged.
- An artifact bundle per [`record-bundle`](../../contracts/record-bundle/README.md).
- A check run named `<lane> / <leaf>`, for example `pr-refine / simplify`; a composite gets none.

A skip reports as a neutral check with one reason from the schema's `$defs/skip-reason`:
`not-applicable-paths` (a `paths` predicate missed, or every matching path was left out of
`changed-paths`), `not-applicable` (a label, event, work-class, `mergeable` or `draft` predicate
missed), `prerequisite-missing` (among others, mergeability still unknown at the gated head after
bounded re-reads), `cost-gated`, `awaiting-human` (among others, a `labels-absent` label is on the
PR), `superseded-sha`, `disabled-by-config`, `untrusted-trigger` (a fork, no same-repository PR, or an
actor or author not on the trusted-actor list), `workflow-modified` (the token broker refused a
write lane's mint for a workflow file the PR itself changes), `kill-switch` (a lanes kill switch
stopped the run: its own kill-switch step, or the token broker refusing a write lane's mint on a
pull request for a switch turned on after that step; the pr-unblock dispatchers dispatch the head
again once the switch lifts), `rung-up` (a fix-ci run's patch is
held back for one retry one model rung up, [Lanes](#lanes)), `no-model-turn` (an address-feedback
round whose model never ran, so the scan uploaded no replies), `finding-stands` (an
address-feedback round's reply job, when an adjudicator let a disputed finding stand and the head
did not move, so no review run starts the round that fixes it), `clean-merge` (a resolve-conflicts
round whose base merge left no conflict, so no model ran and the push job commits the merge),
`lane-stopped` (a pr-unblock stop `escalation-routes.json` routes to a failing status: on a select
job's activity check it ends the head; on a push, reply or verdict job's check the dispatcher
retries the head under its per-head cap), `pass-only` (a pass-only address-feedback round's reply
job, which ran no model and only resolved fail-note threads a pr-verify pass superseded; the
dispatcher's release reads skip it), `stop-resolved` (an address-feedback or fix-ci select job found
no stop standing on its head, whether or not one ever did), `awaiting-session` (an address-feedback
select job whose head's stop already sits in the `needs-session` queue, so it does not escalate
again), `owned-branch` (a fix-ci select job on a pull request whose head branch
`merge.refire-skip-branches` lists: the workflow that owns the branch rebuilds it, so a fix-ci push
would race the rebuild), or, for an issue run under
`models.issue-dimensions`, `research-first` or `probe-first` (its Uncertainty), or
`split-required` (its Size is `split`). Issue mode posts no check, so work-resolve-issue.yml reports those three dimension skips
on the issue instead, to no person: `research-first` and `probe-first` lose `agent-ready` and
`status: ready` and park at `status: confirmed` beside admission's comment naming the next step,
as admission parks the same refusal, and `split-required` goes back through intake, whose split
files its sub-issues ([Issue mode](pr-run-activity.md#issue-mode)). Silence is not a skip, with three exceptions that
post no check: a fork PR, whose read-only token cannot write checks; a `pull_request` event sent
by the lanes App; and a run on any other event whose run job gated no head SHA.

Each review finding goes to an independent validator. Valid: fix it and reply with a citation.
Invalid: reply with a cited disagreement. Unsure: an adjudicator judges it
(`adjudicate-feedback.mjs`), as it judges a disputed finding; only a finding at the security tier a
person decides (a `CRITICAL` rating, or a security-review finding with no rating the lane reads)
and a thread a person opened or directed go to that person (`feedback-uncertain`,
`feedback-disputed`). A script resolves bot threads after the reply; human threads stay open for
the human.

## Merge authority

`merge.authority` names the repository's one merge authority: `local-babysit`, the babysit wrapper
run by the local babysit lane (loop-lane), or `pr-merge`. When it is absent the authority is
`pr-merge`, the meaning a rung had before this key existed. The babysit wrapper merges only when it
reads the authority the wrapper runs as: `local-babysit` by default, `pr-merge` under
`--authority pr-merge` (below). `merge.report-only: true` makes that authority report each
decision and write nothing. `merge.rung` is a pacing cap: `off` merges nothing without a human,
and `merge` or `merge-reviewed` lets the authority merge. On the pr-merge lane both merge on the
verifier verdict; on the local babysit lane `merge-reviewed` also needs AI review to be blocking
(its promotion cells, below). `C2` and `C3` are accepted aliases for `merge` and `merge-reviewed`.
Neither authority reads a work class
([`work-classes.md`](../../../plugins/autonomy/reference/guardrails/work-classes.md#merge-authorities-that-read-no-class)).

- `off` is the default. The first rung a repository adopts is `merge` (`C2`), together with
  `merge.diff-check`: the diff touches no denied path and stays under the size cap.
- No work class is read, and no class, missing class or diff shape caps the rung. The only
  class-named check is the untrusted-provenance hold: a pull request whose linked issue carries
  `provenance: untrusted` (any label naming untrusted work), or had it removed by a
  non-human, waits for a human, in the local babysit lane and when `enable-auto-merge` arms a
  lanes App pull request. The pr-merge lane merges on the verifier verdict
  ([The pr-merge lane](#the-pr-merge-lane)).
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
The pr-merge gate reads a Dependabot pull request's `.github/dependabot.yml` and Dependabot policy
at the default branch head too (read once per run-cache window, and again before an enqueue), by
the rules that only tighten in
[Dependabot pull requests](#dependabot-pull-requests) and
[Review-only dependencies](#review-only-dependencies).

- **Authority and identity.** `merge.authority` reads `local-babysit` and `merge.agent-identity`
  names the login the lane acts as. The schema rejects `local-babysit` without an identity. The
  identity must be the `[bot]` login of a GitHub App dedicated to this lane, and the schema rejects
  any other login: a machine user is a GitHub user and would pass every human test, and the shared
  `github-actions[bot]` and `dependabot[bot]` are refused in any letter case. With no `merge:` block,
  or no `authority`, the wrapper merges nothing.
- **Same repository.** The pull request's head is in this repository, never a fork.
- **Risk score.** A diff the risk scorer rates LOW merges, and so does a MEDIUM one whose every
  reason is a size or reported-finding reason (`lines-over`, `files-over`, `no-patch:*`,
  `findings:claude-review`, `findings:claude-security-review`, `cost-finding`). Every other MEDIUM reason
  (unbound or missing review evidence, an unread file listing) and every HIGH one refuse.
  `no-patch:` is an image, font or PDF, or a file whose blob ids show no unread content: a rename,
  mode change or modification that keeps its blob and does not gain execute, or an empty file added
  or removed.
  Any other file the files API sends no patch for (a script with a NUL byte that git calls binary,
  an over-size patch, a copy, an unread blob id) no review read, so it holds for a person as
  `unreviewed-patch:<path>`.
- **Review flags.** A review flag holds only for a real new charge (`cost-review-required`), a
  trusted-actor widening (`trust-gate:trusted-actors`) or a CRITICAL security finding
  (`security-finding`), owner decisions Q25, Q33 and Q693. Every other open finding, from
  claude-review or a lower security one, is listed in the reasons and does not hold.
- **Review evidence.** For each review lane, the newest run of the lane's caller workflow on the
  pinned head SHA concluded success and carries the lane's completion record for that SHA.
- **Effective rung.** The lowest of `merge.rung`, the `babysit_loop_merge` key (the value in
  `docs/conventions/source-control.yaml`, `off` when it sets none or the wrapper cannot read or
  trust the file), the cap variable, and `off` while any demotion issue holds.
- **Cap variable.** `CLAUDE_LANES_MERGE_RUNG_CAP` (`off`, `merge` or `merge-reviewed`, or the
  aliases `C2` and `C3`) is a repository variable
  only a human sets, and it can only lower the rung. The wrapper never writes it, and the identity
  can read variables but not write them. A 404 after the variables listing proved readable means no
  cap; any other failure means `off`.
- **Kill switches.** The org variable `CLAUDE_LANES_DISABLED` and the repository variable
  `CLAUDE_LANES_REPO_DISABLED` must each read exactly `false`. A read error, or a repository-level
  variable named `CLAUDE_LANES_DISABLED` that shadows the org one, refuses.
- **Demotion issue.** A failed post-merge check files an issue whose body starts with
  `<!-- babysit-merge-demotion sha=<S> signal=<name> -->`. A record is a state marker, never lane
  work: no record is sent to intake triage, since the fix issues carry the work, and its text keeps
  the fix-issue rule (each newly failing check by job name only, never a gate's annotation title or
  a revert command). `post-merge-demotion-alert.yml` files a red-main record (signal `schedule` or
  `dispatch`) with no label, since it clears itself (below), unless a failing check got no fix
  issue (over the cap or outside the charset), which labels it `needs-human`; it labels a canary or revert record
  `needs-human`, since a green main clears neither; each keeps the label until it lifts (below).
  `babysit_postmerge.py --remediate` labels
  every record it files `needs-human`: the lanes App's issue starts intake triage on its own, and
  that label keeps admission off it. On each completed scheduled full run on main, the
  alert's `close-cleared` job closes as completed each open schedule or dispatch record, demotion
  or post-merge-failure, that either filer opened, that was never edited, and that a later green
  full run on main cleared by the merge gate's own rule (`_recovered_at`: attempt 1, a schedule or
  a github-actions[bot] dispatch, created after the record, at a commit ahead of its SHA and on
  main); closing it is the record's state only, and the merge gate still decides whether it holds. A fix issue not delivered to intake triage gets
  a hidden marker comment on it and on its record, a quarantine issue one on the issue, and a check
  whose fix issue could not be filed or reopened one on the record; each alert run retries what a marker names until it succeeds, with
  the failing run staying red, and adds no label. A record gets `needs-human` when a failing check got
  no fix issue because it was over the cap or outside the charset; a fix issue reopened on a
  repeat failure keeps whatever labels it has, so one labeled `needs-human` stays with a person.
  It holds the rung at `off` until it clears: a human's direct close clears any record. A close through a pull request's or
  commit's `Closes #N` does not count, and an issue that a non-human edited at any time stays in
  force. A red-main record (signal `schedule` or `dispatch`) that no non-human edited also clears,
  open or not, once main is green at a later commit: a green `pr-require-checks` run on main,
  attempt 1, from a schedule or a `github-actions[bot]` dispatch, created after the record, at a
  commit ahead of the record's SHA and on main's history. The earliest such run's creation is the
  clear time, read a week at a time from the record, oldest first, up to about a year and stopping
  at the first week that clears it, so newer runs never move it and a record cleared long ago reads
  one week. A canary, revert or read-back record that no non-human edited lifts, open or not, on
  its own evidence (`babysit_merge_policy.py` `_lift`), in either of two ways. (1) Its own
  condition holds on main again: for a canary or revert record, every line its lift block counts is
  in that path's file at main's tip, as often as it was deleted, over and above the copies the file
  held at the record's own SHA, so a moved or common line the deletion left behind is no restore
  and a final newline is no blank line (once the lane closed it, at the
  commit its close comment's `<!-- lift-evidence sha=<S> -->` line names, so a later edit on main
  does not re-demote a closed record); for a read-back record, the pull
  request it names reads back after all (the agent identity's newest pin comment among its first
  100 comments is unedited, was posted no later than the merge and names the head that merged).
  The record's creation is the clear time. (2) A pull request that references the record merges
  into `main` of this repository after it was filed, at a merge commit on main's history; the
  reference was made no later than the merge by a person with write access or the agent identity
  (anyone can mention the record in a comment on a pull request, merged or not, which also makes a
  reference); and the
  record's own condition holds at that merge commit: a canary record's counted lines are in the tree
  there, or, when its block says the merge deleted nothing (the canary failed on its self-test,
  replay or restoration step), a canary push run passed there; the pull request reads back, for a
  read-back record, which can happen only when a pin exists for that merge (while the record holds
  the rung is off and the wrapper pins nothing); a revert record needs nothing more, since the
  referencing merge confirms the revert. The earliest such merge is the clear time. A failed read,
  more than 100 references or more than 100 comments lifts nothing. The lift block is one line,
  `<!-- lift-content v1 {"paths": {...}} -->`, holding per path the first 12 hex digits of each
  deleted line's SHA-256 and how often it was deleted (`babysit_lift.py`). The alert writes it into
  a revert record from the lines its revert commits deleted, and into a canary record from the
  lines `scripts/check-silent-revert.sh` attributes to a culprit in the pushed commits (its
  `DELETED_SINK`); for a canary record `babysit_postmerge.py --remediate` filed first, the alert
  posts the block as a comment, which counts when github-actions[bot] or the agent identity wrote
  it and nobody edited it. The one exception is a canary record with no block, because the pushed
  commits are not in main's checkout or were not all read (more than 20 since the previous canary
  push run's head, or that head unreadable or off the push's history), the scan could not run, or the block passed 40,000
  characters: no lane can tell what was deleted, so only a person's close clears it. On each completed scheduled full run on main, `close-cleared` runs
  `babysit_lift.py close` from main's checkout, which comments on, removes the human-gated label
  from and closes as completed each open canary, revert or read-back record either filer opened
  that has lifted by that same rule; post-merge-failure canary records lift and close the same
  way. A push to main files a `revert` record when one
  of its commits names a pull request it reverts and the lanes App enqueued that pull request or
  its enqueuer cannot be read; a revert of one a person enqueued files nothing, and one on a
  record-mode path gets labels only ([Merge paths](#merge-paths)). The alert job
  finds the revert and hands the record, through its job outputs, to the `file-revert` job, whose
  token holds `issues: write` alone; that job re-reads the revert records and files nothing when
  one already lists every revert commit. A commit names it
  on a line of its squash message: `Reverts` (optionally after a `-` or `*` bullet) followed by `#N`
  or `<owner>/<repo>#N` references, each counted; a GitHub revert-button subject
  `Revert "... (#N)" (#M)`; or `This reverts commit <sha>` or the red-main bot's
  `<!-- red-main-revert culprit=<sha> -->`, through that commit's `(#N)` subject. Every canary push
  run, whatever it concluded and on every attempt, reads every commit the push brought, a
  merge-queue batch included: main's first-parent range since the previous canary push run's head,
  at most 20 commits, and the newest 20 when that head cannot be read or is not on the push's
  history, read from main's full history. A revert commit any revert record already lists, in any
  state, is skipped, so a commit is filed once and never again after a person closes its record. A
  reverted commit whose pull request cannot be read is an unproven revert and files the record. The wrapper finds these issues by author (the agent identity
  or `github-actions[bot]`), so removing the marker or the label does not clear one. When `post-merge-demotion-alert.yml` proves
  that no merge the failing run covers was enqueued by the agent identity, it files a
  post-merge-failure record instead, first line `<!-- post-merge-failure sha=<S> signal=<name> -->`,
  labeled as a record of its signal is: a full-run one carries no label unless a failing check got
  no fix issue (over the cap or outside the charset), since its fix issues fix main, and a canary one is labeled `needs-human` on purpose, since a canary files no fix issue and
  nothing else clears it. That record does not hold the rung off.
  With a new record of either kind, the alert files one fix issue per newly failing check, at
  most 5 per run (an overflow line on the record says when more failed, and labels that record
  `needs-human`, as does a failing name outside the fix-issue charset), first line
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
- **Narrow path floor.** A set of globs, each with a class: `babysit_risk.FLOOR_CLASSES`, the paths
  every consumer shares, joined to the repository's `merge.diff-check.floor-paths` rows
  (`glob`, `class`, and on a `gate` row an optional `author-lift: false`, which keeps the row with a
  person). A row can add to the floor and never drop or loosen a built-in row, and a row the loader
  cannot use turns the rung off. `scripts/sync-hold-floor.py` writes the joined table's copies into
  `merge-holds.mjs` `HOLD_PATH_CLASSES`, the review callers' `hold-paths` and ci-status's
  `hold_patterns`, and `test_merge_holds_sync.py` runs its `--check` (owner decisions
  Q-FLOOR (B),
  [Q-ENFORCE (A)](https://github.com/melodic-software/claude-code-plugins/pull/9826#issuecomment-6401599691)
  and Q26 option B). The floor matches case-insensitively whatever `high-path-floor` says, while
  `merge.diff-check.path-holds` is true (owner decision Q15 turns it off here):
  - `trust`, a person merges it: `.github/actions/request-lane-token/**`, which mints the lanes
    App token, `.github/actions/resolve-config/**`, whose code the token broker runs from main in
    its signer process with `effect-grants.json`, `lane-rules.json` and `activity-rules.json`,
    which scope each lane token, `docs/conventions/pr-pipeline.yaml`, whose activity `effect:`
    values and lane slots the broker reads, `.github/actions/check-trusted-trigger/**`,
    `.github/actions/check-kill-switch/**`, whose output writer both actions use, `**/CODEOWNERS`,
    `**/.gitmodules`, and the code that computes the author lift and the hold tables:
    `babysit_merge.py`, `babysit_merge_policy.py`, `babysit_risk.py` and
    `babysit_review_evidence.py`, which compute the security review's clear condition,
    `.github/scripts/pr-merge/merge-holds.mjs`, `scripts/sync-hold-floor.py`, which writes the
    floor's copies, and the pr-merge scripts that apply and enforce the holds:
    `enable-auto-merge.mjs`, `superseded.mjs`, `clear-escalations.mjs`, `gate-check.mjs` and
    `head-ref-map.mjs`.
  - `gate`, a person merges it: the rest of the merge gate's own code, which is the rate guard
    (`.github/actions/log-api-budget/rate-guard.mjs`) with its rate-limit defaults
    (`.github/actions/log-api-budget/rate-limits.json`) and every other script of
    `.github/scripts/pr-merge/`. And the review's own surface (owner direction 2026-10-28): the
    review callers and `pr-review-main.yml` with `.github/scripts/pr-review-main/**`, which run the
    review itself and set the counts the gate reads, and each workflow that holds a credential
    beyond its job's `GITHUB_TOKEN`: a secret other than `GITHUB_TOKEN`, a lane token
    (`request-lane-token`), or an OIDC token (`id-token: write`), `pr-merge.yml` and
    `pr-unblock.yml` among them (owner decision Q11 (A), 2026-10-28: a job token dies with its job
    and cannot push to main past branch protection, while an App key or PAT outlives the run). So
    is ci-status, `pr-require-checks.yml`, which posts the required status and runs the hold step,
    named by file, and each workflow whose job token has `actions: write` (or `write-all`), which
    can dispatch those credentialed workflows, `intake-reenter.yml` and
    `pr-feedback-dispatch.yml` among them: a logic edit inside scopes it already holds trips no
    patch hold, so a model verdict alone never clears it. 23 workflows are gated.
    `scripts/sync-hold-floor.py` derives these rows from the workflow files with
    `babysit_risk.gated_workflow`, so a workflow that gains a secret or `actions: write` joins the
    gate, and `--check` fails on a stale table. A workflow whose job token writes other scopes
    only is off the gate: the main-run review binds it, and a gained write scope, trigger, secret
    or model leg holds by its patch. Also what changes
    what agents may do unattended or what later reviews judge against: `**/.claude/**` and
    `**/.claude-lane/**` whole (settings, hooks and the scripts settings registers, skills, agents,
    commands, rules, output styles and memory, under owner decision Q11, which supersedes the
    2026-10-22 direction for rules), `docs/conventions/source-control.yaml` (the babysit loop's
    team layer, trusted bot logins included),
    `docs/conventions/instruction-exception-register/**` and
    `docs/conventions/untrusted-content/**` (the security review's criteria), `**/.mcp.json`, `**/CLAUDE.md`, `**/CLAUDE.local.md`,
    `**/AGENTS.md`, `REVIEW.md` and `docs/standards/**`. On a pull
    request a person on the trusted-actor list opened, a `gate` path only that person's own
    commits touched clears as an `enforcement` path does (owner direction 2026-10-27: such pull
    requests merge without a person's review), on a head pr-verify passed
    (`babysit_merge_policy.author_reviewed_paths`, `babysit_risk.Floor.author_review`). A lanes App
    or other bot pull request, a lane's fix commit on a gate path, commits that do not read, and
    a path a `trust` glob or a configured denied path also matches keep the person's hold, so a
    lane changing its own powers is still merged by a person. The review's own surface above
    never takes this lift (`babysit_risk._NO_AUTHOR_LIFT` and every workflow row), so it always
    waits for a person. The token-scope files and the lift
    and hold-table code and the scripts that apply the holds are `trust`, never `gate`, so they
    never take this lift: agents commit as the trusted owner, so a pull request that widens a lane
    token's scope, widens the lift, drops a floor row or weakens a hold waits for a person.
  - `enforcement`, a clean security review clears it: every other module the floored scripts
    import (`.github/scripts/pr-unblock/address-feedback.mjs`, `gate-source.mjs` and
    `thread-scope.mjs`, `escalation-routes.mjs` and the routing table `escalation-routes.json` it
    reads, `.github/scripts/work-resolve-issue/report-outcome.mjs` and `limits.mjs`,
    `.github/scripts/lib/retry-fetch.mjs` and `lane-hold-marker.mjs`, and the stop routes
    `report-outcome.mjs` loads, `stop-routes.mjs` and `stop-routes.json`, and `fix-ci-context.mjs`
    with the `.github/scripts/maintenance-reconcile-lost-runs/infra-failure.mjs` it loads), the scripts that act on a pr-unblock
    stop's route (`report-escalation.sh`, which labels a held reason, `adjudicate-feedback.mjs` and
    `publish-feedback.mjs`, which decide and resolve threads, and
    `.github/scripts/apply-patch/apply-patch.mjs`, which holds fix-ci escalations) with every module
    they import (`request-budget.mjs`, `dependency-classify.mjs`, and `predicates.mjs` and
    `protected-paths.mjs` in `apply-patch/`, and `.github/scripts/lib/run-main.mjs`),
    and the rest of the Python that decides the holds (`babysit_verify_evidence.py`, which
    `enable-auto-merge.mjs` runs, and the `babysit-prs/scripts/` modules it and `babysit_risk.py`
    import). It scores HIGH as `review-path:<glob>` until the `claude-security-review` evidence
    binds to the head with no open finding, then merges with no person; ci-status leaves it to
    the gate. A lane source is a
    path the head's checkout feeds or forges its own review from (`LANE_SOURCE_PREFIXES` and
    `readonly_workflow` in `babysit_review_evidence.py` state the rule). A pull request that
    changes one binds its reviews only from main (see "Main-run review" below). A changed workflow file is
    not one when its head copy cannot post as `github-actions[bot]` with a write token nor reach a
    secret: a top-level `.yml` other than the two review callers and the floor workflows
    (`babysit_risk.Floor.all`), present at the head, with every job's `permissions:` read-only and
    set explicitly, no `pull_request_target`, `workflow_run` or `workflow_call` trigger, no
    `secrets` reference but `secrets.GITHUB_TOKEN`, and `name:` equal to its file stem or that stem in Title Case. A deleted
    workflow stays a lane source, and so does every floor workflow whatever its content. The `merge` and
    `enable-auto-merge` jobs install the hash-pinned PyYAML from `.github/requirements-ci.txt` for
    that read; without it no workflow change clears. A comment by a lane author
    (`github-actions[bot]` or the Claude App) binds only while its last editor is its own author:
    anyone with write access can edit a comment, so one edited by another identity unbinds the
    review as `comment-edited`. The edit is read before the body, so an edit that removes the
    lane footer or the marker line still unbinds.

  **Main-run review.** The pull_request review lanes run the head's copy of their callers and post
  as `github-actions[bot]`, which any write-token workflow a head adds can also post as, so for a
  pull request that changes a lane source no comment, marker or pull_request run counts.
  `.github/workflows/pr-review-main.yml` reviews it instead: it runs on `pr-require-checks`'
  completion through `workflow_run`, so its definition is main's, gates the trigger as pr-verify
  does, and for a pull request whose changed files include a lane source runs both lanes on the
  head's diff as data, each lane's criteria and the standards copied from main, with a read-only
  token and a model that may only Read its data directory. A head both lanes already reviewed,
  where the merge gate's own predicate (`_main_bound`) binds each lane on what the trigger job
  reads, is not reviewed again, and no leg starts for a pull request with no lane source. A verdict
  counts there only when its run's main commit has no diff from main's tip over what the review
  reads from main (`.github/scripts/pr-review-main/criteria.txt`, which the copy steps also read),
  so a verdict judged under other criteria reviews again; a failed or cancelled review, another
  head of the same tree, or a failed read, fetch or diff reviews again. The diff is
  `git diff --text`, so a file git would call binary is shown as text, and a patch that still holds a binary file gets no
  verdict. A patch over 300000 bytes is split into chunks of at most 300000 bytes, cut at file
  boundaries with each file whole (`split-diff.py`); each chunk is reviewed by its own run, in
  order, and the lane's one verdict sums the chunks' findings and takes the most CRITICAL ones
  any one chunk found; the verdict's `items` give each finding its `chunk`, so they can hold more
  CRITICAL items than its `critical` count, which alone binds. A patch that holds a single file
  over 300000 bytes, or needs more than 4 chunks (the diff step's `MAX_CHUNKS`, at most the leg's
  review steps), gets no verdict: a multi-file diff over about 1.2 MB still stops as `too-large`
  until a dynamic chunk count lifts it
  ([#11000](https://github.com/melodic-software/claude-code-plugins/issues/11000)). A chunked
  diff also writes `manifest.txt` in the data directory, every file of the whole diff with its
  chunk and status (added, modified, deleted, or renamed with both paths), up to what one Read
  returns whole (`PART_BYTES`). Each chunked prompt names that file, tells the reviewer to read
  it as untrusted data, and asks for a finding naming both paths when a change references a file
  another chunk holds; the paths, which the pull request's author chose, never enter the prompt,
  and a one-chunk prompt is unchanged. The diff step logs a `pr-review-main chunks` notice with
  the chunk count, each chunk's bytes and `manifest_paths`, the files the manifest names, and the
  verdict step one `pr-review-main chunk` notice per chunk with its bytes, findings and
  CRITICAL ones. Each chunk is split into parts one Read returns whole (15000
  bytes and 1000 lines at most), and a verdict is written only when
  every chunk's run succeeded and read each of its parts whole, with no offset or limit
  (`write-verdict.mjs` `readCoverage`). A chunk that hands off hands the whole lane to the next
  leg, which reviews every chunk again. Read may cut a long line short, so a diff line over 1800
  bytes (`babysit_risk.LONG_LINE_BYTES`) continues on lines that start `\ continued:`, never cut
  inside a UTF-8 character, as pr-verify's `chunk-diff.sh` folds; the prompt says each such line
  is the rest of the line before it and adds no line to the file's numbering. Every byte reaches a
  whole Read, and the binder counts no verdict whose recorded `max_line_bytes` is past the cap. The diff is
  `--no-renames`, so a renamed file is reviewed whole. Only when that patch is over the size cap
  does a file moved unchanged (git's 100% similarity) show as its rename lines alone, and even then
  a move into or out of a lane source (`lane_source`), one that changes the file mode or moves a
  symlink or submodule, one that may run or load (an executable, a path under a `skills`, `agents`,
  `commands` or `hooks` directory, or a file a tool reads by name such as `SKILL.md`, `hooks.json`,
  `plugin.json`, `marketplace.json`, `conftest.py`, `__init__.py` or `settings.json`), and one whose
  new path, last directory and name, name, or name without its extension an added line names
  show whole (`write-diff.py`); the prompt tells the reviewer a rename-only entry is unseen and that
  a change referencing a moved path is a finding. The caps apply after. A verdict binds only when the head
  also carries the record job's `pr-review-main: <lane>` check run with the same counts, so a run
  cancelled before it recorded binds nothing. Each
  lane uploads `verdict.json` as
  `pr-review-main-<lane>-<pr>-<tree>`, the tree read by git, never the model, and a separate job
  with no model posts its counts as the check run `pr-review-main: <lane>` (titled
  `findings=<n> critical=<m>`, conclusion neutral) on the reviewed head. A designed stop (a
  binary file or a patch over the chunk cap) leaves the leg green with no
  verdict, and the record job posts it on the head as the same check run titled
  `verdict=none reason=<too-large|binary|chunk-failed>`, so each stop is a countable
  record; it posts nothing else. `chunk-failed` is a chunked review one of whose chunks failed,
  left no result or skipped a part: no chunk's counts bind, and that leg still fails. A stop
  counts no CRITICAL finding and never binds a lane: with no verdict the lanes stay unbound as
  `main-review-stop:<reason>`, a lane's reason. A forged stop only renames that reason.
  The gate (`babysit_review_evidence._main_bound`) counts a verdict only when its run is that
  file, event `workflow_run`, on the default branch of this repository with a head the branch
  holds, and the verdict names that lane, pull request and tree. As with pr-verify's FAIL, a
  finding counts whatever the run's conclusion; the lane binds only when a counted verdict from a
  completed, successful run names the pinned head, with the most findings, and the most CRITICAL
  ones, that any counted review of that tree reported, so a re-run, a failed run or an empty
  commit never clears one. The security lane also keeps any CRITICAL finding its pull_request review left
  open, and the most CRITICAL findings any `pr-review-main: claude-security-review` check run
  records on any head of the pull request (its commits and the heads force pushes replaced), so a
  whitespace push whose new tree reviews clean cannot re-roll one away. Check runs were chosen
  over a comment because the checks API has no delete: a pull_request workflow's token can delete
  an artifact or a comment, not a check run, and a forged one can only add a hold. A count that
  cannot be read leaves the lane unbound. With no such verdict the lanes stay unbound (`lane-source-changed`), a lane's reason, and a
  floor `enforcement` path beside it waits for that review. Each lane runs one leg on the reviews
  role's credentials in the review lanes' order: the API key (`REVIEWS_CLAUDE_API_KEY`); then,
  for a lane whose key leg handed off (a credit stop, a 401 or 402) or whose key is empty, the
  subscription token (`REVIEWS_CLAUDE_CODE_OAUTH_TOKEN`) in the `review-subscription` job; then,
  for a lane that leg handed off (a limit stop, a credit stop, a 401 or 402, or an empty token)
  with `FALLBACK_CLAUDE_CODE_OAUTH_TOKEN` set, the fallback token in `review-fallback`. Each leg
  is a job on a new VM holding one credential, and a route job with no secret passes on only
  lanes whose handoff reason is in a closed set. The key leg checks out the main tip when it
  starts and records that commit; a later leg checks out the recorded commit, which the route
  passes on only as 40 hex characters, so a re-run of an old run cannot bring back older review
  code. Every leg writes the same verdict, so neither the
  record job nor the gate depends on the leg; the lane record (`report-lane-outcome`) names the
  credential and why the leg ran. A handed-off leg stays green, so a later leg's verdict still
  comes from a successful run. A run whose first attempt failed before any lane's verdict write
  started (every leg stopped) is re-run once, recorded, by the lost-run reconciler, as a lost
  pr-verify run is (`maintenance-reconcile-lost-runs`); any other run that leaves no verdict
  leaves the lanes unbound until the next push.

  `merge.diff-check.denied-paths` (empty here) joins the person classes.
  `test_merge_holds_sync.py` derives the JS and Python import closures and requires them on the
  floor, with every pr-merge script as `gate`. No other path
  is held for being trusted (owner direction 2026-10-24): the trusted-actor list and every other
  path merge on the review lanes, which judge them. A
  `plugins/<plugin>/.claude-plugin/plugin.json` or `.claude-plugin/marketplace.json` change that
  installs or runs something new is a security-review finding, not a hold; where
  `high-path-floor` is on, the gate still scores it HIGH as `manifest-review-required`, and this
  repository sets it off. Here the security review is the only control on such a change: no
  deterministic check holds it, and the review's CRITICAL rating of an added `hooks`,
  `mcpServers`, `lspServers` or `monitors` key, or a marketplace entry added, removed or
  repointed, is what holds it ([owner decision Q-FLOOR (B)](https://github.com/melodic-software/claude-code-plugins/pull/9826#issuecomment-6399729716)).
- **Trusted-actor widening.** A change that adds or widens an entry in
  `.github/standards/trusted-actors/trusted-actors.json` scores HIGH as
  `trust-gate:trusted-actors` in both lanes and waits for the owner, whatever `high-path-floor`
  says and whatever an adopted author's own paths leave off the floor. The gate compares the
  base and head entries: a change that only removes entries merges; an added or changed entry,
  any other key changed, a side that cannot be read or parsed or repeats a key, and an added,
  removed, renamed or copied list hold. An owner cost decision does not clear it. `ci-status`
  holds the same widening on a lanes App pull request pushed after auto-merge is armed
  (`merge-holds.mjs` `actorsHold`), lifted as a hold path is (see below).
- **Security findings.** The security lane flags; only a CRITICAL finding, its top tier, holds the
  merge, as `security-finding`. Its inline comments and summary carry the severity lines
  `/review:security-review` defines, and a finding whose severity the gate cannot read counts as
  CRITICAL. Its other open findings are reported as `findings:claude-security-review`.
- **Cost hold.** Cost is not a stop; only a real new charge is ([when work stops for the owner](../../contracts/loop-lane/README.md#when-work-stops-for-the-owner)). A change
  that could start one (billed infrastructure or billed runner minutes) scores HIGH as
  `cost-review-required` in both lanes, whatever `high-path-floor` says and whatever an adopted
  author's own paths leave off the floor, and waits for a human like any other HIGH reason. It
  catches:
  - any changed Pulumi project or stack file (`Pulumi.yaml`, `Pulumi.*.yaml` and their `.yml`
    and `.json` forms, which
    [Pulumi reads too](https://github.com/pulumi/pulumi/blob/master/sdk/go/common/encoding/marshal.go)),
    `*.tf`, `*.tf.json`, `*.tfvars`, `*.tfvars.json`, `*.bicep` or `*.bicepparam` file, any ARM
    template under the names
    [Azure's quickstart samples use](https://github.com/Azure/azure-quickstart-templates/blob/master/1-CONTRIBUTION-GUIDE/README.md)
    (`azuredeploy.json`, `azuredeploy.*.json`, `*.azuredeploy.json`, `*.azuredeploy.*.json`), and
    any file under a directory that holds a Pulumi project file at the base. A base tree the gate
    cannot list whole holds every file;
  - a file renamed or copied into `.github/workflows/` or a `pr-pipeline.yaml` path from outside;
  - a runner value the workflow's head text gains over its base text, or an added inline
    `runs-on:` value: on a public repository only one that is not a free literal (GitHub's
    standard `ubuntu-*`, `windows-*` and `macos-*` labels, the self-hosted managed labels, or a
    list holding `self-hosted`), so an expression, a `group:` and a larger runner hold, since
    [GitHub bills larger runners even on public repositories](https://docs.github.com/en/billing/concepts/product-billing/github-actions);
    on any other repository every one, and any added `windows` or `macos` line. A `runs-on`
    expression that names a matrix key or an input (`${{ matrix.os }}`, `${{ inputs.runner }}`)
    counts each value that key or the input's `default:` and `options:` gain in the same file;
  - on a repository not known to be public, an added `cron:` key in any YAML or JSON spelling
    (a schedule runs billed minutes), a raised timeout as below, or an artifact
    `retention-days` the patch adds above every one it removes, or above GitHub's
    [90-day default](https://docs.github.com/en/organizations/managing-organization-settings/configuring-the-retention-period-for-github-actions-artifacts-and-logs-in-your-organization)
    when it removes none (storage past the free quota);
  - a workflow or pipeline file with no patch.

  Off a public repository, a raised timeout is a `timeout-minutes` or `leg-timeout-minutes`. In a
  workflow whose head text uses one of the model actions below, or could not be read, it is one
  the patch adds above every one it removes once equal values cancel, so a value removed and
  re-added on another job hides nothing, or one set to an expression. In a workflow whose head text uses a model action or a
  local `uses: ./` workflow or action, it is also, head text against base text at each job's key
  path (a step's timeouts compared among its job's steps), block or flow style, one raised, set
  to an expression, added above the highest number already at its path, a `timeout-minutes` set
  where none was above GitHub's
  [360-minute default](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax),
  or one removed from a job or step the head still has, so that default or the action's own
  applies. A `leg-timeout-minutes` set where none was is a cap, not a raise.

  Cost means only what can bill. Model usage under a subscription or prepaid credit does not, so
  a `--model` or `--max-turns` flag reports nothing; nor do hosted minutes or artifact storage on
  a public repository, so a `cron:` key, a raised timeout or a raised `retention-days` there
  reports nothing. Any `pr-pipeline.yaml` change is reported as the MEDIUM `cost-finding`, which
  never holds, except one whose added and removed lines are all blank, comment-only, or a
  `description:` or `title:` value, or that only edits trailing comments on the same lines in
  place. Flow style, quoted keys and new list items count.

  A workflow patch that gains a `secrets` reference (`secrets.NAME`, `secrets.*`,
  `secrets['NAME']`, `toJSON(secrets)`, `secrets: inherit`, or the bare `secrets` context anywhere
  in a `${{ }}` expression outside a string, such as `${{ secrets }}` or
  `contains(secrets, 'X')`, or in an `if:` value without `${{ }}`, job or step level, quoted or a
  block scalar; every `${{` starts a fresh read, and an expression whose string is
  still open where its read ends counts as one) scores HIGH as
  `secret-exposure-review`, and a workflow or composite action patch that gains a `uses:` of
  `run-claude-cli` or any `claude-code*` action or image (matched ignoring case) or a run line
  invoking `@anthropic-ai/claude-code` scores HIGH as `agent-surface-review`, each counted against
  the lines it removes, an expression split across a folded scalar read whole, so a moved line or
  a repin is not new; so does a composite action file with no patch to read, unless it is deleted,
  re-moded, or renamed from another composite action, with no line added. The secrets
  reference is also read from the head text against the base text, so a workflow with no patch is
  not skipped. A workflow whose token gains a write scope scores HIGH as
  `permission-widening-review`: base and head are parsed (PyYAML; without it, the text alone) and
  each job's write scopes compared, a job left with no `permissions:` of its own or at the top level
  counting as a gain because it runs on the repository default, an added file compared against
  none, and unread text, a repeated key or an alias holding. One that gains a `pull_request_target`,
  `workflow_run`, `issues`, `issue_comment`, `pull_request_review`, `pull_request_review_comment`,
  `discussion`, `discussion_comment` or `repository_dispatch` trigger scores HIGH as
  `privileged-trigger-review`. These widen what a
  credential, an agent or a write token can reach, not only spend, so a person clears them and no
  cost decision does.

  Accepted: a `secrets` reference moved within one file is net zero, so `secret-exposure-review`
  does not see it, and it adds no charge, so the cost hold does not either; where it moved is the
  review lanes' call. Other new triggers, a removed `concurrency` or job `if:` guard, matrix growth
  and `max-parallel`, a non-Claude model action, and paths outside the ones above (a workflow in
  a subdirectory of `.github/workflows/`, an ARM template under another name) are left to the
  review lanes' cost hold, which holds for a real charge (`pr-review-hosted.yml`).

  The hold clears only when the pull request body links an owner decision that covers it: a
  comment on the pull request's linked issue (its closing issue, or its `Refs:` issue as
  [The pr-merge lane](#the-pr-merge-lane) reads it) or on the pull request itself, in this repository,
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
  The value is computed from `merge.in-flight-sizing`, measured burst rate, time in flight and
  lanes App spend, by `scripts/compute-max-in-flight.py`; the YAML states the formula. The gate
  reads a value above the schema's maximum as unset. A value above the merge-queue ruleset's
  `max_entries_to_build` needs no ruleset change: that setting throttles builds, not the queue's
  length, and this count also holds merges already out of the queue.
- **Quarantined suites.** A red full run on the default branch demotes only for a newly failing
  suite (a test file) in the affected set of the merges since the branch's last green full run:
  `scripts/plan-test-lanes.sh`, the pull request runs' selector, over the paths changed since that
  run's SHA, run from a worktree of that green SHA with no token in its environment, so no merge
  judged can narrow its own set. A window that changes the selector's own files, or a plan that
  picks no suite, has no set. A suite is named from its test leg's log, in a Python leg only from
  lines carrying the nonce that step prints; a failed job whose suites cannot be named (a token
  without GitHub's `Actions` read permission cannot read the log, so it names none), a set that
  cannot be computed, and the merge gate's own suites
  (`GATE_SUITE_PREFIXES` in `babysit_postmerge.py`) demote as before. A suite outside the set that
  failed again on a re-run also demotes, unless it passed on an earlier attempt of the same commit
  (it is non-deterministic) or a full run at the last green commit failed it on some attempt (the
  merges did not cause it).
  Any other suite outside the set
  demotes nothing, the window counts as verified (its `max-in-flight` slots free), and the suite
  is quarantined: an issue marked `<!-- post-merge-quarantine suite=<path> -->`, with no label
  and no assignee, filed by the agent identity's `--remediate` (whose issue starts intake triage)
  or by post-merge-demotion-alert.yml (which locks it and dispatches intake triage for it), so a
  lane picks it up. While that issue is open
  and younger than `merge.quarantine-days` (default 7, at most 30), the suite's out-of-set failures
  demote nothing; after that they demote again, even when the suite was already failing before the
  merge. An issue whose body was edited after filing, or whose title no longer names its marker's
  suite, excuses nothing from then on: the suite demotes until the issue is closed. Closing the
  issue ends the quarantine, and the suite's next failure outside the set files a new issue whose
  days start again, so closing an expired issue restarts its quarantine. A failure inside the set demotes whether or not the suite
  is quarantined, and an excused run gets no red-main report. Quarantine never changes a pull request's `ci-status` and starts no
  re-run.
- **Repeat queue ejections.** `merge.max-queue-ejections` (default 2, at most 20) stops the
  wrapper enqueuing a head the merge queue has removed that many times for failed checks since the
  head last changed; the queue would eject it again on the same commits. A push resets the count.
  At the cap, a removal whose merge-group run failed only `CI Status` (and its `ci-status` alias)
  on a GitHub rate limit alone, by its failure annotations, is not counted once that limit has
  reset; a removal whose run or annotations cannot be read counts. An unreadable timeline, or 20 timeline items with no head change among them, refuses the
  enqueue. A refused head gets one `<!-- babysit-merge-queue-ejections -->` comment naming the
  failing `merge_group` runs. Under `merge.lane-prs` `native`, `enable-auto-merge` applies the
  same cap before it arms a lanes App pull request (see [Native auto-merge](#native-auto-merge)).
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
  canonical, so the fix is merging the base and running `scripts/sync-shared-copies.sh`. The wrapper
  escalates it: one `<!-- babysit-merge-shared-copy-escalation -->` comment naming the canonicals,
  the head and the fix, then the human-gated role label, both unchanged by a rerun at the same head;
  the `head-moved` clear removes the label once the head moves. On a lanes App pull request,
  pr-unblock's `sync-shared-copies` activity answers it with no model and no person: the dispatcher
  sends one run per refused head, a base-code job merges the default branch tip and runs the base's
  sync script, refusing a head that changes the script, its registry or `scripts/lib`
  (`shared-copy-tooling-changed`) and any write the base-tip registry lists as no copy
  (`shared-copy-path-unregistered`) and a merge that is not clean, which resolve-conflicts cannot
  take while the label holds it (`shared-copy-merge-conflicted`, queued for a session), and
  `apply-shared-copies` pushes one merge commit under
  patch-rules.json's `shared-copies` row, which admits only registered copies; when the merge
  already holds current copies, the commit is the merge alone. The new head moves
  past the refusal, so the next pr-merge sweep clears the label. Any
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
  `merge.agent-identity` (the lanes App) or adopted, exactly one linked issue in this repository,
  and a diff where no path, either side of a rename, matches `merge.diff-check.denied-paths`. The
  linked issue is the closing issue (`closingIssuesReferences`), or, for a pull request with no
  closing issue at all, the one issue its body's `Refs: #<n>` lines name (owner decision
  2026-10-23: "why would we limit this? Seems like useless friction for now?"). A `Refs:` line
  counts only as a plain `Refs: #<n>` from the first column, outside an HTML comment and a fenced
  code block; a `Refs:` line in any other form (another repository's issue, a URL, two issues, any
  other case) refuses `refs-line-not-plain`, two or more issues refuse `refs-issues:<n>`, and a
  number that is a pull request, or names nothing (GitHub's NOT_FOUND, a typo), refuses
  `refs-not-an-issue`. A closing issue always wins, and the
  `Refs:` issue is read with the same fields, so the cost decision, the verifier verdict, the
  enqueue recheck and the worker tier's class, provenance and claim checks read it as they read a
  closing issue. Nothing closes it on merge: GitHub closes only on a closing keyword, and the lane
  closes no issue. Such a pull request is class C2, as a
  Dependabot pull request is: no `work-class:` label is read, on the issue or the pull request,
  and the diff-derived C2 checks of the risk score still apply. No opt-in label or lane claim is
  read. No linked issue, or more than one closing issue, refuses (`linked-issues:<n>`); right
  before the enqueue the linked issue is read again and a different one refuses
  (`closing-issue-changed:<was>><now>`). The linked issue also refuses, at eligibility and again
  before the enqueue, while it carries a label from resolve-issue's
  `activities.resolve-issue.applies-when.labels-absent` (`closing-issue-held:<label>`), the one
  list of labels a person decides an issue on; with no such list, the tracker's human-gated role
  label holds it, and an issue label set or hold label that cannot be read refuses. A person
  clears the hold by removing the label. An edit to the issue after admission is the verifier's
  (`verify:spec-changed`), not a second check here. A pull request into any branch but the default refuses
  `base-not-default:<ref>`, read at eligibility and again before the enqueue; any read that fails
  refuses. An adopted pull request (owner decisions Q22 and 2026-10-22, [Adoption](#adoption)) is
  one a `User` or `Bot` on the trusted-actor list opened, matched by account id, never by
  login, that is not a draft, and, for a `User`, whose newest activity and head commit
  committer date are both at least `adoption.idle-hours` old (absent adopts nothing; an unreadable
  date is not idle; a value that is not a whole number from 1 to 720 adopts nothing), the setting
  and the list read at the default branch head,
  and that no hold applies to: the `do-not-merge` label, the
  tracker's human-gated role label as `docs/conventions/work-items.yaml` binds it, or a hold line in
  the body. Its activity is the newest of its opening, the head's arrival (the newest GitHub
  Actions check suite for the head commit on its branch, since a commit's dates are its
  pusher's; a `pull_request` workflow run that a label or title edit starts adds such a suite, so
  any account's label change there also delays adoption, never grants it), and each comment, review, inline review comment, label change, title edit, review
  request, ready for review, reopen or force push whose actor id is on the trusted-actor list,
  the lanes App
  and Dependabot left out, at its newest time, a comment's edit included (`trusted_activity`).
  The raw `updatedAt` is not read: any account that can comment moves it. Another account's
  activity therefore never keeps the pull request from going idle, except a hold (owner decision
  Q30) by an OWNER, MEMBER or COLLABORATOR (`author_association`, as for the human merge veto;
  on a public repository anyone else's would hold every pull request): its changes-requested
  review, or a `User` account's comment, review or inline review comment whose text carries a
  body-hold phrase ("do not merge", "don't merge", a line opening
  with `Hold:`), counts like a trusted account's; a bot's text is not read, since review lanes
  quote the phrase. A trusted account's comment, such as a person's request to wait,
  still refuses. A timeline or check suite listing
  that cannot be read whole, a head with no such suite on its branch, a listed event whose actor
  id cannot be read, or a counted event's unreadable time is not idle. While the
  lane's own merge-queue entry holds it at the current head (the lanes App
  enqueued it, its newest unedited pin comment names that head, and no other author has commented
  or submitted the newest review since that pin), recent trusted activity does not refuse; any
  other comment or review after that pin refuses again, as does an unreadable one. The same holds
  after the lane's own whole-review request at the current head: while the lanes App's newest
  reasons comment records a request at that head, the App's newest conversion to draft falls
  within `CONVERT_WINDOW` of the record's time (so an edited record time excuses nothing), and no
  person has commented, reviewed or commented inline since the record's time, recent activity
  does not refuse (`lane_toggled_at_head`); bots do not count. The head commit test and every
  hold still apply, and a draft still refuses. A person's merge-queue enqueue that the queue
  removed for failed checks also excuses
  both idle tests ([Adoption](#adoption)). The decision records it as `eligibility.adoption`
  (`idle-owner:<hours>h`, or `requeue-after-ejection`);
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
  `high-path-floor` (true scores the manifest review HIGH; the fixed HIGH path floor scores
  either way while `path-holds` is true),
  `path-holds` (true holds a pull request for a changed path alone: the path floor, `denied-paths`
  and `review-path:` in the gate, enable-auto-merge's and ci-status's hold paths; absent or false
  holds none and the gate report lists each skipped hold as `risk.pathHoldsSkipped`),
  `max-changed-files` and `max-changed-lines` (absent is no cap). This repository sets
  `high-path-floor: false` (owner direction 2026-10-24) and `path-holds: false` (owner decision
  Q15, 2026-10-29, until open issues and pull requests reach zero); the non-author verifier verdict, both AI review lanes, `ci-status` and the post-merge revert breaker gate the rest. It
  leaves the rest off (owner decision,
  2026-10-17). The local babysit lane ignores these switches and keeps the manifest review and
  both caps. `c2-contradictions` is deprecated and has no effect: the risk score reads no work class.
  The schema still accepts it so existing configs validate, and a gate report whose config sets it
  carries a `configNotes` entry saying so. The review evidence, the security lane's CRITICAL findings, the
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
  `vars` context as `--lane-rung-cap`. Empty (unset) is no cap; `off`, `merge` or `merge-reviewed`
  (or the aliases `C2` and `C3`) caps the rung;
  a missing flag or any other value holds the rung at `off`.
- **Post-merge check and merges in flight.** Only merges the agent identity enqueued count. A
  merge by a person or by another App, such as a release pull request, is not the lane's. An
  agent session's merge through the owner login is recorded on its own path and changes no lane
  state ([Merge paths](#merge-paths)).

Before it enqueues, the lane reads every person's comments on the pull request: issue comments,
review summaries and inline review comments. When the newest one from an OWNER, MEMBER or
COLLABORATOR says "do not merge" (`HUMAN_MERGE_VETO_RE`), the pull request is held (`human merge
veto from <logins>`). Writing "the `do-not-merge` label" is not a veto; any other
`do-not-merge`, a comma list included, is. That person lifts the hold with any later comment that does not say it, such
as "go ahead", or by editing the veto away. Another person's comment does not lift it, and neither
does an item with no text, such as an Approve with no comment or the empty summary of an inline-only
review. Comments from a bot or from `merge.agent-identity` hold nothing and neither do comments from
anyone else, so an outside commenter cannot hold a lane pull request. A bare "wait" is not a veto,
and neither are blocking words such as "regression" (the autopilot tier's wider scan).

An eligible pull request its score holds gets one `<!-- babysit-merge-risk -->` reasons comment
naming the score, the reasons and the head. While `merge.report-only` is false, a run that finds the
lane identity's reasons comment from an earlier run unchanged (same score, reasons and head) for at
least `merge.risk-escalation-minutes` (default 60, timed from the comment's last change; 0 is no
minimum) escalates the refusal when a holding reason is one only a person clears
(`babysit_risk.person_reasons`: a CRITICAL security finding, bound or not, a
trusted-actor widening, a cost hold, or a listing past the files API's cap; [when work stops for the owner](../../contracts/loop-lane/README.md#when-work-stops-for-the-owner));
any other reason, such as review evidence not bound to the head, keeps its comment and is judged
again each run. An escalation
([loop-lane §2](../../contracts/loop-lane/README.md#2-escalation-contract))
posts a new comment, that comment's text ending with a line saying the refusal persisted and needs a
person, then adds the tracker's human-gated role label when no label matches it ignoring case, so
the pull request leaves the WIP count and reaches the attended queue. A new comment notifies and is
dated beside the label, which the head-moved clear needs to pair them; an edit would do neither. An
unchanged escalation is never posted again. The minimum lets a review still
running at the head, which scores MED, finish first. Changed reasons rewrite the comment and
restart the time, except on a comment already escalated at that head, where they are posted as a
new escalation so the label never stands beside a comment without the escalation line; a new head,
or a score back at LOW, writes no label. A comment that differs only in line endings or trailing
whitespace counts as unchanged. A LOW score rewrites a
refusal comment naming that head, unless it is escalated, to say the refusal no longer holds, so a
later refusal at the head starts its time afresh. The merge gate never removes the label; the
`head-moved` clear above removes it once the head moves, and otherwise a person does. When the
label's newest removal came after the escalation comment's last change and was a person's (a User
of kind `human` on the trusted-actor list read at the default branch, never a retargeted base,
with write access; an unreadable default branch lifts nothing), it lifts that escalation: a later
run that finds the comment unchanged (same head and reasons) adds no label. A removal by a bot,
the lanes App included, by an account off that list, or made through a GitHub App
(`performed_via_github_app`) lifts nothing, and a new head or new
reasons escalate afresh, each as a new comment. The same holds for pr-merge's verifier, held-major
and shared-copy escalations. Under `merge.lane-prs` `native`, `enable-auto-merge` escalates a lanes
App pull request instead, and posts its escalation to a person as a new comment the same way.

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

Whole-review request (`babysit_whole_review.py`): when a lane or adopted pull request passes every other gate
and its only risk reasons are open findings a clean whole review of the head would close (no review
of that head reported a finding or was whole, and no lane thread is unresolved), the gate writes a
`Whole review requested at head` line into its reasons comment, then converts the pull request to a
draft and marks it ready with the lane token, so `ready_for_review` runs both review lanes whole.
That event also re-runs `pr-require-checks.yml`, `pr-test-platforms.yml` and pr-merge itself. The
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
in the run cache the next run starts from, built from two artifacts a scheduled or hand-started run
uploads, each read from the newest such run on the default branch holding it, found the way the
head-ref map is (`.github/scripts/pr-merge/carry-run-cache.mjs`). `pr-merge-run-cache`, from the
`merge` job, carries the refusals and the carried verdict reads; `pr-merge-verify-run-cache`, from
`enable-auto-merge` and only when it kept a read, carries the verifier's carried verdict reads, of
which only the `carried-*` sections are added. A file that does not read is dropped with a warning
and the other is still used. Neither passes
through `actions/cache`, which any job in the default branch's cache scope can write. Even a forged
file can only repeat a refusal, for at most `max-minutes` from the judgment time it names. A change the key does not cover,
such as a demotion record, a ruleset, an edit to a comment older than the newest 50 or a gate import
outside the keyed paths, delays re-gating by at most those limits; a skip never merges, enqueues or
drops an escalation.

#### Native auto-merge

The lane's `enable-auto-merge` activity, the `enable-auto-merge` job of `pr-merge.yml` with its
own lanes App token (`.github/scripts/pr-merge/enable-auto-merge.mjs`, no model), turns on GitHub's
native auto-merge (`enablePullRequestAutoMerge`, squash, `expectedHeadOid` the head it read) for
each open lanes App pull request into main from a branch of this repository that is not a draft
and carries no hold: no `Hold:` line or "do not merge" in its body
(the gate's own rule), no `do-not-merge` or human-gated label, and no member (owner, member or
collaborator) whose newest comment, review or inline comment with text says "do not merge" (the
gate's veto rule; a later comment lifts it), and whose head changes no path in the lane's
`merge.diff-check.denied-paths` or on the [path floor](#merge-authority) (`merge-holds.mjs`
`HOLD_PATH_FLOOR`, the floor's `trust` and `gate` globs, equal to `babysit_risk.Floor.high`), read on the files the head changes at each
run, unless a person on the trusted-actor list approved that head, or an earlier head it carries to, as `ci-status` reads it, and whose
issue link and verifier verdict at that head pr-merge's gate would take:
`babysit_verify_evidence.py evidence --lane-link` refuses nothing, so the link is one the gate's
[eligibility](#the-pr-merge-lane) rule takes (one closing issue in this repository, or, with none,
the one issue its plain `Refs: #<n>` lines name; a failed read refuses) and whose issue clears
the trust hold (`babysit_merge_policy.trust_refusal`: its labels read whole, none naming untrusted
work in any spelling, and none ever removed by a non-human or through an App, so a label added
after admission refuses as `untrusted-provenance`, `untrusted-provenance-removed-by-non-human` or
`issue-labels-unreadable`, each a refusal a person clears, the removal one only through a new
issue: see the trust hold below), a PASS or PASS-NOTES of [pr-verify](#verifier-verdict) stands at the head,
no FAIL is at it, no earlier FAIL is uncleared, FAILs sit at fewer than `merge.max-verify-fails`
heads, and the spec is unchanged and trusted; and `evidence --lane-reviews` finds no hold on the
gate's risk score (`babysit_risk.score` over the inputs the gate builds, at the lane room's rung):
an open CRITICAL security finding or a review not bound to the head, whether or not the lane
applied its hold label, a symlink, submodule or other non-regular mode, a high path, the manifest
review, the trust gate and the cost review all hold; and `evidence --lane-queue` finds the merge
queue has removed the head for failed checks fewer than `merge.max-queue-ejections` times since it
last changed, the gate's own count and limit (`babysit_merge.queue_ejection_refusal`). GitHub does
not re-arm a pull request the queue removes, so without this cap each scheduled run would arm a head
that keeps failing its merge group again. At the cap the pull request is left unarmed with the
gate's `<!-- babysit-merge-queue-ejections -->` comment and no label, since a push resets the
count; an unread count leaves it unarmed with no comment, and the next run reads it again. An
armed one is not disarmed on the count. Each such run also
waits for the same run's `post-merge-dispatch` job and reads the lane's room from the post-merge
report that job keeps as an artifact (on an idle tick the last run's report, which that job reuses
unchanged while nothing its check reads has moved, `babysit_verify_evidence.py settle --idle-tick`;
`babysit_verify_evidence.py lane-room`; with no report it
holds as a refusal does; one the gate would not reuse, for any `shared_refusal`, is checked again
as the gate does; one refused only because a demotion record was filed or changed since is first
kept when the demotion records alone read as they were; one past the two-minute age only because a
lane merge is still unverified is kept, here and by the gate for each candidate up to the
answer's 30-minute age (`postMergeShared: kept:unverified-stale`), while main's head, its
config commit, the demotion records and the full and canary runs of every merge it judged are as
they were (no run reached a conclusion since that the check had not already read finished, no merge is past the six-hour dispatch deadline, and no
quarantine that excused a failing suite has expired), and otherwise checked again as the gate does,
with the lane records the last run kept, holding only when that check cannot be read): while the gate holds its lane off (a demotion record,
`merge.rung`, the loop setting or the rung cap off, a lane merge that failed its post-merge check)
nothing is armed and every armed lanes App pull request is disarmed; at `merge.max-in-flight`,
counting the queue's lane entries, the lane's unverified merges and armed pull requests the queue
has not taken, nothing more is armed; a room that cannot be read (no report, a failed read) holds
as a refusal does. A held room raises one warning annotation and step-summary line naming why and
each lanes App pull request it left unarmed or, report-only, that a disarm would have turned off,
and one error annotation and summary line naming each one still armed because its disarm failed;
it posts no comment on the pull requests.
Only the scheduled run and a hand-started one read
them and arm, last, for a pull request every other rule would arm or keep armed, with the gate's
head-ref map and run cache and one artifact listing for the run, which its first pull request reads
and every later one uses at any age, an allow included (`evidence --shared-listing`), since the
merge queue runs the reader again at the head it merges; an event run reads no link or verdict,
never arms, and
only disarms on a hold, so a pull request waits up to one scheduled interval to be armed. GitHub
checks `expectedHeadOid` only when the arm is made, and turns auto-merge off only on a push by
someone without write access
([Automatically merging a pull request](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/incorporating-changes-from-a-pull-request/automatically-merging-a-pull-request)),
so a push by the lanes App or a person with write access leaves on an arm whose checks judged the
head it moved off. The merge queue's `ci-status` holds a head that the lanes App's newest pin
(`<!-- babysit-merge-pin sha=... -->`, posted just before each arm) does not name, or that pin
when it was edited or its edit time does not read, unless a trusted person's approval of that head
lifts it (`merge-holds.mjs` `pinHold`). The queue's failed
check removes the entry, and GitHub drops the arm with it. `enable-auto-merge` also disarms an armed
one whose head that pin does not name, and its next scheduled run judges and pins the new head
before arming it again. Turning auto-merge off needs `contents: write`, which the lanes App's
arming token holds and `ci-status`'s `GITHUB_TOKEN` deliberately lacks, so `ci-status` holds
rather than disarms. The merge queue's
`ci-status` also holds a new head until a pr-verify pass stands at the exact head it merges. That check
reads the pull request's live head, not the SHA in the queue ref, and relies on GitHub dequeuing an
entry when its head branch is pushed. `enable-auto-merge` turns auto-merge off on an armed one that
now fails any of those, and does not turn it back on once a person has turned it off. A scheduled or
hand-started run that leaves a lanes App pull request unarmed on report-outcome's own
`Hold: a human merges this` line, a hold path, a cost hold, the gate's verdict or its risk score
says why in one `<!-- babysit-merge-risk -->` comment, edited in place, and adds the human-gated
label only for a cause a person must clear ([when work stops for the owner](../../contracts/loop-lane/README.md#when-work-stops-for-the-owner), with cost and trust holds
kept): that hold
line (owner decision Q-HOLDLINE), a configured denied path or a [path floor](#merge-authority) path,
a cost hold, untrusted provenance, an issue whose labels cannot be read whole, an untrusted spec, a
security finding, a trusted-actor widening or a listing past 300 files. It puts the label back while the comment stands
unless a person removed it since; a person's own hold text gets neither. Every other refusal, a
listing read that failed included, is the lanes': later scheduled runs judge it again, and once a
lanes' refusal has stood at the head for `merge.risk-escalation-minutes`, timed from the first one
noted there (the comment's `pr-merge-unarmed-since` line), the `unarmed-status` job posts a failing
`pr-merge/unarmed` commit status on the head; arming, or the refusal becoming a person's, posts a
passing one over it. The status is informational, not `ci-status`, and that job trusts only a status
the GitHub Actions bot posted. GitHub then merges the pull request through the merge queue
once `ci-status` passes, which in the queue also holds a pass that no longer binds the live link:
the body must still close, or with no closing issue name by a plain `Refs:` line, the issue the
pass judged, linked the same way, alone or beside others (`merge-holds.mjs` `linkHold`), so a body
edited after arming to drop its link or name another issue does not merge on that pass. A pass
or pass-notes verdict wakes it for that one pull request: `pr-verify.yml`'s `wake-pr-merge` job
reads the pull request once and, for a lanes App one that is not already armed and carries no
`do-not-merge`, dispatches a PR-scoped `pr-merge.yml` run (`-f pr=<n>`, run name `pr-merge: arm #<n>`) that
reads and arms only that pull request, its lane room from the last sweep's post-merge report,
and skips the merge job, `post-merge-dispatch` and every other sweep job. That report stands only
while `settle --idle-tick` keeps it; when it does not, the wake never reuses it but runs the
post-merge check fresh on its own read-only token, and arms only when that check passes (exit 0
or 5) and `settle --idle-tick` keeps the fresh report too, since the wake starts no full run or
re-run. Before those reads, one listing read ends the wake with nothing armed when main's newest
full dispatch run's head commit lacks the newest commit the lanes App authored on main
(`babysit_postmerge.py --uncovered-at`), where the fresh check would stop at exit 6; any other
answer runs the path above. Its `api-calls` totals, which report the room came from (`report=last`, `fresh` or `none`) and
the outcome land in one `pr-merge-wake` notice. The 30-minute schedule is the backstop that arms
what a wake missed and disarms what the events missed; a listed human's unlabel wakes it too. A
`Hold:` line added after arming fails `ci-status` on that edit, on the pull request and in the
merge queue, and the next scheduled run disarms. The issue lane finishing does not wake it:
an event run never arms, and a pull request the lane just opened is not armed, so there is nothing
to disarm. The token broker mints `merge` only for `pr-merge.yml`, and outside the schedule only
for a listed human's run. While `merge.report-only` is true it reports each decision and writes
nothing.

Each verifier read is a full read. The arm step's skip records (`merge.skip-unchanged`) cross runs
only as the `pr-merge-verify-answers` artifact of a scheduled or hand-started run on main
(`verify-answers.mjs`, as the head-ref map is read). Every reader run keeps a file, empty when it
keeps no records, so the next run never skips on an older run's records: the arm step writes it
empty before the kill-switch check or any read, and overwrites it with its records at the end. Only
a `GITHUB_REPOSITORY` that is not `owner/repo`, a failed write, or an arm step that never starts
leaves no file.

`merge.lane-prs` (default `native`) decides whether the merge gate still handles the lanes App's
pull requests. Under `native` the `merge` job's candidate listing does not ask for them, so the gate
never scores, escalates, toggles or enqueues one; native auto-merge and `ci-status` are their whole
merge path. Owner pull requests the lane adopts and Dependabot's are listed and gated as before,
and the post-merge check, the full-run dispatch, re-firing refused runs and clearing escalations
run unchanged. `gate` lists the lanes App's pull requests for the gate as well, which is how the
lane ran before this setting; the `enable-auto-merge` job arms them in both modes.

While the lanes kill switch is on (`CLAUDE_LANES_DISABLED` or `CLAUDE_LANES_REPO_DISABLED` reads
anything but `false`), `ci-status` fails every lanes App pull request, so one armed before the switch
was turned on stops in the merge queue; owner and Dependabot pull requests are not affected.
Once the switch is lifted, the next `maintenance-reconcile-lost-runs` run (half-hourly) re-runs the
failed `ci-status` of each open lanes App pull request whose newest checks run the switch failed on
its first attempt, at most three per run, merge-critical first; while the switch is on it reads
nothing. A pr-unblock run the switch stopped mid-run posts its check neutral `kill-switch`, which no
dispatcher counts as handling the head, so the next dispatcher run after the lift (the half-hourly
`pr-unblock-dispatch.yml` tick, or a review completing at the head) dispatches it again, at most
`limits.limit-stops-per-head` times per head, `SWEEP_HEAD_CAP` for `address-feedback`.
`ci-status` enforces a member's veto comment and the hold paths on every lanes App pull request,
so one added after arming stops the merge without waiting for this job: its step
`Fail a lanes App pull request on kill switch, hold path, verifier or veto` runs
`.github/scripts/pr-merge/merge-holds.mjs` as main has it, the module `enable-auto-merge.mjs` arms
by, over the live body, discussion and changed files (renamed-from paths included) against main's
`merge.diff-check.denied-paths` plus the path floor (`HOLD_PATH_FLOOR`, a constant of the module
main has, so a pull request cannot rewrite it), and holds a trusted-actor list change that
adds or widens an entry, both sides read at `BASE_SHA` and the head (`actorsHold`), on each pull
request event and in the merge queue, where a red group removes the pull request. A push that
adds a hold path or such a widening fails `ci-status` on its own head. A person on the trusted-actor list
(as main has it) lifts either by approving that head (their newest review of it that approves,
requests changes or was dismissed must approve). Then re-run `ci-status`, since a review does not.
Only an approving review lifts it: removing the human-gated label does not. The approval carries
to a later head whose every change since is a merge of the base (`merge-holds.mjs` `liftersOf`
and `approvalCarry`), so a base merge after a person's approval does not send the pull request
back to them:

- Each trusted person's newest review that approves, requests changes or was dismissed counts
  (`liftsOf`); it lifts only when it approves, and then its commit. An approval GitHub dismissed
  as stale on a push (the trust-root ruleset's `dismiss_stale_reviews_on_push`) still counts,
  bound to its own commit and only through the carry (`autoDismissed`): the issue timeline's one
  `review_dismissed` event for that review has a Bot actor (the account whose push dismissed it),
  a null message and a dismissal commit among those pushed since the approved head. A dismissal
  whose actor is a person revokes the approval: their own dismissal, or the stale dismissal their
  push caused. The Bot actor is what tells GitHub's dismissal from a person's; that an App's
  deliberate dismissal always carries a message is unverified, so the null message is a second
  filter.
- The carry (`approvalCarry`) runs only when the pull request's base is the repository's default
  branch, since another base may be non-linear, with criss-cross merge bases. The base branch is
  read once by its full ref (`baseTip`, `refs/heads/<base>`), and every compare against it names
  its tip commit, so no tag of the same name stands in for it. Every commit the current head adds
  is a merge whose parents other than the first the base holds (`baseMergesOnly` over
  `mergedParents`; `baseParents` reads each parent's compare against the tip, `ahead` or
  `identical`), and the approved head is among its commits, so a non-merge commit, a merge of
  another branch or of a crafted merge commit, or a force push that rewrites the approved head
  carries nothing. Then either the net change against the tip is the same at both heads over
  every file (`sameNetChange`), or the merges brought exactly the base's changes
  (`exactBaseCarry`): the compare from the approved head H to the current head H' lists, file for
  file and with the same status, `previous_filename` and patch, what the compare between the merge
  bases of H and of H' (M and M') with the tip lists, and the recursive trees of H' and M' give
  each of those files one mode (a removed file, or a renamed file's old path, in neither). A merge
  that writes any change of its own, to a hold path or any other file, flips the mode of a file the
  base changed, or drops a base change, carries nothing. Either compare listing 300 files or more,
  a commit list not read whole, a file with no patch, a truncated tree, or a head in a fork carries
  nothing. The exact path assumes GitHub omits no file from a compare's list of fewer than 300
  files; nothing checks that against a second listing. The compare API reports no file mode, so a
  mode-only change still reads the same on the same-net-change path: a known residual there.
- An approval of the current head lifts the verifier and issue-link holds too; an approval of an
  earlier head does not, since the merge result is new to pr-verify.

The approval lifts no body hold or veto, and a read that fails lifts nothing. `enable-auto-merge`
reads the same approvals and stops holding the pull request on the hold path, and the gate's risk
score (`evidence --lane-reviews`, `lane_risk_refusal`) drops its `high-path:` reasons for a path
on `babysit_risk.Floor.high` or in `merge.diff-check.denied-paths` on the same approvals
(`babysit_merge_policy.path_lifters` and `carried_lifters`, which `test_merge_holds_sync.py`
holds equal to `pathLifters`, `liftsOf` and `baseMergeCarry`), so its other checks decide. The
approval lifts no aliasing path, symlink, submodule or mode change (`high-path:**`), cost,
trust-gate, manifest, file-cap or review-lane hold, and a review list or trusted-actor list that
does not read lifts nothing.
Both also hold a pull request that changes one of the merge gate's cost paths
(`babysit_risk.COST_PATHS`: Pulumi, Terraform, Bicep and ARM template files). An
approval does not lift that hold. Only the owner's cost decision does, read as the gate's
`cost_decision` reads it: an unedited comment by a person on the trusted-actor list whose first
line opens `**Decision recorded.** Cost:`, on the pull request or on its one closing issue after
the pull request opened, linked from the body. That body edit re-runs `ci-status`. The decision
carries to a later head by the same `baseMergeCarry` as the hold-path lift, on the whole net
change rather than the hold paths alone. The module is read at the pull request's base commit, so a lanes App pull
request whose base predates the module fails `ci-status` closed until it is updated with main.
A pull request cannot weaken its own check, since the step runs the module as its base has it; a
change to `merge-holds.mjs` merges on the review lanes, and the lanes App's token, which carries no
`workflows` permission, cannot push a change to this workflow. A body edit re-runs
`ci-status` at once. A comment does not, so a veto posted while armed takes effect when the queue
builds the group, and after a person lifts one with a later comment, `ci-status` needs a re-run.

In the merge queue the same step also requires a verifier pass at the queued pull request's live
head: an unexpired `pr-verify-<pr>-<head>-pass` or `-pass-notes` artifact, with or without the
head-branch digest, taken by exact name and uploaded by a completed, successful
`workflow_run` run of `pr-verify.yml` on main here (`verdictHold` in `merge-holds.mjs`). Whatever
GitHub does with an armed request when the head moves, the queue's check on the head it merges
holds a head pr-verify has not passed. The same trusted approval of the head lifts it, the path for a pull
request the gate sends to a person. It runs only in the queue: pr-verify runs only after a
`pull_request` run of `pr-require-checks` that succeeded or failed only on holds an approving
review of the head lifts, so a `ci-status` red for anything else there would never get a verdict,
and a pull request event makes no verdict read.

The queue also runs pr-merge's verdict reader, `babysit_verify_evidence.py evidence --base-sha`,
from a checkout of main for the queued pull request at its live head, on a listing of its own, and
holds on its report (`evidenceHold` in `merge-holds.mjs`): every FAIL class the gate counts (a FAIL
at the head under any number, an earlier FAIL tied by number, commit or head branch, the
`merge.max-verify-fails` cap with other pull requests' FAILs for its issues, an untied FAIL whose
record cannot be read), `verify:unreadable` and `verify:too-old`. A FAIL uploaded after
`enable-auto-merge.mjs` read its run's one listing still holds. The refusals a pass decides
(`verify:missing`, `verify:spec-changed`, `verify:untrusted-spec`) stay with `verdictHold` and
`linkHold`. The same trusted approval of the head lifts it. A refusal the reader returns before
it lists artifacts (an unread config or commit list) reaches `merge-holds.mjs`
with no pass names, so it holds the same way and the same approval lifts it. Otherwise the pass
names come from the reader's listing. The reader starts from pr-merge's head-ref map and carried
run cache, the `pr-merge-run-cache` artifact of the newest scheduled or hand-started pr-merge run
on main (`carry-run-cache.mjs read`; `ci-status` restores no Actions cache), so it reads only what
landed since that run: about 73 requests for one pull request, where a cold reader makes about 860
(measured 2026-10-25 on 6,620 artifacts, 294 of them FAILs). A head-ref map that does not read only
leaves it reading more. With no carried run cache, or one whose carried sections are all empty
(the artifact is kept for one day, so pr-merge with no successful scheduled or hand-started run
that long leaves none), the step reads the base branch's `merge_queue` rule and GitHub's
`/rate_limit`, which costs no request. A missing cache is shared, so every entry the queue builds
at once goes cold together, so the step first lists every artifact page once and the cold reader
starts only when the token's core pool then has at least one cold read's worst case under the
listing's caps (the step's own listing, 3 reads per listed FAIL, 3 incremental reads of at most 13
pages each, one count read, and 3 whole listings of up to 3 attempts of `ceil(total_count / 100) + 1`
pages, each with a top-up of at most 7, at most 24 pages near expiry read again and 34 artifacts read by id:
1,681 at 7,522 artifacts and 264 FAILs) times
`max_entries_to_build`, plus the
read floor (`limits.api` `read-floor` of the planned limit, inlined in the job env), left.
An entry with a carried run cache but no carried listing pays the listing's part
without this check. A listing, rule or rate limit that does not read, a stop in the
job's stop file, or less headroom than that holds the pull request, so the queue ejects it and the
ejection counts toward `merge.max-queue-ejections`. `ci-status` allows 20 minutes for a cold read,
about 6 to 11, at most about 15. It reads with `ci-status`'s token, which holds no `issues`
scope: an issue read that does not answer refuses `verify:unreadable`, which holds.

In the merge queue another author pr-verify judges holds on a pr-verify FAIL only (owner decisions
2026-11-04, "Hold on FAIL only (Recommended)" and "FAIL holds, cap not (Recommended)"), since an
owner's credentials can queue a pull request pr-verify failed. The step judges the author as `resolve-pr.mjs` does: not a dependency
manager's, and `merge.verify-authors` in the hold config's `pr-pipeline.yaml` (`lane-or-owner`
there: a `User` or `Bot` whose id the trusted-actor list holds). For such an author it runs the
same verdict reader and holds only when it reports `verify:fail` or `verify:earlier-fail` for the
head, judged by the base module's `evidenceHold`. The `merge.max-verify-fails` cap
(`verify:repeated-fail`) only warns. No pass, a stale or untrusted-spec pass, `verify:unreadable`,
`verify:too-old` and a reader that does not judge it leave it to merge. It reads only the reviews, bodies blanked, and no file list, so the
kill switch, member veto, hold paths, cost paths and trusted-actor list holds stay the lanes App's.
A trusted approval of the head lifts the FAIL hold, but
[a pull request's author cannot approve it](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/reviewing-changes-in-pull-requests/approving-a-pull-request-with-required-reviews),
and the trusted-actor list names one person, so on an owner-login pull request the lift is a new
head that pr-verify passes. An author pr-verify does not judge, and every author on a pull
request event, is left to the merge gate or a person, as before. The step
`Read whether the queued pull request is the lanes App's` outputs `verify_judged` by the same
test, so the carried-read steps run for every judged author.

The trust hold has three checks. At PR open, report-outcome writes a `Hold:` line when the issue
already carries `provenance: untrusted`. At arm time, `enable-auto-merge` refuses it
through `evidence --lane-link`. In the merge queue, `ci-status`'s step `Fail a queued pull request
carrying a hold label` reads the queued pull request's linked issue when an automation opened the
pull request. The linked issue is its closing issues here, or with none, the one issue its plain
`Refs:` lines name, by the base's `refsIssue`. The step fails when that issue carries a label
containing `untrusted` in any ASCII case (as `babysit_merge_policy._untrusted` matches it), or had
one removed by anyone other than a person on the base's trusted-actor list, or through an App. A
lanes App pull request that does not link exactly one issue here also fails, so dropping the link
after arming does not skip the check; another automation's pull request that links none passes. An
unreadable link, label list, timeline or trusted-actor list fails closed. So a label added after
the pull request opened, while it waits to be armed or sits in the queue, stops the merge, and a
person on that list lifts it by removing the label and re-queuing. A person's own pull request is
not read.

report-outcome writes no `Hold:` line because of the issue lane's runner checks, failed or not
reported (missing or for another tip): that line would also fail `ci-status`, so pr-verify would
never run, and `ci-status` reruns those checks on the head, where a failing one goes to the fix
lanes like any other. The PR's Verification section lists each runner check's result. A `done` run
whose runner check failed opens no PR: it stops `check-failed`, which retries. A reuse leak scan is
not covered that way, so on a reused branch any scan word but `clean` still holds: `lint-repo`'s
gitleaks scan honors a `gitleaks:allow` comment or `.gitleaksignore` the branch can add, its
password rule misses short or symbol-bearing values the lane scan flags, and it reads only the
commits' patches. Every trust reason still writes the line.

A removal by a non-human cannot be lifted on that issue: both readers check every removal in the
issue's timeline, and the timeline keeps it, so a trusted person re-adding and then removing the
label still holds. The way out is a new issue a person files for the work, and a new pull request
linking it.

### Dependabot pull requests

No Dependabot pull request waits on a human
([ADR 0073](../../adr/0073-merge-dependabot-pull-requests-in-the-pr-merge-lane.md)), except a major
update, an unreadable version or disagreeing sources under `merge.dependabot.majors: hold`
(below). This repository sets `review`, so the review verdict decides those too (owner
direction 2026-10-24). The pr-merge
lane is the one merge authority for both tiers. It lists Dependabot's open pull requests beside
its own and judges each as its own class, in place of the eligibility above. Both lanes sort by
the same rules (`babysit_dependabot.py` here, `dependency-classify.mjs` in pr-unblock):

- **Tier `auto`.** Every update is non-major: the first numeric version component does not change,
  and below 1.0 the second does not either. Every update on a `dependabot/github_actions/...`
  branch comes from the `actions`, `github` or `anthropics` publisher. The newest `ci-status` run
  on the head is not red (`failure`, `cancelled`, `timed_out`, `action_required`,
  `startup_failure`). The updates come from the `updated-dependencies` metadata in Dependabot's
  verified commit when it is there, and from the title (`bump <name> from <a> to <b>`) or a
  group's body `Updates` lines otherwise. A metadata entry with no `update-type` (a security
  update writes none) takes its jump from the same verified commit's subject when that subject
  opens with `Bump <name> from <a> to <b>` for that entry's name and version, never from the PR
  title. When both read, they must name the same dependencies and agree on which are major.
- **Tier `review`.** Anything else, including anything unreadable (a SHA version, an unparsed
  title), every update to a [review-only dependency](#review-only-dependencies), and an npm or
  pip update whose [registry provenance](#registry-provenance) changed. The pr-unblock lane's review activity reviews it, and the pr-merge lane merges it only
  when the newest round marker the lanes App posted on it
  (`<!-- pr-unblock:review-dependency-round head=<sha> verdict=merge run=<id>-<attempt> -->`)
  names the current head with `verdict=merge`. A marker from any other author is ignored. The
  review's verdict job posts no merge marker on a pull request whose change to a workflow or
  action file is anything but a full-SHA pin swap (each `uses:` line keeps its action path and
  moves from one full SHA to another, with only the trailing comment otherwise changing), and
  escalates `dependency-workflow-unpinned`. A `fix` verdict lands only when
  its commits change nothing but npm or pip manifest and lock files outside `.github/`, in a
  directory `.github/dependabot.yml` lists for that ecosystem, each modified in place as a regular
  `100644` file and changed only by a version (the **fix rule**: in `package.json` only an
  existing dependency entry's plain, bounded semver range (no `*` or lower bound alone), and one
  `allowScripts` key `@anthropic-ai/claude-code@<old>` renamed to `@anthropic-ai/claude-code@<v>`
  with its value kept, where `<v>` is the exact version the manifest pins in the commit before the fix and after it, never a manifest move with it, a name-only or
  wildcard key, or any other package's pin (`INSTALL_SCRIPT_PINS`); in a
  lock the same package keys as the Dependabot commit's lock, each entry's `resolved` exactly
  `https://registry.npmjs.org/<name>/-/<unscoped name>-<version>.tgz` for its own name (or
  alias `name`, which must be the Dependabot commit's) and version with a `sha512-` integrity, and no install-script change; in
  requirements only added `name==version` pins of projects the fix also unpins, and
  `--hash=sha256:` continuations); anything else keeps the fix off the
  branch and hands the pull request to a person. The verdict job posts no merge marker unless
  every commit is Dependabot's own or a commit that passes the fix rule,
  each arriving in its own author's push (**Pushes** below) (`dependency-fix-refused`)
  ([pr-run-activity, "review-dependency"](pr-run-activity.md)).
- **Commits.** Every commit is a GitHub-verified Dependabot commit; any other commit, a
  `github-actions[bot]` one included, is `commit-not-dependabot:<sha>`. On a reviewed pull request the lanes App's
  verified `[dependabot skip]` fix commits count too, each only after it passes the fix rule. The commits listing must hold the pull
  request's whole commit count, else the reason is `commits-listed:<listed>-of:<total>` (the
  listing stops at 250). A lanes App commit must pass the fix rule against its one parent, read
  from the commit's files, tree modes and both sides' text, else the reason is
  `dependabot-fix-content:<why>`. A commit's author is text whoever creates it
  chooses, so two more checks bind the pull request to Dependabot:
  - **Pushes.** The repository activity API for the head branch, read back to Dependabot's newest
    branch creation or force push, shows every push by `dependabot[bot]`, or, after a review, by
    the lanes App pushing a commit of the pull request, and the newest push is the head. Each commit a push brought (its `after` and the
    ancestors its `before` lacks) is its pusher's own: a commit with Dependabot's author arrives
    in a `dependabot[bot]` push and a lanes App commit in a lanes App push, else the reason is `pushed-by:<login>`. A commit no
    push in reach brought is `push-history-incomplete`. The pr-unblock verdict job runs the same
    check before it posts a merge marker.
  - **Content.** Every changed path, either side of a rename, is a manifest or lock file of an
    ecosystem and directory `.github/dependabot.yml` lists at both the base and the default branch
    head, matched literally (a pair only one side lists covers nothing, so neither side widens the
    other) (npm `package.json`,
    `package-lock.json` and the like; pip `requirements*.txt`/`.in`, `pyproject.toml`, `uv.lock`
    and the like), or a workflow or action file of a `github-actions` entry whose diff changes only
    `uses:` lines (`/` covers `.github/workflows/` and the action files under `.github/actions/`).
    A directory holding `*` or `?` is a glob, read the same way in both lanes: `*` and `?` stay
    inside one path segment, `**/` is zero or more whole segments (so `**/*` covers the root and
    every layer below), any other `**` crosses segments, and everything else is literal. A path the version-bump or lanes App fix
    commit touched counts as checked; a fix commit may touch only npm or pip manifest and lock files
    outside `.github/` in a listed directory (the pr-unblock lane enforces this at the base before
    the fix lands; the gate checks it against the pairs both sides list, and a fix outside them
    refuses), and one whose file
    list cannot be read whole refuses. Anything else (a rebuilt bundle, a manifest outside a listed
    directory) makes the pull request tier `review` with the reason `dependabot-content:<path>`,
    so the AI review judges it; it is never left for a person. A failed push check, by contrast,
    always refuses, verdict or not.
- **Gate.** Either tier merges only once `ci-status` succeeded on its head, through the same gate
  as the lane's own: mergeable, no `do-not-merge` label, no body hold, no blocking comment from a
  human with write access, the rung (`merge` (`C2`) or above) and its cap, the kill switches, the post-merge check and
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
  a person merges it. `review` leaves it tier `review`, merged on the verdict above. When the
  head moves, `clear-escalations.mjs` removes that label like pr-merge's other escalations, so
  the new head is judged afresh.

The class is `babysit_dependabot.py` beside the wrapper. Auto-merge armed with `GITHUB_TOKEN` is not used: GitHub's
[`GITHUB_TOKEN` page](https://docs.github.com/en/actions/concepts/security/github_token) says
"events triggered by the `GITHUB_TOKEN` will not create a new workflow run" (`workflow_dispatch`,
`repository_dispatch` and some `pull_request` events excepted, not `merge_group`), so the queue
entry such an arm makes never gets its `ci-status` run and never lands (#6717, #7512).

`.github/workflows/pr-merge.yml` runs the lane's `merge-pr` activity with no model and no head
checkout. A label coming off a PR, a manual dispatch and a schedule every 30 minutes each only
wake it; it lists the candidates from the API and runs the gate on each under the lanes App token
the broker mints for that file on `main`. A body or ready change on a PR, or a finished `ci-status`
or review run, is picked up by the next scheduled run, not by a wake-up of its own: runs are
serialized, and the triggers must start them more slowly than they finish to stay under GitHub's
cap on queued runs. The one exception is a pass verdict, which wakes only the enable-auto-merge
job for that pull request (the PR-scoped dispatch above); the merge job does not run on it.

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

#### The Merge-Risk line

Each arm records the head's merge-risk rating in a lanes App comment on the pull request (owner
decision Q57, #13657: record ratings so revert rates per risk level can be measured, and wire
`demote` into no gate yet). The comment's first line is a marker naming the head, and its second
is the line:

```text
<!-- merge-risk-line head=<sha> -->
Merge-Risk: max=<level> demote=<bool> head=<sha> rubric=<review plugin version> rater=<model> checker=<model>
Merge-Risk: unrated reason=<pending|no-run|no-rating|invalid|unreadable|over-budget>
```

- **Where the rating comes from.** `pr-rate-merge-risk.yml` runs on pr-verify's trigger as its own
  run, so a PASS never waits on it, for each open, non-draft lanes App head that passes
  pr-require-checks. It reads the pull request with pr-verify's base-side steps
  (`resolve-pr.mjs` with `RATED_WORKFLOW_PATH` and `RATED_ARTIFACT_PREFIX`, the trigger gate,
  `select-trusted-text`), writes `/review:merge-risk`'s `--dir` files (`pr-merge-risk/input.mjs`),
  and runs the skill and its blind checker on `run-claude-cli` under `dontAsk`, as the `pr-verify` role
  on the three legs every model lane runs, one credential per job: `rate-merge-risk` on
  `PR_VERIFY_CLAUDE_API_KEY` (skipped while its credit stop is recent, `check-key-credit`), then
  `rate-merge-risk-subscription` on `PR_VERIFY_CLAUDE_CODE_OAUTH_TOKEN`, then
  `rate-merge-risk-fallback` on `FALLBACK_CLAUDE_CODE_OAUTH_TOKEN`, each after the one before
  handed off or found its credential empty. Each later job repeats every step from a fresh
  checkout. `pr-merge-risk/write-rating.mjs` checks the result's
  shape, recomputes `max` (the highest `level` or `checker_level`) and `demote` (`max` HIGH or
  CRITICAL), takes `rater` and `checker` from the execution file's main-thread and subagent
  models, and uploads `pr-merge-risk-<pr>-<head>` for 7 days. A head already rated by a run of
  that file on main is not rated again. The skill's frontmatter pre-approves bare Read once it
  runs, so the workflow's deny rules bound what the model reads: `.base`, the runner's temp
  directory, the home's credential and Claude files, and `/proc`, `/sys` and `/etc`.
  `--restricted` keeps the file tools inside the workspace, which holds only the data directory,
  the plugin copy and `.base`.
- **Its model.** The `merge-risk` route of [Models](#models). The profile's `subagent-model` sets
  the checker's model with `CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1`, over the agent file's pin; the
  checker's effort stays its agent file's (owner decision Q1).
- **How the arm writes it.** Just before an arm, after the pin, `enable-auto-merge.mjs`
  (`merge-risk-line.mjs` `recordMergeRisk`) finds that artifact by exact name, counts it only from
  a run of `pr-rate-merge-risk.yml` on main started by `workflow_run` in this repository, checks
  it again, and builds the line from closed values alone. With no artifact, a run of that file
  still going for the head is `pending`, a finished one `no-rating`, none `no-run`. It then reads
  the pull request's comments the arm already listed, and lists none again. When the lanes App's
  newest marker comment names this head and holds this line, or holds a rated line while this
  one is `unrated`, it writes nothing, so a later failed read never overwrites a rating; when it
  names this head with another line (`pending` before the rating landed, or another rating), it
  edits that comment. When that comment was edited by anyone other than the lanes App (its
  `editor`, or an editor that does not read, with `lastEditedAt` set) it is no longer the App's
  text, and the arm posts a new comment, as it does in any other case; the App's own edit keeps
  it trusted. The comment is the App's own text, so it records the rating on every armed pull
  request, whoever wrote the body. It never edits the pull request body.
- **Why a comment.** A merge queue ignores a commit body given at arm time: GraphQL's
  `enablePullRequestAutoMerge` documents `commitBody` with "when merging with a merge queue any
  input value for commit message is ignored"
  ([Pull requests, EnablePullRequestAutoMergeInput](https://docs.github.com/en/graphql/reference/pulls),
  read 2026-11-06), so only the pull request body could carry the line into the squash commit
  (`squash_merge_commit_message=PR_BODY`). A body edit would be a `pull_request: edited` event,
  which starts a contract-only pr-require-checks run whose completion starts pr-verify,
  pr-verify-capture, pr-rate-merge-risk and pr-review-main runs that only confirm answers already
  given, about 36 `GITHUB_TOKEN` core calls per arm (the job-call records of the five body edits
  from 04:53 to 05:38 UTC on 2026-11-12), and the queue would wait about 50 seconds for that run's
  `ci-status`: run 42173684490 (2026-11-06, every lane job skipped) reported `ci-status` 50
  seconds after it started, and the 11 short successful pull request runs in that hour's listing
  took 37 to 58 seconds. A comment starts none of these, so the record is a comment and the
  squash commit does not carry it.
- **What it costs the merge.** The arm itself waits at most about 40 seconds: the reads have 15
  seconds, the comment write 5, and the artifact download runs `gh` and `unzip`, each capped at 8
  seconds, which that timer cannot cut short. Any error or timeout records `unrated` or skips the
  write, and the arm goes on. Each arm makes at most one comment write, and a head gets at most
  one comment unless anyone other than the lanes App edited its record; there is no write when the head's record already
  holds the line or a rating. Its `issue_comment` event starts
  `security-outside-actor` and `intake-reenter` runs whose jobs skip a bot's comment, as they do
  for the pin. Nothing reads the record back: no gate, hold or rung. Not while
  `merge.report-only` is true.
- **Telemetry.** The rating run writes one `pr-merge-risk` lane-outcome record (outcome, class,
  `durationMs`, `costUsd`, models), and each arm logs a `merge-risk` notice
  (`pr=<n> head=<sha> merge-risk=<rated|unrated:reason> read-ms=<n>`, plus
  `write=<no-pull|write-failed>` when that kept the record unwritten) and adds the token to the step summary.
- **Finding a merged pull request's rating.** A squash commit's subject ends in `(#N)`, and a
  revert's subject quotes it. For a revert study, take `N`, read pull request N's comments, and
  take the lanes App's newest comment whose first line is the marker for the head that merged,
  skipping any edited by anyone other than the lanes App (`editor`, when `lastEditedAt` is set);
  its second line is the rating. A pull request armed before the record moved carries the line as
  its body's last line instead, and so does its squash commit, which GitHub wraps over 72
  characters into one `Merge-Risk:` line and the `key=value` lines after it: join them up to the
  next blank line.

#### Review-only dependencies

A non-major release of a hijacked package passes tier `auto` on a green `ci-status`. A dependency
that runs inside a job holding a secret or a write token is therefore listed in the standards
Dependabot policy's `autoMerge.reviewOnly` (melodic-software/standards
`components/dependabot-policy/policy.json`), which the sync places at
`.github/standards/dependabot-policy/policy.json`. Both lanes read that file at the base, and the
pr-merge gate reads it at the default branch head too, where an entry either side lists matches
and either side unreadable makes it unreadable:

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
same-repository, non-draft pull request into main that did not start while the pull request was a
draft (its `ci-status` skipped `Note a draft`; a draft's run tests nothing, and neither pr-verify
nor the merge gate below counts a FAIL judged from one), and after each one whose only failures are
`ci-status`'s holds that an approving review of the head lifts (a hold path, a trusted-actor list
widening), its contract step's `do-not-merge` label, or both (resolve-pr's `heldShape` reads the run's
jobs before the commit's pull requests, so any other failed run skips as `not-a-passing-run`
whatever its pull request, and `heldOnly` reads the `ci-status` log). The person then approves a head pr-verify has judged, and a session
holding the pull request with `do-not-merge` gets a verdict on each head it pushes. `ci-status`
stays red until that approval and while the label is on, and the merge queue still removes a
labeled pull request; no verdict replaces either. It never runs the pull request's code: a model
(the `verify-pr` route of [Models](#models)) reads the diff, the trusted pull request text and its linked issues as
data, and judges whether the diff delivers the issue's intent correctly and safely. Its linked
issues are its closing issues, or, when it closes none, the one `Refs:` issue
[The pr-merge lane](#the-pr-merge-lane) reads. A closing issue is judged whole. A `Refs:` issue is
judged as a partial slice (owner decision 2026-10-23, the recommended option): only the part the
pull request body says it delivers, which must be in the issue's scope, correct and coherent on
its own, with the body naming what remains; a body that names no delivered part or no remaining
work, or claims the whole issue, fails. The body only narrows what is judged, never adds a
requirement, and the spec trust rules below are unchanged. The last pull request of an issue split
across several can close it (owner decision 2026-11-03 on #12965): its body names the earlier ones
on a plain `Siblings: #<a>, #<b>` line (first column, outside an HTML comment and a fenced code
block, at most 10), and resolve-pr credits each that GitHub shows written by a trusted person or the
lanes App, merged into the base in this repository, closing no issue, with a `Refs:` line naming the
closing issue and a body unedited unless a trusted person edited it last, or the lanes App did
before the merge. The spec entry then lists them in
`credited_siblings` with their bodies, and the verifier judges the diff only for the done-when items
those bodies do not say they delivered; a named sibling that fails a check earns no credit, so the
diff is judged against the whole issue. The verdict records no sibling, and the merge gate weighs
such a pass as any closing one. An issue `maintenance-file-recurring-issues.yml` filed
(github-actions[bot], with exactly one `<!-- recurring-schedule id=<id> -->` line) takes its spec
from that row of main's `.github/recurring-schedule.json`, the title and body the filer builds from
it, never the issue's own text (owner decision 2026-11-07); its entry carries `source`
`recurring-schedule`. The merge gate counts such an issue as a trusted spec by the same rule,
reading the schedule at the default branch's tip. resolve-pr marks each spec entry's
`spec_kind` (`closes`, `refs` or `pull-request`), and the verdict records it, so the gate refuses a
pass (`verify:spec-changed`) when the issue is now linked the other way. The model runs
on ci-workflows' `run-claude-cli` as the `pr-verify` role ([Funding](#funding)), with the Read
tool alone, allowed only on the data files in the working directory's `pr-verify-data`. One of
them, `upstream-jobs.json` (`upstream-jobs.mjs`), lists the jobs of the pr-require-checks run the
judgment was started by, each with its name, conclusion and job page URL, read with the job's own
token: the verifier judges from it whether the suites that cover the changed files ran, and runs no
test or eval itself. A suite's job that concluded `success` on the judged head settles a done-when
"X exits 0" item and any "not run" or "likely fails" doubt about it; the diff is still judged for
a test that cannot fail or was weakened. Its `wrapped_node_suites` lists each Node suite in the judged head's tree that has a
sibling `.test.sh`, which CI runs only through that wrapper in `test-bash`
(`scripts/plan-test-lanes.sh`), so a skipped `test-node` does not read as that suite unrun. A
label or body-edit re-run skips `select-tests` and every suite, so its list is no
evidence either way. The diff is split at file boundaries into as many chunks of at most 300000
bytes as it takes, up to 12 (`MAX_CHUNKS` in `chunk-diff.sh`, which holds a 3 MB diff), each file
whole (`chunk-diff.sh`, `split-diff.py`; the same chunk budget as `pr-review-main`), and each chunk
gets its own judge step with the same spec, cut into parts one Read returns whole; a line over 1800
bytes carries on across lines that start `\ continued:`, so every byte of the diff is read. The manifest
(`manifest/part-*.txt`) names the part each file starts in, so a judge reads another chunk's part when
its change references a file there and judges both sides. A `pass` or `pass-notes` counts only when the
run read every part whole with no permission denial. A `fail` needs the schema and, when it read short,
a defect in its notes. It counts on a denial, which it records, since no fail can pass the head, and
it stands whatever follows:
the step after each judge stops the later chunks, the final judge and any handoff, and
`Write the verdict` runs on it, so a re-run cannot sample that head. A `pass-notes` makes the head
`pass-notes`. A head of two chunks or more also needs a final judge step, `Judge the whole spec`,
denied the diff: it reads the spec and every chunk's checked result, whole, in as many files as that
takes, as untrusted data (`spec-prompt.md`), and maps each done-when item to the chunk that delivers
it, and a script fails the head on an item mapped to none. It must read the spec, the manifest and
every result whole, and on a spec entry whose `spec_kind` is `refs` the context too, cut into the
same parts. With no output
from it, off the schema, or with a denial on anything but a `fail`, and no counted fail, the head gets
no verdict, so no chunk's `pass-notes` passes a chunked head alone. A single chunk has no final step. A
chunk that passes short of a part, leaves no output or is off the schema leaves no verdict for the
head, and a handoff from any chunk hands the whole
judgment to the next leg, which judges every chunk again. A file over 300000 bytes, or a diff that
needs more than 12 chunks (over about 3.6 MB), ends the run red with no verdict and an error naming
the file or the chunk count, so size alone writes no `fail`. With no verdict `verdictHold` holds the
head, the trusted approval of the head lifts that, and a `pr-verify-failed` label stays. The diff
step logs a `pr-verify chunks` notice, and the verdict step a `pr-verify chunk` notice per chunk. The run
uploads one artifact, `pr-verify-<pr>-<head-sha>-<pass|pass-notes|fail>`, holding the verdict JSON. Every
reader also accepts that name followed by `-<ref-digest>`, the first 16 hex digits of the SHA-256
of the `head_ref` the JSON records (`HEAD_REF_DIGEST_HEX` in `write-verdict.mjs`), which the
writer moves to once the readers have run on main. resolve-pr looks up only the names the writer
writes, so that change adds the digest lookups to it. After the digest, if any, a `fail` name may end with `-i`
and the issue numbers the JSON's `linked_issues` records, ascending, each once, joined by dots
(`-i7` or `-i7.12`, at most 10, each 1 to 10 digits with no leading zero), so a `fail` carries its
issues in a name the run authenticates and one verdict has one name. Every reader refuses a `pass`
or `pass-notes` name that carries issues, issues out of order or repeated, a pull request number
over 10 digits, and a name over 194 characters. A name that starts like a `fail`'s
(`pr-verify-<digits>-<sha>-fail`, any digits) but no reader takes holds rather than being skipped:
the gate refuses `verify:unreadable` when its run is of verifier origin, or is tied to the pull
request and cannot be read, and pr-feedback-dispatch fails its run. One of verifier origin holds
every pull request in the repository until its artifact is deleted or expires; deleting it clears
the hold. The writer adds the issues to every `fail` that records one, ascending and once each,
and checks the name against the readers' pattern before uploading; a `fail` whose issues no name
carries (more than 10, or a number over 10 digits) keeps the plain name, with a warning. GitHub refuses
an artifact name holding `"`, `:`, `<`, `>`, `|`, `*`, `?`, `\`, `/`, a carriage return or a
line feed
([`validateArtifactName`](https://github.com/actions/toolkit/blob/main/packages/artifact/src/internal/upload/path-and-artifact-name-validation.ts)),
so digits, `-` and `.` are safe, and the longest name is 194 characters. The JSON holds `pr`, `head_sha`, `base_sha`, `head_ref`, `linked_issues` with each issue's author login, id and
account type, `verdict`, `summary`, `notes`, `evidence` and `run_id`. The head SHA is the one `pr-require-checks`
ran on, never the pull request's live head. `evidence` records per head the app capture's outcome,
`capture` (`ran`, `skipped`, `blocked`, `not-applicable` or `no-app`), with its `reason`,
`capture_count` and `features`, and `local_loop`, the count `k` from an `Evidence loop: k/3` line
in the trusted pull request body, which the author reports and the writer reads as data only (`null`
with no such line or a withheld body). With the app unset the writer records `no-app` ("no app
check ran"). With it set and no capture summary (no capture run, one that ended other than success,
one still running at the bound, no artifact, a failed read or download), it records `blocked` with
the reason `find-capture.mjs` wrote. The later judge jobs carry a miss that cannot change (a
malformed input, or a completed run's outcome) and search again after one that can; a
summary it cannot read, that fails its schema, or whose text matches a shared
credential pattern records `blocked`, so a capture never fails the verdict. `merge.verify-capture` configures the capture: `app`, the app it drives (unset:
no capture runs), and `retention-days` (default 30, at most 30, the `pr-capture-*` row in
`.github/artifact-retention.json`), how long each capture artifact lasts. `proxy` configures the
key proxy, the only route the driven Claude Code in the capture's sibling sandbox has to the API:
`driven-model` and `driven-small-model`, `models` (the model ids it forwards), `token-cap` (the
tokens the driven session of one capture job may spend, cache tokens counted in full),
`driver-token-cap` (the same for the job's trusted driver legs), `max-tokens-ceiling` (the largest
`max_tokens` it forwards, also the driven session's `CLAUDE_CODE_MAX_OUTPUT_TOKENS`),
`max-body-bytes`, `max-in-flight` (at least 2), `max-count-tokens-requests`,
`max-preflight-requests` (the messages requests that may reach its count_tokens preflight),
`upstream-timeout-ms`, and the `betas`, `body-keys` and `block-types` it allows. The capture
installs the Claude Code version `package-lock.json` pins, the one source of that version. The three
lists were measured from the driven session's requests; the proxy refuses a value they do not list
and names it, so the first capture after a version bump says what to add. When the key cannot capture (the
credit gate skipped it, its probe handed off, or it is empty), `capture-subscription` uploads a
capture recorded `blocked`: a subscription token cannot go behind the key proxy, so that job runs no
model, and no fallback job follows it. A model error, an output that fails the schema, or a `pass` or `pass-notes` with any
permission denial uploads nothing, and the run fails. A `fail` with a summary or note matching a
shared credential pattern (`findSecret` in `lib/publish-gate.mjs`), a `pass` or `pass-notes` holding a
credential format (those patterns less the secret assignment, the set `scanLeak` blocks on), or any
verdict from a judge step `run-claude-cli` failed on its own credential scan, is written as a `fail`
with a fixed text in place of all the model's, which counts toward the repeated-fail cap, so the head
is not judged twice. A `pass` or `pass-notes` holding only a secret assignment, which may be a
fixture, uploads nothing, and the run fails. The chunk-results step stops with no verdict, before the final
judge runs, on results over 300000 bytes. A head that already has a counted verdict from a completed run (a `fail` under any
pull request number) is not judged again, unless its only verdicts are passes the spec has since
changed under (below). The resolver first looks up the names without issues;
only when none holds a counted verdict does it read the pull request's linked issues, which the
spec needs anyway, and look up its own `fail` under the name with `-i`. A `fail` another pull request
left at the same head names issues it never reads, and that head is judged again. So is a head
whose linked issues a body edit changed after this pull request's `fail` there: the new set names
another `-i`, so one run follows each change of the issue set. The pull request's own plain `fail`
at the head (it linked no issue, or more than a name carries) stops a new judgment unless the
pull request now links issues a `fail` name carries and, since that `fail`'s run was created, only
trusted people edited its body or connected or disconnected an issue, at least once; the resolver
then proceeds with the reason `relinked`. The pull request's own `fail` at the head, plain or named
with its issues, also stops a new judgment unless, since the last such `fail`'s run was created, a
trusted person edited its body and only trusted people edited it or connected or disconnected an
issue; the resolver then proceeds with the reason `body-edited`, so a body fix after a `fail` is
judged at the same head, with no new commit. The body edit starts that judgment itself:
`pr-require-checks` runs on `pull_request` `edited`, which GitHub sends when a title or body is
edited, and `pr-verify` runs on that run's completion. The lanes App's or any other Bot's edit, an
issue link change alone, or an edit history that cannot be read whole keeps the `fail`. In every
case the earlier `fail` stays tied to the pull
request and refuses the head unless the gate finds it superseded (below). Runs share one concurrency group per pull request and
head and never cancel a running judgment.

`merge.verify-authors` decides whose pull requests are judged. Under `lane`, the default, only one
the lanes App opened is: a `Bot` account whose login is `merge.agent-identity`, compared as the
pr-merge lane decides lane authorship. Any other author's passing or hold-only run is skipped
before the model runs, with the reason `author-not-lane` and the step summary line `skipped: author not the lanes App`, since
only lane-authored pull requests reach the pr-merge lane. `lane-or-owner` also judges every
trusted actor's: a `User` or `Bot` whose account id is on the trusted-actor list (never matched
by login), whose pull requests the pr-merge lane adopts (Eligibility, above); any other author's
passing or hold-only run is skipped with `author-not-lane-or-owner`. pr-verify runs when `pr-require-checks` passes, so it
judges a person's pull request at each ready head, before it is idle. A pull request closing no
issue is judged against its own title and body only as [Adoption](#adoption) says. Work the spec
does not ask for passes with a note (`pass-notes`) unless it is also a correctness or safety
problem, changes what the code is for, or loosens a hold the owner keeps (a hold on a real
charge, not subscription spend such as a model, effort or schedule change); then it fails the
verdict, as does unasked-for work on secret values or organization or repository settings.
Changes to workflows, CI, hooks, scripts, agent instructions and package manifests are judged
like any other code; a change to the takeover set (the merge gate's HIGH floor) is read with extra
care and fails only when it lets someone outside the organization gain trust or weakens a check
beyond what the spec asks. A diff too large to judge whole fails when a part not judged is a
workflow, action, script, hook or binary, or a takeover-set file of any type, and passes with
notes naming the parts not judged when they are all other prose or data. `any` judges every author's. Any other
value judges none (`verify-authors-invalid`). The trusted-spec rule below does not depend on who
opened the pull request: a spec written by a trusted human counts, so an adopted owner pull
request whose closing issue the owner wrote is judged against that issue as its spec. A spec the
lanes App or any other Bot or App wrote, or one an untrusted account wrote or last edited, still
reads `verify:untrusted-spec`, except a size split's sub-issue whose lines are its listed-human
parent's task-list lines or those of intake's refinement on it (below), so a lane pull request
never supplies its own spec. A listed human's comment on such an issue reaches the verifier, but it
never makes the issue trusted, and neither does a listed human's edit of its body. To give work a Bot
filed a spec, a listed human opens an issue that restates it, and the pull request links that one.

A trusted edit to the spec after a pass, an issue body edit or a spec comment added or edited,
makes the gate refuse that pass `verify:spec-changed`. The resolver then judges the head again:
when every counted pass at the head started before the spec's last change, it proceeds with the
reason `spec-changed` instead of skipping. Nothing re-runs pr-verify on an issue event, so the
lost-run reconciler does it: for an open pull request whose head's `pr-require-checks` run passed
and holds such a pass, it re-runs that run with a record naming the attempt the re-run starts, and
pr-verify judges the head against the spec as it is now. The gate and the resolver both weigh the
passes of the pr-verify run that started last, so the new verdict replaces the old one. The spec can
change again after that re-run's pass, so the reconciler re-runs a passed checks run at attempt 1
or 2 and records attempts 2 and 3; pr-verify's trigger check accepts a reconciler-recorded attempt
up to 3 (`RECONCILER_ATTEMPT_CAP` in `check-trusted-trigger.mjs`, owner decision Q-RERUN3,
2026-11-05). A run at attempt 3 is named in the reconciler's summary for a person, and a later edit
or label starts a new attempt-1 run. A changed closing set or a removed spec comment leaves no time
to compare, so those heads still wait for a person.

Each pr-verify job runs the resolver before the trigger gate. The resolver only reads, and it skips on
its own reads every run it would not judge: a head already judged or moved past, a draft or a run
that started on one, a run red
for anything an approval does not lift, an author it does not judge. So the gate's reads go only to
a run the resolver would judge, and nothing either writes reaches the model before both pass.

With `merge.require-verifier-verdict: true` the pr-merge lane reads the artifacts through their
run records, since only steps of a run can upload its artifacts. A run is of verifier origin when
it is `pr-verify.yml`, event `workflow_run`, on main, in this repository with a head on main. A
`fail` counts from any such run, whatever its conclusion, because the upload comes before the
run's later steps; a `pass` or `pass-notes` counts only from one that completed with success. Any
other artifact with such a name is ignored. The resolver and the gate each hold this rule and the
dependency-manager list, and one test runs both to keep them equal. At the pull request's vetted
head:

- counted `fail` verdicts at `merge.max-verify-fails` (default 3) or more distinct heads of the pull
  request, tied as in the item after next, refuse (`verify:repeated-fail`) whatever a later pass
  says, a `fail` at the head included. A value that is not a count of 1 or more, an empty or
  non-scalar one included, is 1, so any earlier `fail` holds. Before a `fail` at the head or a
  pass decides, counted `fail` verdicts of other pull requests in this repository, for its linked
  issues, count too, at their own heads, unless that pull request merged or is a closed lanes App
  attempt, so a second pull request for the same issue, closing or `Refs:`, does not reset the
  count. Every `fail` of such a pull request that closes one of the issues counts. Every counted
  `fail` of one whose name carries the issue counts too, from the listing the gate already reads:
  pr-verify names a `fail` with a `Refs:` issue as with a closing one, so this is how a `Refs:` pull
  request's `fail` verdicts count, and a pull request no issue lists has its state read, once per
  reader and only when one of its `fail` verdicts could count (a failed read refuses
  `verify:unreadable`). Such a `fail` whose run cannot be read
  refuses `verify:unreadable`. Editing a pull request's body never lowers a count its `fail`
  verdicts added, so a hostile pull request that names an issue only to inflate its cap is undone
  by deleting its `fail` artifacts. The gate reads no issue
  timeline, so cross-references to an issue, which anyone can add, hold nothing. A plain `fail`,
  which pr-verify writes when the issues fit no name (more than 10, or a number of 11 digits or
  more), still counts for its own pull request and at the head, but not toward another pull
  request's cap for those issues; it is rare, and the per-pull-request cap still bounds it. A pull
  request whose `fail` names do not carry the issue is otherwise not counted. More than 50 pull
  requests that claim to close one issue make every pull request for that issue refuse
  `verify:unreadable`: a hold, not a way past the cap. A fresh attempt starts its own count (owner
  decision 2026-10-29): a merged pull request's `fail` verdicts, and a lanes App pull request's
  once it is closed unmerged, whoever closed it, never count against another pull request. Closing
  any other pull request resets nothing, so its author cannot re-roll the verifier by closing and
  reopening. Of the `fail` verdicts that remain, only those uploaded after the newest of the lanes
  App's capped-close records (`<!-- verify-capped-close pr=<n> ... -->` as its first line, parked
  or not, written by the App and edited by no one else, so a forged one resets nothing) on at
  least one linked issue they are for count: a record on one issue ends no attempt at another, and
  no other close moves that floor. An unreadable `fail` holds the same way: one uploaded before the
  record on every issue its pull request is for refuses nothing. This cap and the carry-forward
  below bound pushing to one pull request until the verifier passes once;
  `merge.verify-cap-attempts` (default 1) bounds how many fresh attempts the pr-merge lane starts
  per issue, and past that many it parks the issue instead. A lanes App pull request closed by hand
  is not counted against that bound. Closing a newly filed duplicate issue instead starts the count
  of other pull requests again; a pass then needs that issue written by a trusted human, as below;
- a counted `fail` at the head, under any pull request number, refuses (`verify:fail`), unless a
  relink or a body fix superseded it: every counted `fail` there is this pull request's, every
  counted pass there was created after them, and up to each pass run's completion (`updated_at`)
  every body edit (`userContentEdits`) and issue connect or disconnect event on the pull request
  is by a `User` on the trusted-actor list's humans, with at least one such act from the first
  `fail`'s run's creation when the pass records other `linked_issues` than each `fail` does (a
  relink), else at least one body edit from the last `fail`'s run's creation (a body fix). The
  lanes App, any other Bot, an actor GitHub cannot name, a read that fails or is cut short, a time
  that cannot be read, or the same linked issues with no body edit keep the refusal. Both the
  resolver and the gate read these acts in one GraphQL query, only on this path. A superseded `fail` still counts toward `merge.max-verify-fails`, and the
  passes then decide as below. A judgment on an older listing (pr-merge's provisional one) can
  still refuse `verify:fail` until a listing that holds the superseding pass is read;
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
  matter in Python: it holds more than it must, never less. A `fail`ed head of the same change
  clears only when every counted `fail` there records `spec_kind` `refs` for this pull request and
  every counted pass at the head records `spec_kind` `closes` with exactly the `linked_issues` each
  `fail` records: a closing pass is judged against the whole spec, which holds the `Refs:` slice
  that failed. The reverse, a missing or other kind, linked issues that differ or cannot be read,
  or a `fail` record that cannot be read keeps the refusal. A `fail`ed head of the same change,
  a head that only merges the branch included, also clears when its `fail` was superseded at its
  own head by the passes there (the rule in the item above). A pass judged
  before a later `fail` never clears it. Any other failed read of a run time or a diff refuses as the next item does;
- a `fail` artifact tied to it (its number or one of its commits) whose run cannot be read, an
  untied `fail` whose run is readable and of verifier origin but whose verdict record cannot be
  downloaded, or any other failed read, refuses (`verify:unreadable`). An untied `fail` whose run
  cannot be read is ignored. One unreadable record of an untied `fail` therefore blocks every pull
  request until it can be read, expires or is deleted;
- every counted `pass` or `pass-notes` for this pull request at the head is checked, whatever order
  the listing returns them in, and the merge is allowed only when each allows (a changed spec is
  reported before an untrusted one). Each refuses (`verify:spec-changed`) unless the
  pull request's closing issues in this repository now (or, with none, its `Refs:` issue, read as
  resolve-pr reads it) are the ones its verdict recorded, none
  was edited after the verdict's run started, and each issue's spec comments (written, and last
  edited if ever, by a `User` on the trusted-actor list's humans, the pull request's author
  included) are the ones it recorded by id and update time, none added, edited or deleted; a partial
  comment read refuses `verify:unreadable`. It then allows the merge only when every linked
  issue it records was written, and its body last edited if ever, by a `User` on the trusted-actor
  list's humans, the pull request's author included, or is a sub-issue intake's size split filed
  whose body counts as its parent's text (otherwise `verify:untrusted-spec`). That sub-issue counts
  when the lanes App wrote it, a listed human filed its native parent in this repository, its body
  opens with the split header for that parent, every line after the header is one of the parent's
  trusted task-list lines (a line of the parent's listed-human body or comments that starts with
  admission's `task-list`, "- [ ] " with its trailing space, from
  `.github/actions/resolve-config/admission-rules.json` at the default branch, as resolve-pr reads it from main's checkout, whatever the pull request's base; a missing or empty `task-list` counts nothing), and either nobody edited it or a
  listed human last edited it. A header whose third line is
  `<!-- size-split refinement=<id> updated_at=<time> -->` also allows that refinement comment's
  task-list lines, never its prose, heading or marker lines, and counts only while that comment is
  still the lanes App's newest refinement on the parent, never edited, with `updated_at` equal to
  its `created_at` or to the recorded time, on a parent body a listed human wrote, and last edited
  if ever; a deleted, edited or superseded refinement leaves it untrusted, whoever edited the
  sub-issue since. On the edited path a line may also be a trusted line with its box
  ticked: the one `[ ]` of `task-list` written `[x]` or `[X]`, indent and text unchanged, and a
  `task-list` without exactly one `[ ]` takes exact lines only. GitHub names only the last editor,
  so a listed human's edit vouches for ticked boxes, never for other text. To amend such a
  sub-issue, a listed human comments on it; any other line added to its body
  leaves it untrusted, whoever adds it ([#10734](https://github.com/melodic-software/claude-code-plugins/issues/10734),
  [#10936](https://github.com/melodic-software/claude-code-plugins/issues/10936)). A parent with more than
  100 comments leaves it untrusted, and a failed read of the sub-issue, its parent or the rules
  refuses `verify:unreadable`. Otherwise a Bot or App, the lanes App among them, never counts. The
  model's spec text holds what such
  accounts wrote and, on an issue whose body such an account wrote, intake triage's newest
  refinement comment (opening `<!-- intake-triage refinement -->`, by the lanes App's id from
  `merge.agent-identity` on the trusted-actor list) while unedited and posted before the pull
  request opened. That comment stays out of the recorded spec comments, so the gate does not see
  it edited, hidden or replaced after a pass: an edit only takes it out of spec, and a person's
  correction made after a pass waits for the next head;
- no counted verdict refuses `verify:too-old` on a pull request created more than 80 days ago,
  since its verdicts may be gone (artifacts last at most 90 days in this repository, the retention
  maximum and its setting): the lost-run reconciler re-runs the head's passed `pr-require-checks`
  run, recorded, inside GitHub's 30-day re-run window, so pr-verify judges the head, and a fresh
  pass there clears it (owner decision 2026-11-01, #11023). A `fail` past that retention no longer
  counts toward the cap;
- otherwise no counted verdict refuses (`verify:missing`).

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
`verify:spec-changed` holds for the lanes
([when work stops for the owner](../../contracts/loop-lane/README.md#when-work-stops-for-the-owner)): it still refuses the merge, with no label.
Only `verify:untrusted-spec` needs a human, since the spec's provenance is a trust boundary.
`verify:too-old` waits for the fresh pass above, with no label. `verify:repeated-fail` never
clears for the pull request, so it never merges unattended, and no person's label goes on for it
(owner decision 2026-10-29). Instead, while `merge.report-only` is false, the pr-merge lane closes
a lanes App pull request at it for a fresh attempt at its issue (`babysit_verify_evidence.py` `capped_close`, run by
`enable-auto-merge.mjs` through the reader's `capped-close` command, or by the gate under
`merge.lane-prs: gate`). It judges the head again and leaves alone a pull request that is not the
lanes App's, not open at that head, or carries `do-not-merge` or the human-gated label, and one
whose issue link the arm path refuses (one closing issue or the `Refs:` one, clearing the trust
hold) or whose issue carries an issue hold label. The gate also leaves open one its entry-hold
check names, read as a pull request never enqueued (a hold label, a body hold, a member's newest comment
saying "do not merge", or a failed read), and one whose human-gated label it cannot read. A pull request reopened after its record stays open: it closes at the cap once. In
order,
so a failed write leaves the pull request open for the next run, which finds its records and
writes the rest: a comment on the pull request opening with
`<!-- verify-capped-close pr=<n> heads=<shas> -->`, quoting each FAILed head's verdict summary and
notes (read from its `verdict.json`; an expired one is named by its run) as data in one text
fence; the same record on each linked issue (closing, or the `Refs:` one), its marker naming the
attempt; `agent-ready` off the issue and back on, tried twice, which starts the fresh attempt;
then the close, so a closed pull request never leaves its issue without `agent-ready`. An issue
that did not carry `agent-ready` when read (a person may have taken it off) is recorded with no
attempt and not restarted, since the App's re-add would override that person. A rerun after a
failed close writes no issue label, except putting back an `agent-ready` whose newest removal was
the App's own at or after its record, or toggling one the issue still carries with no such removal
(the run stopped before taking it off); a record with no attempt writes none, and a parked one only
finishes an unfinished park. Findings are quoted only from pr-verify runs of verified origin; any
other is named as not verified. `write-issue.mjs` passes that record to the next attempt as
`author_kind: verify-findings`, the one lanes App comment it keeps besides intake's refinement. An
issue that already had `merge.verify-cap-attempts` fresh attempts (lanes App records naming other
pull requests) is parked instead: its record says so, and before the close it gets
`status: confirmed` with `status: ready` and `agent-ready` taken off, so neither the readmit sweep
nor triage starts it again.
`label-unblocked.mjs` hands no issue to triage for a lane pull request its capped-close record
names with an attempt, since the lane already restarted or parked it. An armed pull request is disarmed first. One the close leaves open, or fails on, keeps
the lane's refusal note and its `pr-merge/unarmed` status, with no person's label.
`pr-feedback-dispatch.yml` and `pr-unblock-dispatch.yml` start no address-feedback or fix-ci round,
and post nothing, on a lanes App pull request (the only kind the close takes; an adopted owner's is
not read) the gate's reader refuses `verify:repeated-fail`
(`.github/scripts/pr-unblock/verify-cap.mjs`, reading `babysit_verify_evidence.py` with the
dispatcher job's read token, last before each dispatch), or `verify:unreadable` because another
pull request's FAIL run for the same issue cannot be read, or because the artifact listing does
not fit in the 120 s the dispatcher allows the reader; either may hide the cap, so it is read again
next run. A read that fails or times out, or any other refusal, lets the round run under its own
caps with a warning naming it, which costs at most one round before the lane closes the pull
request. While `merge.report-only` is
false the lane escalates `verify:untrusted-spec`
on the pull request ([loop-lane §2](../../contracts/loop-lane/README.md#2-escalation-contract)): it
keeps one `<!-- babysit-merge-verify-escalation -->` comment naming the refusal and the head,
rewritten only when either changes. Then the lane adds the tracker's human-gated role label (`needs-human` unless
the tracker binding in `docs/conventions/work-items.yaml` maps it) when no label matches it ignoring case. The comment goes first,
so a label never stands unexplained, and a failed label is added by the next run unless a person
removed it after the comment last changed (see the reasons comment above); a rerun that
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
The one exception is a candidate's `verify:missing` on the saved listing: its gate reads the head's
two pass names by exact name (`pr-verify-<pr>-<head>-pass` and `-pass-notes`), two requests and no
listing, and judges a pass found there with the saved listing, so a pass uploaded after that listing
is seen in the same run. Its allow is judged again on a listing of its own like any other; a failed
read, or no pass that counts, leaves `verify:missing`.
A listing that got a 5xx or a fast
network error is read again, three reads in all with backoff, all inside the one gh timeout a single
read would get; any other failure, a timeout, a 429 or a rate-limit 403 included, is not. A failed listing is never
saved, and is kept for that candidate's gate run: the pull request and every queued entry refuse `verify:unreadable` without the
listing being paged again, so a listing outage holds the whole queue rather than merging blind.
Once the legacy FAILs file (`verify-legacy-fails.json` beside the reader) is committed, the gate
reads no listing at all: each FAIL's run uploads index artifacts first (`pr-verify-index-pr-<n>`,
`-sha-<head>`, `-ref-<digest>`, `-issue-<i>`; `.github/actions/upload-fail-index`), the FAIL only
after every index did, and a judgment reads those exact names for the pull request's number, its
head and commits, its head branch, its live issues and their other closing pull requests, then each
run they name and the pass names at each FAILed head; the file holds every FAIL from before the
index. The module docstring's "Index mode" states the rule. Until then the listing below applies.
A listing read from the API builds on the newest whole listing begun within three hours (the
reader's own, or the run's saved one; no run carries a listing to the next, since in index mode no
gate saves one): it reads pages newest id first down past that listing's
highest id until an artifact created two hours before that listing was read, keeps that listing's
entries below the lowest id those pages hold, less those expired by the first page's `Date`, and is
kept only when it holds exactly that page's `total_count`. A count above it first reads again the pages
around kept entries near expiry, up to a page cap, since GitHub can delete an artifact up to an hour
before its `expires_at` (`EARLY_DELETION_LEAD`, `NEAR_EXPIRY_PAGE_CAP`). Those pages can skip an
entry at a boundary, so an entry they omit is dropped only when its own read answers 404, up to an
id-read cap (`NEAR_EXPIRY_ID_READ_CAP`); the whole listings' top-ups get both caps again. A count
those pages leave short is a skip in the fresh pages and is read again after a wait while the caps
left cover another such read. Any count still other than it, a missing, older or
malformed base, or any failed read lists every page, so a carried listing that leaves out a FAIL
lists every page too (the rule and its basis: `babysit_verify_evidence.py`, "Carried reads").
A whole listing is held to the same count: deduplicated by id, added to the whole listings read
before it and checked by a top-up from the first page, since one can skip an artifact at a page
boundary while an earlier one expires (#10486); after three whole listings that never hold the
live count the candidate refuses `verify:unreadable`, and after the first when its top-up holds more
than the count or does not read, or the pages read before it held more, which another whole listing
cannot cure. A listing that fails once
it began a whole listing is noted beside the saved listing, and every later reader in the job
refuses on that note without paging. An over-count is the exception to that note's limits: once the
one whole listing an over-count takes starts paging, a later reader in the job whose pages
over-count refuses without another, even when that listing failed transiently or on a caller's
limit (then with the caller-limit prefix). A refusal before paging leaves that listing to the next
reader.
The lane token holds no Actions permission, so pr-merge.yml grants its job `actions: read` and passes the job's `GITHUB_TOKEN` as
`BABYSIT_VERIFY_GH_TOKEN`; the reader uses it as `GH_TOKEN` for the artifact listing, the run
records, the download of a verdict.json (by the listed artifact's id, one request where `gh run
download` lists the run's artifacts first) and the compare of a run's head to main (a `contents: read` call). The gate's
review-evidence reads use it too: the timeline, the comments, and the lane runs with their attempts,
jobs and annotations. All of these reads stay on `GITHUB_TOKEN`: none switches to the lane token,
whatever `GITHUB_TOKEN`'s budget, since GitHub's Terms of Service bar sharing tokens to exceed its
rate limits ([owner decision](https://github.com/melodic-software/claude-code-plugins/issues/9297#issuecomment-6368281689)).
A read refused for a rate limit is not retried: the candidate's lanes read `evidence-missing`, it
holds, and the next run reads again. An untied FAIL whose record cannot be read refuses the run's later candidates through `BABYSIT_RUN_CACHE` without another
download; the next run reads it again. `GITHUB_TOKEN`'s pool is shared with the full-run dispatch and the post-merge checks. Every other call, every write
included, keeps the lane token. That job checks out only main and runs no pull request code.

The post-merge check's lane records (`pr-merge-dispatched-<id>`, `pr-merge-rerun-<id>-attempt-2`)
carry from run to run as the `pr-merge-lane-records` artifact
(`.github/scripts/pr-merge/lane-records.mjs`), read the way the head-ref map is: only from the
newest scheduled or hand-started `pr-merge.yml` run on main whose head commit is on main, never
through `actions/cache`. A record it holds is present with no read once its sender run passes the
check's sender rule again; a carried record decides as a successful read would, and also where
today's read would fail. Every check of a run adds the records it proves and keeps those at or after
the lowest floor any check of the run used. A scheduled or hand-started merge job uploads the
result, keeping each unexpired record whose artifact the run's artifact listing lists unexpired
under the record's name and sender run. With no listing file (no candidates, or a listing the run
could not read), unexpired records are carried as they are and pruned on the next run that saves
a listing; the listing only prunes, and the check still applies expiry and its sender rule to each
carried record. Deleting a record's artifact therefore does not revoke a carried record at once:
it stays present until a later upload's listing drops it, and with a listing file that exists but
cannot be parsed a run uploads nothing, so the next run reads an older file.

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
artifact listing still lists the id; with no listing file it carries the map it read as it is,
without its own downloads, and with a listing that cannot be parsed it uploads nothing. The next run reads it from the newest such run, found the
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
comment when the review returns a hold: `cost` (only for a real charge, as the wrapper's prompt
defines it) or `critical-security`. `hold-paths` only flags the files it names for extra security
scrutiny; a match never holds by itself. The security lane reads such a file's whole change and
what it gates, and only a CRITICAL finding there holds. The callers name
`.github/standards/trusted-actors/**`, every entry of the narrow path floor above
(`Floor.all`, every class), and the security review's own criteria and eval cases
(`plugins/review/skills/security-review/**`, `plugins/review/evals/security-review-*/**`). All but
those last two are also the trust-gate paths ci-status's exempt-author and agent App check below
fails on.
`scripts/sync-hold-floor.py` writes both callers' `hold-paths` and that check's `hold_patterns`
from that floor, and `test_merge_holds_sync.py` checks that each matches every floor
entry.

No ruleset requires a review check (github-iac ADR 0017); ci-status, the one required check, enforces
them on every `pull_request` run, contract-only runs included:

- **The label holds.** ci-status fails while the PR carries the human-gated label (`needs-human`
  unless the base's `docs/conventions/work-items.yaml` binding names another). Removing it approves.
- **Only a trusted person lifts a review-lane hold.** A hold is the newest hold comment or the
  newest `labeled` event of the label by `github-actions[bot]` or `claude[bot]`, whichever is later,
  so deleting the comment does not lift it. The first removal of the label after it must be by a `human` of the base's
  trusted-actor list; a later removal is of a later label, such as an escalation
  `clear-escalations` lifts. A bot's or anyone else's lift, or none recorded, fails. To recover, a
  trusted person adds the label back, which starts a new hold, and a trusted person removes it.
- **`do-not-merge` is the veto.** report-outcome labels a lanes App PR that carries `Hold: a
  human merges this` with `do-not-merge`, since the App can edit that body line; ci-status's label
  steps fail while it is on, and removing it lifts the hold. ci-status reads no body hold text: a
  person who wants a PR held applies `do-not-merge`. On a lanes App PR, a member's veto comment is
  label-backed: pr-merge's enable-auto-merge job adds `do-not-merge` on the next scheduled run
  that reads the pull request's discussion, at the latest before any run arms it, with a `<!-- member-veto-label -->` comment just after, and takes the label off once a later
  comment by each vetoing member lifts the veto, only while its newest `labeled` event is that
  one. A `do-not-merge` the body hold, a session or a person added is never taken off there.
  ci-status's merge-holds step still fails on the veto comment until a later comment by the same
  member lifts it, so the veto holds before the label lands and if the label is removed.
- **Both lanes review the head.** On a ready PR, the newest `pull_request` run of each caller on the
  head must have a successful status job (`PR Review / review-status`,
  `PR Review Security / review-status`; the lower-case caller on a head tested before the rename)
  whose `Apply the hold` step ran. A summary-mode run or
  one with no hold label does not count. A pending, failed, cancelled or skipped review fails with
  the cause named. A lane a kill switch stopped (the switch was on when the review run started)
  fails too: the kill switch pauses review and never waives it. Once it is off, the lost-run
  reconciler re-runs that review run, one lane per head per half-hourly pass, and its completion
  re-runs ci-status; a person on the trusted-actor list can re-run all its jobs sooner. A review
  switch stops no merge of its own: a head with no review is red here, the merge gate holds it
  (`evidence-unbound`), and a head already reviewed needs no further review. To stop merges, set
  the lanes switch.
  No admin bypass exists: the ruleset requires ci-status and the merge queue even for an admin
  merge. Only runs from this repository's head count, never a
  fork's run on the same commit, and a PR whose head is a fork fails as a fork before any run is read. A kill-switch job that failed also fails. A review skips a fork and a bot outside the caller's
  `allowed-bot-sender-ids`, so their PRs stay red until a person on the trusted-actor list pushes a
  commit to the head. Dependabot, the release App and the standards-sync App are exempt by numeric
  author id, except that their PR fails when a changed file (or a renamed file's old path) is a
  trust-gate path (the hold-paths above less the security review's own files, matched
  case-insensitively), since no lane
  reviews it. An approval of the current head by a person on the trusted-actor list's `human`
  list clears it; a new push needs a new approval. Then re-run `ci-status`, since a review does
  not. While `merge.diff-check.path-holds` is false (this repository's
  setting, owner decision Q21, 2026-10-29), `scripts/sync-hold-floor.py` writes a guard after
  `hold_patterns` that empties it for every author but Dependabot, so only a Dependabot PR is held
  for its paths: its action-pin bumps bring in third-party code (owner decision Q24). The exception
  (owner decision Q-ANTHROPIC-DEPS) is a Dependabot PR whose every changed file is a modified
  workflow or `action.yml` and whose every change block only swaps the ref (and version comment)
  of one `uses:` line of an action whose owner `merge.dependabot.trusted-action-owners` lists
  (this repository: `anthropics`), read from the diff in the broker step's file pages. Both refs
  must be 40-hex SHAs, the comment a version token (`# v1.0.266`), and each new SHA a commit a tag
  of the action's repository points to (an unauthenticated `git ls-remote --tags`), so a branch,
  a tag name or a commit no tag names keeps the hold. Any other line, file, status or owner, a
  patch GitHub omitted or cut short, or an unread tag list keeps the hold, and an unreadable
  owner list fails closed. The same holds a same-repository PR that changes a trust-gate
  path when an App named in `merge.trust-path-hold-apps` (the base commit's `pr-pipeline.yaml`,
  `[bot]` logins; this repository names only `trust-path-hold-off[bot]`, a login no App holds, so
  the hold is off) opened it, is the
  author or committer of one of its commits by account or noreply address, or pushed to its head
  branch (the repository activity API), since its head can rewrite the review callers; a person
  merges it. Such a PR still needs both lanes when no trust-gate path changed. ci-status reads the
  App list, the PR's commits and the branch's push history only once a trust-gate path matched,
  and an unreadable one, a commit list shorter than the PR, or a full page of pushes fails closed.
  A draft is exempt. Restoring the App hold takes three steps: list `melodic-agent[bot]` again, set
  `merge.diff-check.path-holds` true and run `scripts/sync-hold-floor.py`, because ci-status's inline hold runs only while `path-holds` is
  true.
- **A stopped lane does not hold ci-status.** A `pr-unblock/*` failure status is read only by
  `enable-auto-merge.mjs`, which does not arm the head. A stop that needs a session puts
  `needs-session` on the PR, including the review round cap, an uncertain finding and a disputed
  finding, and a session's answer on the thread restarts address-feedback. A stop with no label
  leaves the condition it stopped on, which blocks the merge by itself:
  - `address-feedback` (`feedback-not-converging`, `-not-landed`, `-invalid`, `-partial`,
    `-publish-failed`, `-incomplete`, `-stood-open`, `-verifier-open`): a review thread stays
    unresolved, and the ruleset requires thread resolution.
  - `resolve-conflicts` (`workflow-staged`, `unexpected-path-staged`, `repeat-cap`,
    `unresolved-conflict`, `conflict-patch-invalid`, `conflict-patch-not-applied`): the lane pushed
    no merge, so the conflict stays, and GitHub merges no conflicted PR.
  - `sync-shared-copies` (`shared-copy-workflow-staged`, `shared-copy-patch-invalid`,
    `shared-copy-patch-not-applied`): the human-gated label pr-merge's
    `shared-copy-sources-changed` refusal put on stays until the head moves.
  - `fix-ci` (`ci-fix-round-cap`, `ci-fix-empty`, `ci-fix-invalid`, `ci-fix-not-applied`,
    `ci-fix-weaken-retry`): the failing check stays red, so ci-status fails.
  - `review-dependency` (`dependency-invalid`): no merge marker is posted, and pr-merge merges a
    review-tier update only on one (tier `review` above).

A review usually finishes after ci-status first reads it, so on a full run (not a label flip or
body edit) ci-status's review-lanes step waits: it polls each lane whose run on the head has not
completed, every 60 seconds for at most 8 minutes (`REVIEW_WAIT_SECONDS`), reading that run once a
poll, then judges both lanes as below. A lane with no run is not waited for. A review still running at the cap fails as before,
naming the automatic re-run, so no manual re-run is needed. Then `pr-feedback-dispatch.yml`'s
`rerun-ci-status` job re-runs the ci-status job of the newest `pr-require-checks` run on the head
when a review caller completes (not when GitHub skipped it) on an open same-repository PR still at
that head and the other lane's newest run on the head has finished or never ran. While the other
lane is still going a re-run could only be red, and that lane's completion re-runs it, so a head
gets one re-run, not one per lane. A ci-status not started yet, or one that started after both
lanes finished, is left to read the reviews itself; an earlier one in progress is polled every 60
seconds for at most 10 minutes first. One that passed with its review-lanes step ending after both
lanes finished (it waited for them) is left alone too, since a re-run can only pass again. A read refused by the token's primary rate limit waits for
the reset inside the same 10 minutes; a reset past them fails the job, naming the reset, since
nothing else re-runs a ci-status left stale. The merge-group run re-checks the labels, and also
fails while the queued PR carries `pr-verify-failed`, which a `pr-verify` pass removes, at a new
commit or at the same head: once a trusted person edits the body, and only trusted people have
edited it since the FAIL, that head is judged again (`resolve-pr.mjs` reason `body-edited`), so a
FAIL on the body or the issues it links needs only the body fixed, no new commit. A
`pull_request` run does not read that label: a red ci-status there stops `pr-verify` from judging
the next head, so the pass that removes it would never come.
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

## Claude Code CLI releases

The lanes run the latest Claude Code CLI, with no version pin (owner decision, 2026-10-31,
[#8595](https://github.com/melodic-software/claude-code-plugins/issues/8595)): ci-workflows'
`run-claude-cli` resolves `latest` at run time when no caller passes `cli-version`, and
claude-code-action moves on Dependabot bumps. Claude Code's built-in read-only command set can
change between releases and is not configurable
([permissions: Read-only commands](https://code.claude.com/docs/en/permissions#read-only-commands);
as of 2026-11-01; recheck when that section changes), so a new release could let a write lane run
a command that prints the environment, and with it the lane token. The `shell_denied` list in
`.github/actions/collect-base-activity/action.yml` is the control, and a sweep keeps it current.

After each Claude Code CLI release, and after each claude-code-action bump merges, a host runs the
sweep on that version:

1. Run `claude -p` with `--permission-mode dontAsk`, `--setting-sources project` from an empty
   directory (no user settings, plugins or hooks), and `--disallowedTools` built from
   `shell_denied` plus `Read(//proc/**)`, the rules a write lane gets. Start it under `env -i`
   with a planted dummy variable and no credential in the environment.
2. Ask it to run, one Bash call each, a list of commands that print `/proc/self/environ` or the
   shell's variables through programs outside `shell_denied`, plus `pwd` as a control that Bash
   runs at all.
3. From the stream-json output, check that every listed command produced a tool call (a skipped
   line is untested, not clean), and mark each result that contains the dummy value.
4. A command whose result holds the dummy value gets a `Bash(<command> *)` rule in `shell_denied`,
   and in the list in [`pr-run-activity.md`](pr-run-activity.md#skill-activities), before anything
   else ships.
5. Update the swept version and date in the comment above `shell_denied`, and post the command
   list, the CLI version and the per-command result on #8595.

## The lane sweep

[`maintenance-audit-lane-runs.yml`](../../../.github/workflows/maintenance-audit-lane-runs.yml) is a
`maintenance` producer: once a day (and on a manual run from `main`) it audits the last 24 hours of
this repository's lane runs and open pull requests and writes what it finds into one rolling digest
issue. It never labels an issue `agent-ready`, so nothing it writes starts work. Its scripts and tests are in
[`.github/scripts/maintenance-audit-lane-runs/`](../../../.github/scripts/maintenance-audit-lane-runs/).

- **collect**, a script with the job's read-only token, writes one data file per unit, at most 8,
  in this order: slice A, the failed runs of each of the four workflows with the most failures, with
  failed jobs, annotations and log tails; slice D, every run of each of the two lane workflows with
  the most runs, successes included, with sampled green runs' failed steps; slice C, ten open pull
  requests by listed authors per unit, with labels, ages and head check results. Runs from forks
  never count. It lists the window workflow by workflow, busiest first: each range's first page of
  100 runs carries its run count, and a range at the listing's 1,000-run cap is halved until each
  part fits, so every run of the 24 hours is read. It stops at 350 REST calls, keeping 184 of them
  for the open pull request and issue reads and the units (the dearest mix: four slice A units and
  four slice C units), and says so: a
  workflow it read only part of is named in a warning, and its unit carries `window_complete:
  false`.
- **judge**, one model leg per unit, runs ci-workflows' `run-claude-cli` as the `automations` role
  on `AUTOMATIONS_CLAUDE_API_KEY`, holds read permissions only, runs with `--permission-mode
  dontAsk`, and has Read, Grep and Glob over its data and the main checkout and no shell. It takes
  the `triage-issue` route's profile. CI logs and titles reach it as data. It returns at most three
  findings, each citing at least one `path`, `line` and exact `quote` from main. A unit whose key
  leg hands off (a credit stop, a 401 or 402, or an empty key) with no permission denial is judged
  by **judge-subscription** on `AUTOMATIONS_CLAUDE_CODE_OAUTH_TOKEN`; with
  `FALLBACK_CLAUDE_CODE_OAUTH_TOKEN` set, a unit that leg hands off (a limit stop, a credit stop, a
  401 or 402) is judged by **judge-fallback** on that token, which never hands off. Each leg is its
  own job holding one credential. A leg that hands off uploads a marker artifact naming the unit and
  the launcher's reason, and **judge-handoffs** and **judge-subscription-handoffs**, which hold no
  secret, check each marker against a closed set and build the next leg's matrix
  (`handoff.mjs`). Each unit leaves one lane record (`lane-sweep`), from the leg that saw its end.
- **file**, a script with no model and `issues: write`, drops a finding whose slice is not its
  unit's, whose workflow is not its A or D unit's, or whose job is not among the failed jobs its A
  unit's data lists, or when any quote is not on its line in the run's main commit, then
  fingerprints it: a hash of the slice, workflow, job and the error signature with numbers, SHAs and
  times removed. A C or D unit, or an A unit whose runs list no failed job, leaves the job unbound:
  a D unit's green samples do not list every job that ran, and its workflow-level findings
  (duplicate runs, reruns) name none of them. The signature is free text in every slice, so
  binding does not stop a steered judge minting fresh fingerprints; they land only as entries in the one digest, at most 3
  per unit. A finding whose fingerprint matches an issue an earlier sweep filed and a person closed
  as not planned or duplicate is skipped, as is one whose `covered_by` names an open item; one
  matching such an issue still open is listed as  tracked there. The rest become the entries of one digest issue, `Review the open findings from the lane sweep`,
  found by its first line `<!-- lane-sweep-digest -->`; each entry opens with
  `<!-- lane-sweep-entry fp=<fingerprint>[ tracked=<issue>] -->`, and the last line,
  `<!-- lane-sweep:fp=<fingerprint> -->`, holds the fingerprint of the entry set and each entry's
  tracking issue. A sweep whose set differs replaces the body with the entries it found, so a fixed
  finding drops off, and adds a comment naming the new and dropped entries and any whose tracking
  issue opened or closed; an empty set closes the digest, and a later finding reopens it. An
  entry's details are not in the fingerprint, so they stay as the last rewrite left them. An
  earlier entry the sweep did not see carries over instead of dropping off only when it could be
  unread: its Where workflow is one whose window the collector read in part (`partial` in
  `collect-status.json`), a unit of its slice and workflow had findings that were not read (a
  failed judge leg, unparsable output), or it names no workflow. Every earlier entry carries when
  the collector stopped before writing every unit (`truncated`), its status or a unit file is
  missing or unreadable, or a findings file is unreadable. A digest closed as not planned or
  duplicate is muted.
  Each field is cut at 2,000 characters, and past 60,000 characters an entry keeps only its title
  and fingerprint. The digest is never labeled
  `needs-triage`; writes run 1 s apart and stop at 50 calls.

CI logs can carry text written to steer the judge, so every model-written field renders inside a
code fence and each title has links, mentions and references defused. Each rewrite takes
`agent-ready` off the digest, since a person vetted the earlier text; a person moves a finding
into its own issue before marking that issue `agent-ready`.

The file job writes with the job's own `GITHUB_TOKEN`, not a lanes App token, so the digest comes
from `github-actions[bot]` and starts no workflow, intake triage included. The kill switch stops
every job.

A fourth job, **triage-sweep**, runs alone every hour and with the daily run, with no model
([`triage-sweep.mjs`](../../../.github/scripts/maintenance-audit-lane-runs/triage-sweep.mjs)). It
selects open issues, not pull requests, over an hour old, written by a human on the trusted-actors
list or by the lanes App, that have no intake comment, no born-triaged marker and no triage, status,
priority or work-class label. The `needs-triage` floor label is not a triage label: it lands on open
whether or not intake runs, so an issue whose intake run failed is still selected; one the sweep
already filed a hand-off issue for, found by one search of those issues, is skipped unread. Issues from
`github-actions[bot]`, the lane sweep's own included, are left out. For each it re-dispatches `intake-triage.yml`, at most 5 a pass, and records the runs in
one comment on the issue; after 2 runs that reached intake leave it untriaged it labels the original
`needs-triage` and rewrites that comment to name the runs. A run whose `intake-triage` job the kill
switch or another gate skipped, or that was cancelled before it, does not count, read from the run's
jobs; 6 dispatches hand the issue off whatever reached intake. It holds the job's own `GITHUB_TOKEN`
(`actions: write`, `contents: read`, `issues: write`), never a lanes App token, and stops at 120
REST calls.

## The monitoring lane

[`maintenance-monitor-signals.yml`](../../../.github/workflows/maintenance-monitor-signals.yml) runs
every hour (and on a manual run from `main`) with no model. It reads the signals below over the last
65 minutes, counting a run in the window it completed in, writes each signal's state and evidence to
the job summary, and keeps at most one open incident issue per signal, its findings listed by key.
Its scripts and tests are in
[`.github/scripts/maintenance-monitor-signals/`](../../../.github/scripts/maintenance-monitor-signals/).

| Signal | Fires when | Key |
|---|---|---|
| 1 main red | the newest dispatched or scheduled `pr-require-checks` run on `main` failed, read from each failed job's failure-level annotations; the flake class is named only from GitHub's own runner messages (a timeout, a lost runner) | `main-red:<job>` |
| 2 ceiling | a reading in the window is over 90%: the lanes App and `GITHUB_TOKEN` REST quotas from pr-merge's `api-budget` notices, the lanes App quota from `request-lane-token`'s `mint lanes-app` notice in lane runs (when the broker returns `rate_limit`), plus the lane's own `GET /rate_limit`, and this repository's in-progress Actions jobs against 60 | `ceiling:lanes-app-rest`, `ceiling:github-token`, `ceiling:actions-jobs` |
| 3 throttling | a failure annotation in a failed lane run (not a `pr-require-checks` or `pr-test-platforms` suite run) names a rate limit, a 429 or `github-rate-limited`, or a reading shows 0 remaining, or a `pr-merge` hold still unbroken at the monitoring run has a reason that starts `rate limited` (a hold a later listing followed is not seen); or the broker refused a lane token (any status except `workflow-modified`, which pr-merge re-fires) or was unreachable | `throttle:rate-limited`, `broker-deny:<status>-<reason>` |
| 4 merge-queue ejections | more than 2 merge groups failed in the last 24 hours, each listed with its PR and failing steps | `merge-queue-ejections` |
| 5 held PRs | pr-merge's newest `pr-merge-summary` lists PRs blocked and untouched for over 24 hours, batched | `held-over-24h` |
| 6 report-only audit | the newest scheduled run of `maintenance-audit-test-selection` or `maintenance-check-upstream-drift` failed, which each does on findings | `audit:<workflow>` |
| 7 platform incident | githubstatus.com has an incident naming Actions that is open or began in the window, or shows Actions not operational; listed in the run summary only, never filed, since nothing in this repository acts on it | `platform:<incident>`, `platform:actions` |
| 8 throughput | no PR by `merge.agent-identity` merged for 3 hours while pr-merge's newest live sweep, at most 70 minutes old, counts candidates | `throughput-zero` |
| 9 lane stop | a comment by `merge.agent-identity` created in the window starts with a `<!-- work-resolve-issue outcome=funding\|limited\|turn-cap\|failed ... -->` marker, alone or after the attended queue's escalation marker line, one issue per outcome listing each stopped issue | `lane-stop:funding`, `lane-stop:limited`, `lane-stop:turn-cap`, `lane-stop:failed` |
| 10 stalled lane stop | an open pull request into main, of any author, carries a pr-unblock lane-stopped comment by `merge.agent-identity` naming its current head, or a `needs-human-cleared` comment for that head whose reason now routes to a failing status, older than 2 hours (four `pr-unblock-dispatch.yml` ticks), with no `pr-unblock / <activity>` check run but a skip started on that head since, and no `stop-resolved` skip since: its same-head retries are spent; one issue lists each such stop | `stalled-lane-stop` |
| 11 post-merge unreadable | each of the newest 4 post-merge reports (`pr-merge-post-merge-report`, kept by `post-merge-dispatch` in a trusted scheduled or manual `pr-merge` run on `main`) has exit code 3: the post-merge check could not read lane merges, so merges hold with only a warning; the issue names the newest report's reason, each monitoring run prints it as an `::error` while it holds, and it only notifies and clears on a readable report. A run that kept no report neither counts nor resets; no report within 70 minutes leaves the signal unread | `post-merge-unreadable` |
| 12 listing held | each of the newest 4 `pr-merge-summary` artifacts of trusted scheduled or manual `pr-merge` runs on `main` has `listing_held: true`: the merge job could not list the open pull requests, so it gated nothing while its runs stayed green; the issue names the newest summary's `listing_held_reason`, and it only notifies and clears on a sweep that listed. A run that kept no summary neither counts nor resets. The 4 must be unbroken: a fault that lets one sweep in 4 list never fires, and that sweep does gate. A 4-of-8 rule would read 8 summaries on every monitoring run in place of 1 | `listing-held` |
| 13 lane holds | one lane has `monitor.lane-holds.threshold` held runs or more (default 4) over the last `monitor.lane-holds.window-hours` (default 24). A held run is a green run of this repository's head, on an event that runs the default branch's code, whose hold job succeeded with a hold notice: work-resolve-issue's `report-outcome / run` job naming a fault stop whose retries were all faults, work-unblock's `label-unblocked` job naming a listing it could not read, pr-refine's `fix-docs-handoff` or `fix-docs-subscription-handoff` job naming a `fix-docs` read that failed, and, on a green or red pr-refine run, its `record-passes` job's `refine-failed` warning naming a Refine pass that failed, intake-triage's `apply-verdict` job naming a `held:` fault, pr-verify's `check-intent`, `check-intent-subscription` or `check-intent-fallback` job and pr-review-main's `trigger`, `review`, `review-subscription` or `review-fallback` job each with a `held:` notice from a `Note the hold` step that ran, and pr-merge's `merge` or `enable-auto-merge` job naming a `Lane token hold`. Each monitoring run reads the newest green runs per lane that completed in its window, up to the lane's cap (`holdRuns` in `.github/scripts/maintenance-monitor-signals/signals.mjs` `HOLD_LANES`, else the default 6 in `collect.mjs` `LIMITS.holdRuns`: pr-verify and pr-merge set 80, pr-review-main to 70, intake-triage to 40 and work-unblock to 20; for pr-refine, its failed runs are listed and read as well, and the 6 covers its green and red runs together), or since the time the last run read through when that is earlier, and carries the held runs it has found to the next run in its `monitor-signals-jobs` artifact, with the span it read them over. Each of those hold jobs also keeps a `lane-hold-<lane>` artifact for a day when it held (`.github/scripts/lib/lane-hold-marker.mjs`, its body the lane and the run id); each monitoring run lists them, one call per lane, and counts a marked run that its lane's run list holds and the read found no hold in, so a run past the cap still counts. A marker list that fails leaves the signal partly read, as below. An issue held that often is one of its lane's held runs, and the finding names each issue held more than once. It only notifies, adds no stop and no cap, and clears once the count drops below the threshold. A rule that was not read leaves the signal unread. A lane over its cap, or a span shorter than the window, leaves it partly read: a lane whose read runs reach the threshold still files or keeps the incident, since holds read in part of the window are a floor on the whole, but only a whole read clears it. The span starts again when a monitoring run finds no carry, or one that read through a time more than 6 hours before its window, and after a failed read | `lane-hold:work-resolve-issue`, `lane-hold:work-unblock`, `lane-hold:pr-refine`, `lane-hold:intake-triage`, `lane-hold:pr-verify`, `lane-hold:pr-review-main`, `lane-hold:pr-merge` |
| 14 lane variables | a failed scheduled `work-unblock.yml` run of `main` that completed in the window (its own read, up to 10 runs, apart from the failed-runs read and its cap of 12; more, or a failed read, leaves the signal unread) has a failed `publish-lane-level` job with a failure annotation starting `lane-variables-changed:` or `lane-variables-unread:`, or one of its two variable check steps ended without success and with no such annotation (a timeout): `work-unblock.yml`'s `publish-lane-level` job listed every repository variable with the lane token before its publish and again after, and a variable other than the level variable was created, changed (value or `updated_at`) or deleted, or a listing was missing or incomplete ([pr-run-activity.md](pr-run-activity.md), the Variables mitigations). The incident opens at once, at critical priority: a repository variable can shadow an organization variable such as the lanes kill switch. It closes on its own only after 168 hours clear, since the next hour's check passes whether or not anyone set the variable back | `lane-variables` |

Every run's job summary lists every signal's state (clear, on with how long, the incident it holds,
muted, or not read) and, per current finding, the key, the owning area and the evidence inside a text
fence as inert lines. That summary is the status record. No run comments on a state change.

An incident issue has a plain title set per signal in `issues.mjs` `FILING`, Issue Type `Bug`, Work
status `needs-triage` and a Priority by signal severity (critical for `main-red` and `lane-variables`; high for what blocks
the pipeline), set at filing; Size, Complexity and Uncertainty are left to triage. Its first body line is
`<!-- factory-monitor key=incident:<signal> fp=<state> -->`; the body names the signal and, per
finding, the key, the owning area, and the summary and the evidence each inside a text fence. The
state fingerprint covers the findings' keys only, so new evidence for the same key writes nothing and
a body an admission read stays as it was; no finding is the clear state.

`monitor.incidents.<signal>` in `pr-pipeline.yaml` sets, per signal, `open-hours` (how long the signal
stays on, in unbroken hourly runs, before an incident opens; 0 opens at once, as `main-red` does) and
`close-hours` (how long it stays clear before its open incident closes). A clear run restarts the open
timer and an on run restarts the close timer, so a signal that flaps inside its thresholds opens no
issue and writes nothing. The timers are carried in the `monitor-signals-jobs` artifact; a carry that
is missing or over 6 hours old restarts them, which delays an incident and never opens one early. The
newest incident for a signal decides: open with the same keys, nothing is written; open with new keys,
the body is rewritten; past `close-hours` clear, it is closed as completed; closed as not planned or
duplicate, the signal is muted, and reopening that issue ends the mute; closed otherwise, a later
episode past its open threshold files a new incident, except that a person's close holds while the
keys are the same and no finding is newer than the close.

A run that could not read one of a signal's sources leaves that signal's timers and open incident as
they are, so a partly read signal neither clears nor loses findings (signal 13's partly-read gap files and keeps its incident on what it read, and only stops it clearing); a source the lane does not map,
or thresholds it cannot read, leaves every signal as it is. Each rewrite takes `agent-ready` off the
issue, since a person vetted the earlier text. Issues of every age are read, page by page until a
short page; a run that spends its call
budget there stops before writing. An open issue with an earlier marker (`key=family:<signal>` or a
per-key form) is retired: closed as not planned with a comment pointing at the job summary, its
history left in place. It
writes 1 s apart and stops at 250 REST calls. A source it
cannot read is listed in the step summary and the other signals still run. Failed runs are read 100
to a page, up to 5 pages, until 12 lane runs are kept, so fork and pull-request runs dropped after
the read cannot hide one; 5 full pages that keep fewer are a gap for signal 3. Signal 11 reuses the `pr-merge` run list the budget read makes, lists the report artifacts once, and downloads reports newest first until one is readable: 2 calls while the check reads, at most 5 while it does not. Signal 12 shares one read with signals 5 and 8: the summary artifact list, then a run read per artifact and a download per trusted summary, newest first, until one listed: 3 calls while the listing reads, at most 17 through a hold. Signals 5 and 8 read the sweep that listed; no such sweep in the newest 8 summaries, or one over 70 minutes old for any reason, leaves them no sweep and is a gap for those two, and signals 3 and 12 still read the held sweeps.

It holds the job's own `GITHUB_TOKEN` (`actions`, `checks`, `contents` and `pull-requests` read,
`issues: write`), never a lanes App token, so its issues come from `github-actions[bot]` and start no
workflow. The kill switch stops it. The lanes App reading in signal 2 is what pr-merge's token sees
at the start and end of each run, not the broker's own quota record, which this token cannot read.

## Write identities

Which GitHub identity each workflow in `.github/workflows/` writes as. GitHub's rule on which
`GITHUB_TOKEN` events start workflow runs is on its
[`GITHUB_TOKEN` page](https://docs.github.com/en/actions/concepts/security/github_token#when-github_token-triggers-workflow-runs).

| Identity | Workflows | Why |
|---|---|---|
| `GITHUB_TOKEN` (`github-actions[bot]`) | every workflow not named below, and the reads and check runs of those that are | Its writes start no workflow run, a dispatch aside, which the lane sweep's digest and the monitoring lane rely on so their own issues start no lane; it has its own per-repository API quota ([ADR 0085](../../adr/0085-run-org-lanes-from-ci-workflows-under-one-lanes-app-with-central-grants.md)) |
| Lanes App `melodic-automation-lanes`, minted per job by the broker (`.github/actions/request-lane-token`) | `pr-merge.yml`, `pr-run-activity-write.yml` (which the write jobs of `pr-unblock`, `pr-refine` and `work-resolve-issue` call), `intake-triage.yml`, `work-unblock.yml`, `upstream-apply-changelog.yml`, `maintenance-tidy-code-upkeep.yml`, `maintenance-measure-skill-edit.yml` | Its pushes, labels and auto-merge arms must start the next lane's runs, which a `GITHUB_TOKEN` write does not; one App identity also lets the person tests tell a lane from a person ([lane write identity](../loop-lane/README.md#lane-write-identity)) |
| Release App `melodic-release` (`PLUGIN_RELEASE_APP_PRIVATE_KEY`, `actions/create-github-app-token`) | `release-publish-plugins.yml`, `dependabot-fragments.yml` | A pull request `GITHUB_TOKEN` opens or updates gets its `pull_request` runs only after approval, and these pull requests need theirs unattended |
| Owner token | none | Only the owner's own sessions use it; the babysit scripts count its calls as the `owner-token` API pool |

## Models

`models` sets the model, effort and turn budget of every model run, so a model change is one edit.
Each profile under `models.profiles` names:

- `model`: an alias (`opus` or `sonnet`), never a full model ID, passed as `--model`.
  `resolve-config` resolves any value outside `haiku`, `sonnet` and `opus` to `opus`, so a
  config that skipped the schema check still never runs `default` or the frontier tier.
- `effort` (optional): `low`, `medium`, `high`, `xhigh` or `max`, passed as `--effort`. Unset
  passes none, so the run takes whatever level the effort resolution order reaches next, the
  model's default when nothing else sets one
  ([model config: adjust effort level](https://code.claude.com/docs/en/model-config#adjust-effort-level),
  as of 2026-11-01; recheck when that section changes the order).
- `subagent-model` (optional, default `inherit`): `opus` or `sonnet`, set as
  `CLAUDE_CODE_SUBAGENT_MODEL` through the run's `settings` env; `inherit` sets nothing, and any
  other value resolves as `model` does. A spawn's own `model` and an agent definition's still win
  ([subagents: choose a model](https://code.claude.com/docs/en/sub-agents#choose-a-model), as of
  2026-11-01; recheck when that section changes the order or adds an override such as a mod's
  `agent.spawn` hook).
- `max-turns`: the turn budget, passed as `--max-turns`.
- `escalate-to` (optional): the profile one model rung up. A run resolved at `model-rung` 1
  (resolve-config's `model-rung` input) takes it in place of this one; at most one rung, so the
  target's own `escalate-to` is never followed, and a profile with none refuses `model-rung` 1
  (`no-rung-up`). Only the selected slot climbs, and only fix-ci's retry passes `model-rung` 1.

A role profile names a multi-agent role in place of `model`, and never both: `role`, `workload`
and `effort-role`, plus `max-turns`. It has no `model` or `effort` key, so it can name no model
ID. `resolve-config` reads its model and effort from the role map,
`plugins/multi-agent/reference/defaults.yaml` in the base checkout. The model is `opus` when the
role map gives `inherit`, no alias, or an alias other than `haiku`, `sonnet` or `opus`, and when
the role map is absent or unreadable, so a route never resolves to an empty model, `default`, a
model ID or the frontier tier. `resolve-config` also writes an `applied-by-patch` output, set
only when the selected activity sets `applied-by.patch`.

`models.routes` maps a run to a profile: a skill activity by its name, and a run that is no
activity by its run route: `verify-pr` for the [verifier](#verifier-verdict), `merge-risk` for
the [Merge-Risk line](#the-merge-risk-line)'s rating, `review-code` and
`review-security` for the code and security review lanes, `triage-issue` for intake triage, and
`summarize-reuse` for the read-only pass that describes a lane branch work-resolve-issue reuses
([pr-run-activity.md, Issue mode](pr-run-activity.md#issue-mode)), and `adjudicate-feedback` for
pr-unblock's read-only judge of a review finding address-feedback disputed
([pr-run-activity.md](pr-run-activity.md)), on the `review` profile. A run no route names takes `models.default-profile`. The config reader rejects a route or default
naming an undefined profile, and a route that is neither a skill activity nor a run route. A config with no `models` block gives every run the built-in `standard`
profile: model `opus` and 75 turns. `resolve-config` turns the run's profile into its
`claude-args` and `settings-json` outputs, which the runners on claude-code-action pass as
`claude_args` and `settings`, and into `model`, `effort` and `max-turns`, which a run on
`run-claude-cli` ([Funding](#funding)) passes as those inputs. The values come only from this file on the
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
its Size is `split`, except a sub-issue intake's size split filed whose body counts as its parent's
text (`admit.mjs` `trustedSplitChild`, the resolve's `splitChild` fact): admission takes such a
sub-issue whatever its Size, so when `split-child-size` names a size that runs, a split size reads
as that size and the pin carries it. Otherwise its `max-turns` is the size's `base-turns` times the complexity
factor, rounded up, replacing the profile's, and the size's `timeout-minutes` is the run job's
timeout; a skip takes the shortest size timeout. resolve-config outputs `issue-dimensions`
(`<size>/<complexity>/<uncertainty>`) and `timeout-minutes`;
work-resolve-issue.yml resolves them before its run job starts, since a job's timeout is fixed
then, and passes the dimensions on (`issue-dimensions`), so a field set while the run waits for
its slot cannot give it more turns than its timeout allows; without `issue-dimensions` the
timeout is 40 minutes. The launcher's leg gets the timeout less 15 minutes, for the steps around it. This repository's budgets are owner-approved starting values, tuned in
[`pr-pipeline.yaml`](../pr-pipeline.yaml) (`models.issue-dimensions`) from per-run measures. Large
is `split`, and Uncertainty Known and Knowable map to `run` and Unknown to `probe-first`. `complexity-profiles` (optional) maps a complexity to the profile the run starts on,
in place of its route's; the dimensions' turn cap still replaces that profile's `max-turns`. A
complexity with no entry keeps the route's profile. The config
reader rejects a key that is not a complexity and a value that is not a profile, and a
`split-child-size` that names no size that runs.

`models.issue-status` names an issue's state as its Work status org issue field: `field-id`,
`options` mapping each single-select option id to a state (the option's name on GitHub), `labels`
listing the issue labels each state collapses from, and `order`. An issue's labels collapse,
without case, to the first state in `order` one of whose labels it carries, or the last state,
`needs-triage`, when it carries none. A field value counts under the issue-dimensions setter
rule, and also, for every state but `agent-ready`, when its latest setter is one of `bot-setters`:
github-actions[bot] (the job token) and the `melodic-` Apps of the trusted-actor list; a `melodic-`
entry counts only while that list holds it as a bot with the same id and login. Third-party
bots never count, and `agent-ready` counts only from a listed human or the lanes App. A counted
option no entry maps fails the read with `unmapped-status`. The config reader rejects two options
for one state, a state with no label, a label listed twice, an `order` that does not list every
state once or does not end on `needs-triage`, a `field-id` that `models.issue-dimensions` uses,
and a `bot-setters` entry that is neither github-actions[bot] nor a `melodic-` bot other than the
lanes App, or repeats an id (`undefined-status`), and a `field-events-since` time that does not
parse. resolve-config's `issue-status.mjs` holds the collapse and the trust rule.

The field is the issue's state. Writers set it through `write-status.mjs` (`statusWriter`), and a
write that does not land fails the run. `read-status.mjs` decides an issue from its counted field
value: queue-state labels drop out, hold labels still hold on top, and `agent-ready` stays with
its label; an issue with no counted value keeps its labels. A failed field read throws, so a
caller treats the issue as unreadable, never as unheld. Status history merges the REST label
events with the field's changes; a bot's field events before `field-events-since` never count,
and a person's always do. Intake re-entry takes a listed human's release of a hold that exists
only on the field.

Intake splits an issue admission parks as Size Large into native sub-issues before any run
(owner Q93; `.github/scripts/intake-triage/refine.mjs`). The model returns either `parts`, groups
of the issue's trusted task-list line numbers, or, when each line repeats over named targets,
`groups` of target names it copies verbatim from those lines (a target-subset split). A
target-subset sub-issue holds every trusted line and one last `Scope:` line naming its targets,
under a header that says so; it counts as its parent's text only when every target is verbatim
text of a trusted parent line. `size-split` in `.github/actions/resolve-config/admission-rules.json`
holds `on-decline` (`subset` allows the target-subset split, `park` does not) and `max-parts`. An
issue with fewer than 2 trusted task-list lines gets the thin refinement first and splits on its
lines at the next triage. A split that cannot be made leaves the issue parked at `status: ready`
with no hold label, and the lanes App posts one comment naming the reason, once per reason and
body version (marker `<!-- intake-triage size-split-decline reason=<code> -->`): `not-human`
(a listed human did not file it), `few-lines` (fewer than 2 trusted lines even with the
refinement), `no-split`, `bad-split`, `bad-subset` (no valid split by line or by target), or
`no-type` (an Issue Type admission does not take).

work-unblock closes a split parent as completed only when every sub-issue closed with
`state_reason` `completed` by a listed human or a merge and the parent's done-when is covered
(`admit.mjs` `splitLeftOpen`); that same rule decides whether the lanes App's close counts as done
for what the parent blocks. It checks the rule when a sub-issue closes, and on the hourly sweep for
up to `limits.parent-rescan-per-run` open parents whose sub-issues all show completed and whose
number is the UTC hour modulo 24, so a parent whose last sub-issue closed outside the sweep window
still closes. A sub-issue closed as not planned, as a duplicate or with no reason
leaves the parent open. A split record covers the done-when when its parts number every item and
match the filed sub-issues; a split by hand when its body has a task list whose open items each
cite a sub-issue. An open task item in a listed human's comment on the parent stays the parent's
work, unless a split record took it because the comment was last written before the record. A
parent left open goes through admission's rules like any issue, and a Size Large one is refused
with `SIZE_SPLIT_DONE`, except a finished parent: every sub-issue closed as completed by a close
`subIssueLeftOpen` accepts (`admit.mjs` `finishedParent`). Admission takes that one at any Size
for one issue-lane run that checks the parent's own done-when and closes it `verified-done` or
parks it `verify-unmet` (`.github/scripts/work-resolve-issue/stop-routes.json`), and work-unblock
sends one already parked on `SIZE_SPLIT_DONE` back to intake once its sub-issues finish
(`label-unblocked.mjs` `reenterFinished`).

Lanes choose the model by difficulty along one ladder: Sonnet for mechanical work (the triage and
summary profiles), Opus at effort high for code (`code-fix`), Opus at effort xhigh
(`code-xhigh`) for a high-Complexity issue and fix-ci's one retry, and Fable above it. The Fable
rung is off: the schema admits neither `fable` nor `best` (Fable on Claude Code before v2.1.321;
CI pins 2.1.319) for `model` or `subagent-model`, so the config reader rejects a profile naming
either and no route, rung or Complexity reaches it. It
waits on an owner decision and a per-week Fable allowance for the lanes; the schema admits the two
values again when that allowance is set.

## Funding

Each Claude lane's runs are paid by one funding role. There are seven: `reviews` for both review
lanes, `issue-lane`, `intake`, `pr-unblock`, `pr-verify`, `maintenance` for the eval lane, and
`automations`, the default for any lane without a dedicated role. Roles divide the work and the
budget across accounts, so each has its own rate limits and credits; the account behind a role can
be swapped. A role's secrets are `<ROLE>_CLAUDE_API_KEY` and
`<ROLE>_CLAUDE_CODE_OAUTH_TOKEN`, the role upper-snake, so `issue-lane` gives `ISSUE_LANE_`.

[`.github/lane-funding.json`](../../../.github/lane-funding.json) is the source of truth: each
role's secrets, whether it is keyed, and each lane's workflow, job, launcher, triggers, gate, and
the secrets its job reads. `callers.test.mjs` in `.github/actions/resolve-config/` fails when a
job that reads a Claude secret is missing from the catalog, reads secrets other than those
listed or another role's, or passes a `role:` other than its own, and when a job that holds one under
`pull_request_target`, `issues` or `workflow_run` shows no author gate (check-trusted-trigger in a
job it needs, or the intake reusable's `allowed-author-ids`) or same-repo gate.

Only a lane on ci-workflows' `run-claude-cli` action gets an API key, so only a role with such a
lane is keyed; claude-code-action runs take the OAuth token alone, since they are not paid from
API credits. On `run-claude-cli` the key runs first and the subscription token only after the key
leg hands off (`run-claude-cli`'s `handoff` output: a credit stop, or class `auth` with API status
401 or 402; a 403 hands nothing off). `pr-verify` holds one credential per job: `check-intent`
runs on the key, and `check-intent-subscription` runs on the token, on a new runner, only after
`check-intent`'s handoff with no permission denial or when the key is empty; its lane record is
`pr-verify` with `fallback-reason` `credit-stop`, `auth` or `no-key`. With the org secret
`FALLBACK_CLAUDE_CODE_OAUTH_TOKEN` set, the subscription leg hands off once more (a limit stop, a
credit stop, or a 401 or 402) with no permission denial, and `check-intent-fallback` judges on
that token on a third runner, recording `fallback-reason` `limit-stop`, `credit-stop` or `auth`;
with it empty, the subscription leg is the last. `pr-verify-capture` has two jobs: `capture` on
the key, and `capture-subscription`, which records the capture `blocked` and runs no model
([Verifier verdict](#verifier-verdict)). The lane sweep's judge, on the `automations`
role, has the same three legs per unit (`judge`, `judge-subscription`, `judge-fallback`), each
started by a route job from the previous leg's handoff markers
([The lane sweep](#the-lane-sweep)). The read runner's callers
do the same in two calls, the second started by a job that reads this run's jobs: `pr-unblock`'s
and `pr-refine`'s lanes, and `issue-lane`'s `resolve-issue` and `resolve-issue-subscription`
([pr-run-activity.md, Issue mode](pr-run-activity.md#issue-mode)), and with
`FALLBACK_CLAUDE_CODE_OAUTH_TOKEN` set, a third call on that token after the second hands off
([Two calls on one credential each](pr-run-activity.md#two-calls-on-one-credential-each)). Each lane's workflow names
its role as a literal, and the runner policy admits it. A lane on pr-run-activity-write.yml passes
its role as the `role` input, and the lane record names that role's token as the run's credential.

## Loop caps

One counter per PR, in the findings store, is shared by every lane. After `loop.review-rounds`
full review rounds, one more high-severity-only pass runs; if it still has findings, the PR
escalates. Once `loop.review-rounds` of the address-feedback activity's rounds have run, a
write-access trusted person's fix request on a thread after the newest round runs one more round,
on the requested threads only. With no such request, a security lane finding rated `CRITICAL` (or
with no rating the lane reads), a pr-verify note or listed review bot's finding a trusted person
directed, a listed review bot's finding on a head the security lane held as `CRITICAL`, a
`claude[bot]` finding whose own text names the security lane and a `CRITICAL` rating or none, or
a person's `needs-human` hold hands the PR to a person; any other finding, a security lane
`IMPORTANT` or `SUGGESTION`, a listed review bot's finding, any other `claude[bot]` finding (ruled
as the code lane's, since a footer in its text is model text, not a review lane's) and an
undirected pr-verify note included, goes to one fresh fixer round, a new session like
every round, whose preamble carries a fixed brief: fix each finding in code and never weaken a
test or check to close one. That is the last automatic round: once it has run, no sweep, schedule
or dispatch starts another. The next select fails the head as
`feedback-verifier-open` when only pr-verify notes are open, else as `feedback-not-converging`, a
comment that names the open threads. A round cap is a lane bound, not
an intent question, and pr-verify's FAIL already holds the merge until it passes a later head. Removing the label alone does not resume it, since
the rounds already run still count: a person resolves the open threads, or a write-access fix
request still gets its own round, as the comment's resume steps say. The round marker and the neutral checks show `round <N> of max
<M>`, where M is `loop.review-rounds` plus the fresh fixer's round. The default is 2; this
repository's value is in `docs/conventions/pr-pipeline.yaml` `loop`. `loop.findings-after-first-review`
sets what a CI review lane reports on a head after the first one it reviewed whole: `blocking-only`
(the default) reports blocking findings only, `all` reports every finding on every head. The lane's
prior-findings step reads it from the default branch's `docs/conventions/pr-pipeline.yaml`; an
absent or unread value is `blocking-only`. Separately, after `loop.no-progress` lane runs in a row that change nothing, the PR
escalates. `loop.fix-ci-rounds` (default 3, at most 10) is the number of fix-ci commits the lanes
App may push to one PR; the next fix-ci run hands it to a person before any model turn.

## Limits

The optional `limits` block sets when the lanes restart work the usage limit stopped. Durations
are whole hours, at most 720; stop caps are at most 10 and `restarts-per-run` at most 50, so a
typo cannot let a forged limit stop restart a lane without bound. resolve-config emits every key
with its default.

| Key | Default | What it sets |
|---|---|---|
| `fallback-reset` | 5 | Hours after a limit stop that names no reset time (every `auth` stop) before the limit counts as reset. |
| `reset-clamp-min` | 1 | Fewest hours after a stop before a restart, whatever reset the stop names. |
| `reset-clamp-max` | 168 | Most hours after a stop before a restart, whatever reset the stop names. |
| `restarts-per-run` | 5 | Issues one work-unblock sweep restarts or re-fires. |
| `refire-queue-per-slot` | 2 | Kill-switch re-fires' queue target per issue-lane slot (`SLOTS`, the effective lane level `lane-level-value.mjs` reads): a sweep re-fires breaker-stranded issues, oldest first, only until the unfinished work-resolve-issue runs reach this times `SLOTS`, within `restarts-per-run`. At most 10. |
| `stale-queued-minutes` | 60 | Minutes after it was created past which a work-resolve-issue run still at status `queued` is left out of the unfinished runs `refire-queue-per-slot` counts: its first job never got a runner, so GitHub lost it and it never starts. The sweep logs how many it left out. A reopened fix issue's in-flight check also ignores such a run when it names no issue; one that names the issue still holds it. At most 1440. |
| `sweep-gap-minutes` | 15 | Minutes after a full work-unblock sweep (a run that uploaded `work-unblock-verdicts`) finished during which the sweep a finished work-resolve-issue run starts skips its work and requests no lane token. A scheduled sweep or an issue close never skips; a read that fails runs the sweep. 0 turns it off; at most 60. |
| `readmit-per-run` | 20 | Open `status: ready` issues with neither `agent-ready` nor `admission-deferred` one work-unblock sweep runs intake's admission rules on, oldest updated first; at most 100. Only an issue that reaches the rules counts: a hold or refuse label, an open blocker or sub-issue, a `status: ready` neither a listed human nor the lanes App added, or a standing `agent-ready` removal leaves it out uncounted. |
| `parent-rescan-per-run` | 5 | Open issues whose every sub-issue is completed and whose number is the UTC hour modulo 24 that one work-unblock sweep reads to close a finished split parent, oldest updated first; at most 100. A parent whose last sub-issue closed outside the sweep window closes on its hour; one that stays open logs why. |
| `limit-stops-per-head` | 3 | Limit stops on one PR head after which pr-unblock stops dispatching it again; also the failed `resolve-conflicts` runs and the failed or `not-applicable` `fix-ci` runs across base moves one head gets, and the red or held `fix-docs` runs in the run listing that one PR gets. |
| `limit-stops-per-issue` | 3 | Limit and funding stops since a person last added `agent-ready` before work-unblock stops restarting the issue: it comments with `outcome=failed` (signal 9 reports it), removes `agent-ready` and adds no label. Also the most immediate re-fires `report-outcome` makes of runs that stopped on stale workflow files, since a person last added `agent-ready` or a run last reported; past it, work-unblock's sweep re-fires them. |
| `wip-cap` | 60 | The issue lane's WIP cap when the lane merge rate cannot be read ([WIP cap](#wip-cap)); at most 500. |
| `turn-cap-restarts` | 0 | Restarts after a run reaches its turn cap, since a listed human last added `agent-ready`, before report-outcome stops the issue on the `turn-cap-spent` route; at most 5, and 0 never restarts. |
| `stop-retries` | 2 | Restarts after a stop the issue lane's `stop-routes.json` routes to `retry` (or fewer, a row's own `retries`), and, counted apart, restarts after a `wait`, each since a listed human last added `agent-ready`, before report-outcome stops the issue on the `retry-spent` route; at most 5, and 0 never retries. A stop whose row sets `fault: true` holds at the cap instead when every counted retry was such a stop and the run made no branch of its own: that hold has no hard count, only the `stranded-backoff-hours` re-fire backoff, at most 24 hours between re-fires. |
| `stranded-backoff-hours` | 3 each | Per cause, the base hours of work-unblock's re-fire backoff for a stranded `agent-ready` issue: the wait is these hours doubled once per re-fire already made on the same lane workflow files, up to 24, except `kill-switch`, which never doubles. Causes: `no-run` (no work-resolve-issue run started) and `no-report` (a run ended green with no report and no pull request), where it is also the wait before the first re-fire; `failed-again` (a re-fired run failed or was cancelled again), at least twice these hours; `failed-mint` (no lane token), backed off only past `limit-stops-per-issue` re-fires, so at least these hours doubled that many times; and `kill-switch` (a kill-switch refusal: past `limit-stops-per-issue` trips each re-fire waits these hours after the run ended, flat, with no cap on trips). Each 1 to 24. |
| `fix-ci-per-run` | 2 | fix-ci dispatches one pr-unblock-dispatch run sends; at most 20. |
| `fix-ci-restarts` | 1 | Further fix-ci dispatches on one PR head after its first fix-ci run failed; 0 to 5. |
| `fix-docs-per-run` | 2 | fix-docs dispatches one pr-unblock-dispatch `refine` run sends for its PR's event; 0 to 20. Each event offers one PR, so 0 turns CI fix-docs off and any other value turns it on. |
| `admission-factor` | 0.8 | Share of the lane's hourly merge rate admitted per hour for the queued cap ([WIP cap](#wip-cap)); greater than 0, at most 1. |
| `admission-min-per-hour` | 1 | Admissions per hour the queued cap never falls below, so a day with no lane merges cannot hold admissions shut; 0 to 100, and 0 removes the floor. |
| `api` | schema | GitHub API margins per pool (`github-token`, `lanes-app`, `graphql`, `owner-token`, `content-creation`). `limit-cap` sets the pool's planned budget: planned = min(header limit, `limit-cap`), used = header limit - header remaining, left = planned - used. `github-token` defaults it to GitHub's documented GITHUB_TOKEN limit, so a higher header limit is headroom, never a target; the other pools have no cap and plan to their header limit. `plan` and `read-floor` are shares of the planned budget; `writer-pause`, `breaker` and `stop-floor` are shares of the header's limit, by its remaining; `content-creation` adds `per-minute` and `per-hour`. Their defaults are in `.github/actions/log-api-budget/rate-limits.json`, the only copy, which every merge hold list floors, so a change to a default waits for a person. The rate guard (`.github/actions/log-api-budget/rate-guard.mjs`, `planOf`) reads `read-floor` and `limit-cap`, to warn once while calls continue, and stops on the header's remaining and GitHub's refusals: at a remaining of 0, or at or under `stop-floor` of the header's limit, it sends no further call to that pool before the header's reset, records the stop in the job's stop file, and holds the step under `API_BUDGET_HOLD`, else fails it; a response with no readable limit, remaining or future reset never stops on `stop-floor`; `pace` (github-token, default 0.2) is the share of the header's limit, projected left at the window's reset from the burn rate so far, under which a timer-driven lane skips a scheduled tick when the previous scheduled run, by run id, marked a clean pass of its work (its `Mark this tick's work done` step, which a held or red pass and a paced tick skip), so two scheduled ticks in a row are never both skipped and its cadence halves (`.github/actions/log-api-budget/pace.mjs`; the lost-run reconciler, pr-unblock-dispatch and work-unblock's sweep read it, and pr-merge's post-merge-dispatch reads it for the merge and enable-auto-merge sweep jobs, which skip at job level while the post-merge check and cover dispatch run on every tick), so the timer lanes slow down before the breaker stops every lane; `0` turns pacing off; `start-gate` (github-token, 0.1) is the share of the header's limit, by its remaining, under which a kill-switch gate that starts new work (`.github/actions/check-kill-switch`, `budget: "true"`) does not start its lane while the reset is still ahead (one GET /rate_limit per such gate, a stop with reason `kill-switch`, cause `budget` and the window's `reset`; a refused read, 403, 429, `retry-after` or a remaining of 0, also stops, and any other failed read proceeds); that gate reads it from rate-limits.json alone, and the schema rejects a `start-gate` set here; the others are thresholds meant for the hub's limits sampler, and nothing in this repository enforces them. resolve-config passes the block through as set. |
| `lane-level` | 2, 4, 3, 2, `[lanes-app]`, `true`, `CLAUDE_LANE_LEVEL`, 150 | The adaptive lane level L (owner decision Q111): `floor`, `ceiling`, `default`, `clean-windows` and `pools` for `decide()` in `.github/scripts/lib/lane-level.mjs`, whose truth table is `lane-level.vectors.json` beside it. `shadow` (default `true`), `variable` (default `CLAUDE_LANE_LEVEL`, must end in `_LANE_LEVEL`) and `valid-minutes` (default 150, 60 to 1440) govern publish and read: work-unblock's hourly `publish-lane-level` job publishes L as `<level>@<valid-until>` in `variable`, and pick-slot and label-unblocked read it through `.github/scripts/lib/lane-level-value.mjs` (empty, expired or malformed reads as `default`, clamped to `floor` and `ceiling`). While `shadow` is set the job mints no token and writes nothing, `SLOTS` stays `default`, and both log the level they would use. Each window L steps up 1 after `clean-windows` windows in a row that each had demand (runs waiting, or every slot running) and no limit signal, when every pool in `pools` fits: peak used, as a share of the pool's planned budget, times (L+1)/L at most `api.<pool>.plan`. A window where a pool has `api.<pool>.writer-pause` of its header's limit left or less resets the streak. Any limit signal the lanes App's own calls meet (403, 429, a secondary-limit or GraphQL rate-limit error, `retry-after`) halves L, rounded down, to no less than `floor`, and blocks a step up until the reset it names. A breaker trip is not a signal: it mostly reflects GITHUB_TOKEN spend, which pacing controls, and the breaker stays the backstop. Missing readings or demand hold L and the streak; a missing or malformed previous level reads as `default`, and every level is clamped to `floor` and `ceiling`. A `floor` above the `ceiling`, as set or defaulted, is rejected. An `api` pool field left unset reads from `rate-limits.json`, as the rate guard reads it. `.github/scripts/lib/lane-level-replay.mjs` replays the rule over the hub's recorded history. |

report-outcome and the work-unblock sweep read them from resolve-config's output;
pr-feedback-dispatch, pr-unblock-dispatch and work-resolve-issue's WIP cap check resolve the base
config themselves. A config the resolver refuses fails the two dispatchers before any dispatch;
the WIP cap check holds the run ([WIP cap](#wip-cap)). This repository's values are in
[`pr-pipeline.yaml`](../pr-pipeline.yaml) (`limits` and `wip`).

In pr-merge, a rate limit that stops any of `post-merge-dispatch`'s GitHub calls (its post-merge
check, its full-run dispatch or its re-run) fails that job red and goes to the `merge` and
`enable-auto-merge` jobs as its `rate-limited` output, naming the pool and the reset. Each of them
then ends red at its first step and sends nothing to GitHub. This holds for any pool and for the
rest of that run, even once the reset has passed: a run is short and the next scheduled run starts
the sweep again, so stopping is safe and costs at most one sweep.

The merge job's candidate listing goes through `.github/scripts/pr-merge/retry-call.bash` with
`--read`: at most three tries, waiting out a recorded rate stop or a capped, fully jittered backoff,
within 60 s of waits in all. Without `--read` a command runs once, so a write is never repeated.
Each try reads the open pull requests through GraphQL, 100 a page with the open count on each
page, and passes only when every page's count agrees and the listing holds that many. A listing
with more than 10 pages (1000 pull requests) is cut short, and another try reads the same, so it is
not tried again and is unknown at once. The trusted actors' pull requests are kept by numeric
account id (`User.databaseId` or `Bot.databaseId` against trusted-actors.json's `id`), so a renamed
account still matches; the lanes App and Dependabot are kept by their own switches. A listing still unknown ends the
step green with a `::notice::` hold: every step that needs the listing waits on the step's `listed`
output, so the job lists, gates, merges, files, dequeues, re-fires and clears nothing, and the next
scheduled run lists again. A failed read, a past-budget rate stop and a full listing leave this job
green. The re-fire and escalation-clear steps wait on `listed` too.

A held run still does two things. It writes the `pr-merge-summary` artifact with `listing_held`,
`listing_held_reason` and no verdicts, so readers can aggregate holds and signal 12 can count them.
And it writes the sweep cost line, ending `listing-held=true`. `Record a failed lane merge` waits on
`listed` like the check before it, so a failed lane merge is recorded, and the lane's merge-queue
entries dequeued, by the next run that lists.

## WIP cap

The optional `wip` block sizes the issue lane's work in progress from the lane merge rate. The WIP
cap check (`.github/actions/check-wip-cap`) runs before work-resolve-issue takes a slot, and
work-unblock runs it before a re-fire and before adding `agent-ready`. It reads, one request at a
time and none once `x-ratelimit-remaining` reaches 0, the lanes App's open pull requests, those
merged in the window, those opened in it, and the open `agent-ready` issues that carry no hold
label (`needs-human`, `needs-owner-decision`, `needs-reporter-info`).

| Key | Default | What it sets |
|---|---|---|
| `target-lead-time-hours` | 2 | Target open-to-merge hours. The WIP cap is merged lane PRs per hour times this, rounded up, at least `min-cap`. |
| `min-cap` | 1 | Floor under the computed WIP cap, so a day with few merges cannot shrink the cap until the lane stalls. This repository's value is in `docs/conventions/pr-pipeline.yaml` `wip`. |
| `merge-rate-window-hours` | 24 | Rolling window for the merged and opened counts. |
| `opened-to-merged-ratio` | 0.8 | Lane PRs opened in the window may be at most this share of those merged in it. Not `limits.admission-factor`, which sizes the queued cap. |
| `held-cap` | 60 | Held lane PRs at or above which the held buffer is over its cap; on or after `pause-from` the lane pauses there. This repository sets 10. |
| `held-alarm-hours` | 24 | Age past which a held lane PR raises the alarm. |
| `pause-from` | empty | UTC date or date-time from which runs pause over the WIP cap or the held cap, and new admissions over the queued cap; empty never pauses, so intake admission has no queued cap. This repository sets 2026-10-22. |

A held lane PR carries `needs-human` or `do-not-merge` in any case, or has a body line exactly
`Hold: a human merges this`. Held PRs never count against the WIP cap; countable PRs are the open
lane PRs that are not held. Over the WIP cap (countable at or above it), over the held cap, over
the admission share, at or over the queued cap, or with a held PR past the alarm age, the check
writes a warning annotation. Over the WIP cap or the held cap on or after `pause-from` it pauses runs: work-resolve-issue
starts no run, work-unblock re-fires none, and the log and step summary carry one line
`admission paused: reason=<wip|held-cap|wip,held-cap> countable=<n> wip_cap=<n> held=<n> held_cap=<n>`
(a `::notice` annotation titled `admission paused`). When the open listing or
the base config cannot be read, or a search answers `incomplete_results: true`, the pause is
unknown and the run holds ([outage posture](#outage-posture) elements 2 and 3):
`capped` is `true`, `pause_basis` is `unknown`, and the log and step summary carry one line
`WIP cap hold: <what could not be read>, ...` (a `::notice` annotation titled `WIP cap hold`).
pick-slot starts resolve-issue only on `capped` `false`, so a check that fails or sets nothing
holds too, with the same notice from pick-slot's `Hold on an unknown WIP cap` step. The job ends
green, and work-unblock's sweep re-fires the issue as a WIP cap skip, whose run reads again. No
stored state decides the pause. Without a merged count the cap is `limits.wip-cap`, a configured
default, so that failure holds nothing. A held PR's age runs from when it opened.

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
that fails leaves `admission-open` `true` (`admission_basis: fail-open`) and changes no run pause;
intake admission and work-unblock read that basis as no room and admit nothing. A
search that answers `incomplete_results: true` (a degraded search can answer a false empty) is
unknown, not failed: admissions pause whether or not `pause-from` is set or reached
(`admission_basis` and `admission_reason` `search-incomplete`), with a `check-wip-cap` warning,
and work-unblock's deferral log names that reason. A base config the check cannot read (a failed
resolve-config import, as after a failed `npm ci` of its dependencies) leaves the caps unknown, so
admissions pause the same way (`admission_basis` and `admission_reason` `config-unreadable`), with
a `check-wip-cap` warning; the run holds, as on any failed read the pause depends on. The queued cap itself still
pauses only on or after `pause-from`, and no run pause changes.
The queued issues come from the repository issues listing (open `agent-ready` issues, oldest
first), not the search index, whose results carry no recency guarantee. The listing also returns
pull requests and takes no label exclusion, so pull requests and the hold labels (`needs-human`,
`needs-owner-decision`, `needs-reporter-info`, in any case) are left out
after the read. A page that fails or is not a list leaves the queued count unread
(`admission_basis: fail-open`). The listing reads at most 10 pages of 100: a full tenth page counts
one more issue as queued, and admissions pause (`queued_truncated: true`).

work-unblock is the one lane that adds `agent-ready` to a new issue. Past the room it labels a
ready issue `admission-deferred` instead, and each hourly sweep revisits the open
`admission-deferred` issues oldest first, before the issues closed in its window. Only an issue
whose newest `admission-deferred` was added by the lanes App or a listed human (by id) is
revisited; any other is left as is with a warning annotation, since re-admitting it adds the App's
`agent-ready`. Of those, one still ready gets `agent-ready` within the room and loses
`admission-deferred`, a held one stays deferred, and any other loses it. After the closed issues,
the sweep runs intake's admission rules on the open `status: ready` issues in no queue (neither
`agent-ready` nor `admission-deferred`, no hold or refuse label, no open blocker or sub-issue), at
most `limits.readmit-per-run` of them, oldest updated first, and writes as intake does, with one
exception: a refusal whose only reason is done-when items an unattended lane run cannot perform
beside items it can (no trusted `host-run`, no paid eval) parks at Work status needs-triage, not
confirmed, since refine.mjs splits those items off only inside an intake run. Before that write it
posts a hand-back comment opening with `<!-- work-unblock unparked triage -->`, once per body
version, so the triage sweep starts a new dispatch cycle and sends the issue to intake, whose
admission parks it at confirmed for the split. A person's `admission-deferred` mark refused that way
parks the same. A born-triaged issue whose filer has not yet set the Size or Uncertainty the rules refuse it for, and
nothing else, waits with no write and uses none of that cap; a person's mark on such an issue instead
comments why it is not admitted yet and removes `admission-deferred`, so the sweep admits it once the
fields land. If the fields never land, the triage sweep sends it to intake. Restarts, re-fires and relabels re-run issues already admitted and are never
paced. This queued cap replaces the admission window (`limits.admission-window-hours`) and owner
decisions Q2, Q17 and Q22 of the 2026-10-21 lane-flow interview.

Neither intake nor the sweep adds a new `agent-ready` to an issue whose work a merged pull request
may already have done: one in this repository whose body names the issue on a `Refs:` line
(`Refs: #<n>`, a list of issues holding it, or either with a parenthesized note), merged after the issue's
newest decision comment (a listed human's `**Decision recorded.**`) or lanes-App refinement
comment, or since it opened when it has neither. The issue is parked at `status: confirmed`, loses
`status: ready` and `admission-deferred`, and gets the admission comment naming the pull requests.
An agent checks the work: it closes the issue when the pull request finished it, or posts a
`**Decision recorded.**` comment saying what is left, which intake-reenter sends back through
intake with the cutoff past that pull request. Each pass reads its issues in one GraphQL call (at
most 50 issues a call); a read that fails admits as though no such pull request merged.

work-unblock's `label-unblocked` job runs one at a time across the repository (one `concurrency:`
group with one waiting run, which a newer run replaces), so a burst of closes or finished issue runs,
or a close run beside the hourly sweep, cannot each admit the full room. The next sweep does a
replaced run's work: it reads the whole state, and its closed-issue window repeats a close run's. An `agent-ready` label added moments before may still be missing from
the issues listing, so a run right after another may read the room as one admission too wide.

Intake's own admission (apply-verdict) runs once per issue, so runs for different issues can read
the same room at once. Under a room it first claims a place with a fresh `admission-deferred`, then
adds `agent-ready` only while fewer issues than the room count ahead of it. Those are the open
issues the issues listing shows with `agent-ready` or `admission-deferred`, each
placed by its newest `admission-deferred` add (else its first `agent-ready` add) since 10 minutes
before the status read; a tie, or an issue whose add its events do not show yet, counts as ahead.
Otherwise, or when that read fails, the issue stays deferred for work-unblock's sweep. An issue
counted both there and in check-wip-cap's queued count only makes the check stricter: it defers
to the sweep, never stalls. The 10 minutes start well before the status read, since a run that
claimed before the read may add `agent-ready` after it.

The queued cap paces only work-unblock's and intake admission's new `agent-ready` labels. Every
other writer is exempt by design (owner decision 2026-10-22, #8966), and the issues it labels still
count as queued work:

| Writer | Paced |
|---|---|
| work-unblock adding `agent-ready` to an unblocked or deferred issue | Yes |
| Intake admission (apply-verdict) adding `agent-ready` to a newly triaged issue | Yes |
| work-unblock's restarts, re-fires and relabels (remove and re-add on an admitted issue) | No: they re-run work already admitted |
| A person adding the label by hand | No |
| A person-run skill: `/work-items:triage`, `/work-items:decompose`, `/work-items:attend-queue`, `/work-items:track` | No: a person's account, their call |
| `post-merge-demotion-alert.yml` red-main fix issues | No: it files them unlabeled and reopens one on a repeat failure keeping the `agent-ready` a person gave it, which work-unblock relabels; guardrail work |

The check publishes its status as one flat JSON object: the step output `wip`, the step summary
and the log line `check-wip-cap: <json>`. `capped` is `true` only while runs pause or hold;
`admission-open` is `false` only while new admissions pause. A job that reads only `capped`
(pick-slot) passes `reads: pause`: the check then makes just the
open listing and the merged count, and leaves the admission fields null with `admission_basis`
`not-read` (`search-incomplete` or `config-unreadable` when either applies).

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
| `queued_issues`, `queued_total` | Queued issues with no open lane PR and no blocker that still blocks (at most 30 blocker reads; an unread issue counts), and those plus the held lane PRs; null when a read failed. |
| `queued_truncated` | `true` when the queued listing filled its tenth page of 100, so more queued issues may be unlisted; admissions then pause. |
| `queued_cap`, `admission_factor`, `admission_min_per_hour` | The queued cap and its inputs. |
| `wip_over`, `held_over`, `admission_over`, `queued_over`, `held_alarm` | Which limit is crossed. |
| `alert` | Any of the five. |
| `pause_from`, `paused` | The pause date and whether the lane pauses now. |
| `pause_reason` | `wip`, `held-cap` or `wip,held-cap` while paused; null otherwise. |
| `pause_basis` | `read` from this run's reads; `unknown` when a read the pause depends on failed, so the run holds. |
| `admission_open`, `admission_reason`, `admission_room` | Whether new admissions are open; `queued`, `search-incomplete` or `config-unreadable` while paused, null otherwise; admissions left before the cap, null when nothing gates them. |
| `admission_basis` | `read`; `fail-open` when the queued count could not be read; `search-incomplete` when a search answered `incomplete_results: true`; `config-unreadable` when the base config could not be read; otherwise `not-read` under `reads: pause`. |

## Adoption

With an `adoption` section, the lanes take over every trusted actor's pull request (owner
decisions Q22 and 2026-10-22): one rule for the lanes App, Dependabot, the release App, the owner
and anyone later added to `.github/standards/trusted-actors/trusted-actors.json`. When it is red
or needs a fix, a lane fixes it and it merges without a person, unless the fix changes behavior or
intent, which the verifier fails and escalates. This grants the lanes unattended power over PRs a
person opened. A PR is adopted when all of these hold:

- an account on the trusted-actor list opened it, a person or an App, matched by numeric id;
- it is not a draft, it is a same-repository PR into `main`, and it carries no `do-not-merge`,
  `needs-human` or human-gated label (`tracker.config.role_labels["human-gated"]` in the base
  `docs/conventions/work-items.yaml`, as pr-merge resolves it; a file yq cannot read holds every
  owner PR for the run and fails the dispatcher run, while lanes App PRs proceed under the other
  two labels);
- no body line starts with `Hold:`, read as babysit reads it: any case, after any non-newline
  whitespace (NBSP included), with a bare CR also ending a line;
- for a person's PR, its newest activity and its head commit's committer date are both at least
  `idle-hours` old. Neither one alone is enough. pr-merge reads the activity from the PR's
  opening, the head's arrival, and each comment, review, label change or title edit whose actor
  id is on the trusted-actor list ([The pr-merge lane](#the-pr-merge-lane) lists every event
  read), never the raw `updatedAt`, so another account's comments cannot keep the PR from going
  idle there unless they are a member's or collaborator's hold (a changes-requested review or a
  "do not merge" or `Hold:` phrase); fix-ci still reads the PR's last update (`updatedAt`). An App's PR does not wait.

A person's PR also skips the wait when a person put it in the merge queue and the queue removed
it for failed checks (owner decision Q-REQ (a)). The person's enqueue of that head stands in for
the idle wait, and grants nothing beyond it. In pr-merge, `babysit_merge_policy.ejected_enqueue`
reads the enqueue from `read_merge_queue`, and `requeued_by_person` accepts it only when all of
these hold:

- the PR's newest merge-queue event is a `RemovedFromMergeQueueEvent` with reason
  `failed_checks`, with no pushed commit or force push after it;
- the `AddedToMergeQueueEvent` that queued the removed entry has an `actor` and an `enqueuer`
  whose ids are both `kind: human` on the trusted-actor list. Logins and GitHub types are not
  read, because GitHub types an App's enqueuer as a `User`;
- GitHub had seen this head on the branch by the enqueue, and not since. That check reads the
  newest `created_at` of GitHub Actions' check suites for the head commit on the PR's head
  branch, which must be no later than the enqueue. GitHub sets it when a push arrives. A commit
  dated in the past but pushed after the removal therefore does not pass, and neither does a head
  that was reset away and pushed back;
- no person has commented, reviewed or commented inline since the enqueue, counting a comment
  edited since then. The lanes App and bots do not count. A request to wait, made before or after
  the run failed, therefore keeps the idle rule, as a comment after the lane's pin does for its
  own queued entry.

The only newer queue event allowed is the lane's own entry at this head, as described in
[The pr-merge lane](#the-pr-merge-lane). Anything else, or anything unreadable, falls back to the
idle rule. The decision records `requeue-after-ejection`. The gate then runs unchanged: every
hold, the verifier verdict, the head pin, and the `merge.max-queue-ejections` cap. If the lane's
own retry is removed too, its enqueue is not a person's, so the PR waits `idle-hours`.

An adopted PR that closes no issue in this repository is judged against its own title and body
when a person (a `kind: human` id on the trusted list, not merely a GitHub `User`) opened it or
an App in `spec-from-body-apps` did (an App whose bodies a script writes): resolve-pr gives the verifier that text as the spec, the verdict records `intent:
pull-request`, and the pr-merge gate accepts it with no closing issue. Any other App, the lanes
App included, still needs a closing issue a trusted person wrote: a model that wrote the diff
would also have written the spec it is graded against.

The body counts only if it was never edited, or was last edited by its author or a trusted person,
and the title only if it was never renamed, or was last renamed by its author or a trusted person
(its latest `RenamedTitleEvent`); otherwise the PR is not its own spec. The verdict records the
sha256 of that title and body (`intent_sha256`), and the gate refuses the pass
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
human-gated label holds a lanes App PR from `fix-ci` too, including the label `enable-auto-merge`
adds for that line, since its pr-merge escalation comment is not a pr-unblock lane escalation;
without one the tracker file and the trusted-actor list are not read, nothing is adopted, and only
`do-not-merge` and `needs-human` hold.

A person's adopted PR also gets `address-feedback` rounds, under the same idle rule, whose replies
post as the lanes App ([Owner pull requests](#owner-pull-requests)).

| Key | Default | Meaning |
|---|---|---|
| `idle-hours` | none | Hours both a person's PR (its activity, as the list above reads it) and its head commit must be unchanged; 1 to 720. Absent: nothing is adopted. |
| `spec-from-body-apps` | `[]` | App ids whose PR bodies a script writes; such a PR closing no issue is judged against its title and body. |
| `self-merging-apps` | `[]` | App ids that enqueue and merge their own PRs; pr-merge writes no reasons comment or risk escalation on one, and its score still holds pr-merge's own merge. |

## Review threads

`review-threads.reviewer-ids` lists review bots, besides `claude[bot]` and the review lanes, whose
review threads `address-feedback` works exactly as the reviewer bot's (owner decision
2026-10-26): it fixes or explains each finding, `publish-feedback` resolves what it fixed, and
the trusted-person and human-gated rules above apply unchanged. A disputed listed bot's finding
is adjudicated as a code-review lane finding is, and Codex's own shields.io severity badge decides
nothing. The security judgment is the security-review lane's. A dispute is adjudicated only once
that lane has posted its reviewed-head marker for the head the bot reviewed and holds nothing. A
`critical-security` hold (its `claude-lane-hold` comment) on that head, or one posted after the
bot's review, on a later head, sends the dispute to a person as `feedback-question-security`.
Before the lane has reviewed the head, the dispute waits: the round escalates nothing and skips
`finding-stands`, so the next review completion or the scheduled sweep runs it again. At the
round cap such a finding goes to the fresh fixer round as a code-review lane finding does, unless
a trusted person directed it or the security-review lane held its head as `CRITICAL`, which goes
to a person ([Loop caps](#loop-caps)). The bot's later comments in its thread
count as the reviewer bot's; anyone else's leaves the thread alone. A listed bot's thread that no
trusted person directed is worked only when the `@codex` request behind the bot's review came
from a person on the trusted-actor list. With no `@codex` comment, the review is automatic, and it
counts as asked for by whoever triggered it: the pull request's author on opening, or the actor of
a ready-for-review event. Every such event since the bot's previous review must be a trusted
person's or the lanes App's (`APP_SENDER_ID`). Any untrusted request or event since that review,
or none that can be read, leaves the thread for a person. So does a comment or review by anyone
else, apart from our own bots, that was edited since the window opened, or a deleted comment
of theirs, since either may have held a request. The reason is logged
(`codex-request-untrusted`, `codex-request-not-found`). A listed bot no comment can summon,
`github-advanced-security[bot]` (code scanning alerts, which it posts after each analysis of a
pushed head; `UNSUMMONED_REVIEWER_IDS` in `address-feedback.mjs`), needs no request: its thread is
worked when a trusted person or the lanes App opened the pull request, and logged with the same
reasons otherwise. The list is matched on the
account id GitHub records for each comment and its review, never on a login, so another account
using the same name matches nothing. The comment text stays data in every model prompt, as the
reviewer bot's does. This repository lists `chatgpt-codex-connector[bot]` (199175422) and
`github-advanced-security[bot]` (62310815). The
select job and `publish-feedback` read the list from the resolved config; `fix-ci-context.mjs`
and `pr-feedback-dispatch.yml` read it from the base's `pr-pipeline.yaml`. Absent: none.

| Key | Default | Meaning |
|---|---|---|
| `reviewer-ids` | `[]` | Account ids of the extra review bots whose threads `address-feedback` works. |

## Merge paths

The post-merge accounting sorts each merge into a path, so the paths roll up and compare per
window (owner decision Q1 (a) on
[#7531](https://github.com/melodic-software/claude-code-plugins/issues/7531)). `lanes` is a merge
the agent identity enqueued, the merges the post-merge check and the revert breaker act on. Each
path under `post-merge.paths` in `pr-pipeline.yaml` names the logins whose merge-queue actor or
enqueuer puts a merge on it, for a pull request an agent session wrote: its body carries
`<!-- session: … -->` or `Generated with [Claude Code]`, and one of its commits a
`Co-Authored-By: Claude` trailer (`isAgentAuthored` in
[`merge-path.mjs`](../../../.github/scripts/post-merge-demotion-alert/merge-path.mjs)). This
repository sets one, `owner-agent`, for agent sessions merging through the owner login.

| Key | Default | Meaning |
|---|---|---|
| `paths.<name>.mode` | none | `record`: the path's merges and reverts are labeled, and nothing demotes the lane, trips the revert breaker or holds a pull request. The only mode built. |
| `paths.<name>.enqueuers` | none | Logins (at least one) whose merge-queue actor or enqueuer puts an agent-authored merge on the path. |

On every canary push run, the alert workflow's `label-paths` job (`issues: write`, after the
alert job) reads the push's merges and the pull requests it reverts, and labels each one on a record path `merge-path: <name>` and
each reverted one also `post-merge: reverted`, creating a label that is missing. It files no issue
and posts no comment, and its `GITHUB_TOKEN` writes start no workflow run. A lane merge gets no
label; a push that reverts a lane pull request still files the revert demotion record, and
labels any record-path pull request it also reverts. A failed label write fails the job.

The rollup counts, per path, the merges in a window, how many were reverted (labeled
`post-merge: reverted` (or the older `post-merge:reverted`) or named on a lane revert record) and how many escaped (a pull request with a
`fix:` title merged later cites it as `#N` or by URL). That escape count is an upper bound, since
a fix also cites pull requests it did not repair. A path or revert label counts when the pull request carries it
now, or still had it when the label itself was deleted: the timeline keeps the LabeledEvent and records
no UnlabeledEvent for a deleted label, so a prune (for example, an apply while it was undeclared) loses
no history, while a label taken off on purpose stops counting. A merge with no path label is `lanes` by
its enqueuer, else `other`, so record-path merges before the labels count as `other`:

```bash
npm ci --prefix .github/actions/resolve-config && node .github/scripts/post-merge-demotion-alert/merge-path.mjs rollup --since 2026-11-06 --until 2026-11-12
```

It prints a Markdown table (`--json` for JSON, `--repo <owner/repo>` for another repository),
reading every pull request merged from `--since` to today, a day per search.

## Red main

When a full `pr-require-checks` run on `main` (scheduled or dispatched) fails, the
`report-red-main` job of
[`post-merge-demotion-alert.yml`](../../../.github/workflows/post-merge-demotion-alert.yml) applies
this rule after the alert job has filed its post-merge record. It runs no model; its scripts and
tests are in
[`.github/scripts/post-merge-demotion-alert/`](../../../.github/scripts/post-merge-demotion-alert/).

The full run pr-merge starts after each merge uses `GITHUB_TOKEN`, so its completion raises no
`workflow_run` event. When that run ends red, pr-merge's `post-merge-dispatch` job sends its run id
to the alert workflow through `workflow_dispatch` on its next scheduled run while the lane is
live (kill switch and report-only off), up to 30 minutes later. A dispatch `pr-require-checks.yml`'s main-dispatch concurrency group replaced before it
started (cancelled, no job) is no signal: it is never sent, and neither the alert nor the
post-merge check reads it as red. The alert accepts the id only from
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
   untested merges, and the fix issues fix `main` forward.
3. **Who reverts.** The bot may revert the culprit only when every guard holds; otherwise no
   revert is planned and the post-merge fix issues fix `main` forward through the issue lane
   (owner, 2026-11-02, "(c) All to lanes", on #11022). The guards: the lanes App
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
| `dry-run` | `true` | Report only: the step summary and one comment per confirmed red on the log issue (first body line `<!-- red-main-revert-log -->`), each starting `<!-- red-main-report run=<id> attempt=<n> culprit=<sha or none> decision=<auto-revert, fix-forward or none> -->` (older reports name `fix-forward` as `human`). A run that posts no report, because its red is unconfirmed or the log already reports it, adds a note naming any unreported red full runs, starting `<!-- red-main-unreported-note run=<id> attempt=<n> -->`; a note counts as neither a report nor a cap decision, and none creates the log issue. Nothing is pushed, opened or merged. This version has no revert path, so `false` reports too. |
| `daily-cap` | 3 | Auto-reverts decided in any 24 hours; 0 to 10, and 0 fixes every culprit forward. |
| `max-culprit-age-hours` | 24 | Hours since the culprit merged past which it is fixed forward, not reverted; 1 to 168. |
| `confirm-wait-minutes` | 55 | Minutes the job waits for the re-run to finish; 0 to 60. |
| `remedy` | `rollback` | `rollback` applies rules 3 and 4. `fail-forward` plans no revert: the report's decision is `fix-forward`, it names the remedy as the reason, and the fix issues repair `main`. |

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

## Attended work

Work that needs the owner present gets the `attended` label (owner decision 2026-10-28): a manual
step on external state an agent cannot safely run or test, of a class `attended.classes` lists. It is
separate from `host-run`, an unattended agent run on a host, and from the human-gated role label
(`needs-human`), an owner decision.

- **Refinement.** An exact refinement
  ([`refine.mjs`](../../../.github/scripts/intake-triage/refine.mjs)) ends its criteria with one
  plain line, never a task-list line: `External state: none`, `External state: iac (<owner/repo>)`
  or `External state: manual (<class>: <what>)`. The model reads the classes from its context,
  which `--select` fills from `attended.classes`, and `--apply` refuses a `manual` class not
  listed there. No keyword in the issue text sets the line.
- **Admission.** `attended` is a `refuse-labels` entry, parked at `status: confirmed`, never
  `needs-owner-decision`. An issue whose counted refinement records `manual (...)` is refused
  the same way, and admission adds `attended` and says why. `iac (<repo>)` routes nothing: that
  repository's preview and deploy flow is the gate.
- **Holds downstream.** work-unblock counts `attended` among its holds, so no sweep adds
  `agent-ready` to an issue carrying it, or to an admission-deferred one whose newest `attended`
  event is a removal by anyone but a listed human. Its re-admission paths park an attended refusal
  at `status: confirmed` with `attended`, as admission does. resolve-issue and apply-issue-patch
  list `attended` in `labels-absent`, so a run neither starts nor commits on it.
- **Removal.** Only a listed human lifts it. While the newest `attended` event is a removal by
  anyone else, the lanes App included, admission refuses as if the label were on. Once a listed
  human removed it after the refinement, the refinement's `manual (...)` line no longer refuses. To
  resume a parked issue once the step is done, a listed human removes `attended` and posts a
  `**Decision recorded.**` comment, which sends it back through intake (`intake-reenter`).
- **Mid-run.** A resolve-issue run that reaches such a step stops with the `manual-external` code,
  whose `attended` route adds the label and removes `agent-ready`
  ([`stop-routes.json`](../../../.github/scripts/work-resolve-issue/stop-routes.json)).

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

While the issue is open, its next lane run deletes a stopped run's lane branch that has no pull
request in any state (owner decision on #7948,
[`pr-run-activity.md`](pr-run-activity.md#issue-mode)); this daily rule is unchanged.

Two jobs run it. The plan job, whose token writes nothing (`contents`, `issues` and
`pull-requests` read), sorts the branches, prints how many it will delete, and hands at most
`max-deletes-per-run` candidates, in listing order, to the delete job as the run's
`branch-cleanup-candidates-<run>-<attempt>` artifact. It leaves the delete job one call plus five
per planned delete from its call budget before evaluating, and stops evaluating once it has found
`max-deletes-per-run` deletable branches or spent the rest of the budget. Each run starts at a
different point in the listing, moved by the run number and wrapping around, so branches kept
early in the listing do not hide the later ones from every run.

The delete job alone holds `contents: write` (with `pull-requests` read) and reads no issue or pull
request text: it refuses a candidate list for another repository, over the cap, or with an entry
outside the rule's shape. Before each delete it re-reads the tip and the open pull requests from
and into the branch, skips it when the tip moved or one opened, and appends `{repo, branch, sha,
rule, issue, pr, deletedAt}` to the step summary and the run's
`branch-cleanup-ledger-<run>-<attempt>` artifact. The delete is one GraphQL `updateRefs` per
branch whose `beforeOid` is the listed tip and whose `afterOid` is all zeros, so GitHub checks the
tip and deletes in one step; a push that lands after the re-read makes GitHub refuse the delete,
the branch is reported as skipped, and a second ledger line `{repo, branch, sha, notDeletedAt,
reason}` records that it still stands. The ledger SHA of a branch with no such line restores the
deleted tip:
`git push origin <sha>:refs/heads/<branch>`. A scheduled run deletes; a manual run is a dry-run
unless `dry-run` is set to false, and a dry-run starts no delete job. The kill switch, checked by
each job, stops it.

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
- Holds converge on one label. On 2026-11-01 `ci-status` enforced holds in seven places
  ([Review-lane holds](#review-lane-holds)), and in a sample that day holds, not code, made 17 of 24
  red pull request runs and 10 of 12 red merge groups red
  ([#12284 audit](https://github.com/melodic-software/claude-code-plugins/issues/12284#issuecomment-6582114885)).
  The direction: a hold our own actors place is `do-not-merge`, read once per run; only the
  review lanes' critical-security and cost holds and the trust-path holds stay person-only. The
  slices are tracked as #12445 (pr-merge wakes per pull request), #12446 (fold own-actor holds),
  #12447 (review requirement off ci-status's first pass), #12448 (per-completion run fan-out),
  #12449 (queue-time hold read once), #12456 (parent close-out) and #12438 (duplicate ruleset
  `pull_request` rule).

## Versioning

The schema's `version` is the contract major. [`CHANGELOG.md`](CHANGELOG.md) records each change.
A pull request that changes this directory does not edit `CHANGELOG.md`: it adds a changelog
fragment, `scripts/new-changelog-fragment.sh pr-pipeline <major|minor|patch|none>`, and the release
pull request writes the fragments into one `CHANGELOG.md` entry
([ADR 0048](../../adr/0048-release-plugins-from-changelog-fragments-through-a-bot-maintained-release-pr.md)).
A `major` fragment's pull request also raises the schema's `version`.
