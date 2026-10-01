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

# The README's REST search filter: doc and test read the same text.
README="$(dirname "${BASH_SOURCE[0]}")/README.md"
FILTER="$(sed -n "/rest-search-filter:start/,/rest-search-filter:end/{s/^FILTER='\(.*\)'\$/\1/p}" "$README")"
assert_eq "README carries the REST search filter" "1" "$([[ -n "$FILTER" ]] && echo 1 || echo 0)"
ISSUES='[{"number":1,"title":"Fix Login Bug","state":"open"},{"number":2,"title":"Fix login bug","state":"closed","pull_request":{}},{"number":3,"title":"Other","state":"open"}]'
assert_eq "REST search filter drops PRs, matches case-insensitively" $'1\tFix Login Bug\topen' \
  "$(jq -r --arg q "LOGIN fix" "$FILTER" <<<"$ISSUES")"

[[ $FAILED -eq 0 ]] || exit 1
