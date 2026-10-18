#!/usr/bin/env bash
# decide-rebuild.sh <main-sha>
#
# Decide whether release-publish-plugins.yml rebuilds the release pull request.
# Run from the root of a full-history checkout of <main-sha> (main's tip), with
# GH_TOKEN and GITHUB_REPOSITORY set. Writes to $GITHUB_OUTPUT:
#   found    whether a release pull request is open
#   id, number, head    that pull request, when found
#   rebuild  false while it is in the merge queue; otherwise true when none is
#            open, when it has a merge conflict, when main holds a fragment it
#            did not consume for a plugin it bumps (or one it consumed has
#            changed), or when its ci-status failed on a base behind main
#            (ADR 0048, The release pull request)
# A gate run leaves the tree detached at <main-sha>. Exit 0 decided, anything
# else an error.
set -euo pipefail

decide() {
  local main_sha=$1 pr id number head queued rc=0
  : "${GITHUB_REPOSITORY:?}" "${GITHUB_OUTPUT:?}"
  pr="$(gh pr list --repo "$GITHUB_REPOSITORY" --head release/plugins --base main --state open \
    --json id,number,headRefOid,mergeable,isCrossRepository --jq '[.[] | select(.isCrossRepository | not)][0] // empty')"
  if [[ -z $pr ]]; then
    echo "No release pull request is open; building one."
    printf 'found=false\nrebuild=true\n' >>"$GITHUB_OUTPUT"
    return
  fi
  number="$(jq -r .number <<<"$pr")"
  head="$(jq -r .headRefOid <<<"$pr")"
  id="$(jq -r .id <<<"$pr")"
  printf 'found=true\nid=%s\nnumber=%s\nhead=%s\n' "$id" "$number" "$head" >>"$GITHUB_OUTPUT"
  # GitHub refuses to update a queued branch (HTTP 422). Leave a queued release
  # to the queue: it merges, or the merge_group fragment gate ejects it and the
  # next scheduled or fragment-push run rebuilds it from main's tip. A merged
  # release leaves any fragment it missed on main for the next release.
  # A failed lookup stops the run here, before any ref write.
  # shellcheck disable=SC2016  # the $ names are GraphQL variables, not shell
  queued="$(gh api graphql -f id="$id" \
    -f query='query($id: ID!) { node(id: $id) { ... on PullRequest { isInMergeQueue } } }' \
    --jq '.data.node.isInMergeQueue')"
  if [[ $queued == true ]]; then
    echo "::notice::Release pull request #$number is in the merge queue; not rebuilding it. If the queue ejects it, the next run rebuilds it."
    echo "rebuild=false" >>"$GITHUB_OUTPUT"
    return
  fi
  if [[ "$(jq -r .mergeable <<<"$pr")" == CONFLICTING ]]; then
    echo "Release pull request #$number has a merge conflict; rebuilding."
    echo "rebuild=true" >>"$GITHUB_OUTPUT"
    return
  fi
  git fetch -q --no-tags origin "$head"
  git checkout -q --detach "$head"
  # Run main's copy of the gate, without the App token: the head is the branch under review.
  git checkout -q "$main_sha" -- scripts
  env -u GH_TOKEN scripts/check-changelog-fragments.sh --check-release "$main_sha" || rc=$?
  git checkout -q -f --detach "$main_sha"
  case "$rc" in
  0)
    # A failed check on a base behind main never clears on a re-run; rebuild on main's tip.
    if ! git merge-base --is-ancestor "$main_sha" "$head" &&
      [[ "$(gh api "repos/$GITHUB_REPOSITORY/commits/$head/check-runs?check_name=ci-status" \
        --jq '.check_runs | sort_by(.started_at) | last | .conclusion // "pending"')" == failure ]]; then
      echo "::warning::ci-status failed on release pull request #$number and its base is behind main; rebuilding it."
      echo "rebuild=true" >>"$GITHUB_OUTPUT"
    else
      echo "Release pull request #$number consumes every pending fragment for the plugins it bumps."
      echo "rebuild=false" >>"$GITHUB_OUTPUT"
    fi
    ;;
  1)
    echo "::warning::Release pull request #$number is stale against main; rebuilding it."
    echo "rebuild=true" >>"$GITHUB_OUTPUT"
    ;;
  *) return "$rc" ;;
  esac
}

# The checkouts above rewrite this file's path; bash has parsed the whole
# function before it runs, so the call below is all that is read after them.
decide "$@"
