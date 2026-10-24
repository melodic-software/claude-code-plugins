# check-trusted-trigger

Gate a CI lane on what triggered it, before its model step. The lane proceeds only for a PR from
this repository whose event actor, PR author and re-runner are all on the trusted-actor list
([ADR 0049](../../../docs/adr/0049-run-ci-lanes-on-github-hosted-runners-under-trigger-and-token-hardening.md)
conditions 1 and 2,
[ADR 0051](../../../docs/adr/0051-start-pr-fix-ci-from-workflow-run-for-same-repository-trusted-prs.md)
condition 1 and the actor and author parts of condition 2).

## Inputs

| Input | Default | Meaning |
|---|---|---|
| `event-name` | `${{ github.event_name }}` | The triggering event |
| `event-path` | `${{ github.event_path }}` | The event payload file |
| `trusted-actors-path` | `.base/.github/standards/trusted-actors/trusted-actors.json` | The list, from the base-SHA checkout |
| `pr-number` | empty | The PR on `workflow_dispatch`; ignored otherwise |
| `github-token` | `${{ github.token }}` | Reads this run's own record on every path, the PR on `workflow_dispatch` and `workflow_run`, and its branch ref on `workflow_dispatch` |
| `denied-actor-ids` | empty | Comma- or space-separated user ids that stop the lane with `bot-actor` |
| `triggering-actor` | `${{ github.triggering_actor }}` | The login that started this run attempt; only routes `github-actions[bot]` to the reconciler check |
| `dispatcher-run-id` | empty | The dispatcher run that sent a `github-actions[bot]` `workflow_dispatch`; empty keeps today's rules |
| `dispatcher-workflow` | empty | The workflow path that run must have; empty stops every dispatcher-sent run |
| `run-dispatcher-workflow` | empty | The workflow path a dispatcher run started by `workflow_run` must have; empty stops every such run |
| `run-dispatcher-upstreams` | empty | Space-separated workflow paths that dispatcher's upstream run may have; empty stops every such run |
| `expected-upstream-head` | empty | For a job after pr-unblock's model job, the head that job gated; set on any path but a `workflow_run` dispatcher, it stops the run |
| `lanes-app-id` | empty | The lanes App bot's user id: an upstream it started vouches, and only its commits may follow `expected-upstream-head` |
| `dispatched-workflow` | empty | The workflow path this dispatched run must have; empty stops every dispatcher-sent run |
| `require-pr` | `true` | `false` checks only the actors and reads no PR |
| `require-kind` | empty | `human` narrows the actor-only checks to actors listed as `kind: human` |
| `app-label` | empty | With `require-kind: human`, the one label the lanes App may apply to an issue to start the lane |
| `reconciler-workflow` | empty | The lost-run reconciler's workflow path: a `github-actions[bot]` re-run proceeds only as its recorded re-run; empty stops every such re-run |

## Rules

- **List.** The file must hold `version: 1` and an `actors` array whose entries have exactly an
  integer `id` of at least 1, a string `login` and a `kind` of `human` or `bot`. Matching is on
  `id`, because a login can be renamed and later registered by someone else.
- **`pull_request`.** Same repository when `pull_request.head.repo.full_name` equals the
  repository; a null head repo is a fork. Actor is `sender`.
- **`workflow_dispatch`.** Fetches the PR named by `pr-number`; a null head repo is a fork.
  Actor is `sender`. `GET /pulls` can lag a push by minutes, so a same-repository PR is re-read
  after 5, 10, 20 and 25 s until its `head.sha` equals its branch ref; if they never agree, or
  the branch ref is missing, the lane stops with `head-lag` rather than gate a stale head, which
  `report-check-run` posts as a `superseded-sha` skip, since the push that moved the branch is
  gated by its own run; a failed read stops with `no-pr`. A fork's ref is not read.
