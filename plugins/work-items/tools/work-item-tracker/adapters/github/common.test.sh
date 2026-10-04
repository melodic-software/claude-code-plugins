#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced lib
# common.sh is a sourceable contract lib — assert it sources cleanly and exposes
# its public helpers (no --help contract; it is sourced, never invoked).
set -uo pipefail

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../tests/lib.sh"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

for fn in gh_write wit_run_gh wit_resolve_repo wit_emit_item wit_lease_json \
  wit_lease_is_live wit_list_lease_comments wit_help_if_requested wit_map_gh_error; do
  assert_succeeds "common.sh exposes $fn" "declared" "missing" declare -F "$fn"
done

assert_eq "lease marker constant" "<!-- work-item-lease v1 " "$WIT_LEASE_MARKER"

# Lease-time logic (wit_iso_to_epoch, wit_lease_is_live, wit_lease_json) is
# shared with the local-markdown adapter and tested once in lib/lease.test.sh.

# Error mapping is pure — spot-check the classifier.
assert_eq "404 → not-found (5)" "5" "$(wit_map_gh_error 'HTTP 404 Not Found')"
assert_eq "rate limit → unavailable (8)" "8" "$(wit_map_gh_error 'API rate limit exceeded')"

# Bot-wrapper resolution (CONTRACT.md "Identity routing (GitHub adapter)"):
# consumer-local-first, plugin-bundled fallback, regardless of adapter location.
CONSUMER_ROOT="$(mktemp -d "$TMP_ROOT/d.XXXXXX")"
mkdir -p "$CONSUMER_ROOT/tools/github-auth"
CONSUMER_WRAPPER="$CONSUMER_ROOT/tools/github-auth/gh-bot.sh"
: >"$CONSUMER_WRAPPER"
EMPTY_ROOT="$(mktemp -d "$TMP_ROOT/d.XXXXXX")"
BUNDLED="$WIT_GH_ADAPTER_DIR/../../../github-auth/gh-bot.sh"

RESOLVED="$(CLAUDE_PROJECT_DIR="$CONSUMER_ROOT" wit_gh_resolve_bot_wrapper)"
if [[ "$RESOLVED" -ef "$CONSUMER_WRAPPER" ]]; then
  pass "resolves consumer-local wrapper first when present"
else
  fail "resolves consumer-local wrapper first when present" "$CONSUMER_WRAPPER" "$RESOLVED"
fi

RESOLVED_EMPTY_PROJECT="$(CLAUDE_PROJECT_DIR="$EMPTY_ROOT" wit_gh_resolve_bot_wrapper)"
assert_eq "falls back to bundled path when consumer has none" "$BUNDLED" "$RESOLVED_EMPTY_PROJECT"

RESOLVED_UNSET="$(
  unset CLAUDE_PROJECT_DIR
  wit_gh_resolve_bot_wrapper
)"
assert_eq "falls back to bundled path when CLAUDE_PROJECT_DIR unset" "$BUNDLED" "$RESOLVED_UNSET"

rm -rf "$CONSUMER_ROOT" "$EMPTY_ROOT"

# --- wit_emit_item / wit_resolve_repo take the REST path below gh 2.94 ---
# The stub 403s every GraphQL-backed call (`issue view`, `repo view`) the way a
# sandboxed session does and serves `gh api`; gh 2.94 reads through `issue view`.
if command -v jq >/dev/null 2>&1; then
  EMIT_STUB="$(mktemp -d "$TMP_ROOT/d.XXXXXX")"
  cat >"$EMIT_STUB/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "--version" ]]; then
  printf 'gh version %s (test)\n' "${GH_STUB_VERSION:-2.45.0}"
  exit 0
fi
printf '%s\n' "$*" >>"${GH_STUB_DIR:?}/calls.log"
case "$1" in
issue)
  if [[ "${GH_STUB_VERSION:-2.45.0}" == 2.94.0 ]]; then
    printf '{"number":1,"title":"t","state":"OPEN","assignees":[],"labels":[],"url":"https://github.com/o/r/issues/1"}\n'
    exit 0
  fi
  printf 'HTTP 403: GitHub GraphQL is not available\n' >&2
  exit 1
  ;;
