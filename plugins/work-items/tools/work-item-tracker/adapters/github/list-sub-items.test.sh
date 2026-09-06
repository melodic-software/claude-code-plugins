#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced helper
# Offline contract stub — the GitHub subIssues + intersect path needs live gh, so
# its behavior is exercised by the on-demand e2e-probe; here we assert only the
# skill-script contract (--help) and the pre-I/O usage-error paths.
set -uo pipefail
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/list-sub-items.sh"
source "$(dirname "$S")/../../lib/verb-test-helpers.sh"

assert_help "$S"
assert_usage_error "$S"                              # no parent id
assert_usage_error "$S" "github:o/r#1" --state bogus # bad state
assert_usage_error "$S" "not-an-id"                  # malformed id
assert_usage_error "$S" "local-markdown:o/r#1"       # foreign provider

# --- container rollup over the real gh subIssues shape (#3825) ---------------
# A gh stub serving the projection gh 2.97 actually returns — subIssues nodes
# with NO `repository` object — proves the enumeration survives it end to end.
# The predicate this replaced (`.repository.nameWithOwner == $repo`) returned an
# empty item list here, which is exactly the reported bug.
if command -v jq >/dev/null 2>&1; then
  STUB_DIR="$(mktemp -d)"
  cat >"$STUB_DIR/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "--version" ]]; then
  printf 'gh version 2.97.0 (test)\n'
  exit 0
fi
if [[ "$1" == "issue" && "$2" == "view" ]]; then
  cat <<'JSON'
{"subIssues":{"nodes":[
  {"id":"I_a","number":11,"state":"OPEN","title":"child open","url":"https://github.com/o/r/issues/11"},
  {"id":"I_b","number":12,"state":"CLOSED","title":"child closed","url":"https://github.com/o/r/issues/12"},
  {"id":"I_c","number":13,"state":"OPEN","title":"foreign child","url":"https://github.com/other/repo/issues/13"}
],"totalCount":3}}
JSON
  exit 0
fi
if [[ "$1" == "issue" && "$2" == "list" ]]; then
  cat <<'JSON'
[
  {"number":11,"title":"child open","state":"OPEN","assignees":[],"labels":[],"issueType":null,"blockedBy":{"nodes":[]},"url":"https://github.com/o/r/issues/11"},
  {"number":12,"title":"child closed","state":"CLOSED","assignees":[],"labels":[],"issueType":null,"blockedBy":{"nodes":[]},"url":"https://github.com/o/r/issues/12"},
  {"number":13,"title":"unrelated same-numbered issue","state":"OPEN","assignees":[],"labels":[],"issueType":null,"blockedBy":{"nodes":[]},"url":"https://github.com/o/r/issues/13"},
  {"number":99,"title":"not a child","state":"OPEN","assignees":[],"labels":[],"issueType":null,"blockedBy":{"nodes":[]},"url":"https://github.com/o/r/issues/99"}
]
JSON
  exit 0
fi
printf 'unexpected gh call: %s\n' "$*" >&2
exit 1
EOF
  chmod +x "$STUB_DIR/gh"

  SUBS="$(PATH="$STUB_DIR:$PATH" bash "$S" "github:o/r#1" --state all)"
  IDS="$(jq -c '[.items[].id]' <<<"$SUBS")"
  assert_eq "container with sub-issues rolls up its same-repo children" \
    '["github:o/r#11","github:o/r#12"]' "$IDS"
  assert_not_contains "cross-repo sub-issue number does not pull in the local same-numbered issue" \
    "$IDS" "github:o/r#13"
  assert_not_contains "non-child rows stay out" "$IDS" "github:o/r#99"
  assert_eq "children are re-parented to the container" \
    '["github:o/r#1","github:o/r#1"]' "$(jq -c '[.items[].parent_id]' <<<"$SUBS")"

  rm -rf "$STUB_DIR"
fi

[[ $FAILED -eq 0 ]] || exit 1
