# GitHub: pull-request monitor

The GitHub commands behind the pull-request skill's
[monitor phase](../../../../skills/pull-request/reference/monitor.md). The phase owns the loop, its
cadence, and every rule and gate; this file holds the commands and the GitHub and `gh` facts behind
them.

## Resolve PR identity

`<checkout>` is the checkout of the PR's repository the session works on, as
[ready-for-review 2.5.3](../../../../skills/pull-request/reference/ready-for-review.md#253-review-and-verify-the-updated-head)
defines it (absolute, or `.` when the shell sits in it), so neither the repository nor the branch
depends on the shell's directory:

```bash
OWNER_REPO=$(bash "<skill-dir>/scripts/target-repo.sh" --dir "<checkout>") || exit 1
OWNER=${OWNER_REPO%%/*} REPO=${OWNER_REPO#*/}
PR_NUMBER=$(gh pr view "$(git -C "<checkout>" branch --show-current)" -R "$OWNER_REPO" --json number -q '.number' | tr -d '\r')
[ -n "$PR_NUMBER" ] || exit 1
```

On a triangular flow (the branch pushed to a fork, the PR opened on its upstream base), the base
repository takes `target-repo.sh`'s place, named explicitly, since the script resolves the
checkout to the fork, and the head is namespaced `<fork-owner>:<branch>`, as in
[create's triangular flow](create.md#open-the-pr-from-an-out-of-tree-orchestrator):

```bash
FORK=$(bash "<skill-dir>/scripts/target-repo.sh" --dir "<checkout>") || exit 1
OWNER_REPO="<base-owner>/<repo>"   # the PR's target, not the push destination
OWNER=${OWNER_REPO%%/*} REPO=${OWNER_REPO#*/}
PR_NUMBER=$(gh pr view "${FORK%%/*}:$(git -C "<checkout>" branch --show-current)" -R "$OWNER_REPO" --json number -q '.number' | tr -d '\r')
[ -n "$PR_NUMBER" ] || exit 1
```

The commands below write that repository as `<owner>/<repo>`: put the resolved value in its place.

## Read PR state

```bash
gh pr view <pr_number> -R <owner>/<repo> --json state -q '.state'
```

## Poll checks over REST

The Monitor watch's `command` is the bundled poll script, run by path; no script body goes inline:

```bash
bash "<skill-dir>/scripts/monitor-poll.sh" --pr <N> --checkout "<checkout>"
```

The script resolves `OWNER` and `REPO` from `--checkout` as
[Resolve PR identity](#resolve-pr-identity) does, and exits 1 when `target-repo.sh` refuses. On a
triangular flow, add `--repo <base-owner>/<repo>`, the PR's base repository named explicitly, which
wins over `--checkout`. Every read is a conditional request: each page goes out with the ETag of
its last answer, a `304 Not Modified` replays the cached body, and GitHub does not count an
authorized 304 against the primary rate limit
([conditional requests](https://docs.github.com/en/rest/using-the-rest-api/best-practices-for-using-the-rest-api#use-conditional-requests)),
so a poll where nothing changed costs nothing. The comment reads keep `since` at the watch's start,
because a changed query string gets a new ETag. Raise `--interval <seconds>` (default 90) only
when the [API budget](../README.md#api-budget) arithmetic says so. `--once` exits 0 after the first poll that emits
a line, for a background Bash run where the Monitor tool is unavailable. The first arming passes no `--baseline`; a re-arm
passes `--baseline <file>`, the file this same script wrote in a snapshot run (`--snapshot <file>`:
one state check and checks read, the `cur_checks` lines and any `PR-VERIFY <verdict> <head-sha>`
lines written under a marker line, then exit 0, or exit 1 with nothing written when the checks read
failed). The pr-verify verdict reads use the artifacts endpoint's `name` filter, one exact name per
call ([List artifacts for a repository](https://docs.github.com/en/rest/actions/artifacts#list-artifacts-for-a-repository)),
because a paged listing can miss a verdict past its page size. A baseline file without that marker line is
refused with `BASELINE-UNREADABLE`, so only this script's serializer produces a baseline. A usage
error exits 3.

Keep the script free of `rm`: an auto-mode session's safety check denied the inline `command`
while it ran `rm` on a stderr temp file (issue #16201). The reads' stderr collects in `errs`. The
same check later refused the inline script with no `rm` in it (issue #16353), so the watch runs it
from the file, and the REST read of a PR's checks lives only there. For a one-off read, run the
script once with `--snapshot <file>` and read the lines after the file's marker line: one
`name: bucket` line per finished check, none for a pending one. The bucket mapping and the
latest-per-name/workflow/event dedupe follow gh's `pkg/cmd/pr/checks/aggregate.go`.

## Why polling uses REST

`gh pr checks` (including `--watch`) and `gh pr view --json` query GraphQL (`GH_DEBUG=api` shows
`POST /graphql` for `gh pr checks` and for `gh pr view --json state`), and
concurrent workers under one token have hit GraphQL secondary rate limits. GraphQL and REST draw on
separate per-minute point budgets (2,000 and 900 points per minute) and separate primary limits
(5,000 points per hour for GraphQL, 5,000 requests per hour for REST), and a REST `GET` costs 1
point, so moving the polling to REST leaves the GraphQL budget for the calls that have no REST
equivalent, such as review-thread resolution. The 100-concurrent-request ceiling is shared by
both APIs, so REST polling does not raise it. Verified 2026-09-25, and 2026-09-26 with gh 2.97.0 for the `gh` behavior, against
[List check runs for a Git reference](https://docs.github.com/en/rest/checks/runs),
[Get the combined status for a specific reference](https://docs.github.com/en/rest/commits/statuses),
[Rate limits for the REST API](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api),
and [Rate limits for the GraphQL API](https://docs.github.com/en/graphql/overview/rate-limits-and-query-limits-for-the-graphql-api).
Recheck when either rate-limits page changes its secondary-limit figures, or when a `gh` release
note says `pr checks` or `pr view` moved off GraphQL or changes the `pr checks` bucket mapping.

## List other open PRs

```bash
gh pr list -R <owner>/<repo> --state open --json number,title,headRefName,statusCheckRollup \
  --jq '.[] | "\(.number) \(.headRefName) \(.title)"'
```

## Read mergeability

```bash
gh pr view <N> -R <owner>/<repo> --json mergeable,mergeStateStatus
```

## Wait on a pending check

`gh pr checks --watch` re-runs its GraphQL query every `--interval` seconds (default 10) until every
check settles.

### List unfinished jobs for the head

```bash
gh api --paginate "repos/$OWNER/$REPO/actions/runs?head_sha=$head_sha&per_page=100" \
  --jq '.workflow_runs[] | select(.status != "completed") | .id' | tr -d '\r' |
  while read -r run_id; do
    gh api --paginate "repos/$OWNER/$REPO/actions/runs/$run_id/jobs?per_page=100" \
      --jq '.jobs[] | select(.status != "completed") | "\(.name) | \(.status) | \(.labels | join(",")) | created \(.created_at)"'
  done | tr -d '\r'
```

### Evidence

**Claim:** a long CI wait must poll REST on a fixed schedule and must not use `gh pr checks
--watch`; a `pending` check is reported as queued or running before the wait starts; a queued job
is routed as stuck only when no online runner matches its label, or when occupancy is unreadable
or shows a free matching runner past the threshold, never on age alone while the pool is busy.
**Basis:** `gh pr checks --help` (`--interval` default 10) on gh 2.99.0; [Workflow
jobs](https://docs.github.com/en/rest/actions/workflow-jobs) (`status`, `labels`, `runner_name`);
[Self-hosted runners](https://docs.github.com/en/rest/actions/self-hosted-runners) (`busy`,
`status`, `labels`; admin access); [Check runs](https://docs.github.com/en/rest/checks/runs)
(six `status` values); [Best practices for using the REST
API](https://docs.github.com/en/rest/using-the-rest-api/best-practices-for-using-the-rest-api)
("poll only as often as you need to, on a fixed schedule"). Probe on this marketplace's repo the
same day: jobs read succeeded; both runner-list endpoints returned 403 to a non-admin token.
Issue #3955 evidence: `--watch` exhausted GraphQL while a self-hosted `test` job was still queued.
**As of:** 2026-09-28. **Recheck:** when a `gh` release changes `--watch`'s transport or default
interval, or when either runners endpoint changes its permission requirement.

## Fetch failed logs

`gh run view --log-failed` is the last resort: it truncates at the CLI display layer
(cli/cli #11059, #10551, #7771, #7642), while the bundled scripts' REST path returns complete logs.
`fetch-annotations.sh` and `fetch-failed-logs.sh` take `--dir "<checkout>"` and resolve the
repository with `target-repo.sh`, as [Resolve PR identity](#resolve-pr-identity) does. On a
triangular flow, name the PR's base repository in `GH_REPO`, or in `FETCH_ANNOT_REPO` and
`FETCH_LOGS_REPO`, which win over `--dir`, since the script resolves the checkout to the fork.
The last-resort eyeball:

```bash
gh run view <run-id> -R <owner>/<repo> --log-failed 2>&1 | grep '##\[error\]'
```

## Reply on an inline thread

```bash
gh api repos/<owner>/<repo>/pulls/<pr_number>/comments/{comment_id}/replies -f body='...'
```

Writing the body to a file first is safer; see the
[provider reference](../README.md#review-surfaces).

## Read the head's check runs

```bash
gh api "repos/<owner>/<repo>/commits/<head-sha>/check-runs"
```

## Why the comment script

`gh pr view --json comments,reviews` misses inline review comments, so the bundled
`fetch-all-pr-comments.sh` reads all three surfaces instead. Like the log scripts, it takes
`--dir "<checkout>"`; on a triangular flow, name the PR's base repository in `GH_REPO`, or in
`FETCH_COMMENTS_OWNER` and `FETCH_COMMENTS_REPO`, which win over `--dir`.
