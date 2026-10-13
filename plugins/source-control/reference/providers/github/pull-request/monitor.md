# GitHub: pull-request monitor

The GitHub commands behind the pull-request skill's
[monitor phase](../../../../skills/pull-request/reference/monitor.md). The phase owns the loop, its
cadence, and every rule and gate; this file holds the commands and the GitHub and `gh` facts behind
them.

## Resolve PR identity

```bash
PR_NUMBER=$(gh pr view --json number -q '.number' | tr -d '\r')
OWNER=$(gh repo view --json owner -q .owner.login)
REPO=$(gh repo view --json name -q .name)
```

With multiple PRs open against this checkout, name the branch:
`gh pr view "$(git branch --show-current)" --json number -q '.number'`.

## Read PR state

```bash
gh pr view <pr_number> --json state -q '.state'
```

## Poll checks over REST

The Monitor watch's poll script, passed inline in the `command` parameter. `<scripts-dir>` is the
placeholder the pull-request skill resolves.

```bash
PR_NUMBER=<N>
OWNER=$(gh repo view --json owner -q .owner.login)
REPO=$(gh repo view --json name -q .name)
prev_checks=""
last_comment_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
prev_threads=""
poll=0

while true; do
  # Terminal state check — exit watch if PR closed/merged. REST, like the
  # CI read below (§3.1 "Polling CI from more than one worker").
  read -r state head_sha < <(gh api "repos/$OWNER/$REPO/pulls/$PR_NUMBER" \
    --jq '"\(if .merged then "MERGED" elif .state == "closed" then "CLOSED" else "OPEN" end) \(.head.sha)"' \
    2>/dev/null | tr -d '\r')
  if [ "$state" = "MERGED" ] || [ "$state" = "CLOSED" ]; then
    echo "PR #$PR_NUMBER $state — watch complete"
    exit 0
  fi

  # CI changes: one "name: bucket" line per check, the same rows and
  # buckets `gh pr checks` reports, read over REST. Check runs are
  # deduplicated as gh does (latest start per name/workflow/event);
  # commit statuses are always read, since check-runs omit them.
  b='def b: ascii_upcase | if . == "SUCCESS" then "pass" elif . == "SKIPPED" or . == "NEUTRAL" then "skipping" elif . == "CANCELLED" then "cancel" elif . == "ERROR" or . == "FAILURE" or . == "TIMED_OUT" or . == "ACTION_REQUIRED" then "fail" else "pending" end;'
  wf=$(gh api --paginate "repos/$OWNER/$REPO/actions/runs?head_sha=$head_sha&per_page=100" \
    --jq '.workflow_runs[] | {(.check_suite_id | tostring): "\(.name)/\(.event)"}' 2>/dev/null | jq -s -c 'add // {}')
  cur_checks=$({ gh api --paginate "repos/$OWNER/$REPO/commits/$head_sha/check-runs?per_page=100" \
      | jq -s -r --argjson wf "$wf" "$b"' [.[].check_runs[] | {k: "\(.name)/\($wf[.check_suite.id | tostring] // "")", name, t: (.started_at // ""), s: (if .status == "completed" then .conclusion else .status end)}] | group_by(.k) | map(max_by(.t))[] | "\(.name): \(.s | b)"'
    gh api --paginate "repos/$OWNER/$REPO/commits/$head_sha/status?per_page=100" \
      --jq "$b"' .statuses[] | "\(.context): \(.state | b)"'
  } 2>/dev/null | tr -d '\r' | grep -v ': pending$' | sort || true)
  if [ "$cur_checks" != "$prev_checks" ]; then
    # Bucket values mirror gh pr checks: pass|fail|pending|skipping|cancel.
    # The first poll only records the checks, so a re-arm at the
    # deadline does not re-emit every completed check.
    if [ "$poll" -gt 0 ]; then
      comm -13 <(echo "$prev_checks") <(echo "$cur_checks") | \
        grep --line-buffered -E ': (pass|fail|skipping|cancel)$' \
        || true
    fi
    prev_checks="$cur_checks"
  fi

  # New comments — ALL THREE review surfaces (issue-level, inline
  # review comments, review bodies). Watching only issues/comments
  # misses inline findings posted with no CI state change.
  # Advance the watermark ONLY when every fetch succeeded — a transient
  # gh failure would otherwise skip past comments that arrived during
  # the failed poll window and never emit them.
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  fetch_ok=1
  if out=$(gh api --paginate "repos/$OWNER/$REPO/issues/$PR_NUMBER/comments?since=$last_comment_ts&per_page=100" \
    --jq '.[] | "COMMENT \(.user.login): \(.body[:80])"' 2>/dev/null); then
    printf '%s\n' "$out" | tr -d '\r' | grep --line-buffered . || true
  else fetch_ok=0; fi
  if out=$(gh api --paginate "repos/$OWNER/$REPO/pulls/$PR_NUMBER/comments?since=$last_comment_ts&per_page=100" \
    --jq '.[] | "INLINE-COMMENT \(.user.login): \(.body[:80])"' 2>/dev/null); then
    printf '%s\n' "$out" | tr -d '\r' | grep --line-buffered . || true
  else fetch_ok=0; fi
  # Reviews API has no `since` param — filter client-side on submitted_at.
  # Client-side filtering makes pagination required: an unpaginated read
  # returns the 30 OLDEST reviews, so on a PR past that count the new ones
  # this poll exists to catch are exactly the ones never fetched.
  if out=$(gh api --paginate "repos/$OWNER/$REPO/pulls/$PR_NUMBER/reviews?per_page=100" \
    --jq ".[] | select(.submitted_at > \"$last_comment_ts\") | \"REVIEW \(.user.login) [\(.state)]: \(.body[:80])\"" 2>/dev/null); then
    printf '%s\n' "$out" | tr -d '\r' | grep --line-buffered . || true
  else fetch_ok=0; fi
  [ "$fetch_ok" -eq 1 ] && last_comment_ts="$now"

  # Review threads: resolving one moves no check and posts no comment, so
  # the reads above never see it. The Gate 7 read (readiness.md) costs a
  # GraphQL call, so it runs every 4th poll (about 2 minutes) and emits
  # when the unresolved count, or THREADS_UNPROVEN, changes.
  if [ $((poll % 4)) -eq 0 ]; then
    cur_threads=$(bash "<scripts-dir>/source-control-review-threads" "$OWNER/$REPO#$PR_NUMBER" 2>/dev/null \
      | awk 'NR == 1 && /^THREADS_(OK|BLOCKED) unresolved=/ { sub(/.*unresolved=/, ""); sub(/[^0-9].*/, ""); print }')
    cur_threads=${cur_threads:-THREADS_UNPROVEN}
    if [ "$cur_threads" != "$prev_threads" ]; then
      [ "$poll" -gt 0 ] && echo "REVIEW-THREADS unresolved=$cur_threads"
      prev_threads="$cur_threads"
    fi
  fi
  poll=$((poll + 1))

  sleep 30
done
```

