#!/usr/bin/env bash
# queue-ahead.sh <main-sha> <head-sha>
#
# Read main's merge queue for the merge job of release-publish-plugins.yml in one
# GraphQL call. Run from a checkout holding both commits, with GH_TOKEN and
# GITHUB_REPOSITORY set. Prints:
#   queue=<id>    the merge queue's id, empty when main has none
#   ahead=<why>   one line per queued pull request that changes a file the
#                 release changes (git diff <main-sha>...<head-sha>), or that the
#                 read cannot list in full, which counts as one
# Queued behind such an entry, the release fails its merge group's release gate
# (check-changelog-fragments.sh --check-release, CHANGED ON BASE) once that
# entry lands, and each removal re-runs every group queued behind it. Exit 0
# read, anything else an error.
set -euo pipefail
: "${GITHUB_REPOSITORY:?}"
main_sha=$1 head_sha=$2
released="$(git diff --name-only "$main_sha...$head_sha" | jq -Rsc 'split("\n") | map(select(length > 0))')"
# shellcheck disable=SC2016  # the $ names are GraphQL variables, not shell
gh api graphql -f owner="${GITHUB_REPOSITORY%/*}" -f name="${GITHUB_REPOSITORY#*/}" \
  -f query='query($owner: String!, $name: String!) { repository(owner: $owner, name: $name) { mergeQueue(branch: "main") { id entries(first: 100) { totalCount nodes { pullRequest { number files(first: 100) { totalCount nodes { path } } } } } } } }' |
  jq -r --argjson released "$released" '
    (.data.repository // error("the response holds no repository")).mergeQueue as $q
    | "queue=\($q.id // "")",
      ($q // empty
        | (if .entries.totalCount > (.entries.nodes | length) then "ahead=more than \(.entries.nodes | length) pull requests are queued" else empty end),
          (.entries.nodes[].pullRequest // empty
            | (.files.nodes | map(.path) | map(select(IN($released[])))) as $both
            | if ($both | length) > 0 then "ahead=#\(.number) changes \($both[0])"
              elif .files.totalCount > (.files.nodes | length) then "ahead=#\(.number) changes more than \(.files.nodes | length) files"
              else empty end))'
