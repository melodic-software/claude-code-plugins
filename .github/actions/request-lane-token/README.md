# request-lane-token

Get the lane App token for one write activity from the lanes token broker, in place of minting it
from the App private key. The job sends its GitHub OIDC token to the broker, which checks it and
returns one installation token for this repository, scoped to the effect the default-branch config
gives the activity and valid for at most one hour. No workflow holds the App key.
[ADR 0058](../../../docs/adr/0058-mint-lane-app-tokens-through-an-oidc-broker.md) records the
decision; the run job contract is in
[`pr-run-activity.md`](../../../docs/conventions/pr-pipeline/pr-run-activity.md), run job step 6.

## Inputs

| Input | Meaning |
|---|---|
| `broker-url` | The token endpoint, `${{ vars.LANES_BROKER_URL }}`. Empty or not `https://` fails red |
| `audience` | The OIDC audience, `${{ vars.LANES_BROKER_AUDIENCE }}`. Empty fails red |
| `lane`, `activity` | Sent to the broker; the lane must be the caller workflow's file stem |
| `pr-number` | The gated PR; sent as `pr_number` when set, which the broker needs off `pull_request` |
| `effect`, `contents`, `pull-requests`, `issues` | This job's own `resolve-config` outputs, compared with the broker's answer |

## Outputs

| Output | Value |
|---|---|
| `token` | The lane token, masked. Set only when every check passed |
| `expires-at` | The expiry the broker returned |
| `mint-id` | `<check_run_id>-<run_attempt>`, the broker's audit key for this mint |

## What it does

1. Fails red when either variable is empty, when the resolved grant is not `read` or `write` for
   each of `contents`, `pull-requests` and `issues`, or when the job lacks `id-token: write`.
2. Requests an OIDC token for `audience` and masks it.
3. Sends one `POST` to `broker-url` with `Authorization: Bearer <OIDC token>` and the body
   `{"lane", "activity", "pr_number"?}`. It never retries: the broker spends the job's one mint
   when it answers, so a second request could only be denied `already-minted` or issue a token
   nobody revokes. No response at all fails red with `broker-unreachable`.
4. Any status but 200 fails red with `lane-token-denied`, the HTTP status, and the broker's
   `reason` and `detail`, printed as one line of data. The reasons are listed in the contract.
5. On 200, masks the token, then compares the broker's `effect`, `permissions`, `lane`, `activity`
   and `repository_ids` with this job's values (`pull-requests` is `pull_requests` in the API). Any
   difference revokes the token and fails red with `effect-mismatch`. That happens when the PR's
   base SHA and the default-branch tip resolve the activity differently.
6. Writes the outputs. Any failure after the broker issued a token revokes it before the step
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
