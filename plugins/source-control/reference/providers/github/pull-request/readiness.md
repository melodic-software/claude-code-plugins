# GitHub: pull-request readiness

The GitHub commands behind the pull-request skill's
[readiness checklist](../../../../skills/pull-request/reference/readiness.md). The checklist owns
every gate, rule and threshold; this file holds the commands it runs.

## Discover actors

The checks list shows every check run and commit status. It is a one-off read: poll with the REST
read in [monitor.md](monitor.md#poll-checks-over-rest).

```bash
gh pr checks <pr_number> --json name,state,bucket
```

The conversation (issue-level) comments, where comment-only actors post:

```bash
gh api --paginate "repos/{owner}/{repo}/issues/<pr_number>/comments?per_page=100"
```

## Assert the check-run total

```bash
gh api --paginate "repos/{owner}/{repo}/commits/<sha>/check-runs?per_page=100" \
  | jq -s -r '"total_count=\(.[0].total_count) returned=\([.[].check_runs[]] | length)"'
```

## Gate 1: list the checks

```bash
gh pr checks <pr_number> --json name,state,bucket
```

`gh pr checks` aggregates both workflow check-runs and external commit-statuses, which is why one
name can show two rows.

### Verify a duplicated check name

Put the duplicated name in place of `<name>`:

```bash
gh api --paginate "repos/{owner}/{repo}/commits/<sha>/check-runs?per_page=100" \
  --jq '.check_runs[] | select(.name | test("<name>"; "i")) | "\(.status) \(.conclusion)"'
```

## Gate 2: list failing checks

```bash
gh pr checks <pr_number> --json name,state,bucket --jq '.[] | select(.bucket == "fail")'
```

The last-resort log eyeball is `gh run view <run-id> --log-failed`, which truncates at the CLI
display layer; see [monitor.md](monitor.md#fetch-failed-logs).

## Gate 4: read the three comment surfaces

```bash
# PR reviews (review body — a reviewer that posts no issue comment lands here)
gh api --paginate "repos/{owner}/{repo}/pulls/<pr_number>/reviews?per_page=100" \
  | jq -r '.[] | "\(.user.login): \(.state) — \(.body[:100])"'

# Inline review comments (diff-level)
gh api --paginate "repos/{owner}/{repo}/pulls/<pr_number>/comments?per_page=100" \
  | jq -r '.[] | "\(.user.login): \(.body[:100])"'

# General PR comments (conversation tab)
gh api --paginate "repos/{owner}/{repo}/issues/<pr_number>/comments?per_page=100" \
  | jq -r '.[] | "\(.user.login): \(.body[:100])"'
```

## Gate 5: count inline comments on this head

One reviewer per run, with its discovered login in the `--arg login` value:

```bash
HEAD_SHA=$(git rev-parse HEAD)
gh api --paginate "repos/{owner}/{repo}/pulls/<pr>/comments?per_page=100" \
  | jq -s --arg sha "$HEAD_SHA" --arg login "<discovered reviewer login>" \
    '[.[][] | select(.user.login == $login and .original_commit_id == $sha)] | length'
```
