#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced helper
set -uo pipefail
unset RUNNER_TEMP GITHUB_ACTIONS
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/set-native-status.sh"
FIXTURES="$(dirname "$S")/fixtures"
source "$(dirname "$S")/../../lib/verb-test-helpers.sh"

assert_help "$S"
assert_usage_error "$S"
assert_usage_error "$S" --nope
assert_usage_error "$S" "github:o/r#1"
assert_usage_error "$S" "github:o/r#1" --status
assert_usage_error "$S" "github:o/r#1" --status ""
assert_usage_error "$S" "github:o/r#1" --status 3
assert_usage_error "$S" "github:o/r#1" --status Todo --status Done
assert_usage_error "$S" "local-markdown:o/r#1" --status Done

command -v jq >/dev/null 2>&1 || skip_suite "jq not on PATH"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
STUB="$TMP_ROOT/bin"
mkdir -p "$STUB"
cat >"$STUB/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${GH_STUB_LOG:?}"
case "${GH_STUB_MODE:-ok}" in
ok)
  status_val=""
  for a in "$@"; do
    case "$a" in status=*) status_val="${a#status=}" ;; *) : ;; esac
  done
  jq -cn --arg s "$status_val" '{number: 19449, status: {id: 5, name: $s, category: "completed"}}'
  exit 0
  ;;
unenrolled-422)
  printf 'gh: Validation Failed (HTTP 422)\n' >&2
  exit 1
  ;;
unenrolled-403)
  printf 'gh: Resource not accessible by integration (HTTP 403)\n' >&2
  exit 1
  ;;
unenrolled-200)
  printf '{"number":19449,"title":"Unenrolled","state":"open"}\n'
  exit 0
  ;;
404-exists)
  if [[ "$*" == *"-X PATCH"* ]]; then
    printf 'gh: Not Found (HTTP 404)\n' >&2
    exit 1
  fi
  printf '19449\n'
  exit 0
  ;;
404-missing)
  printf 'gh: Not Found (HTTP 404)\n' >&2
  exit 1
  ;;
rate-limit)
  printf 'gh: API rate limit exceeded\n' >&2
  exit 1
  ;;
auth-401)
  printf 'gh: Bad credentials (HTTP 401)\n' >&2
  exit 1
  ;;
esac
EOF
chmod +x "$STUB/gh"

export GH_STUB_LOG="$TMP_ROOT/gh.log"
export PATH="$STUB:$PATH"
export WIT_WRITE_SPACING_S=0

assert_eq "fixture has 7 planning statuses" "7" "$(jq 'length' "$FIXTURES/gh-planning-statuses.json")"
for st in Backlog Todo "In progress" "In review" Done "Not planned" Duplicate; do
  assert_eq "fixture contains status $st" "true" \
    "$(jq --arg s "$st" 'any(.[]; .name == $s)' "$FIXTURES/gh-planning-statuses.json")"
done

: >"$GH_STUB_LOG"
out="$(GH_STUB_MODE=ok bash "$S" "github:o/r#19449" --status Done 2>/dev/null)"
assert_eq "set-native-status Done → exit 0" "0" "$?"
assert_eq "set-native-status Done output" '{"schema_version":"1.0","id":"github:o/r#19449","status":"Done","available":true,"updated":true}' "$out"
assert_contains "set-native-status uses REST PATCH with string -f status=" "$(cat "$GH_STUB_LOG")" \
  "api -X PATCH repos/o/r/issues/19449 -f status=Done"

: >"$GH_STUB_LOG"
out="$(GH_STUB_MODE=ok bash "$S" "github:o/r#19449" --status "Not planned" 2>/dev/null)"
assert_eq "set-native-status Not planned → exit 0" "0" "$?"
assert_eq "set-native-status Not planned status" "Not planned" "$(jq -r '.status' <<<"$out")"

: >"$GH_STUB_LOG"
out="$(GH_STUB_MODE=ok bash "$S" "github:o/r#19449" --status Duplicate 2>/dev/null)"
assert_eq "set-native-status Duplicate → exit 0" "0" "$?"
assert_eq "set-native-status Duplicate status" "Duplicate" "$(jq -r '.status' <<<"$out")"

for mode in unenrolled-422 unenrolled-403 unenrolled-200 404-exists; do
  out="$(GH_STUB_MODE="$mode" bash "$S" "github:o/r#19449" --status Done 2>/dev/null)"
  assert_eq "set-native-status $mode → exit 6 (capability unavailable)" "6" "$?"
  assert_eq "set-native-status $mode reports available:false, updated:false, fallback:none" "false|false|null|none" \
    "$(jq -r '"\(.available)|\(.updated)|\(.status)|\(.fallback)"' <<<"$out")"
done

out="$(GH_STUB_MODE=404-missing bash "$S" "github:o/r#99999" --status Done 2>/dev/null)"
assert_eq "set-native-status missing issue → exit 5" "5" "$?"
assert_eq "set-native-status missing issue prints nothing" "" "$out"

out="$(GH_STUB_MODE=rate-limit bash "$S" "github:o/r#19449" --status Done 2>/dev/null)"
assert_eq "set-native-status rate limit → exit 8" "8" "$?"
assert_eq "set-native-status rate limit prints nothing" "" "$out"

out="$(GH_STUB_MODE=auth-401 bash "$S" "github:o/r#19449" --status Done 2>/dev/null)"
assert_eq "set-native-status 401 → exit 4" "4" "$?"
assert_eq "set-native-status 401 prints nothing" "" "$out"

[[ $FAILED -eq 0 ]] || exit 1
