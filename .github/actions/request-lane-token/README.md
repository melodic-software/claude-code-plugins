# request-lane-token

Get the lane App token for one write activity from the lanes token broker, in place of minting it
from the App private key. The job sends its GitHub OIDC token to the broker, which checks it and
returns one installation token for this repository, scoped to the effect the default-branch config
gives the activity and valid for at most one hour. No workflow holds the App key.
[ADR 0058](../../../docs/adr/0058-mint-lane-app-tokens-through-an-oidc-broker.md) records the
decision; the run job contract is in
[`pr-run-activity.md`](../../../docs/conventions/pr-pipeline/pr-run-activity.md), run job step 6.

`mode: check` is the read file's use: it asks the broker's check endpoint whether the read lane may
run, and mints nothing ([Check mode](#check-mode)).

## Inputs

| Input | Meaning |
|---|---|
| `mode` | `token` (default) or `check` |
| `broker-url` | The token endpoint, `${{ vars.LANES_BROKER_URL }}`. Empty or not `https://` fails red |
| `audience` | The OIDC audience, `${{ vars.LANES_BROKER_AUDIENCE }}`. Empty fails red |
| `lane`, `activity` | Sent to the broker; the lane must be the caller workflow's file stem |
| `pr-number` | `token` mode: the gated PR; sent as `pr_number` when set, which the broker needs off `pull_request` |
| `issue-number` | `token` mode: the issue an `issues` lane works; sent as `issue_number` when set, which the broker needs on an `issues` event. Never with `pr-number` or `dispatcher-run-id` |
| `dispatcher-run-id` | `token` mode: the `pr-unblock-dispatch.yml` run that dispatched this one; sent as `dispatcher_run_id` when set. The broker needs it to trust a run sent by `github-actions[bot]` |
| `effect`, `contents`, `pull-requests`, `issues` | `token` mode: this job's own `resolve-config` outputs, compared with the broker's answer |
| `superseded-ok` | `true` ends green, with a `lane-token-superseded` warning and no token, on a 403 whose reason is `workflow-modified` (a newer copy of the caller workflow on the default branch, whose run does the work). Default `false` |

## Outputs

| Output | Value |
|---|---|
| `token` | The lane token, masked. Set only when every check passed |
| `expires-at` | The expiry the broker returned |
| `mint-id` | `<check_run_id>-<run_attempt>`, the broker's audit key for this mint |
| `failure-reason` | The one-line reason the step failed with (`lane-token-denied: ...`); empty on a success |

## What it does

1. Fails red when either variable is empty, when the resolved grant is not `read` or `write` for
   each of `contents`, `pull-requests` and `issues`, or when the job lacks `id-token: write`.
2. Requests an OIDC token for `audience` and masks it.
3. Sends a `POST` to `broker-url` with `Authorization: Bearer <OIDC token>` and the body
   `{"lane", "activity", "pr_number"?, "issue_number"?, "dispatcher_run_id"?}`. It retries, up to
   three times and each with a fresh OIDC token, only two 503s that come before the broker reserves
   the job's mint, as GitHub's
   [rate-limit guidance](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api#exceeding-the-rate-limit)
   asks:
   - `github-rate-limited`: GitHub rate-limited the broker. The retry waits exactly the
     `Retry-After` header (a minute when it is absent) plus up to 20 seconds of jitter. When that
     wait would end more than 8 minutes after the first request, it fails red at once, naming the
     limit kind (`primary` or `secondary`), its resource and the time it resets. On an issue lane,
     work-unblock's hourly sweep re-fires such a run once the reset has passed.
   - `github-unavailable`: another broker call to GitHub failed. The retry waits 60, 120 and 240
     seconds plus up to 20 seconds of jitter, or a longer `Retry-After`.

   No retry starts more than 8 minutes after the first request. `mint-unavailable`, a failed mint
   after the broker reserved the job's one mint, is final, and its failure says so; a retry would
   be denied `already-minted`, and a failure after a retry names the 503 before it. Every other
   answer is final, and no response at all fails red with `broker-unreachable`, since a 200 lost in
   transit leaves a token nobody revokes.
4. Any status but 200 fails red with `lane-token-denied`, the HTTP status, and the broker's
   `reason` and `detail`, printed as one line of data. The reasons are listed in the contract.
   With `superseded-ok: true`, a 403 with reason `workflow-modified` warns and ends green instead,
   setting no output, so steps gated on the `token` output skip.
5. On 200, masks the token, then compares the broker's `effect`, `permissions`, `lane`, `activity`
   and `repository_ids` with this job's values (`pull-requests` is `pull_requests` in the API). Any
   difference revokes the token and fails red with `effect-mismatch`. That happens when the PR's
   base SHA and the default-branch tip resolve the activity differently.
6. Writes the outputs. Any failure after the broker issued a token attempts to revoke it, and prints the status, before the step
   exits.

It does not revoke a token it handed out. The workflow does, in a final step with
`if: always() && steps.<id>.outputs.token != ''`, because a composite action has no post step.

## Use

Run it from the base checkout before any head checkout, after `resolve-config`:

```yaml
- name: Request the lane token
  id: lane-token
  if: steps.config.outputs.applies == 'true'
  uses: ./.base/.github/actions/request-lane-token
  with:
    broker-url: ${{ vars.LANES_BROKER_URL }}
    audience: ${{ vars.LANES_BROKER_AUDIENCE }}
    lane: ${{ inputs.lane }}
    activity: ${{ inputs.activity }}
    pr-number: ${{ steps.gate.outputs.pr-number }}
    effect: ${{ steps.config.outputs.effect }}
    contents: ${{ steps.config.outputs.contents }}
    pull-requests: ${{ steps.config.outputs.pull-requests }}
    issues: ${{ steps.config.outputs.issues }}
```

The job needs `permissions: id-token: write`, and so does the caller job that grants it.

## Check mode

With `mode: check` the action takes only `broker-url`, `audience`, `lane` and `activity`; a
`pr-number`, `issue-number`, effect or grant fails it red, so the read file's check job never carries the write
path's inputs. It posts to `broker-url`, retrying a 503 `github-unavailable` or `github-rate-limited` as in step 3, with its final `/token` replaced by `/check` (a URL
that does not match `^https://[^/]+/(.+/)?token$` fails red), with the body `{"lane", "activity"}`, and passes only on a 200
whose `decision` is `allow` and whose `lane` and `activity` are its own. Any other answer fails red
with `lane-check-denied`; no response is `broker-unreachable`. It sets no output.

```yaml
- name: Ask the broker whether the lane may run
  if: steps.kill.outputs.proceed == 'true'
  uses: ./.base/.github/actions/request-lane-token
  with:
    mode: check
    broker-url: ${{ vars.LANES_BROKER_URL }}
    audience: ${{ vars.LANES_BROKER_AUDIENCE }}
    lane: ${{ inputs.lane }}
    activity: ${{ inputs.activity }}
```