repo)
  printf 'HTTP 403: GitHub GraphQL is not available\n' >&2
  exit 1
  ;;
api)
  case "$*" in
  *"repos/{owner}/{repo}"*) printf 'o/r\n' ;;
  *) printf '{"number":1,"title":"t","state":"open","assignees":[{"login":"u"}],"labels":[{"name":"a"}],"type":null,"html_url":"https://github.com/o/r/issues/1"}\n' ;;
  esac
  exit 0
  ;;
esac
exit 90
EOF
  chmod +x "$EMIT_STUB/gh"

  : >"$EMIT_STUB/calls.log"
  OUT="$(GH_STUB_DIR="$EMIT_STUB" GH_STUB_VERSION=2.45.0 PATH="$EMIT_STUB:$PATH" wit_emit_item o r 1)"
  rc=$?
  assert_eq "wit_emit_item on gh 2.45 → exit 0" "0" "$rc"
  assert_eq "wit_emit_item on gh 2.45 → id" "github:o/r#1" "$(jq -r '.id' <<<"$OUT")"
  assert_eq "wit_emit_item on gh 2.45 → state" "open" "$(jq -r '.state' <<<"$OUT")"
  assert_eq "wit_emit_item on gh 2.45 → assignees" '["u"]' "$(jq -c '.assignees' <<<"$OUT")"
  assert_eq "wit_emit_item on gh 2.45 → labels" '["a"]' "$(jq -c '.labels' <<<"$OUT")"
  assert_eq "wit_emit_item on gh 2.45 → type null" "null" "$(jq -r '.type' <<<"$OUT")"
  assert_eq "wit_emit_item on gh 2.45 → url from html_url" "https://github.com/o/r/issues/1" \
    "$(jq -r '.url' <<<"$OUT")"
  assert_eq "wit_emit_item on gh 2.45 → parent_id null" "null" "$(jq -r '.parent_id' <<<"$OUT")"
  assert_eq "wit_emit_item on gh 2.45 → blocked_by_count 0" "0" "$(jq -r '.blocked_by_count' <<<"$OUT")"
  assert_contains "wit_emit_item on gh 2.45 reads over REST" "$(<"$EMIT_STUB/calls.log")" \
    "api repos/o/r/issues/1"
  assert_not_contains "wit_emit_item on gh 2.45 skips issue view" "$(<"$EMIT_STUB/calls.log")" "issue view"

  PR_STUB="$(mktemp -d "$TMP_ROOT/d.XXXXXX")"
  cat >"$PR_STUB/gh" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == "--version" ]] && { echo "gh version 2.45.0 (test)"; exit 0; }
echo '{"number":2,"pull_request":{}}'
EOF
  chmod +x "$PR_STUB/gh"
  (PATH="$PR_STUB:$PATH" wit_emit_item o r 2 >/dev/null 2>&1)
  assert_eq "wit_emit_item on gh 2.45 rejects a pull request with not found" "5" "$?"
  rm -rf "$PR_STUB"

  : >"$EMIT_STUB/calls.log"
  GH_STUB_DIR="$EMIT_STUB" GH_STUB_VERSION=2.94.0 PATH="$EMIT_STUB:$PATH" wit_emit_item o r 1 >/dev/null
  CALLS="$(<"$EMIT_STUB/calls.log")"
  assert_contains "wit_emit_item on gh 2.94 requests blockedBy" "$CALLS" "blockedBy"
  assert_contains "wit_emit_item on gh 2.94 requests parent" "$CALLS" "parent"
  assert_contains "wit_emit_item on gh 2.94 requests issueType" "$CALLS" "issueType"

  : >"$EMIT_STUB/calls.log"
  REPO="$(GH_STUB_DIR="$EMIT_STUB" PATH="$EMIT_STUB:$PATH" wit_resolve_repo "")"
  assert_eq "wit_resolve_repo resolves over REST" "o/r" "$REPO"
  assert_not_contains "wit_resolve_repo skips repo view" "$(<"$EMIT_STUB/calls.log")" "repo view"
  assert_eq "wit_resolve_repo keeps an explicit override" "x/y" "$(wit_resolve_repo x/y)"

  rm -rf "$EMIT_STUB"