Its state check and CI block (the `head_sha` read through `cur_checks`) also run standalone, with
`OWNER`, `REPO`, and `PR_NUMBER` set, as the REST read of a PR's checks. The bucket mapping and the
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
gh pr list --state open --json number,title,headRefName,statusCheckRollup \
  --jq '.[] | "\(.number) \(.headRefName) \(.title)"'
```

## Read mergeability

```bash
gh pr view <N> --json mergeable,mergeStateStatus
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

`gh run view --log-failed` is the LAST resort because it truncates at the CLI display layer (~4MB
cap, cli/cli #11059, #10551, #7771, #7642). The REST API path the bundled scripts use returns
complete logs every time. The last-resort eyeball:

```bash
gh run view <run-id> --log-failed 2>&1 | grep '##\[error\]'
```

## Reply on an inline thread

```bash
gh api repos/{owner}/{repo}/pulls/<pr_number>/comments/{comment_id}/replies -f body='...'
```

Writing the body to a file first is safer; see the
[provider reference](../README.md#review-surfaces).

## Read the head's check runs

```bash
gh api "repos/<owner>/<repo>/commits/<head-sha>/check-runs"
```

## Why the comment script

`gh pr view --json comments,reviews` MISSES inline review comments, so the bundled
`fetch-all-pr-comments.sh` reads all three surfaces instead.
