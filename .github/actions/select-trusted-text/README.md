# select-trusted-text

Build a lane's prompt context from a PR, keeping only text whose own author is on the
trusted-actor list
([ADR 0049](../../../docs/adr/0049-run-ci-lanes-on-github-hosted-runners-under-trigger-and-token-hardening.md)
condition 1). Run it after both gates pass and the App token is minted.

## Inputs

| Input | Default | Meaning |
|---|---|---|
| `pr-number` | required | The PR, normally `check-trusted-trigger`'s `pr-number` output |
| `repository` | `${{ github.repository }}` | owner/name of the PR's repository |
| `trusted-actors-path` | `.base/.github/standards/trusted-actors/trusted-actors.json` | The list, from the base-SHA checkout |
| `output-path` | required | Where the `TrustedContext` JSON file is written |
| `github-token` | required | The lane's App token |

## What it reads and keeps

It reads the PR, its issue comments, reviews and review comments, the issues the PR closes
(GraphQL `closingIssuesReferences`, any repository the token can read) and their comments, every
page of each.

An item is kept only when its `user` is not null, its `user.id` is listed, and its
`performed_via_github_app` is null or names an App whose `<slug>[bot]` account id is listed. The
PR's title and body are kept only when the PR author passes the same check; otherwise the title is
empty, the body null, and the PR counts as dropped. An App's bot id comes from a
`/users/<slug>[bot]` lookup; a lookup that fails counts the App as unlisted.

## Output

The file at `output-path` holds `pr` (number, head and base SHA, author id, title, body), `items`
(kind, id, author id and login, created time, URL, body) and `dropped`, a count per kind: `pr`,
`issue-comment`, `review`, `review-comment`, `linked-issue`, `linked-issue-comment`.

The log gets one line, `select-trusted-text: dropped total=<n> {<counts>}`. Dropped text is never
written or logged. When it cannot run (an unreadable list, a malformed input, any failed read,
including a closing issue in a repository the token cannot read), the step exits 1 and leaves no
file, so a lane never reads a partial context and the model step does not run. Unlike the gates,
which exit 0 with `proceed=false`, a failure here is an error a human should see.

Kept text is still data to the model, never instructions
([`untrusted-content`](../../../docs/conventions/untrusted-content/README.md)): a listed bot can
quote text a stranger wrote, and the model can fetch unfiltered comments itself. ADR 0049's
Consequences record both.

## Job contract

A lane job that uses this filter:

- Sets `permissions: contents: read, pull-requests: read`, both read-only. claude-code-action
  passes the job's `GITHUB_TOKEN` into the model's environment, so
  every write goes through the lane's App token.
- Runs it only after [`check-kill-switch`](../check-kill-switch/README.md) and
  [`check-trusted-trigger`](../check-trusted-trigger/README.md) both report `proceed == 'true'`,
  and after the App token is minted.
- Leaves it without `continue-on-error`, so a failed filter stops the model step.

## Tests

`npm test` in this directory runs `node --test` over recorded-shape API fixtures, with no network;
`scripts/run-outside-node-suites.sh` runs it in CI.
