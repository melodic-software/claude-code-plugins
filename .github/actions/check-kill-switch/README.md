# check-kill-switch

Gate a CI lane on the org and repository kill switches before its model step. The lane proceeds
only when both read exactly `false`; a switch that is unset, empty or holds any other value stops
it
([ADR 0049](../../../docs/adr/0049-run-ci-lanes-on-github-hosted-runners-under-trigger-and-token-hardening.md)
condition 4).

The repository switch has its own name because a repository variable named
`CLAUDE_LANES_DISABLED` replaces the org value in `vars`, so it could re-enable lanes under an
org-wide stop. This gate cannot see such a shadow. The token broker denies a write lane's mint
while one exists; the read lane makes no broker call, so a shadow still lets it run.

## Inputs

| Input | Default | Meaning |
|---|---|---|
| `value` | empty | The org switch, normally `${{ vars.CLAUDE_LANES_DISABLED }}` |
| `repo-value` | empty | The repository switch, normally `${{ vars.CLAUDE_LANES_REPO_DISABLED }}` |

## Outputs

| Output | Values |
|---|---|
| `proceed` | `true` only when `value` and `repo-value` are both exactly `false`; otherwise `false` |
| `reason` | `ok` or `kill-switch` |

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
