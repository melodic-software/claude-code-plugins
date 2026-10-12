# babysit-prs loop on GitHub

This file serves the babysit-prs [loop spoke](../../../../skills/babysit-prs/reference/loop.md):
it holds the GitHub commands for the operations that spoke names. The spoke owns every rule,
order and threshold around them. The [GitHub provider reference](../README.md) indexes the other
operations.

## PR discovery

Your own open PRs, oldest first (spoke §5.0.2):

```bash
gh pr list --state open --author "@me" --limit 200 \
  --json number,title,headRefName,isDraft,author --jq 'sort_by(.number)'
```

`@me` is your `gh api user --jq .login` identity. For each extra posting identity, run the same
listing with `--author <login>` in place of `--author "@me"`.

## Per-PR rescan reads

- Terminal check (spoke §5.0.3 step 1): `gh pr view <N> --json state -q '.state'`. The checklist's
  step A is the same read, `gh pr view <N> --json state`.
- CI check, one-off read (§5.0.3 step 2): `gh pr checks <N> --json bucket -q '[.[] | .bucket] | unique'`.
  A pending check is never waited on with `gh pr checks --watch`, which blocks the foreground. The
  Monitor fallback (§5.1.1) is a 30s REST `gh api` poll instead.
- The comment fetch script derives owner/repo from the current directory via `gh repo view`.
- The true PR head the checklist asserts against (§5.1.3): `gh pr view --json headRefOid`.
- The readiness gate's exit 3 with `reason=identity-unresolved` means the `gh api user` identity
  lookup failed: repair `gh` auth rather than editing the command.
- The §5.5 report's CI evidence is the `gh pr checks <N>` output.

## Branch checkout and push destination

The spoke's §5.1.2 procedure. It takes `$PR_NUMBER`, `<headRefName>` and `<watched-owners>`, sets
`CHECKOUT_MODE`, `PUSH_REMOTE` and `INTEGRATION_STATUS`, and defines `lane_push`. The file names
in its comments (`safety.md`, `orchestration.md`) are the babysit-prs spokes.

