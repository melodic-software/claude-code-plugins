# GitHub: pull-request reassess

The GitHub commands behind the pull-request skill's
[reassess action](../../../../skills/pull-request/reference/reassess.md). The action owns the
verdicts, the limits and the order; this file holds the commands and the GitHub and `gh` facts
behind them.

Run the blocks in one shell, or write each value in literally, since they share these names:

| Name | Value |
|---|---|
| `PR_NUMBER` | The PR being reassessed |
| `REPO`, `REMOTE` | From [Name the repository and its remote](#name-the-repository-and-its-remote) |
| `STATE_DIR` | `--state-dir`, else the path the skill's `reassess` row states. Never expand it from the shell, where the plugin data variable can name another plugin |
| `RUN` | One timestamp this run picks, so a peer's run on the same PR keeps its own ref and worktree |
| `BASE`, `HEAD_SHA` | From [Fetch the head and the base](#fetch-the-head-and-the-base) |
| `FIRST`, `START` | The first line of the commit list, and its parent |
| `SHA` | Each line the path search prints |
| `ISSUE_REF` | `#<number>` for a closing issue in `REPO`, `<owner>/<repo>#<number>` for one elsewhere |
| `BODY_FILE` | The renderer's output, written to a file |

## Name the repository and its remote

The repository comes from the PR's URL, which names the base repository. A failed read, or a base
repository no local remote fetches, ends the run with no verdict.

```bash
REPO=$(gh pr view "$PR_NUMBER" --json url -q '.url | split("/")[3:5] | join("/")') || exit 1
source "<plugin-root>/lib/github-remote.sh"
REMOTE=$(remote_of_repo "$REPO")
[ -n "$REMOTE" ] || exit 1
```

## Read the limits

```bash
bash "<skill-dir>/scripts/reassess-limits.sh" "$PR_NUMBER" --repo "$REPO" --state-dir "$STATE_DIR"
```

Exit 0: no limit. Exit 3: limits on stdout. Exit 4: refused. Exit 1 or 5 ran no read, so treat it as
`unread`. Add `--expect-head "$HEAD_SHA"` for the read before the first write.

## Fetch the head and the base

The pull ref also exists for a fork head, and a fetch runs nothing from it. A fetched head that is
not `HEAD_SHA` ends the run with no verdict.

```bash
read -r BASE HEAD_SHA <<<"$(gh pr view "$PR_NUMBER" -R "$REPO" --json baseRefName,headRefOid -q '"\(.baseRefName) \(.headRefOid)"')" || exit 1
git fetch "$REMOTE" "+refs/pull/$PR_NUMBER/head:refs/reassess/$PR_NUMBER-$RUN" "+refs/heads/$BASE:refs/remotes/$REMOTE/$BASE" || exit 1
[ "$(git rev-parse "refs/reassess/$PR_NUMBER-$RUN")" = "$HEAD_SHA" ] || exit 1
```

The PR's own commits are the non-merge commits the base does not hold, oldest first, and the
range starts at the first one's parent. An empty list ends the run with no verdict.

```bash
COMMITS=$(git rev-list --reverse --topo-order --no-merges "refs/reassess/$PR_NUMBER-$RUN" --not "$REMOTE/$BASE") || exit 1
FIRST=$(head -n 1 <<<"$COMMITS")
[ -n "$FIRST" ] || exit 1
START=$(git rev-parse "$FIRST^") || exit 1
git merge-base --is-ancestor "$START" "$REMOTE/$BASE" || START=$(git merge-base "$START" "$REMOTE/$BASE") || exit 1
```

## Search the other PRs

File names come from the head, so they stay NUL-delimited and never enter the command text.
`pipefail` makes a failed stage a failed read rather than an empty result.

```bash
set -o pipefail
RANGE_COMMITS=$(git rev-list --no-merges "refs/reassess/$PR_NUMBER-$RUN" --not "$REMOTE/$BASE" |
  xargs -r -n1 git diff-tree -z --no-commit-id --name-only -r --root |
  sort -zu |
  xargs -0r git --literal-pathspecs log --format=%H "$START..$REMOTE/$BASE" -- |
  sort -u) || exit 1
```

The merged PR behind each commit:

```bash
PRS=$(gh api "repos/$REPO/commits/$SHA/pulls") || exit 1
jq -r --arg base "$BASE" '.[] | select(.merged_at != null and .base.ref == $base) | .number' <<<"$PRS"
```

Each closing issue is [read with its repository](ready-for-review.md#read-the-closing-claims). The
PRs naming one:

```bash
gh pr list -R "$REPO" --state all --limit 200 --search "$ISSUE_REF in:body" --json number,state,title,mergedAt \
  --jq "map(select(.number != $PR_NUMBER))" || exit 1
```

- **Pointer**: when checking which PRs a commit lists, fetch
  [list pull requests associated with a commit](https://docs.github.com/en/rest/commits/commits#list-pull-requests-associated-with-a-commit)
  live.
- **As of**: 2026-11-08
- **Recheck trigger**: that section changes which pull requests it returns.

## Read the signals without a checkout

The worktree goes outside the repository, under the worktree root when one is set, holds no files,
and runs no hook. Its `.git` file is all it needs to answer the signals.

```bash
ROOT=$(bash "<plugin-root>/scripts/worktree-root-resolve.sh" --repo-dir "$PWD") || exit 1
[ -n "$ROOT" ] || ROOT=$(dirname "$(git rev-parse --show-toplevel)")
TREE="$ROOT/reassess-${REPO//\//-}-$PR_NUMBER-$RUN"
git -c core.hooksPath=/dev/null worktree add --detach --no-checkout "$TREE" "refs/reassess/$PR_NUMBER-$RUN" || exit 1
( cd "$TREE" && bash "<plugin-root>/scripts/branch-update-signals.sh" --pr "$PR_NUMBER" --repo "$REPO" |
  bash "<plugin-root>/scripts/branch-update-method.sh" )
```

A claim hook can lock the new worktree, so release it before removing it:

```bash
bash "<plugin-root>/scripts/worktree-claim.sh" release "$TREE"
git worktree remove --force "$TREE"
git update-ref -d "refs/reassess/$PR_NUMBER-$RUN"
```

## Pass `--allow-rewrite` only for your own PR

```bash
AUTHOR=$(gh pr view "$PR_NUMBER" -R "$REPO" --json author -q .author.login) || exit 1
[ "$AUTHOR" = "$(gh api user --jq .login)" ]
```

## Disarm auto-merge

Only when `autoMergeRequest` is set:

```bash
gh pr view "$PR_NUMBER" -R "$REPO" --json autoMergeRequest -q '.autoMergeRequest != null'
gh pr merge "$PR_NUMBER" -R "$REPO" --disable-auto
```

## Add the hold label

A failed list or a failed edit ends the run with nothing posted. A list that does not name the
label means no hold was applied, so the close comment renders with `--no-label`:

```bash
LABELS=$(gh label list -R "$REPO" --limit 1000 --json name -q '.[].name') || exit 1
if grep -qix do-not-merge <<<"$LABELS"; then gh pr edit "$PR_NUMBER" -R "$REPO" --add-label do-not-merge || exit 1; fi
```

## Post or edit the comment

The renderer's first line is `<!-- source-control-reassess -->`, and its exit 2 posts nothing. A
re-run edits the newest comment that starts with that marker and was written by the acting login; a
marker on anyone else's comment is ignored. A failed read posts nothing. Under a `label` limit, with
no earlier comment, post nothing.

```bash
BODY=$(bash "<skill-dir>/scripts/reassess-comment.sh" --verdict close --replaced-by "$REPLACED_BY" --evidence "$REF") || exit 1
printf '%s\n' "$BODY" >"$BODY_FILE"
LOGIN=$(gh api user --jq .login) || exit 1
COMMENTS=$(gh api --paginate --slurp "repos/$REPO/issues/$PR_NUMBER/comments") || exit 1
ID=$(jq -r --arg login "$LOGIN" 'add // [] | map(select(.user.login == $login and (.body | startswith("<!-- source-control-reassess -->")))) | last | .id // empty' <<<"$COMMENTS") || exit 1
if [ -n "$ID" ]; then
  gh api --method PATCH "repos/$REPO/issues/comments/$ID" -F body=@"$BODY_FILE" >/dev/null
else
  gh pr comment "$PR_NUMBER" -R "$REPO" --body-file "$BODY_FILE"
fi
```
