#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced helper
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/list-relates.sh"
source "$(dirname "$S")/../../lib/verb-test-helpers.sh"

assert_help "$S"
assert_usage_error "$S"
assert_usage_error "$S" "github:o/r#1" extra
assert_usage_error "$S" "local-markdown:o/r#1"

command -v jq >/dev/null 2>&1 || skip_suite "jq not on PATH"

STUB="$TMP_ROOT/bin"
LOG="$TMP_ROOT/gh.log"
mkdir -p "$STUB"

cat >"$STUB/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$GH_STUB_LOG"
if [[ "$1" == "api" && "$2" == repos/*/issues/* && "$2" != *relates_to* ]]; then
  [[ "${GH_STUB_ISSUE_EXISTS:-1}" == "1" ]] && { echo "42"; exit 0; }
  echo "gh: Not Found (HTTP 404)" >&2
  exit 1
fi
if [[ -n "${GH_STUB_FAIL_ERR:-}" ]]; then
  printf '%s\n' "$GH_STUB_FAIL_ERR" >&2
  exit 1
fi
printf '%s\r\n' '[{"number":7,"title":"Same repo","state":"OPEN","html_url":"https://github.com/o/r/issues/7"}]'
printf '%s\r\n' '[{"number":9,"title":"Cross repo","state":"CLOSED","html_url":"https://github.com/other/x/issues/9"}]'
EOF
chmod +x "$STUB/gh"

run() {
  OUT="$(PATH="$STUB:$PATH" GH_STUB_LOG="$LOG" bash "$S" "$@" 2>"$TMP_ROOT/err")"
  RC=$?
}

: >"$LOG"
CLAUDE_CODE_REMOTE=true run "github:o/r#42"
assert_eq "list-relates REST works in cloud sessions → exit 0" "0" "$RC"
assert_eq "list-relates available=true" "true" "$(jq -r '.available' <<<"$OUT")"
assert_eq "list-relates merges paginated arrays" "2" "$(jq '.items | length' <<<"$OUT")"
assert_eq "list-relates same-repo qualified id + lowercase state" "github:o/r#7|open" \
  "$(jq -r '"\(.items[0].id)|\(.items[0].state)"' <<<"$OUT")"
assert_eq "list-relates cross-repo qualified id + lowercase state" "github:other/x#9|closed" \
  "$(jq -r '"\(.items[1].id)|\(.items[1].state)"' <<<"$OUT")"
assert_contains "uses paginated REST relates_to endpoint" "$(cat "$LOG")" "api --paginate repos/o/r/issues/42/relates_to?per_page=100"

GH_STUB_FAIL_ERR="gh: Forbidden (HTTP 403)" run "github:o/r#42"
assert_eq "HTTP 403 → graceful exit 6" "6" "$RC"
assert_eq "HTTP 403 emits empty items + fallback=refs-comment" "[]|refs-comment" \
  "$(jq -r '"\(.items|tojson)|\(.fallback)"' <<<"$OUT")"

GH_STUB_FAIL_ERR="gh: Not Found (HTTP 404)" GH_STUB_ISSUE_EXISTS=1 run "github:o/r#42"
assert_eq "HTTP 404 with existing issue → graceful exit 6" "6" "$RC"

GH_STUB_FAIL_ERR="gh: Not Found (HTTP 404)" GH_STUB_ISSUE_EXISTS=0 run "github:o/r#42"
assert_eq "HTTP 404 with missing issue → exit 5" "5" "$RC"

[[ $FAILED -eq 0 ]] || exit 1
