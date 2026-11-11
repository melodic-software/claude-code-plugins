# check-kill-switch

Gate a CI lane on the org and repository kill switches, then on the GITHUB_TOKEN budget, before
its model step. Each switch proceeds only on exactly `false`, or on `true@<time>` once that time
has passed; a switch that is unset, empty or holds any other value stops the lane
([ADR 0049](../../../docs/adr/0049-run-ci-lanes-on-github-hosted-runners-under-trigger-and-token-hardening.md)
condition 4). Nothing writes the switches automatically: they are manual brakes.

| Switch value | Gate |
|---|---|
| `false` | proceeds |
| `true@2026-11-11T18:00:00Z` (UTC, seconds, `Z`) | stops until that time, then proceeds |
| unset, empty, `true`, a malformed time, anything else | stops |

The `true@<time>` form is this gate's alone. `merge-holds.mjs` `switchHold` and
`babysit_merge_policy.py` still hold on any value but `false`, and the token broker reads the
switches by its own rule, so a lapsed `true@<time>` can still hold those until someone sets
`false`.

With both switches proceeding, the gate makes one GET /rate_limit with `token` and reads the core
pool from the `x-ratelimit-limit`, `-remaining` and `-reset` headers, or from the body's
`resources.core` when a header is missing. It stops the lane while remaining is under
`limits.api.github-token.start-gate` of the limit (default 0.1, in
[`rate-limits.json`](../log-api-budget/rate-limits.json); `pr-pipeline.yaml` overrides it only where
the job's env sets `RESOLVED_CONFIG`, which no workflow does for this gate yet) and the reset is still ahead. A read that
fails, times out or carries no reading proceeds with a warning; the rate guard's `stop-floor` is
the backstop. GitHub counts GET /rate_limit against the secondary limit, not the primary one, so
the gate makes it once, with no retry, and not at all when a switch already stops. Each read
logs one `start-gate` notice with the body's core block and the response's rate-limit headers,
so the two can be compared.

The repository switch has its own name because a repository variable named
`CLAUDE_LANES_DISABLED` replaces the org value in `vars`, so it could re-enable lanes under an
org-wide stop. This gate cannot see such a shadow. The token broker denies a write lane's mint,
and a read lane's broker check, while one exists.

## Inputs

| Input | Default | Meaning |
|---|---|---|
| `value` | empty | The org switch, normally `${{ vars.CLAUDE_LANES_DISABLED }}` |
| `repo-value` | empty | The repository switch, normally `${{ vars.CLAUDE_LANES_REPO_DISABLED }}` |
| `token` | `${{ github.token }}` | The token whose GET /rate_limit answer is the budget reading |
| `budget` | `true` | `false` skips the budget read, so the gate checks the switches only |

A gate in a job that runs after a model turn and consumes its output sets `budget: "false"`, so a
low budget never throws that turn's work away; the rate guard's `stop-floor` stays its backstop.
Those gates are the write runner's (`pr-run-activity-write.yml` `run`), intake-triage's
`apply-verdict` and `apply-refinement`, maintenance-audit-lane-runs' `judge-handoffs`,
`judge-subscription-handoffs` and `file`, the `push-branch(es)` and `publish` jobs of
maintenance-measure-skill-edit, maintenance-tidy-code-upkeep and upstream-apply-changelog, and
pr-unblock's `adjudicate-feedback`. A model leg that takes over after an earlier leg handed off
starts a fresh turn, so its gate still reads the budget.

## Outputs

| Output | Values |
|---|---|
| `proceed` | `true` when both switches proceed and the budget does not stop the lane; otherwise `false` |
| `reason` | `ok` or `kill-switch`, for every stop |
| `cause` | `ok`, `switch` (a switch stops), `expiry` (a `true@<time>` still ahead) or `budget` |

The step always exits 0. A stopped lane is an expected outcome, not a failure.

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
