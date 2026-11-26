#!/usr/bin/env bash
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