- **Dispatcher-sent `workflow_dispatch`.** A dispatch made with `GITHUB_TOKEN` names
  `github-actions[bot]` (id 41898282) as sender, actor and triggering actor, and nothing on the
  run names who started the dispatcher. When `sender.id` is 41898282 and `dispatcher-run-id` is
  set, the sender check is replaced by a check of that run, read through
  `GET /actions/runs/{dispatcher-run-id}`. It proceeds only when every one of these holds:
  - this run's payload `ref` is `refs/heads/{repository.default_branch}`, and this run, read
    through `GET /actions/runs/{github.run_id}`, has `path` equal to `dispatched-workflow` and
    `event` `workflow_dispatch`;
  - its `repository` is this repository and its `path` equals `dispatcher-workflow`;
  - its `head_branch` is the default branch, and no tag has that name
    (`GET /git/ref/tags/{default branch}` answers 404), so the name cannot stand for a tag;
  - its `head_sha` is an ancestor of the branch tip: the tip SHA is resolved once through
    `GET /git/ref/heads/{default branch}`, and `GET /compare/{head_sha}...{tip SHA}` reports
    `ahead` or `identical`;
  - its `event` is `push`, `schedule`, or `workflow_dispatch` with an `actor` listed as
    `kind: human`;
  - when its `run_attempt` is above 1, its `triggering_actor` is listed as `kind: human`;
  - this run's own `created_at` falls between the dispatcher run's `run_started_at` and the
    earlier of its `updated_at` and ten minutes after `run_started_at`, inclusive. The window is
    checked, not whether that run is still going, so a dispatched run that waited in a queue still
    passes; the ten-minute cap keeps a long dispatcher run from holding the window open;
  - the dispatcher run recorded this run: after the checks above,
    `GET /actions/runs/{dispatcher-run-id}/artifacts?per_page=100` lists an artifact with
    `expired` `false`, `workflow_run.id` equal to `dispatcher-run-id`, and a name matching
    `^pr-unblock-dispatched(-[1-9][0-9]{0,14})+$` whose ids include this run's id exactly.
    `pr-unblock-dispatch.yml` uploads that artifact after its dispatch loop, named with every run
    id the dispatch API returned to it, and keeps it for 1 day.

  A dispatcher run whose `event` is `workflow_run` is checked the same way, except:
  - its `path` must equal `run-dispatcher-workflow` (not `dispatcher-workflow`), and its actor is
    not checked. Such a run reports the default branch and its tip at the time as `head_branch`
    and `head_sha` (pr-merge.yml run 38779143370, started by review run 38779135732 on a PR
    branch), so the branch, tag and ancestry checks apply unchanged;
  - its record is named `pr-feedback-dispatched-<upstream run id>-<this run's id>`, exactly two
    ids;
  - the upstream run, read through `GET /actions/runs/{upstream run id}`, has that `id`, a `path`
    listed in `run-dispatcher-upstreams`, `event` `pull_request`, `repository` and
    `head_repository` both this repository, an `actor` and `triggering_actor` that are the lanes
    App (`lanes-app-id`) or a listed human, and `head_sha` equal to the PR's current head. With
    `expected-upstream-head`, `head_sha` must equal it instead, and every commit of
    `GET /compare/<it>...<PR head>` (status `ahead`, untruncated) must have the lanes App as
    `author`, `web-flow` as `committer`, a `valid` verified signature, and a committer date no
    earlier than this run's creation: a commit GitHub signed for an App token during this run. A
    human, foreign, unsigned or older commit stops the run. It does not prove which lane made it.

  The record can land after this run's gate starts, so the gate waits for it. Each read takes the
  dispatcher run's `status` first, then its artifacts, so an upload between the two reads is not
  refused. While the dispatcher run is not `completed`, an absent record is read again every 5 s,
  at most 24 times (2 min). At the first `completed` with the record absent, the gate waits 5 s
  more, reads the artifacts once more, and then refuses; that extra wait counts toward the 24, so
  a first `completed` seen after the 24th wait refuses at once. Each wait logs
  `dispatcher record: absent, re-read N` with the two run ids.

  A failed read, a missing or unparsable field, or any failed condition stops with
  `untrusted-actor`. The re-runner of a dispatched run is read by id from this run's
  `triggering_actor`: `github-actions[bot]` on attempt 1, otherwise a listed id that is not
  denied, or the lane stops with `untrusted-rerunner`. The PR author check still applies.

  A `GITHUB_TOKEN` with `actions: write`, which any workflow on any branch can request, can
  dispatch `dispatched-workflow` naming a real dispatcher run inside its window, but the
  dispatcher run never recorded that run's id, so the gate refuses it. Residuals:
  1. Whether one run can write into another run's artifacts is unverified (judgment). A cross-run
     upload would need the dispatcher run's backend run and job ids, which no REST read exposes.
  2. A re-run of a dispatched run, or a run queued for more than a day, is refused once the record
     expires after 1 day. The fix is to re-dispatch.
  3. The gate token has no `actions: read`. Its run and artifact reads work only because this
     repository is public, so making it private refuses every lane run (the re-runner read below)
     until the calling job grants that permission.
