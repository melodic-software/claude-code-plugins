# check-read-floor

Gate a maintenance lane on the `GITHUB_TOKEN` pool, so a timer lane adds no load once the pool is
low. The gate reads the pool once, from the `x-ratelimit-*` headers of a counted
`GET /repos/<repo>`. `GET /rate_limit` reports a different bucket from the one a job spends
([log-api-budget](../log-api-budget/action.yml)). The lane runs only when the pool holds at least
`limits.api` github-token `read-floor` of its planned budget. The planned budget is the header's
limit, at most `limit-cap`. Both come from the base checkout's `docs/conventions/pr-pipeline.yaml`
over [`rate-limits.json`](../log-api-budget/rate-limits.json), the margin the rate guard warns at.

## Outputs

| Output | Values |
|---|---|
| `skip` | `false` when the pool is at or above the floor; `true` under it, or when the pool cannot be read |
| `reason` | `ok`, `below-floor` or `unreadable` |

The step always exits 0 and writes an `api-read-floor` notice. Gate each work step on
`steps.<id>.outputs.skip == 'false'`, never `!= 'true'`, so a gate that wrote nothing also stops
the work.

## Tests

`npm test` in this directory runs `node --test`; `scripts/run-outside-node-suites.sh` runs it in CI.
