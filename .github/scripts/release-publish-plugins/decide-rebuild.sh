#!/usr/bin/env bash
set -euo pipefail
: "${GITHUB_REPOSITORY:?}" "${GITHUB_OUTPUT:?}" "${GITHUB_EVENT_NAME:?}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
    echo "No release pull request is open; building one."
    printf 'found=false\nrebuild=true\n' >>"$GITHUB_OUTPUT"
    return
  fi
  number="$(jq -r .number <<<"$pr")"
  head="$(jq -r .headRefOid <<<"$pr")"
  id="$(jq -r .id <<<"$pr")"
  printf 'found=true\nid=%s\nnumber=%s\nhead=%s\n' "$id" "$number" "$head" >>"$GITHUB_OUTPUT"
  # A failed lookup stops the run here, before any ref write.
  # shellcheck disable=SC2016  # the $ names are GraphQL variables, not shell
  queued="$(gh api graphql -f id="$id" \
    -f query='query($id: ID!) { node(id: $id) { ... on PullRequest { isInMergeQueue } } }' \
    --jq '.data.node.isInMergeQueue')"
  if [[ $queued == true ]]; then
    echo "::notice::Release pull request #$number is in the merge queue at $head; not rebuilding it. If the queue ejects it, a later run decides it again."
    echo "rebuild=false" >>"$GITHUB_OUTPUT"
    return
  fi
  if [[ "$(jq -r .mergeable <<<"$pr")" == CONFLICTING ]]; then
    rebuild "$head" none "" "Release pull request #$number has a merge conflict"
    return
  fi
  git fetch -q --no-tags origin "$head"
  git checkout -q --detach "$head"
  git checkout -q "$main_sha" -- scripts
  env -u GH_TOKEN scripts/check-changelog-fragments.sh --check-release "$main_sha" || rc=$?
  git checkout -q -f --detach "$main_sha"
  case "$rc" in
    0)
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
        held="$(node "$here/label-holds.mjs" --queue <<<"$pr")"
        if [[ -n $held ]]; then
          echo "::notice::Release pull request #$number carries a hold label; not queuing it: ${held//$'\n'/ }"
          echo "held=true" >>"$GITHUB_OUTPUT"
        fi
        echo "rebuild=false" >>"$GITHUB_OUTPUT"
      fi
      ;;
    1)
      rebuild "$head" "" ::warning:: "Main changed a file release pull request #$number changes since its build base"
      ;;
    *) return "$rc" ;;
  esac
}

decide "$@"