- **Actor-only mode (`require-pr: false`).** No PR is read and the PR outputs stay empty. Only
  `push`, `workflow_dispatch` and `issues` are handled; any other event stops with `no-pr`. A
  `workflow_dispatch` or `issues` event checks `sender`, on `issues` the account that applied the
  label (denied stops with `bot-actor`, unlisted with `untrusted-actor`); every event checks the
  re-runner below. With `require-kind: human`, the
  sender and the re-runner must be listed as `kind: human`. Any `require-pr` value other than `true` or `false`, or `require-kind` value other
  than empty or `human`, stops with `no-pr`.
- **App label (`app-label`).** On an `issues` event with `require-kind: human` whose sender is
  `lanes-app-id`, the label event must be `labeled` with exactly that label, or it stops with
  `bot-actor`; the label alone admits the issue, and no comment or edit history is read. An
  event with no issue number stops with `untrusted-actor`. The re-runner, read as below, must be
  the App (its id listed) or a listed human, not denied, or it stops with `untrusted-rerunner`. Empty keeps the App denied on
  every event.
- **`workflow_run`.** Same repository when `workflow_run.head_repository.full_name` equals the
  repository. The PR is looked up from the run's head SHA, because `pull_requests` is empty for
  more than forks: exactly one open same-repository PR whose head is still that SHA, or `no-pr`.
  Actors are `sender`, `workflow_run.actor` and `workflow_run.triggering_actor`: all three must
  be listed, because ADR 0051 requires the actor that started the failed run to be trusted. The
  one exception is the reconciler's re-run of the upstream run, below.
- **Author.** The PR's `user.id` must be listed.
- **Re-runner.** A re-run keeps the original event and its actors, so the account that started
  this attempt is checked as well, by id: this run's own record, read through
  `GET /actions/runs/{github.run_id}`, must have that `id`, a `run_attempt` equal to
  `GITHUB_RUN_ATTEMPT`, and a `triggering_actor.id` that is listed and not denied. A malformed run
  id or attempt, a failed or malformed read, or an unlisted or denied re-runner stops with
  `untrusted-rerunner`, which `report-check-run` maps to no skip reason, so the check posts
  failure: a re-run cannot turn an earlier red check on the same SHA neutral.
