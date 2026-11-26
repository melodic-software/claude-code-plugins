# check-kill-switch

Gate a CI lane on the org and repository kill switches before its model step, and, on a gate that
starts new work, on the GITHUB_TOKEN budget too. The lane proceeds only when both switches read
exactly `false`; a switch that is unset, empty or holds any other value stops it
([ADR 0049](../../../docs/adr/0049-run-ci-lanes-on-github-hosted-runners-under-trigger-and-token-hardening.md)
condition 4). Nothing writes the switches automatically: they are manual brakes.

With `budget: "true"` and both switches proceeding, the gate makes one GET /rate_limit with
`token` and reads the core pool from the `x-ratelimit-limit`, `-remaining` and `-reset` headers,
or from the body's `resources.core` when a header is missing. It stops the lane while remaining
is under github-token's `start-gate` share of the limit and the reset is still ahead. The share
is read from [`rate-limits.json`](../log-api-budget/rate-limits.json) alone (0.1); no
`pr-pipeline.yaml` field overrides it. A share of 0 turns the read off. A refused read (403, 429,
a `retry-after` header, or `x-ratelimit-remaining: 0`) stops the lane with cause `budget`, since
more calls would be refused too; its reset is `x-ratelimit-reset`, else now plus `retry-after`,
else now plus 60 seconds. A read that fails otherwise (a transport error, a timeout, a 5xx or a
401) or carries no reading, or a share that cannot be read, proceeds with a warning; the rate
guard's `stop-floor` is the backstop. GitHub counts GET /rate_limit against the secondary limit,
not the primary one, so the gate makes it once, with no retry, and not at all when a switch
already stops. Each read logs one
`start-gate` notice with the body's core block and the response's rate-limit headers, so the two
can be compared.

