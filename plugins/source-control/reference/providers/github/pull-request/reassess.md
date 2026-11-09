# GitHub: pull-request reassess

The GitHub commands behind the pull-request skill's
[reassess action](../../../../skills/pull-request/reference/reassess.md). The action owns the
verdicts, the limits and the order; this file holds the commands and the GitHub and `gh` facts
behind them.

## Read the PR and its queue state

The repository comes from the PR's URL, which names the base repository.

```bash
gh pr view "$PR_NUMBER" --json state,isDraft,url,title,body,labels,baseRefName,headRefName,headRefOid,isCrossRepository,closingIssuesReferences
gh api graphql -F owner="$OWNER" -F name="$REPO" -F number="$PR_NUMBER" -f query='
  query($owner: String!, $name: String!, $number: Int!) {
    repository(owner: $owner, name: $name) { pullRequest(number: $number) { isInMergeQueue } } }' \
  --jq '.data.repository.pullRequest.isInMergeQueue'
```

A native stack member is the signals script's `native_stack` answer. The standards-sync role label
is the one `standards_sync_skip` in the babysit-prs engine reads.

## Read the hold sources

The worker lease is `<state-dir>/active-workers/<owner>__<name>__pr-<number>.json`, where
`<state-dir>` is `--state-dir`, else babysit's state directory. A file whose `expires_at` is still
ahead holds the PR. No file holds nothing. An unreadable file holds the PR, since no hold was ruled
out.

```bash
jq -r .expires_at "$STATE_DIR/active-workers/${OWNER}__${REPO}__pr-$PR_NUMBER.json"
```

For each worktree `git worktree list --porcelain` shows holding the head branch, exit 4 is a live
claim by another session. Exit 0 is this session's own claim or no linked worktree, and exit 3 is
an unclaimed worktree; neither holds the PR.

```bash
bash "<plugin-root>/scripts/worktree-claim.sh" check-enter "$WORKTREE" --session-id "$SESSION_ID"
```

## Read the head and the base range

The head arrives by its pull ref, which also exists for a fork head and runs no head code.

```bash
git fetch "$REMOTE" "+refs/pull/$PR_NUMBER/head:refs/reassess/$PR_NUMBER"
git worktree add --detach ".work/reassess-$PR_NUMBER" "refs/reassess/$PR_NUMBER"
gh api --paginate --slurp "repos/$OWNER/$REPO/pulls/$PR_NUMBER/commits" |
  jq -r 'add | map(select(.parents | length < 2)) | first | "\(.sha) \(.parents[0].sha)"'
```

The second field is the range's start. The paths are the union over those non-merge commits.

## Search the other PRs

For each commit in the range that touches one of the PR's paths, the PR that merged it:

```bash
git log --format=%H "$START..$REMOTE/$BASE" -- "${PATHS[@]}"
gh api "repos/$OWNER/$REPO/commits/$SHA/pulls" --jq '.[] | select(.merged_at != null) | .number'
```

And the PRs naming the same closing issue:

```bash
gh pr list --state all --search "$ISSUE_NUMBER in:body" --json number,state,title,mergedAt
```

- **Pointer**: when checking which PRs a commit lists, fetch
  [list pull requests associated with a commit](https://docs.github.com/en/rest/commits/commits#list-pull-requests-associated-with-a-commit)
  live.
- **As of**: 2026-11-08
- **Recheck trigger**: that section changes which pull requests it returns.

## Disarm auto-merge

```bash
gh pr merge "$PR_NUMBER" --disable-auto
```

## Add the hold label

Check the label exists first, so a missing one is reported rather than read as a failed edit:

```bash
gh api "repos/$OWNER/$REPO/labels/do-not-merge" --silent && gh pr edit "$PR_NUMBER" --add-label do-not-merge
```

## Post or edit the comment

The body's first line is `<!-- source-control-reassess -->`. A re-run edits the newest comment that
starts with that marker and was written by the acting login; a marker on anyone else's comment is
ignored. With none, it posts a new one.

```bash
LOGIN=$(gh api user --jq .login) || exit 1
ID=$(gh api --paginate --slurp "repos/$OWNER/$REPO/issues/$PR_NUMBER/comments" |
  jq -r --arg login "$LOGIN" 'add | map(select(.user.login == $login and (.body | startswith("<!-- source-control-reassess -->")))) | last | .id // empty')
if [ -n "$ID" ]; then
  gh api --method PATCH "repos/$OWNER/$REPO/issues/comments/$ID" -F body=@"$BODY_FILE" >/dev/null
else
  gh pr comment "$PR_NUMBER" --body-file "$BODY_FILE"
fi
```