fi

# --- a closed blocker unblocks only when it was completed ---
# Issue N carries one blocker whose state and close reason the stub fixes per N. The
# `gh --json blockedBy` projection has no stateReason, so the reason is served only
# by `gh api graphql` (nodes by id); GH_STUB_GRAPHQL_FAIL makes that query fail.
if command -v jq >/dev/null 2>&1; then
  REASON_STUB="$(mktemp -d "$TMP_ROOT/d.XXXXXX")"
  cat >"$REASON_STUB/gh" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == "--version" ]] && { echo "gh version 2.94.0 (test)"; exit 0; }
printf '%s\n' "$*" >>"${GH_STUB_DIR:?}/calls.log"
node() {
  case "$1" in
  1) printf '{"id":"I1","number":101,"state":"OPEN"}' ;;
  2) printf '{"id":"I2","number":102,"state":"CLOSED"}' ;;
  3) printf '{"id":"I3","number":103,"state":"CLOSED"}' ;;
  4) printf '{"id":"I4","number":104,"state":"CLOSED"}' ;;
  5) printf '{"id":"I5","number":105,"state":"CLOSED"}' ;;
  6) printf '{"id":"I2","number":102,"state":"CLOSED"},{"id":"I6","number":106,"state":"CLOSED"}' ;;
  esac
}
issue() {
  printf '{"number":%s,"title":"t","state":"OPEN","assignees":[],"labels":[],"blockedBy":{"nodes":[%s]},"url":"https://github.com/o/r/issues/%s"}' "$1" "$(node "$1")" "$1"
}
if [[ "$1 $2" == "issue view" ]]; then
  issue "$3"
elif [[ "$1 $2" == "issue list" ]]; then
  printf '[%s,%s,%s,%s]' "$(issue 1)" "$(issue 2)" "$(issue 3)" "$(issue 4)"
elif [[ "$1 $2" == "api graphql" ]]; then
  [[ -z "${GH_STUB_GRAPHQL_FAIL:-}" ]] || { echo "HTTP 403: forbidden" >&2; exit 1; }
  case "${GH_STUB_GRAPHQL_MODE:-}" in
  no-node) printf '{"data":{"nodes":[]}}'; exit 0 ;;
  null-node) printf '{"data":{"nodes":[null]}}'; exit 0 ;;
  blank) exit 0 ;;
  garbage) printf 'not json'; exit 0 ;;
  esac
  out=""
  for a in "$@"; do
    case "$a" in
    "ids[]=I2") out+='{"id":"I2","stateReason":"COMPLETED"},' ;;
    "ids[]=I3") out+='{"id":"I3","stateReason":"NOT_PLANNED"},' ;;
    "ids[]=I4") out+='{"id":"I4","stateReason":"DUPLICATE"},' ;;
    "ids[]=I5") out+='{"id":"I5","stateReason":null},' ;;
    esac
  done
  printf '{"data":{"nodes":[%s]}}' "${out%,}"
else
  exit 90