With `project: "true"` as well (the issue lane's first call only), the same reading also stops the
lane, with cause `budget` and the window's reset, while the pacer's projection
([`projection.mjs`](projection.mjs), the arithmetic
[`pace.mjs`](../log-api-budget/pace.mjs) uses) of the window's burn rate to github-token's
`start-run-minutes` from now leaves under `start-project` of the header's limit: a run started now
would end in a window with less than that share left. When the reset comes first, only the part of
the run before the reset draws on this window, so the projection to the reset is held against
`start-project` scaled by the seconds to the reset over the horizon's seconds.
Both values are read from `rate-limits.json` alone (`start-project` 0.3, `start-run-minutes` 21,
the p90 of 25 successful issue runs' check-broker start to run end, rounded up). `start-project`
is a share of the header's limit, like `pace`. The `start-gate` share is checked first and
still stops on its own. A reading that cannot project, or a value that cannot be read, proceeds
with a warning. The notice names the projected share, the horizon and the threshold. work-unblock's
sweep re-fires a budget stop after the reset it names, as for a low budget.

With `defer: "true"`, on a gate whose work a later run recovers, the same one read defers the job
(proceed `false`, cause `defer`, the window's reset) while the projection of the window's burn rate
to the job's horizon leaves under github-token's `defer-project` share of the header's limit. When
the reset comes before the horizon, only the part of the job before the reset draws on this window,
so it defers while the projection to the reset leaves under `defer-project` x seconds to the reset
/ horizon seconds. The horizon, the job's measured run time (its p90 except
for review, below), is the gate's `defer-minutes` when set, else github-token's `defer-run-minutes-<defer-job>`, else
`defer-run-minutes`. `defer-run-minutes-pr-merge` is 6: the p90 of the 29 first-attempt pr-merge
arm runs listed on 2026-11-20 is 327 s. `defer-run-minutes-review` is 8, for both hosted review
callers' gates, under their p90 of 10.4 minutes (418 hosted review runs of 2 minutes or more, listed
on 2026-11-21): replayed over the 48 busiest windows of 2026-11-22 to 2026-11-24, 8 is the shortest
horizon that leaves every window not already at `stop-floor` at least one review's calls above it
(130 left at the tightest; 7 leaves 102). The github-token values are read from `resolved-config`'s `limits.api` (`pr-pipeline.yaml`) over `rate-limits.json`
(`defer-project` 0.3, `defer-run-minutes` 15: on the mean burn curve of the 16 windows that ran
out between 2026-11-18 and 2026-11-20, at a median of minute 50, those values start deferring at
about minute 23, and the mean curve of the 17 windows that did not run out never reaches them). `defer-project` 0
turns deferral off. The defer path reads no `start-gate` floor and never waits; a run attempt over
1 never defers, so the run that recovers deferred work always does it. A refused read defers, as it
stops a start gate. Each deferral logs a `defer` notice naming the cause, the projected share and
the reset, as an epoch second and in UTC.

A start nothing re-fires sets `wait-seconds` (intake's refine-select alone): a budget stop whose
reset is within it sleeps to a second past the reset and reads the budget once more, deciding
again on that reading. It logs `started after the reset` when the start then goes ahead. The value
follows rate-guard's `waitBudgetMs` rule, and the job's timeout must hold it.

The repository switch has its own name because a repository variable named
`CLAUDE_LANES_DISABLED` replaces the org value in `vars`, so it could re-enable lanes under an
org-wide stop. This gate cannot see such a shadow. The token broker denies a write lane's mint,
and a read lane's broker check, while one exists.

## Inputs

| Input | Default | Meaning |
|---|---|---|
| `value` | empty | The org switch, normally `${{ vars.CLAUDE_LANES_DISABLED }}` |
| `repo-value` | empty | The repository switch, normally `${{ vars.CLAUDE_LANES_REPO_DISABLED }}` |
| `budget` | `false` | `true` also reads the GITHUB_TOKEN budget |
| `project` | `false` | `true`, with `budget`, also stops on the window's projected spend at the run's expected end |
| `defer` | `false` | `true` defers a job a later run recovers while the window is projected to run short by its end |
| `defer-minutes` | empty | With `defer`, the job's horizon in whole minutes, over the config; empty reads the config |
| `defer-job` | empty | With `defer`, the job's horizon key suffix: `defer-run-minutes-<defer-job>`, else `defer-run-minutes` |
| `resolved-config` | empty | With `defer`, a JSON file whose `limits.api` overrides `rate-limits.json` |
| `wait-seconds` | empty | With `budget`, a budget stop whose reset is within this many seconds waits for it and reads once more |
| `token` | `${{ github.token }}` | The token whose GET /rate_limit answer is the budget reading |

Set `budget: "true"` only on a gate that starts new work: the read runner's `check-broker` on the
first call of a caller that passes `start-gate: true` (the issue lane only), and a workflow's
first gate on a schedule or event that begins a run's work (intake triage and its refine select,
the audit, cleanup, recurring-issue, skill-edit, signals, reconcile, tidy, mutation and changelog
ticks, and the work-unblock sweep). A gate that finishes or judges existing work keeps the
default, so a low budget never throws that work away: reviews, merges, verdicts and verify notes,
writes after a model turn, model legs that take over a handed-off turn or run as the fallback,
and the pr-unblock legs (its dispatcher and pr-refine), which fix existing pull requests. Evals,
which a person or a pull request starts, keep it too.

Set `defer: "true"` instead on a gate that finishes existing work only where a later run that never
defers recovers it: pr-merge's PR-scoped arm run (`inputs.pr`), whose work the 30-minute sweep does,
the two hosted review callers' gates, whose stop notice prints `cause=defer reset=<epoch>`, and
pr-verify's Check Intent, whose second gate runs after the resolver and the trigger gate (so a run
that would skip never defers), with the switches already read, and whose `Note the deferral` step
prints the same pair. The lost-run reconciler re-runs each such run once that reset is past
(reconcile.mjs `DEFER_NOTE`, in its own `DEFER_MAX` band). Check Intent has no
`defer-run-minutes-check-intent` key, so its horizon is `defer-run-minutes`.
There a low budget delays the work rather than throwing it away, which is the reason the paragraph
above keeps the budget off. CI Status and pr-dispatch-feedback never defer. A budget or defer stop
ends the run neutral: a notice, no failed step. A job that sets `budget: "true"` or `defer: "true"`
checks out fully or lists `.github/actions/log-api-budget/` in its sparse checkout, where the values
are read.
`check-kill-switch.test.mjs` classifies every gate in `.github/workflows` (start, switch, defer)
and fails on one it does not know.

## Outputs

| Output | Values |
|---|---|
| `proceed` | `true` when both switches proceed and the budget does not stop the lane; otherwise `false` |
| `reason` | `ok` or `kill-switch`, for every stop |
| `cause` | `ok`, `switch` (a switch stops), `budget` or `defer` |
| `reset` | on a budget or defer stop, the epoch second the reading's window resets; otherwise empty |

The step always exits 0. A stopped lane is an expected outcome, not a failure. A step that
reports the stop prints `cause` beside `reason`, so a budget stop is not read as a switch.

## Job contract

A lane job that uses this gate:

- Sets `permissions: contents: read, pull-requests: read`, both read-only. claude-code-action
  passes the job's `GITHUB_TOKEN` into the model's environment, so a job that runs a model holds
  no App token or other write credential
  ([ADR 0085](../../../docs/adr/0085-run-org-lanes-from-ci-workflows-under-one-lanes-app-with-central-grants.md);
  [`model-job-permissions.test.mjs`](../../scripts/lib/model-job-permissions.test.mjs) fails one
  that does). Every write runs in a separate job with no model, under the lane's App token.
- Runs this gate and [`check-trusted-trigger`](../check-trusted-trigger/README.md) with no
  `continue-on-error`.
- Gives the model step this condition:

  ```yaml
  if: steps.kill.outputs.proceed == 'true' && steps.gate.outputs.proceed == 'true'
  ```

  A gate step that errors or writes no output leaves `proceed` empty, which also stops the lane.
- Mints the App token only in the separate write job, which runs no model and starts only after both gates proceed, so a stopped lane never holds one.

## Tests

`npm test` in this directory runs `node --test`; `scripts/run-outside-node-suites.sh` runs it in CI.
