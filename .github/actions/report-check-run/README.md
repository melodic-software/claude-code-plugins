# report-check-run

Write the one `<lane> / <activity>` check run a pipeline activity ends in, so a skip is never
silent ([pr-pipeline](../../../docs/conventions/pr-pipeline/README.md), Outputs and skips). The
conclusion is `success`, `failure`, or `neutral` with one skip reason.

## Inputs

| Input | Default | Meaning |
|---|---|---|
| `lane` | required | The lane, from the report job's own `workflow_call` input |
| `activity` | required | The activity, from the report job's own `workflow_call` input |
| `run-result` | required | `needs.run.result` |
| `act-outcome` | `''` | The run job's `act-outcome` output (`steps.act.outcome`) |
| `gate-reason` | `''` | The run job's gate stop reason output; empty when every gate proceeded |
| `head-sha` | `''` | The run job's `head-sha` output; the check is posted on it |
| `can-commit` | `''` | The run job's `can-commit` output; only `false` skips the signed-commit requirement |
| `all-verified` | `''` | The `check-signed-commits` `all-verified` output |
| `verdict-path` | `''` | The downloaded `verdict.json`; a missing file is a failure |
| `base-path` | `.base` | Base-SHA checkout; the skip-reason enum is read from its pr-pipeline schema |
| `head-sha-fallback` | `${{ github.sha }}` | Head SHA when `head-sha` is empty |
| `github-token` | required | The report job's `GITHUB_TOKEN` |

## Trust rule

The report job trusts only its own inputs and the run job's runner-computed outputs: lane and
activity from its `workflow_call` inputs, `needs.run.result`, and the run job's `act-outcome`,
`can-commit`, gate reason and `head-sha` outputs. The gate reason and head SHA come from the gate
steps, which run before any head-influenced step. The verdict file is written later in that job, so
it is untrusted: it is checked against its contract, and its `lane`, `activity`, gate stop reason
and `head-sha` are cross-checks only. Any disagreement with the inputs is a failure. The verdict's
`outcome` and `run-url` are never used, and no verdict text reaches the check.

## Rules

- The name is `<lane> / <activity>` from the inputs. A lane or activity that is `ci-status`, or is
  not a convention name, exits 1 with no API call: `ci-status` is the single required check.
- `head_sha` is the `head-sha` input, or `head-sha-fallback` when it is empty.
- First match wins:
  1. `run-result` `cancelled`: neutral `superseded-sha`.
  2. No verdict, a malformed verdict, or one whose lane, activity, gate stop reason or `head-sha`
     differs from the inputs: failure.
  3. `config: invalid`: failure.
  4. `gate-reason` `no-pr` with an empty `head-sha`: no check, exit 0.
  5. Any other `gate-reason`: neutral with the reason mapped through
     [`gate-skip-reasons.json`](gate-skip-reasons.json); an unmapped reason fails.
  6. An unverified or missing signed-commit result when `can-commit` is not `false`,
     `act-outcome` `failure`, or `dirty-tree: true`: failure. No skip reason overrides these.
  7. A verdict `skip-reason`: neutral with that reason when `run-result` is `success` and
     `act-outcome` is `success` (a script that exited 0 with a reason) or `skipped` (the act step
     never ran, so no head code wrote the verdict); failure otherwise.
  8. `act-outcome` other than `success`: failure, since nothing explains the skip.
  9. `run-result` other than `success`: failure.
  10. Otherwise success.
- Every neutral reason must be in `$defs/skip-reason` of `<base-path>/docs/conventions/pr-pipeline/pr-pipeline.schema.json`.
  A reason outside it, or an unreadable schema, turns the neutral into a failure.
- `details_url` is this workflow run's page, built from the runner's own environment.
- Exit 0 after posting or after the `no-pr` case; exit 1 on a refusal, a malformed repository,
  head SHA or fallback SHA, or a failed POST.

## Job contract

The job that uses this action:

- Is a scripted job with `permissions: checks: write` (plus `contents: read` for its base
  checkout) and no model step. The model job never holds `checks: write`.
- Runs after the run job with `if: always()`, checks out exactly the run job's `base-sha` output
  as `base-path`, and runs this action from that checkout.
- Sets `gate-reason` and `head-sha` from `needs.run.outputs`, which the run job maps from its gate
  steps, never from the verdict.
- Runs `check-signed-commits` itself unless `can-commit` is `false`, and lets this step run when
  that check fails, so a missing result is reported as a failure rather than nothing.
- Excludes fork PRs in its `if:`, whose read-only `GITHUB_TOKEN` cannot write checks, and the
  lanes App's own `synchronize` runs, which skip both jobs. These, and the `no-pr` case above, are
  the only runs that post no check.