fi
EOF
  chmod +x "$REASON_STUB/gh"
  emit() { GH_STUB_DIR="$REASON_STUB" PATH="$REASON_STUB:$PATH" wit_emit_item o r "$1" 2>/dev/null; }

  : >"$REASON_STUB/calls.log"
  OUT="$(emit 1)"
  assert_eq "OPEN blocker blocks" "1" "$(jq -r '.blocked_by_count' <<<"$OUT")"
  assert_eq "OPEN blocker is not won't-do" "0" "$(jq -r '.blocked_by_wont_do_count' <<<"$OUT")"
  assert_not_contains "no closed blocker → no graphql reason query" "$(<"$REASON_STUB/calls.log")" "api graphql"

  OUT="$(emit 2)"
  assert_eq "CLOSED+COMPLETED blocker unblocks" "0" "$(jq -r '.blocked_by_count' <<<"$OUT")"
  assert_eq "CLOSED+COMPLETED blocker is not won't-do" "0" "$(jq -r '.blocked_by_wont_do_count' <<<"$OUT")"

  OUT="$(emit 3)"
  assert_eq "CLOSED+NOT_PLANNED blocker still blocks" "1" "$(jq -r '.blocked_by_count' <<<"$OUT")"
  assert_eq "CLOSED+NOT_PLANNED blocker counts as won't-do" "1" "$(jq -r '.blocked_by_wont_do_count' <<<"$OUT")"

  OUT="$(emit 4)"
  assert_eq "CLOSED+DUPLICATE blocker still blocks" "1" "$(jq -r '.blocked_by_count' <<<"$OUT")"
  assert_eq "CLOSED+DUPLICATE blocker counts as won't-do" "1" "$(jq -r '.blocked_by_wont_do_count' <<<"$OUT")"

  # Issues closed before GitHub recorded reasons read back with a null stateReason.
  OUT="$(emit 5)"
  assert_eq "CLOSED with null stateReason unblocks" "0" "$(jq -r '.blocked_by_count' <<<"$OUT")"
  assert_eq "CLOSED with null stateReason is not won't-do" "0" "$(jq -r '.blocked_by_wont_do_count' <<<"$OUT")"

  OUT="$(GH_STUB_GRAPHQL_FAIL=1 emit 2)"
  assert_eq "failed close-reason query keeps the closed blocker blocking" "1" "$(jq -r '.blocked_by_count' <<<"$OUT")"
  assert_eq "failed close-reason query is not won't-do" "0" "$(jq -r '.blocked_by_wont_do_count' <<<"$OUT")"

  # A query that succeeds but returns no node, or a null node, for the blocker (a
  # private cross-repo blocker, say) leaves its reason unread: it keeps blocking. So
  # does a blank or unparsable body, which must not escape as a usage error (exit 2).
  # Issue 6's two closed blockers come back as one node (I2, COMPLETED) and no node at
  # all (I6): the answered one resolves, the missing one keeps blocking.
  OUT="$(emit 6)"
  assert_eq "a blocker missing from a partial graphql answer keeps blocking" "1" "$(jq -r '.blocked_by_count' <<<"$OUT")"
  assert_eq "a blocker missing from a partial graphql answer is not won't-do" "0" "$(jq -r '.blocked_by_wont_do_count' <<<"$OUT")"

  for mode in no-node null-node blank garbage; do
    OUT="$(GH_STUB_GRAPHQL_MODE="$mode" emit 2)"
    rc=$?
    assert_eq "graphql $mode → get-item still exits 0" "0" "$rc"
    assert_eq "graphql $mode → closed blocker keeps blocking" "1" "$(jq -r '.blocked_by_count' <<<"$OUT")"
    assert_eq "graphql $mode → not won't-do" "0" "$(jq -r '.blocked_by_wont_do_count' <<<"$OUT")"
  done

  : >"$REASON_STUB/calls.log"
  OUT="$(GH_STUB_DIR="$REASON_STUB" PATH="$REASON_STUB:$PATH" bash "$SCRIPT_DIR/list-items.sh" --repo o/r 2>/dev/null)"
  assert_eq "list-items blocked_by_count per OPEN, COMPLETED, NOT_PLANNED, DUPLICATE" "1 0 1 1" \
    "$(jq -r '[.items[].blocked_by_count] | map(tostring) | join(" ")' <<<"$OUT")"
  assert_eq "list-items blocked_by_wont_do_count per OPEN, COMPLETED, NOT_PLANNED, DUPLICATE" "0 0 1 1" \
    "$(jq -r '[.items[].blocked_by_wont_do_count] | map(tostring) | join(" ")' <<<"$OUT")"
  assert_eq "list-items fetches every closed reason in one graphql query" "1" \
    "$(grep -c 'api graphql' "$REASON_STUB/calls.log")"

  rm -rf "$REASON_STUB"