```bash
# Decide checkout mode by asserting this worktree's HEAD against the TRUE PR head
# — `gh pr view … headRefOid`, queried live, authoritative for same-repo and
# fork PRs alike (never a possibly-stale `origin/<branch>` remote-tracking ref,
# which is itself the silent-revert vector this guards; safety.md, Checkout And
# Push Invariants). Acquire the head with `gh pr checkout`, never a bare
# fetch/checkout by branch name. Mutate only when HEAD == the PR head; otherwise
# read-only. Only the fetch of the default branch (always on origin) is done up
# front, for the freshness merge below.
BRANCH="<headRefName>"
PR_HEAD=$(gh pr view "$PR_NUMBER" --json headRefOid -q .headRefOid)
CUR_WT=$(git rev-parse --show-toplevel)
CUR_BRANCH=$(git symbolic-ref --short -q HEAD || true)  # empty when detached
DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)
git fetch origin "$DEFAULT_BRANCH"
if [ -n "$(git status --porcelain)" ]; then
  # Uncommitted changes may be another session's WIP — never reset/clean work
  # this loop did not create.
  echo "Working tree has uncommitted changes (possibly another session's WIP) — processing read-only"
  CHECKOUT_MODE="read-only"
elif [ "$(git rev-parse HEAD)" = "$PR_HEAD" ] && { [ -z "$CUR_BRANCH" ] || [ "$CUR_BRANCH" = "$BRANCH" ]; }; then
  # HEAD already IS the true PR head AND we are on $BRANCH or detached — not some
  # other local branch that merely points at the same commit (a fix committed there
  # would advance that unrelated branch while only the refspec push lands on
  # $BRANCH). A coincidental same-tip match on another branch falls through to the
  # gh pr checkout paths below, which put us on the actual PR head.
  CHECKOUT_MODE="full"
elif git worktree list | grep -vF "$CUR_WT " | grep -q "\[$BRANCH\]"; then
  # Branch locked in a sibling worktree — `git checkout $BRANCH` here dead-ends
  # (`already used by worktree at ...`). `gh pr checkout --detach` resolves the
  # head for same-repo AND fork PRs; operate in detached HEAD at it and push by
  # refspec below.
  gh pr checkout "$PR_NUMBER" --detach
  [ "$(git rev-parse HEAD)" = "$PR_HEAD" ] && CHECKOUT_MODE="full" || CHECKOUT_MODE="read-only"
else
  # gh pr checkout heals a behind-origin local branch up to the true head and
  # handles fork-sourced PRs; a genuinely divergent local (unpushed commits)
  # leaves HEAD != PR_HEAD and correctly falls to read-only.
  gh pr checkout "$PR_NUMBER"
  [ "$(git rev-parse HEAD)" = "$PR_HEAD" ] && CHECKOUT_MODE="full" || CHECKOUT_MODE="read-only"
fi

# Resolve the push destination ONCE, here, for EVERY full-mode push path — the
# freshness push, the conflict-continue push, and the §5.1.4 fix-cycle push all
# read $PUSH_REMOTE. FAIL CLOSED: a same-repo head pushes to origin; a fork head
# pushes to the destination whose URL resolves to the PR HEAD repository.
# Validate the fork destination by URL, NOT by name: `gh pr checkout` wires the
# branch to whatever remote (or bare URL) reaches the head, and when it cannot
# create a writable fork remote it may point the branch at the base checkout
# remote — commonly named `upstream`, but any name — so accepting any non-origin
# name would push to the BASE repo, writing a same-named branch there instead of
# updating the fork head (the cross-repo regression this guards; safety.md).
# `branch.<b>.pushRemote`/`remote` may hold a remote name OR a URL, and a named
# remote can carry separate `pushurl`(s) that `git push` honors — so resolve the
# actual PUSH urls (`git remote get-url --push --all`) and canonicalize EACH to
# host + owner/repo, then require EVERY one to equal the head repo's own canonical
# URL (`gh api repos/<nameWithOwner> --jq .html_url`), else read-only. A cross-repo
# head is additionally gated on its owner being within <watched-owners>. This
# rejects a same-path remote on a DIFFERENT host, a fork fetch url masking a base
# pushurl, an extra base/attacker pushurl past a matching first one, and an
# external-fork head outside the trust boundary.
if [ "$CHECKOUT_MODE" = "full" ]; then
  if [ "$(gh pr view "$PR_NUMBER" --json isCrossRepository -q .isCrossRepository)" = "false" ]; then
    PUSH_REMOTE=origin
  else
    # Canonicalize each line of stdin — scheme://[user@]host[:port]/owner/repo,
    # user@host:owner/repo, or a bare host/owner/repo — to host/owner/repo so the
    # comparison includes the HOST, not just the path: a same-path remote on a
    # different host (git@evil.example.com:owner/repo) must NOT satisfy it.
    canon() { sed -E 's#\.git$##; s#/+$##; s#^[a-zA-Z][a-zA-Z0-9+.-]*://##; s#^[^/@]*@##; s#:[0-9]+/#/#; s#:#/#'; }
    HEAD_REPO=$(gh pr view "$PR_NUMBER" --json headRepository -q .headRepository.nameWithOwner)
    # Trust boundary: a cross-repo head is writable only when its owner is within
    # <watched-owners> (safety.md Stop And Ask — an external-fork head outside the
    # watched owners stays read-only even with maintainer edits enabled). Enforce it
    # before accepting the fork remote so the pure-bash degrade path never pushes to
    # a repository outside the trust boundary.
    HEAD_OWNER=${HEAD_REPO%%/*}
    case ",<watched-owners>," in
      *",$HEAD_OWNER,"*) : ;;
      *) echo "Cross-repo head owner $HEAD_OWNER outside <watched-owners> — read-only"; CHECKOUT_MODE="read-only" ;;
    esac
    # headRepository carries no URL; canonicalize the head repo's authoritative
    # html_url (a fork head is always on the base instance).
    HEAD_ID=$(gh api "repos/$HEAD_REPO" --jq .html_url 2>/dev/null | canon)
    # git push consults pushRemote before remote; either may be a remote NAME or a
    # URL, and it writes to EVERY configured push url (`--push --all`; `--push`
    # honors remote.<name>.pushurl, which can differ from the fetch url). Require ALL
    # of them to canonicalize to the head repo — any non-matching line (an extra
    # base-repo or attacker pushurl past a matching first one) fails closed. A
    # bare-URL config value is not a known remote, so get-url errors and the literal
    # value is validated instead.
    PUSH_REMOTE=$(git config --get "branch.$BRANCH.pushRemote" \
      || git config --get "branch.$BRANCH.remote" || true)
    PUSH_URLS=$(git remote get-url --push --all "$PUSH_REMOTE" 2>/dev/null || printf '%s\n' "$PUSH_REMOTE")
    BAD=$(printf '%s\n' "$PUSH_URLS" | canon | grep -vxF "$HEAD_ID" || true)
    if [ -z "$PUSH_REMOTE" ] || [ -z "$HEAD_ID" ] || [ -z "$PUSH_URLS" ] || [ -n "$BAD" ]; then
      echo "Fork push URL(s) do not all resolve to the PR head repo ($HEAD_ID) — read-only"
      CHECKOUT_MODE="read-only"
    fi
  fi
fi

# EVERY lane push goes through lane_push: it turns auto-merge off immediately
# before the push and again right after it (the merge lane may re-arm the old
# head mid-push), because a push keeps auto-merge armed and the new head could
# merge on ci-status alone before the AI reviews re-run (safety.md, "Merge-lane
# auto-merge"). It never re-arms; that stays with the merge lane. A failed read
# or disarm stops the push.
disarm_auto_merge() {
  ARMED=$(gh pr view "$PR_NUMBER" --json autoMergeRequest --jq '.autoMergeRequest // empty') || return 1
  [ -z "$ARMED" ] || gh pr merge "$PR_NUMBER" --disable-auto
}
lane_push() {
  disarm_auto_merge && git push "$PUSH_REMOTE" "HEAD:$BRANCH" && disarm_auto_merge
}

# Branch freshness — MERGE-ONLY (full mode only). Rebasing would rewrite history
# and require a force-push, which safety.md ("Never Do Automatically") and
# orchestration.md's never-force-push invariant forbid; the final squash merge
# flattens interim history, so a merge commit here costs nothing the skill cares
# about.
if [ "$CHECKOUT_MODE" = "full" ]; then
  if ! git merge-base --is-ancestor "origin/$DEFAULT_BRANCH" HEAD; then
    echo "Branch $BRANCH is behind origin/$DEFAULT_BRANCH — merging"
    git merge --no-edit "origin/$DEFAULT_BRANCH"
    MERGE_EXIT=$?
    if [ "$MERGE_EXIT" -eq 0 ]; then
      INTEGRATION_STATUS="integrated"
      # Push by refspec (works from a detached HEAD too) to the pre-resolved
      # $PUSH_REMOTE; fast-forward given the head assertion, never force. A
      # rejected non-fast-forward push means the head moved: re-fetch and stop.
      lane_push
    else
      # Graduated conflict handling — attempt simple, abort complex.
      # conflict-attempting is a TRANSIENT state: resolve it (git merge
      # --continue) or abort BEFORE any further processing — never leave an
      # integration in progress (unmerged paths break later checkouts + parking).
      CONFLICT_COUNT=$(git diff --name-only --diff-filter=U | grep -c . || true)
      if [ "$CONFLICT_COUNT" -le 3 ]; then
        echo "Simple conflict ($CONFLICT_COUNT files) — attempting resolution"
        INTEGRATION_STATUS="conflict-attempting"
      else
        echo "Complex conflict ($CONFLICT_COUNT files) — aborting merge"
        git merge --abort
        INTEGRATION_STATUS="conflict-aborted"
      fi
    fi
  else
    INTEGRATION_STATUS="current"
  fi

  # conflict-attempting: resolve NOW — per file, take the mechanical resolution;
  # if ANY file needs intent judgment, `git merge --abort` and set
  # INTEGRATION_STATUS="conflict-aborted". On success: `git add <files>` +
  # `git merge --continue`, then `lane_push` (fast-forward, never force). Set INTEGRATION_STATUS="integrated". Only terminal states pass here.

  # Safe fallback: ONLY the terminal success states keep full mode. A
  # lingering conflict-attempting (resolution skipped) degrades to read-only
  # rather than granting write access mid-merge.
  if [ "$INTEGRATION_STATUS" != "integrated" ] && [ "$INTEGRATION_STATUS" != "current" ]; then
    CHECKOUT_MODE="read-only"
  fi
fi
```

## Merging stays out of this loop

The loop never runs `gh pr merge`, and never calls the async merge API (`gh api …/merge-async`).
