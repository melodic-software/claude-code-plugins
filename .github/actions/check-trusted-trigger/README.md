# check-trusted-trigger

Gate a CI lane on what triggered it, before its model step. The lane proceeds only for a PR from
this repository whose event actor and PR author are both on the trusted-actor list
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
| `github-token` | `${{ github.token }}` | Reads the PR on `workflow_dispatch` and `workflow_run` |
| `denied-actor-ids` | empty | Comma- or space-separated user ids that stop the lane with `bot-actor` |
| `triggering-actor` | `${{ github.triggering_actor }}` | The login that started this run attempt; empty stops with `untrusted-rerunner` |
| `dispatcher-run-id` | empty | The dispatcher run that sent a `github-actions[bot]` `workflow_dispatch`; empty keeps today's rules |
| `dispatcher-workflow` | empty | The workflow path that run must have; empty stops every dispatcher-sent run |
| `dispatched-workflow` | empty | The workflow path this dispatched run must have; empty stops every dispatcher-sent run |
| `require-pr` | `true` | `false` checks only the actors and reads no PR |
| `require-kind` | empty | `human` narrows the actor-only checks to actors listed as `kind: human` |

## Rules

- **List.** The file must hold `version: 1` and an `actors` array whose entries have exactly an
  integer `id` of at least 1, a string `login` and a `kind` of `human` or `bot`. Matching is on
  `id`, because a login can be renamed and later registered by someone else; the re-runner below
  is the one exception.
- **`pull_request`.** Same repository when `pull_request.head.repo.full_name` equals the
  repository; a null head repo is a fork. Actor is `sender`.
- **`workflow_dispatch`.** Fetches the PR named by `pr-number`; a null head repo is a fork.
  Actor is `sender`.
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
  - its `event` is `push`, or `workflow_dispatch` with an `actor` listed as `kind: human`;
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

  The record can land after this run's gate starts, so the gate waits for it. Each read takes the
  dispatcher run's `status` first, then its artifacts, so an upload between the two reads is not
  refused. While the dispatcher run is not `completed`, an absent record is read again every 5 s,
  at most 24 times (2 min). At the first `completed` with the record absent, the gate waits 5 s
  more, reads the artifacts once more, and then refuses; that extra wait counts toward the 24, so
  a first `completed` seen after the 24th wait refuses at once. Each wait logs
  `dispatcher record: absent, re-read N` with the two run ids.

  A failed read, a missing or unparseable field, or any failed condition stops with
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
     repository is public, so making it private refuses every dispatched run until the calling
     job grants that permission.
- **Actor-only mode (`require-pr: false`).** No PR is read and the PR outputs stay empty. Only
  `push` and `workflow_dispatch` are handled; any other event stops with `no-pr`. A
  `workflow_dispatch` checks `sender` (denied stops with `bot-actor`, unlisted with
  `untrusted-actor`); both events check the re-runner below. With `require-kind: human`, the
  sender and the re-runner must be listed as `kind: human` (the re-runner's login is mapped to its
  listed id). Any `require-pr` value other than `true` or `false`, or `require-kind` value other
  than empty or `human`, stops with `no-pr`.
- **`workflow_run`.** Same repository when `workflow_run.head_repository.full_name` equals the
  repository. The PR is looked up from the run's head SHA, because `pull_requests` is empty for
  more than forks: exactly one open same-repository PR whose head is still that SHA, or `no-pr`.
  Actors are `sender`, `workflow_run.actor` and `workflow_run.triggering_actor`: all three must
  be listed, because ADR 0051 requires the actor that started the failed run to be trusted.
- **Author.** The PR's `user.id` must be listed.
- **Re-runner.** A re-run keeps the original event and its actors, so `triggering-actor` is
  checked as well: it must be a listed `login`, compared without case, whose listed id is not
  denied. The context gives the login only, so this one check matches on login, not id. An empty,
  unlisted or denied re-runner stops with `untrusted-rerunner`, which `report-check-run` maps to
  no skip reason, so the check posts failure: a re-run cannot turn an earlier red check on the same
  SHA neutral.
- **Denied ids.** When `sender` or a `workflow_run` actor has an id in `denied-actor-ids`, the
  lane stops with `bot-actor`, even though that actor is listed. `pr-run-activity-write.yml`
  denies the lanes App bot, so the bot's own pushes and dispatches never chain a write activity.
  `pr-run-activity-read.yml` denies nothing, so a `workflow_run` read lane still runs after a bot
  push; a `pull_request` event sent by the bot is skipped earlier, by the runner's job `if:`. A
  value that is not a list of positive integers stops with `list-unreadable`.
- **Head ref.** The PR's head branch must match `^[A-Za-z0-9._/-]+$`; any other branch name, such
  as one carrying `$(`, stops with `no-pr`.
- **`no-pr` for everything unhandled.** Any other event (including `pull_request_target`), a
  missing or malformed `pr-number`, an empty repository, an unreadable event payload, a PR fetch
  that fails, and a `workflow_run` with zero or more than one matching open PR all stop with
  `no-pr`; the reason set has no separate error value.

Pass the job token (the default, `${{ github.token }}`) as `github-token`. The gate runs before
any App token exists, so the job token is the only one available, and it needs
`pull-requests: read` to fetch the PR on `workflow_dispatch` and `workflow_run`. That grant is
read-only, so no write token reaches the model. A token that cannot read the PR stops the lane
with `no-pr`. A dispatcher-sent run also reads two run records, a comparison and the dispatcher
run's artifact list; on this public repository the job token reads them without `actions: read`,
and a token that cannot stops the lane with `untrusted-actor`.

## Outputs

| Output | Values |
|---|---|
| `proceed` | `true` or `false` |
| `reason` | `ok`, `fork`, `no-pr`, `bot-actor`, `untrusted-actor`, `untrusted-rerunner`, `untrusted-author`, `list-unreadable` |
| `pr-number`, `head-ref`, `head-sha`, `base-sha` | The resolved PR; empty unless `proceed` is `true` |

Reasons are checked in the order list and denied ids, event and PR, fork, denied actor, actor,
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
