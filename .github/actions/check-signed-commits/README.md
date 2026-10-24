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
| `github-token` | required | Reads the PR and its commits; adds the label and comment, which needs `issues: write` |
| `escalation-label` | `needs-human` | Label added on an unverified commit |

## Rules

- The PR is re-read, after waits of 5, 10, 20 and 25 s (60 s in all), until its head SHA equals
  the SHA its head branch ref points at, since `GET /pulls` can lag a push by minutes. When they never agree, the lane's commits
  cannot be checked: `all-verified` and `since-is-ancestor` are `false` and the escalation runs.
- The lane's commits are the commits the comparison `since-sha...head` lists, when `since-sha` is
  an ancestor of the head and the comparison lists every commit it counts. Their verification is
  read from the comparison's commit objects. A comparison with no commits passes.
- GitHub lists at most 250 commits for a PR. When the PR list holds the whole PR (its `commits`
  count is no higher than the number listed), comparison commits that are not PR commits, such as
  base commits a merge brought in, are dropped. When the list is capped or the count is missing,
  every comparison commit is checked.
- When `since-sha` is malformed, unknown to GitHub, not an ancestor of the head, or the comparison
  is truncated, every PR commit is checked and `since-is-ancestor` is `false` in the first three
  cases. If the PR list is then capped, the PR cannot be checked whole: `all-verified` is `false`
  and the escalation runs, with a fixed sentence saying the PR exceeds the checkable count.
- A commit counts as verified only when `commit.verification.verified` is `true` and its SHA is
  40 hex characters. A commit with a malformed SHA counts as unverified and is reported as
  `<invalid-sha>`, so no free text reaches the output or the comment.
- On any unverified commit, or a PR it cannot check whole, it adds `escalation-label` only if that label already exists on the
  repository (it never creates one), then posts one fixed comment listing the SHAs. No model text
  reaches the comment. When no commit is unverified but the PR could not be checked whole, the log
  line and the comment say the commits could not be verified, never that they are unverified.

## Outputs

| Output | Values |
|---|---|
| `all-verified` | `true` or `false` |
| `unverified` | Space-separated SHAs |
| `since-is-ancestor` | `true` or `false` |

The step writes its outputs before the escalation. It exits 0 once the check ran, whatever it
found, and any escalation was posted. It exits 1 with no outputs when the check could not run, and
exits 1 with the outputs already written (`all-verified` `false`) when an escalation write fails.
One exception: when no commit was found unverified (the commits could only not be verified) and
GitHub refuses an escalation write, it logs a warning and exits 0 with those outputs.

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

The check itself runs in the scripted `report` job, with that job's `GITHUB_TOKEN`. The label
and comment writes need `issues: write` on that job and never on the model job. A called job holds
no more than its caller grants, so every job that calls `pr-run-activity-write.yml` or
`pr-run-activity-read.yml` grants `issues: write` too.

## Tests

`npm test` in this directory runs `node --test` over recorded-shape API fixtures, with no network;
`scripts/run-outside-node-suites.sh` runs it in CI.
