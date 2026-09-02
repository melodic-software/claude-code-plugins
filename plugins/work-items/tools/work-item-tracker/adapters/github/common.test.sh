#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced lib
# common.sh is a sourceable contract lib — assert it sources cleanly and exposes
# its public helpers (no --help contract; it is sourced, never invoked).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../tests/lib.sh"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

for fn in gh_write wit_run_gh wit_resolve_repo wit_emit_item wit_lease_json \
  wit_lease_is_live wit_list_lease_comments wit_help_if_requested wit_map_gh_error \
  wit_gh_issue_view_json_fields; do
  if declare -F "$fn" >/dev/null; then
    pass "common.sh exposes $fn"
  else
    fail "common.sh exposes $fn" "declared" "missing"
  fi
done

assert_eq "lease marker constant" "<!-- work-item-lease v1 " "$WIT_LEASE_MARKER"

# Lease-time logic (wit_iso_to_epoch, wit_lease_is_live, wit_lease_json) is
# shared with the local-markdown adapter and tested once in lib/lease.test.sh.

# Error mapping is pure — spot-check the classifier.
assert_eq "404 → not-found (5)" "5" "$(wit_map_gh_error 'HTTP 404 Not Found')"
assert_eq "rate limit → unavailable (8)" "8" "$(wit_map_gh_error 'API rate limit exceeded')"

# Bot-wrapper resolution (CONTRACT.md "Identity routing (GitHub adapter)"):
# consumer-local-first, plugin-bundled fallback, regardless of adapter location.
CONSUMER_ROOT="$(mktemp -d)"
mkdir -p "$CONSUMER_ROOT/tools/github-auth"
CONSUMER_WRAPPER="$CONSUMER_ROOT/tools/github-auth/gh-bot.sh"
: >"$CONSUMER_WRAPPER"
EMPTY_ROOT="$(mktemp -d)"
BUNDLED="$WIT_GH_ADAPTER_DIR/../../../github-auth/gh-bot.sh"

RESOLVED="$(CLAUDE_PROJECT_DIR="$CONSUMER_ROOT" wit_gh_resolve_bot_wrapper)"
if [[ "$RESOLVED" -ef "$CONSUMER_WRAPPER" ]]; then
  pass "resolves consumer-local wrapper first when present"
else
  fail "resolves consumer-local wrapper first when present" "$CONSUMER_WRAPPER" "$RESOLVED"
fi

RESOLVED_EMPTY_PROJECT="$(CLAUDE_PROJECT_DIR="$EMPTY_ROOT" wit_gh_resolve_bot_wrapper)"
assert_eq "falls back to bundled path when consumer has none" "$BUNDLED" "$RESOLVED_EMPTY_PROJECT"

RESOLVED_UNSET="$(unset CLAUDE_PROJECT_DIR; wit_gh_resolve_bot_wrapper)"
assert_eq "falls back to bundled path when CLAUDE_PROJECT_DIR unset" "$BUNDLED" "$RESOLVED_UNSET"

rm -rf "$CONSUMER_ROOT" "$EMPTY_ROOT"

# --- get-item / create-item emit omit 2.94 JSON fields on older gh (#3598) ---
# A stub that rejects issueType/blockedBy/parent (what gh 2.45 does) proves
# wit_emit_item still succeeds, and a 2.94 stub proves those fields come back.
if command -v jq >/dev/null 2>&1; then
  EMIT_STUB="$(mktemp -d)"
  cat >"$EMIT_STUB/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "--version" ]]; then
  printf 'gh version %s (test)\n' "${GH_STUB_VERSION:-2.45.0}"
  exit 0
fi
json=""
while [[ $# -gt 0 ]]; do
  case "$1" in
  --json)
    json="$2"
    shift 2
    ;;
  *)
    shift
    ;;
  esac
done
printf 'JSON:%s\n' "$json" >>"${GH_STUB_DIR:?}/calls.log"
if [[ "${GH_STUB_REJECT_NATIVE:-}" == "1" ]]; then
  case "$json" in
  *blockedBy* | *parent* | *issueType*)
    printf 'Unknown JSON field\n' >&2
    exit 1
    ;;
  *) ;;
  esac
fi
printf '{"number":1,"title":"t","state":"OPEN","assignees":[],"labels":[],"url":"https://github.com/o/r/issues/1"}\n'
EOF
  chmod +x "$EMIT_STUB/gh"

  FIELDS_OLD="$(GH_STUB_VERSION=2.45.0 PATH="$EMIT_STUB:$PATH" wit_gh_issue_view_json_fields)"
  assert_not_contains "gh 2.45 view fields omit blockedBy" "$FIELDS_OLD" "blockedBy"
  assert_not_contains "gh 2.45 view fields omit parent" "$FIELDS_OLD" "parent"
  assert_not_contains "gh 2.45 view fields omit issueType" "$FIELDS_OLD" "issueType"

  FIELDS_NEW="$(GH_STUB_DIR="$EMIT_STUB" GH_STUB_VERSION=2.94.0 PATH="$EMIT_STUB:$PATH" wit_gh_issue_view_json_fields)"
  assert_contains "gh 2.94 view fields include blockedBy" "$FIELDS_NEW" "blockedBy"
  assert_contains "gh 2.94 view fields include parent" "$FIELDS_NEW" "parent"
  assert_contains "gh 2.94 view fields include issueType" "$FIELDS_NEW" "issueType"

  : >"$EMIT_STUB/calls.log"
  OUT="$(GH_STUB_DIR="$EMIT_STUB" GH_STUB_VERSION=2.45.0 GH_STUB_REJECT_NATIVE=1 \
    PATH="$EMIT_STUB:$PATH" wit_emit_item o r 1)"
  assert_eq "wit_emit_item on gh 2.45 → id" "github:o/r#1" "$(jq -r '.id' <<<"$OUT")"
  assert_eq "wit_emit_item on gh 2.45 → parent_id null" "null" "$(jq -r '.parent_id' <<<"$OUT")"
  assert_eq "wit_emit_item on gh 2.45 → blocked_by_count 0" "0" "$(jq -r '.blocked_by_count' <<<"$OUT")"
  CALLS="$(cat "$EMIT_STUB/calls.log")"
  assert_not_contains "wit_emit_item on gh 2.45 does not request blockedBy" "$CALLS" "blockedBy"

  : >"$EMIT_STUB/calls.log"
  GH_STUB_DIR="$EMIT_STUB" GH_STUB_VERSION=2.94.0 GH_STUB_REJECT_NATIVE=0 \
    PATH="$EMIT_STUB:$PATH" wit_emit_item o r 1 >/dev/null
  CALLS="$(cat "$EMIT_STUB/calls.log")"
  assert_contains "wit_emit_item on gh 2.94 requests blockedBy" "$CALLS" "blockedBy"
  assert_contains "wit_emit_item on gh 2.94 requests parent" "$CALLS" "parent"

  rm -rf "$EMIT_STUB"
fi

[[ $FAILED -eq 0 ]] || exit 1
