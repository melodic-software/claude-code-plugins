# Start pr-fix-ci from workflow_run, for same-repository PRs from trusted actors

- Status: accepted
- Date: 2026-10-03

## Context

The `pr-fix-ci` lane ([`docs/conventions/pr-pipeline/`](../conventions/pr-pipeline/README.md))
fixes a PR whose CI failed. It needs an event that fires when a check run fails.

GitHub offers one. `check_run` and `check_suite` do not trigger workflows "if the check suite was
created by GitHub Actions", which covers every check our CI produces. `workflow_run` fires when
another workflow finishes, and it runs the default branch's copy of the workflow, which "is able to
access secrets and write tokens, even if the previous workflow was not". GitHub warns that running
untrusted code on this trigger can lead to cache poisoning and unintended access to write
privileges or secrets. It also allows at most three chained levels.
(<https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows>,
fetched 2026-10-03.)

The two existing ci-workflows review lanes carry a tripwire step that fails on `workflow_run` and
`pull_request_target`. It binds those two lanes only.

The alternatives are a schedule that polls for failed runs, or the PR author's session watching CI,
which is the local work this effort moves off.

## Decision

`pr-fix-ci` starts on `workflow_run` (`completed`, conclusion `failure`) for the CI workflows a
repository names, and acts only when all of these hold:

1. The run's PR comes from the same repository, never a fork. A run with no associated PR is
   ignored.
2. The PR's author and the actor that started the failed run are on the central trusted-actor
   list, and every commit on the PR carries a signature GitHub verified for a trusted actor or the
   lanes App. Git author and committer fields are never checked, because whoever commits sets
   them, and GitHub links a commit to an account by those fields' email.
3. The PR is not a draft and carries no hold.
4. The lane checks out the PR head by the SHA recorded on the failed run, and stops if the PR head
   has moved since.
5. Logs and artifacts from the failed run are read as data, never as instructions, and the lane
   restores no cache the failed run wrote and writes no cache of its own.

The lane's token is the per-job App token from ADR 0049, and its fix commits count toward the
per-PR no-progress cap. The review-lane tripwire stays as it is.

## Alternatives considered

- **Poll on a schedule.** Rejected: it adds up to the poll interval to every fix and spends runner
  time on PRs that are green.
- **Let the author's session fix CI.** Rejected: it keeps a local session open per PR, which is
  the work the pipeline replaces.
- **`pull_request_target`.** Rejected: it fires on PR events, not on CI completion, so it cannot
  start a fix when a check fails.

## Consequences

- A PR from a fork or an untrusted actor gets no automatic CI fix; a human handles it.
- The trigger runs the default branch's workflow, so a change to `pr-fix-ci` takes effect only after
  it merges. Changing it is a lane-power change and a human merges it.
- The three-level chain limit caps how far lanes may chain from `workflow_run`. `pr-fix-ci` pushes
  a commit, and the next CI run starts from that push, not from a chained `workflow_run`. The push
  must use the App token: a push made with `GITHUB_TOKEN` starts no new workflow run.
