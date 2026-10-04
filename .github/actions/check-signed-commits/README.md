# check-signed-commits

After a lane's model step, check that every commit the lane added to the PR is GitHub-verified, so
a lane never leaves a PR outside
[ADR 0051](../../../docs/adr/0051-start-pr-fix-ci-from-workflow-run-for-same-repository-trusted-prs.md)
condition 2, which requires a verified signature on every commit. It escalates and never rewrites
or force-pushes.

## Inputs

| Input | Default | Meaning |
|---|---|---|
| `pr-number` | required | The PR |
| `since-sha` | required | The PR head recorded before the model step ran |
| `repository` | `${{ github.repository }}` | owner/name of the PR's repository |
| `github-token` | required | The lane's App token: reads the PR, adds a label, comments |
| `escalation-label` | `needs-human` | Label added on an unverified commit |

## Rules

- New commits are the PR's commits that the comparison `since-sha...head` lists, so base commits
  brought in by a merge are not counted.
- When `since-sha` is malformed, unknown to GitHub, not an ancestor of the head, or the comparison
  is truncated, every PR commit is checked and `since-is-ancestor` is `false` in the first three
  cases.
- A commit counts as verified only when `commit.verification.verified` is `true` and its SHA is
  40 hex characters. A commit with a malformed SHA counts as unverified and is reported as
  `<invalid-sha>`, so no free text reaches the output or the comment.
- On any unverified commit it adds `escalation-label` only if that label already exists on the
  repository (it never creates one), then posts one fixed comment listing the SHAs. No model text
  reaches the comment.

## Outputs

| Output | Values |
|---|---|
| `all-verified` | `true` or `false` |
| `unverified` | Space-separated SHAs |
| `since-is-ancestor` | `true` or `false` |

The step exits 0 once the check ran, whatever it found, and exits 1 with no outputs when it could
not run.

## Job contract

A lane job that uses this check:

- Sets `permissions: contents: read, pull-requests: read`, both read-only. claude-code-action
  passes the job's `GITHUB_TOKEN` into the model's environment, so
  every write goes through the lane's App token.
- Records the PR head SHA before the App token is minted (the
  [`check-trusted-trigger`](../check-trusted-trigger/README.md) `head-sha` output) and passes it as
  `since-sha`, with one concurrency group per PR so no other lane pushes in between.
- Runs both gates with no `continue-on-error`, and gives the model step
  `if: steps.kill.outputs.proceed == 'true' && steps.gate.outputs.proceed == 'true'`.
- Mints the App token only after both gates.

## Tests

`npm test` in this directory runs `node --test` over recorded-shape API fixtures, with no network;
`scripts/run-outside-node-suites.sh` runs it in CI.
