#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced helper
# Offline: the skill-script contract (--help), the pre-I/O usage-error paths, and
# the subIssues + intersect path against a gh stub that reproduces gh's real
# `--json subIssues` projection. End-to-end behavior against the live provider
# stays with the on-demand e2e-probe.
set -uo pipefail
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/list-sub-items.sh"
source "$(dirname "$S")/../../lib/verb-test-helpers.sh"

assert_help "$S"
assert_usage_error "$S"                              # no parent id
assert_usage_error "$S" "github:o/r#1" --state bogus # bad state
assert_usage_error "$S" "not-an-id"                  # malformed id
assert_usage_error "$S" "local-markdown:o/r#1"       # foreign provider

# --- subIssues nodes carry no `repository`, so the filter reads `url` (#3825) ---
# The stub emits exactly what gh's export path emits for `--json subIssues`:
# id/number/title/url/state and nothing else. The old predicate selected on
# `.repository.nameWithOwner`, which is absent there, so it matched no node and
# every container came back childless — this case fails on that predicate.
if command -v jq >/dev/null 2>&1; then
  STUB="$(mktemp -d)"
  cat >"$STUB/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "--version" ]]; then
  printf 'gh version 2.97.0 (test)\n'
  exit 0
fi
for a in "$@"; do
  case "$a" in
  view) mode=view ;;
  list) mode=list ;;
  esac
done
case "${mode:-}" in
view)
  # #12 is a genuine cross-repo sub-issue whose number also exists in o/r —
  # dropping it is what the same-repo filter is for.
  printf '%s\n' '{"subIssues":{"nodes":[
    {"id":"a","number":11,"title":"one","url":"https://github.com/o/r/issues/11","state":"OPEN"},
    {"id":"b","number":12,"title":"foreign","url":"https://github.com/x/y/issues/12","state":"OPEN"}
  ],"totalCount":2}}'
  ;;
list)
  printf '%s\n' '[
    {"number":11,"title":"one","state":"OPEN","assignees":[],"labels":[],"issueType":null,"blockedBy":{"nodes":[]},"url":"https://github.com/o/r/issues/11"},
    {"number":12,"title":"same number, this repo","state":"OPEN","assignees":[],"labels":[],"issueType":null,"blockedBy":{"nodes":[]},"url":"https://github.com/o/r/issues/12"},
    {"number":13,"title":"unrelated","state":"OPEN","assignees":[],"labels":[],"issueType":null,"blockedBy":{"nodes":[]},"url":"https://github.com/o/r/issues/13"}
  ]'
  ;;
*)
  printf 'gh-stub: unhandled\n' >&2
  exit 90
  ;;
esac
EOF
  chmod +x "$STUB/gh"

  OUT="$(PATH="$STUB:$PATH" bash "$S" "github:o/r#99")"
  rc=$?
  assert_eq "list-sub-items over stubbed subIssues → exit 0" "0" "$rc"
  assert_eq "url-derived filter keeps the same-repo child" \
    "github:o/r#11" "$(jq -r '[.items[].id] | join(",")' <<<"$OUT")"
  assert_eq "child row is re-parented to the container" \
    "github:o/r#99" "$(jq -r '.items[0].parent_id' <<<"$OUT")"

  rm -rf "$STUB"
fi

[[ $FAILED -eq 0 ]] || exit 1
