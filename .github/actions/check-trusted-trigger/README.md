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

## Rules

- **List.** The file must hold `version: 1` and an `actors` array whose entries have exactly an
  integer `id` of at least 1, a string `login` and a `kind` of `human` or `bot`. Matching is on
  `id`, because a login can be renamed and later registered by someone else; the re-runner below
  is the one exception.
- **`pull_request`.** Same repository when `pull_request.head.repo.full_name` equals the
  repository; a null head repo is a fork. Actor is `sender`.
- **`workflow_dispatch`.** Fetches the PR named by `pr-number`; a null head repo is a fork.
  Actor is `sender`.
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
with `no-pr`.

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
