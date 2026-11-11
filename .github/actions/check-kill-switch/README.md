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
| `token` | `${{ github.token }}` | The token whose GET /rate_limit answer is the budget reading |

Set `budget: "true"` only on a gate that starts new work: the read runner's `broker-check` on the
first call of a caller that passes `start-gate: true` (the issue lane only), and a workflow's
first gate on a schedule or event that begins a run's work (intake triage and its refine select,
the audit, cleanup, recurring-issue, skill-edit, signals, reconcile, tidy, mutation and changelog
ticks, and the work-unblock sweep). A gate that finishes or judges existing work keeps the
default, so a low budget never throws that work away: reviews, merges, verdicts and verify notes,
writes after a model turn, model legs that take over a handed-off turn or run as the fallback,
and the pr-unblock legs (its dispatcher and pr-refine), which fix existing pull requests. Evals,
which a person or a pull request starts, keep it too. A budget stop ends the run neutral: a
notice, no failed step. A job that sets `budget: "true"` checks out fully or lists
`.github/actions/log-api-budget/` in its sparse checkout, where the share is read.
`check-kill-switch.test.mjs` classifies every gate in `.github/workflows` and fails on one it
does not know.

## Outputs

| Output | Values |
|---|---|
| `proceed` | `true` when both switches proceed and the budget does not stop the lane; otherwise `false` |
| `reason` | `ok` or `kill-switch`, for every stop |
| `cause` | `ok`, `switch` (a switch stops) or `budget` |
| `reset` | on a budget stop, the epoch second the reading's window resets; otherwise empty |

The step always exits 0. A stopped lane is an expected outcome, not a failure. A step that
reports the stop prints `cause` beside `reason`, so a budget stop is not read as a switch.

## Job contract

A lane job that uses this gate:

- Sets `permissions: contents: read, pull-requests: read`, both read-only. claude-code-action
  passes the job's `GITHUB_TOKEN` into the model's environment, so
  every write goes through the lane's App token.
- Runs this gate and [`check-trusted-trigger`](../check-trusted-trigger/README.md) with no
  `continue-on-error`.
- Gives the model step, and the App token step before it, this condition:

  ```yaml
  if: steps.kill.outputs.proceed == 'true' && steps.gate.outputs.proceed == 'true'
  ```

  A gate step that errors or writes no output leaves `proceed` empty, which also stops the lane.
- Mints the App token only after both gates, so a stopped lane never holds one.

## Tests

`npm test` in this directory runs `node --test`; `scripts/run-outside-node-suites.sh` runs it in CI.
