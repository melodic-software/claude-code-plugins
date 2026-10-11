# Phase 2.5: Ready for review

The draft-to-ready flip refreshes the base, reviews and verifies the merged head, and only then
marks the PR ready. Entry action: `/source-control:pull-request ready`.

This is not [readiness.md](readiness.md), which holds the gates that decide whether a PR may
**merge**. This file covers the flip alone.

**The order the skill runs follow is the fleet's pre-PR order**, owned by
[`docs/conventions/pre-pr-ordering/README.md`](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/pre-pr-ordering/README.md).
Read the order there. This phase cites it and never states a different one.

## 2.5.1 Refuse without a pull request

Set `BRANCH` to the current branch and look up its PR number into `PR_NUMBER`
([GitHub](../../../reference/providers/github/pull-request/ready-for-review.md#find-the-pr-for-the-branch)).

Empty: stop and report. There is nothing to flip and no head a reviewer can reach. Route to
`/source-control:pull-request create`, which opens the draft this phase flips, rather than opening
one here.

Already out of draft (the PR's draft flag reads `false`;
[GitHub](../../../reference/providers/github/pull-request/ready-for-review.md#read-the-draft-flag)): the
flip is done, so run 2.5.2 and 2.5.3 and skip 2.5.4 and 2.5.5.

## 2.5.2 Refresh the base with a merge

Read the PR's base branch into `BASE`, resolve `REMOTE` with `resolve-remote.sh`, have the forge
merge the base into the head branch, then fetch the head branch from `REMOTE` and fast-forward the
local branch to it
([GitHub](../../../reference/providers/github/pull-request/ready-for-review.md#refresh-the-base-with-a-merge)).

When the head already contains the base tip, the forge's update pushes nothing (the provider
reference records the evidence and its recheck trigger), so the flip adds no push of its own then.

Push any local commits first: `git merge --ff-only FETCH_HEAD` refuses when the local branch
carries commits the remote lacks, and the local-merge fallback below handles that case too.

Where the forge's update is unavailable or refuses (a fork head, a session that cannot reach the
endpoint), do the same thing locally:

```bash
git fetch "$REMOTE" "$BASE" && git merge "$REMOTE/$BASE"
```

Refresh the base with a merge, never a rebase: a rebase of an open pull request needs a force-push
and rewrites commits reviewers have already read. Conflicts route to
`/source-control:resolve-conflicts`, the sibling skill in this plugin.

Completion criterion: `git rev-parse HEAD` equals the PR's head commit
([GitHub](../../../reference/providers/github/pull-request/ready-for-review.md#refresh-the-base-with-a-merge)).
After the forge's update the merge commit exists on the remote only, so the fetch above is what makes the two agree.

## 2.5.3 Review and verify the merged head

Three runs, in the pre-PR order cited at the top of this file. Both reviews run in a fresh-context
subagent, never in the authoring session: hand it the pull request's diff
([GitHub](../../../reference/providers/github/pull-request/ready-for-review.md#read-the-diff)) and the acceptance criteria, not the author's reasoning.

- **Code review of the pull request's diff**, for any diff that is not docs-only: `/code-review`
  against the pull request, or the `review` plugin's reviewer agents when that resolves instead.
  Fix each verified finding (prep.md §1.3), or record why it stays in the pull request body. It
  repeats prep's review because the diff that ships includes the base merge and every fix since.
- **Security review of the same diff**, for any diff that is not docs-only. It runs here rather than
  in prep because it needs the PR to exist. Run `/review:security-review` over that diff when the
  `review` plugin is installed. Without it, run a security-reviewer agent when your environment
  ships one, and otherwise a fresh-context subagent over the diff for the security scope the
  repository's `REVIEW.md` names (trust boundaries, injection, credential exposure, authorization
  gaps, Actions and hook permissions).
- **The verify gate of [prep.md](prep.md) §1.5, last.** The merge moved HEAD, so the gate that ran
  in prep no longer covers the commit that ships. Commit whatever the reviews changed first;
  nothing that edits the tree runs after the gate. When the repository ships
  `scripts/check-affected.sh`, run `scripts/check-affected.sh --tests` first as the
  deterministic gate; exit 1 stops the flip.

Completion criterion: both reviews' findings are fixed or recorded, and the verify gate is
clean on `git rev-parse HEAD`.

## 2.5.4 Flip to ready

When 2.5.3 committed anything, push it all in one push and flip right after it, so the ready run
replaces that push's draft run within seconds instead of after it ran to the end. Push through
`push-branch.sh`, as [create.md](create.md) does: it pushes to the remote `resolve-remote.sh
--push` resolves, so a fork or triangular checkout never pushes to the wrong remote. `--pr` pushes
the pull request's head branch even when the session runs in another worktree, and exits non-zero
when that branch has no local ref or its push remote is not the PR's head repository.

```bash
bash "<skill-dir>/scripts/push-branch.sh" --pr "$PR_NUMBER" || exit 1   # only when 2.5.3 committed anything
```

Then mark the PR ready
([GitHub](../../../reference/providers/github/pull-request/ready-for-review.md#flip-to-ready)).

In a cloud session the CLI flip fails, because the flip is a GraphQL mutation. Two routes work
there: the proxy's REST route, or the GitHub MCP `update_pull_request` call with `draft: false`
([GitHub](../../../reference/providers/github/pull-request/ready-for-review.md#flip-to-ready)).

Completion criterion: the PR's draft flag reads `false`
([GitHub](../../../reference/providers/github/pull-request/ready-for-review.md#read-the-draft-flag)).

## 2.5.5 Hand the pull request to the change digest

After the flip, so the digest reads the head the push just published: when `/review:explain-change`
resolves in this session, invoke it on the pull request with `--event ready`, naming the blast
radius when a plan or `/review:quality-gate downstream` assessed one. Pass neither `--requested`
nor `--policy`: the flip is not a request for the digest, so the resolved `digest_policy` decides,
per the
[review-digest convention](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/review-digest.md):
`off` does nothing, `offer` offers the digest when a trigger fires, and `always` builds it.

The digest gates nothing: no step of this phase or of [readiness.md](readiness.md) reads it. A
skip, an offer nobody has answered yet, or a skill that does not resolve all go on to 2.5.6, and a
reader who accepts the offer later gets the digest then.

## 2.5.6 Report

Report, in this order: the base merge, both reviews' findings and how each was
dispositioned (or the fallback that stood in for a review), the verify gate's result with the head it
ran on, the flip, and the digest outcome (skipped, offered, built, or not available). Then choose who watches the PR from here, per
[watch-handoff.md](watch-handoff.md).
