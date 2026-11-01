#!/usr/bin/env bash
# decide-rebuild.sh <main-sha>
#
# Decide whether release-publish-plugins.yml rebuilds the release pull request.
# Run from the root of a full-history checkout of <main-sha> (main's tip), with
# GH_TOKEN, GITHUB_REPOSITORY and GITHUB_EVENT_NAME set. Writes to $GITHUB_OUTPUT:
#   found    whether a release pull request is open
#   id, number, head    that pull request, when found
#   rebuild  false while it is in the merge queue; otherwise true when none is
#            open, when it has a merge conflict, when main changed a file it
#            changes (a fragment it consumed, a CHANGELOG.md, a plugin.json)
#            since its build base, or when its GitHub Actions ci-status failed
#            (ci-status.sh) on a base behind main with no hold label
#            (label-holds.mjs). Fragments main added since the build base do not
#            count: they ride the next release (ADR 0048, The release pull
#            request and the 2026-10-20 amendment)
#   deferred true when a push run would have rebuilt an open one while its
#            ci-status is pending or any GitHub Actions check run on its head
#            has not completed (only the second on a conflicted head, which
#            gets no pull_request run): each rebuild cancels the release pull
#            request's running checks, so a later run decides again: a fragment
#            push once they finish, or the next scheduled or dispatched run
#            (ADR 0048, 2026-10-31 amendment). Absent otherwise.
# A gate run leaves the tree detached at <main-sha>. Exit 0 decided, anything
# else an error.
set -euo pipefail
: "${GITHUB_REPOSITORY:?}" "${GITHUB_OUTPUT:?}" "${GITHUB_EVENT_NAME:?}"
# Resolved before the checkouts below move the tree; the read runs on main's.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# rebuild <head> <ci> <annotation> <why>: rebuild, or on a push with <head>'s
# ci-status pending or any of its check runs unfinished leave it to a later run.
# <ci> is a ci-status already read, none when it cannot decide, or empty. A
# failed read stops the run, so it never cancels checks it could not see.
rebuild() {
  local head=$1 ci=$2 annotation=$3 why=$4 unfinished="" running=""
  if [[ $GITHUB_EVENT_NAME == push ]]; then
    if [[ -z $ci ]]; then
      ci="$("$here/ci-status.sh" "$head")"
    fi
    if [[ $ci != pending ]]; then
      unfinished="$("$here/ci-status.sh" --unfinished "$head")"
      running=${unfinished:+ (${unfinished//$'\n'/, })}
    fi
  fi
  if [[ $ci == pending || -n $unfinished ]]; then
    echo "::notice::$why; its checks are running or have not started$running, so a later run decides again."
    printf 'rebuild=false\ndeferred=true\n' >>"$GITHUB_OUTPUT"
  else
    echo "$annotation$why; rebuilding."
    echo "rebuild=true" >>"$GITHUB_OUTPUT"
  fi
}

decide() {
  local main_sha=$1 pr id number head queued held="" ci="" rc=0
  pr="$(gh pr list --repo "$GITHUB_REPOSITORY" --head release/plugins --base main --state open \
    --json id,number,headRefOid,mergeable,isCrossRepository,labels --jq '[.[] | select(.isCrossRepository | not)][0] // empty')"
  if [[ -z $pr ]]; then
    # With none open there are no checks to cancel, so every run builds one.
    echo "No release pull request is open; building one."
    printf 'found=false\nrebuild=true\n' >>"$GITHUB_OUTPUT"
    return
  fi
  number="$(jq -r .number <<<"$pr")"
  head="$(jq -r .headRefOid <<<"$pr")"
  id="$(jq -r .id <<<"$pr")"
  printf 'found=true\nid=%s\nnumber=%s\nhead=%s\n' "$id" "$number" "$head" >>"$GITHUB_OUTPUT"
  # GitHub refuses to update a queued branch (HTTP 422). Leave a queued release
  # to the queue: it merges, or the queue removes it and a later run decides it
  # again against main's tip. A merged release leaves any fragment it missed on
  # main for the next release.
  # A failed lookup stops the run here, before any ref write.
  # shellcheck disable=SC2016  # the $ names are GraphQL variables, not shell
  queued="$(gh api graphql -f id="$id" \
    -f query='query($id: ID!) { node(id: $id) { ... on PullRequest { isInMergeQueue } } }' \
    --jq '.data.node.isInMergeQueue')"
  if [[ $queued == true ]]; then
    echo "::notice::Release pull request #$number is in the merge queue; not rebuilding it. If the queue ejects it, a later run decides it again."
    echo "rebuild=false" >>"$GITHUB_OUTPUT"
    return
  fi
  if [[ "$(jq -r .mergeable <<<"$pr")" == CONFLICTING ]]; then
    # A conflicted head gets no pull_request run, so its ci-status stays pending.
    rebuild "$head" none "" "Release pull request #$number has a merge conflict"
    return
  fi
  git fetch -q --no-tags origin "$head"
  git checkout -q --detach "$head"
  # Run main's copy of the gate, without the App token: the head is the branch
  # under review. The gate compares main with the head's build base, its merge
  # base with main: the build job cuts the head as one commit on main's tip.
  git checkout -q "$main_sha" -- scripts
  env -u GH_TOKEN scripts/check-changelog-fragments.sh --check-release "$main_sha" || rc=$?
  git checkout -q -f --detach "$main_sha"
  case "$rc" in
    0)
      # A failed check on a base behind main never clears on a re-run; rebuild on
      # main's tip. A hold label's red never clears on a rebuild, which would
      # only change held content.
      if ! git merge-base --is-ancestor "$main_sha" "$head"; then
        ci="$("$here/ci-status.sh" "$head")"
      fi
      if [[ $ci == failure ]]; then
        held="$(node "$here/label-holds.mjs" <<<"$pr")"
      fi
      if [[ -n $held ]]; then
        echo "::notice::ci-status failed on release pull request #$number; not rebuilding it: ${held//$'\n'/ }"
        echo "rebuild=false" >>"$GITHUB_OUTPUT"
      elif [[ $ci == failure ]]; then
        rebuild "$head" "$ci" ::warning:: "ci-status failed on release pull request #$number and its base is behind main"
      else
        echo "Release pull request #$number changes no file main changed since its build base."
        echo "rebuild=false" >>"$GITHUB_OUTPUT"
      fi
      ;;
    1)
      rebuild "$head" "" ::warning:: "Main changed a file release pull request #$number changes since its build base"
      ;;
    *) return "$rc" ;;
  esac
}

# The checkouts above rewrite this file's path; bash has parsed the whole
# function before it runs, so the call below is all that is read after them.
decide "$@"