- **Reconciler re-run (`reconciler-workflow`).** On the `pull_request` and `workflow_run` paths,
  when `triggering-actor` is `github-actions[bot]` and `reconciler-workflow` is set, the re-runner
  check is replaced by a check of the lost-run reconciler's record; the event's actors and the PR
  author are still checked as above. It proceeds only when every one of these holds, and any
  failed read or condition stops with `untrusted-rerunner`:
  - `github-actions[bot]` (41898282) is not in `denied-actor-ids`, `GITHUB_RUN_ATTEMPT` is `2`,
    and the payload names the repository's default branch;
  - this run's attempt 2, read through `GET /actions/runs/{github.run_id}/attempts/2`, has that
    `id` and `run_attempt`, `triggering_actor.id` 41898282, this repository, a 40-hex `head_sha`
    and a `run_started_at`;
  - `GET /actions/artifacts?name=reconcile-rerun-<run id>-2-<head_sha>&per_page=100`, up to ten
    pages, lists an
    artifact with exactly that name, `expired` `false`, and a `created_at` no later than the
    attempt's `run_started_at`, whose `workflow_run.id` names a run that has that `id`, this
    repository, `path` equal to `reconciler-workflow`, `head_branch` the default branch, `event`
    `schedule` or `workflow_dispatch` by an `actor` listed as `kind: human`, any re-run of it by a
    `triggering_actor` listed as `kind: human`, and a `run_started_at` no later than the attempt's
    and at most ten minutes before it;
  - that run's `head_sha` passes the same tag and ancestry checks as a dispatcher run.

  Any run can upload an artifact with that name, so each listed artifact's run is read and
  judged, and one that passes is enough; one whose run cannot be read does not vouch. At most 20
  candidate runs are read per check; a 21st candidate stops it with `untrusted-rerunner`. The run id and the attempt bind the record to one run
  attempt, which starts once, so a record cannot vouch for another run or a later attempt. The
  reconciler uploads the record before it calls the re-run, so an absent record is read once more
  after 5 s and then refused.

  The same record vouches for the upstream run on the `workflow_run` path. When
  `reconciler-workflow` is set, `workflow_run.run_attempt` is `2` and
  `workflow_run.triggering_actor.id` is 41898282, that actor need not be listed; `sender` and
  `workflow_run.actor` still must be. Every check above then runs against the upstream run,
  `workflow_run.id` in place of `github.run_id`, and any failure stops with `untrusted-actor`.
  The reconciler records each re-run that makes attempt 2 of a CI run this lane runs after. A
  github-actions[bot] upstream at any other attempt, or with no record, stops with
  `untrusted-actor`. This run's own re-runner is then checked as above.

  `ci-status-rerun-workflow` adds a second recorder for the upstream run only:
  `pr-feedback-dispatch.yml`'s `rerun-ci-status` job, which uploads
  `rerun-ci-status-<run id>-<attempt>-<head_sha>` immediately before it re-runs a ci-status job,
  naming the attempt that re-run starts. A github-actions[bot] upstream at attempt 2 or later is
  checked as above against `GET /actions/runs/{id}/attempts/{attempt}` and that name (at attempt 2
  the reconciler's name is read first), except that the recording run's `event` must be
  `workflow_run` and its `actor` is not checked, since such a run runs the default branch's file,
  and the window runs from the record: the run started no later than the artifact's `created_at`,
  and the attempt started at most ten minutes after it. The job can poll for ten minutes before
  it uploads, so a window from the run's start would refuse it. This run's own github-actions[bot]
  re-runner is never vouched for by this record.

  Residuals: the record names an attempt, not who starts it. A github-actions[bot] re-run of the
  same run that another workflow of this repository starts between the upload and the job's own
  re-run, or within ten minutes of an upload whose re-run then failed, takes that attempt and is
  vouched for. It re-runs only that run at that head, and `sender`, `workflow_run.actor` and the
  PR author must still be listed.

  Residuals: whether one run can write another run's artifacts is unverified, as for the
  dispatcher record. A re-run that waits in a queue past the ten-minute window is refused, red;
  a person re-runs it. More than 1,000 forged artifacts of one name would push the real record
  past the pages read, which refuses the re-run: a denial, never a pass.
- **Denied ids.** When `sender` or a `workflow_run` actor has an id in `denied-actor-ids`, the
  lane stops with `bot-actor`, even though that actor is listed. `pr-run-activity-write.yml`
  denies the lanes App bot, so the bot's own pushes and dispatches never chain a write activity.
  `pr-run-activity-read.yml` denies nothing, so a `workflow_run` read lane still runs after a bot
  push; a `pull_request` event sent by the bot is skipped earlier, by the runner's job `if:`. A
  value that is not a list of positive integers stops with `list-unreadable`.
- **Head ref.** The PR's head branch must match `^[A-Za-z0-9._/-]+$`; any other branch name, such
  as one carrying `$(`, stops with `no-pr`.
- **Base.** The PR's `base.ref` must equal the payload's `repository.default_branch`, on
  `pull_request`, `workflow_dispatch` and `workflow_run` alike: lanes read the list and scripts
  from the default branch, so a PR stacked on any other branch stops with `untrusted-base`, as
  does a payload without the default branch. `report-check-run` maps it to no skip reason, so the
  check posts failure, not neutral.
- **`no-pr` for everything unhandled.** Any other event (including `pull_request_target`), a
  missing or malformed `pr-number`, an empty repository, an unreadable event payload, a PR fetch
  that fails, and a `workflow_run` with zero or more than one matching open PR all stop with
  `no-pr`; the reason set has no separate error value.

Pass the job token (the default, `${{ github.token }}`) as `github-token`. The gate runs before
any App token exists, so the job token is the only one available, and it needs
`pull-requests: read` to fetch the PR on `workflow_dispatch` and `workflow_run`. That grant is
read-only, so no write token reaches the model. A token that cannot read the PR stops the lane
with `no-pr`. Every path reads this run's own record for the re-runner; on this public repository
the job token reads it without `actions: read`, and a token that cannot stops the lane with
`untrusted-rerunner`. A dispatcher-sent run also reads two run records, a comparison and the dispatcher
run's artifact list; on this public repository the job token reads them without `actions: read`,
and a token that cannot stops the lane with `untrusted-actor`. A reconciler re-run reads its own
attempt, the artifact list by name, the recording run and a comparison the same way, and a token
that cannot stops it with `untrusted-rerunner`.

## Outputs

| Output | Values |
|---|---|
| `proceed` | `true` or `false` |
| `reason` | `ok`, `fork`, `no-pr`, `head-lag`, `untrusted-base`, `bot-actor`, `untrusted-actor`, `untrusted-rerunner`, `untrusted-author`, `list-unreadable` |
| `pr-number`, `head-ref`, `head-sha`, `base-sha` | The resolved PR; empty unless `proceed` is `true` |

Reasons are checked in the order list and denied ids, event and PR, head lag, fork, base, denied actor, actor,
re-runner, author. Every failure, including
an unreadable payload or a failed API call, ends in `proceed=false`, and the step always exits 0.
Set `CLAUDE_BRANCH` for the model step from `head-ref`, and record `head-sha` before the model runs
for [`check-signed-commits`](../check-signed-commits/README.md).

Pass every output, `head-ref` included, to later steps through `env:` and read it as a shell
variable. Never write `${{ steps.gate.outputs.head-ref }}` or any other output inside `run:`: the
runner pastes it into the script before the shell parses it.

## Job contract

A lane job that uses this gate:

- Sets `permissions: contents: read, pull-requests: read`, both read-only. claude-code-action
  passes the job's `GITHUB_TOKEN` into the model's environment, so
  every write goes through the lane's App token.
- Checks out the base SHA to `.base/` before the gates, and the PR head only after both pass, so
  a PR cannot change the list or scripts it is judged by.
- Runs this gate and [`check-kill-switch`](../check-kill-switch/README.md) with no
  `continue-on-error`.
- Gives the model step, and the App token step before it, this condition:

  ```yaml
  if: steps.kill.outputs.proceed == 'true' && steps.gate.outputs.proceed == 'true'
  ```

  A gate step that errors or writes no output leaves `proceed` empty, which also stops the lane.
- Mints the App token only after both gates, so a stopped lane never holds one.

## Tests

`npm test` in this directory runs `node --test` over recorded-shape event and API fixtures, with
no network; `scripts/run-outside-node-suites.sh` runs it in CI.
