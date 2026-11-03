# 2.2 Rebase onto the latest default branch

Part of [Phase 2: Create](create.md), which lists every section's file; a bare § number names a section listed there.

Bring the branch current with the default branch before pushing, to prevent merge conflicts and stale-branch CI failures.

**This step keeps its rebase, and it is the last place one is allowed.** It runs before the first push, when no PR exists and no reviewer has read a commit, so rewriting SHAs costs nothing. Once the PR exists, every base refresh is a merge, per [ready-for-review.md](ready-for-review.md) §2.5.2: a rebase then needs a force-push and rewrites commits reviewers have read.

**Ordering: rebase needs a clean tree.** `git rebase` refuses to run with unstaged changes (`error: cannot rebase: You have unstaged changes.`). On the normal `create` path the PR changes are still uncommitted here, so run 2.3 (classify unrelated changes + stage + commit) FIRST, then return and integrate before the 2.4 push. Run 2.2 in listed order only when the tree is already clean (all work committed).

First set `DEFAULT_BRANCH` to the repository's default branch ([GitHub](../../../reference/providers/github/README.md#identity-and-repository)), then:

```bash
# Resolve the FETCH remote that hosts the default branch via the shared resolver
# (scripts/resolve-remote.sh): the current branch's configured remote
# (branch.<name>.remote), else `origin`, else the sole OTHER configured remote
# when exactly one exists — never a hardcoded `origin`, so a repo cloned with a
# different remote name (`git clone -o vendor`) still resolves. A local-only
# upstream (`.`) is treated as unset. Two or more non-origin candidates with
# neither branch.<name>.remote nor `origin` set is ambiguous and the resolver
# fails loudly rather than silently picking one. The §2.4.1 push step calls the
# same resolver with `--push`, which prepends Git's push precedence
# (branch.<name>.pushRemote / remote.pushDefault) so a triangular fork flow —
# fetch from `upstream`, push to the fork — resolves each side correctly instead
# of pushing to the fetch remote.
REMOTE=$(bash "<skill-dir>/scripts/resolve-remote.sh") || exit 1

git fetch "$REMOTE" "$DEFAULT_BRANCH"
MERGE_BASE=$(git merge-base HEAD "$REMOTE/$DEFAULT_BRANCH")
REMOTE_DEFAULT=$(git rev-parse "$REMOTE/$DEFAULT_BRANCH")

if [ "$MERGE_BASE" != "$REMOTE_DEFAULT" ]; then
  BEHIND=$(git rev-list --count HEAD.."$REMOTE/$DEFAULT_BRANCH")
  echo "Branch is $BEHIND commit(s) behind $REMOTE/$DEFAULT_BRANCH. Rebasing..."
  git rebase "$REMOTE/$DEFAULT_BRANCH"
fi
```

**Prefer `git merge $REMOTE/$DEFAULT_BRANCH` over rebase when the branch already contains a merge commit** (`git log --merges $REMOTE/$DEFAULT_BRANCH..HEAD` non-empty): replaying pre-merge commits causes avoidable conflicts, and under squash-merge linear history buys nothing.

**If conflicts occur:** resolve conservatively: take both sides where independent, and pause and present to the user whenever intent is unclear. `git rebase --abort` / `git merge --abort` when resolution needs judgment you don't have.

**Skip conditions:** zero commits ahead (nothing to rebase), or merge-base already equals `$REMOTE/$DEFAULT_BRANCH` (branch is current).

**Sandboxed sessions: resolve the default branch over REST.** The CLI's repository read sends the same GraphQL query as its PR create, so this is the *first* step on the normal `create` path to fail with `HTTP 403` when the GitHub proxy refuses GraphQL. [§2.4.0](create-linked-issue.md) has the full restriction and the placeholder-anchoring rule. Substitute the REST repository read ([GitHub](../../../reference/providers/github/pull-request/create.md#default-branch-over-rest)).