fi

# The README's REST search filter: doc and test read the same text.
README="$(dirname "${BASH_SOURCE[0]}")/README.md"
FILTER="$(sed -n "/rest-search-filter:start/,/rest-search-filter:end/{s/^FILTER='\(.*\)'\$/\1/p}" "$README")"
assert_eq "README carries the REST search filter" "1" "$([[ -n "$FILTER" ]] && echo 1 || echo 0)"
ISSUES='[{"number":1,"title":"Fix Login Bug","state":"open"},{"number":2,"title":"Fix login bug","state":"closed","pull_request":{}},{"number":3,"title":"Other","state":"open"}]'
assert_eq "REST search filter drops PRs, matches case-insensitively" $'1\tFix Login Bug\topen' \
  "$(jq -r --arg q "LOGIN fix" "$FILTER" <<<"$ISSUES")"

# The README's open-linked-PR reductions: only an open PR whose head branch lives in the
# item's own repository is in flight. A fork's `Closes #N` must not park the item.
eval "$(sed -n '/open-linked-prs-filter:start/,/open-linked-prs-filter:end/{/^[A-Z_]*=/p}' "$README")"
assert_eq "README carries the open-linked-PR reductions" "1" \
  "$([[ -n "${PR_GATE:-}" && -n "${PR_READY_GATE:-}" && -n "${PR_REPORT:-}" ]] && echo 1 || echo 0)"
pr_page() { # <nodes-json>: one page of the README's query for item o/r#1
  jq -cn --argjson n "$1" '{data: {repository: {nameWithOwner: "o/r", issue: {closedByPullRequestsReferences: {nodes: $n}}}}}'
}
pr() { # <number> <state> <draft> <head nameWithOwner or null>
  jq -cn --argjson n "$1" --arg s "$2" --argjson d "$3" --argjson h "$4" \
    '{number: $n, state: $s, isDraft: $d, createdAt: "2026-10-01T00:00:00Z", headRepository: (if $h == null then null else {nameWithOwner: $h} end)}'
}
FORK_ONLY="$(pr_page "[$(pr 7 OPEN false '"stranger/r"'), $(pr 8 OPEN false null)]")"
assert_eq "fork PR and deleted-fork PR are not in flight" "false" "$(jq -r "$PR_GATE" <<<"$FORK_ONLY")"
assert_eq "fork PR does not satisfy the ready gate" "false" "$(jq -r "$PR_READY_GATE" <<<"$FORK_ONLY")"
assert_eq "fork PR is not reported" "" "$(jq -r "$PR_REPORT" <<<"$FORK_ONLY")"
SAME_DRAFT="$(pr_page "[$(pr 7 OPEN false '"stranger/r"'), $(pr 9 OPEN true '"o/r"'), $(pr 10 MERGED false '"o/r"')]")"
assert_eq "same-repo draft PR is in flight" "true" "$(jq -r "$PR_GATE" <<<"$SAME_DRAFT")"
assert_eq "same-repo draft PR fails the ready gate" "false" "$(jq -r "$PR_READY_GATE" <<<"$SAME_DRAFT")"
assert_eq "only the same-repo open PR is reported" '{"number":9,"isDraft":true,"createdAt":"2026-10-01T00:00:00Z"}' \
  "$(jq -r "$PR_REPORT" <<<"$SAME_DRAFT")"
SAME_READY="$(pr_page "[$(pr 11 OPEN false '"o/r"')]")"
assert_eq "same-repo ready PR passes the ready gate" "true" "$(jq -r "$PR_READY_GATE" <<<"$SAME_READY")"

[[ $FAILED -eq 0 ]] || exit 1
