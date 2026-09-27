# Phase 2.5: Ready for review

The draft-to-ready flip refreshes the base, reviews and verifies the merged head, and only then
marks the PR ready. Entry action: `/source-control:pull-request ready`.

This is not [readiness.md](readiness.md), which holds the gates that decide whether a PR may
**merge**. This file covers the flip alone.

**The order the skill runs follow is the fleet's pre-PR order**, owned by
[`docs/conventions/pre-pr-ordering/README.md`](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/pre-pr-ordering/README.md).
Read the order there. This phase cites it and never states a different one.

## 2.5.1 Refuse without a pull request

```bash
BRANCH=$(git branch --show-current)
PR_NUMBER=$(gh pr view "$BRANCH" --json number -q '.number' 2>/dev/null)
```

Empty: stop and report. There is nothing to flip and no head a reviewer can reach. Route to
`/source-control:pull-request create`, which opens the draft this phase flips, rather than opening
one here.

Already out of draft (`gh pr view "$PR_NUMBER" --json isDraft -q '.isDraft'` prints `false`): the
flip is done, so run 2.5.2 and 2.5.3 and skip 2.5.4.

## 2.5.2 Refresh the base with a merge

```bash
BASE=$(gh pr view "$PR_NUMBER" --json baseRefName -q '.baseRefName')
REMOTE=$(bash "${CLAUDE_PLUGIN_ROOT}/skills/pull-request/scripts/resolve-remote.sh") || exit 1

gh pr update-branch "$PR_NUMBER"                     # merges the base into the head branch
git fetch "$REMOTE" "$BRANCH" && git merge --ff-only FETCH_HEAD
```

Push any local commits first: `git merge --ff-only FETCH_HEAD` refuses when the local branch
carries commits the remote lacks, and the local-merge fallback below handles that case too.

Where `gh pr update-branch` is unavailable or refuses (a fork head, a session that cannot reach the
endpoint), do the same thing locally:

```bash
git fetch "$REMOTE" "$BASE" && git merge "$REMOTE/$BASE"
```

Refresh the base with a merge, never a rebase: a rebase of an open pull request needs a force-push
and rewrites commits reviewers have already read. Conflicts route to
`/source-control:resolve-conflicts`, the sibling skill in this plugin.

Completion criterion: `git rev-parse HEAD` equals
`gh pr view "$PR_NUMBER" --json headRefOid -q '.headRefOid'`. After `gh pr update-branch` the merge
commit exists on the remote only, so the fetch above is what makes the two agree.

## 2.5.3 Review and verify the merged head

Two runs, in the pre-PR order cited at the top of this file:

- **Security review of the pull request's diff** (`gh pr diff "$PR_NUMBER"`), for any diff that is
  not docs-only. It runs here rather than in prep because it needs the PR to exist. Run
  `/review:security-review` over that diff when the `review` plugin is installed. Without it, run a
  security-reviewer agent when your environment ships one, and otherwise review the diff inline for
  the security scope the repository's `REVIEW.md` names (trust boundaries, injection, credential
  exposure, authorization gaps, Actions and hook permissions).
- **The verify gate of [prep.md](prep.md) §1.5, last.** The merge moved HEAD, so the gate that ran
  in prep no longer covers the commit that ships. Commit whatever the security review changed first;
  nothing that edits the tree runs after the gate.

Completion criterion: the security review's findings are dispositioned, and the verify gate is
clean on `git rev-parse HEAD`.

## 2.5.4 Flip to ready

```bash
gh pr ready "$PR_NUMBER"
```

In a cloud session `gh pr ready` fails, because the flip is a GraphQL mutation. Two routes work
there. The proxy's REST route:

```bash
gh api --method POST "repos/{owner}/{repo}/pulls/$PR_NUMBER/ccr/ready_for_review"
```

Or the GitHub MCP `update_pull_request` call with `draft: false`.

Completion criterion: `gh pr view "$PR_NUMBER" --json isDraft -q '.isDraft'` prints `false`.

## 2.5.5 Report

Report, in this order: the base merge, the security review's findings and how each was
dispositioned (or the fallback that stood in for it), the verify gate's result with the head it
ran on, and the flip. Then hand monitoring off to `/source-control:pull-request monitor`.
