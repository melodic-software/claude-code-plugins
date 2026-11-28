#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced helper
set -uo pipefail
unset RUNNER_TEMP GITHUB_ACTIONS
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/claim.sh"
source "$(dirname "$S")/../../lib/verb-test-helpers.sh"

assert_help "$S"
assert_usage_error "$S" --nope
assert_usage_error "$S" "github:o/r#1" --holder

command -v jq >/dev/null 2>&1 || skip_suite "jq not on PATH"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
STUB="$TMP_ROOT/bin"
mkdir -p "$STUB"
cat >"$STUB/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${GH_STUB_LOG:?}"
case "$*" in
"api user --jq .login")
  printf 'alice\n'
  ;;
*"--method POST"*"/assignees"*)
  printf '["alice"]\n'
  ;;
*".assignees[].login"*)
  printf '["alice"]\n'
  ;;
*"api -X PATCH repos/o/r/issues/1 -f status="*)
  case "${GH_STUB_STATUS_MODE:-ok}" in
  ok)
    printf '{"number":1,"status":{"id":4,"name":"In progress","category":"started"}}\n'
    ;;
  unenrolled-422)
    printf 'gh: Validation Failed (HTTP 422)\n' >&2
    exit 1
    ;;
  unenrolled-200)
    printf '{"number":1,"title":"Unenrolled","state":"open"}\n'
    ;;
  esac
  ;;
*"repos/o/r/issues/1/comments"*"-f body="*)
  printf '101\n'
  ;;
*"--paginate repos/o/r/issues/1/comments"*)
  printf '[{"id":101,"node_id":"N1","body":"<!-- work-item-lease v1 {\\"schema_version\\":\\"1.0\\",\\"holder\\":\\"alice\\",\\"acquired_at\\":\\"2026-11-27T00:00:00Z\\",\\"renewed_at\\":\\"2099-01-01T00:00:00Z\\",\\"ttl_hours\\":24} -->","created_at":"2026-11-27T00:00:00Z","author_association":"MEMBER","user":{"login":"alice","type":"User"}}]\n'
  ;;
*)
  printf 'gh-stub: unhandled %s\n' "$*" >&2
  exit 90
  ;;
esac
EOF
chmod +x "$STUB/gh"

export GH_STUB_LOG="$TMP_ROOT/gh.log"
export PATH="$STUB:$PATH"
export WIT_WRITE_SPACING_S=0

: >"$GH_STUB_LOG"
out="$(GH_STUB_STATUS_MODE=ok bash "$S" "github:o/r#1" --ttl-hours 24 2>/dev/null)"
assert_eq "claim (implementation) exits 0" "0" "$?"
assert_eq "claim (implementation) emits native_status In progress" "In progress" "$(jq -r '.native_status' <<<"$out")"
assert_contains "claim (implementation) PATCHes native status to In progress" "$(cat "$GH_STUB_LOG")" \
  "api -X PATCH repos/o/r/issues/1 -f status=In progress"

for ph in triage discovery; do
  : >"$GH_STUB_LOG"
  out="$(GH_STUB_STATUS_MODE=ok bash "$S" "github:o/r#1" --ttl-hours 1 --phase "$ph" 2>/dev/null)"
  assert_eq "claim --phase $ph exits 0" "0" "$?"
  assert_eq "claim --phase $ph emits native_status null" "null" "$(jq -r '.native_status' <<<"$out")"
  assert_not_contains "claim --phase $ph does not PATCH native status" "$(cat "$GH_STUB_LOG")" "-X PATCH"
done

for mode in unenrolled-422 unenrolled-200; do
  : >"$GH_STUB_LOG"
  out="$(GH_STUB_STATUS_MODE="$mode" bash "$S" "github:o/r#1" --ttl-hours 24 2>/dev/null)"
  assert_eq "claim ($mode) degrades gracefully → exit 0" "0" "$?"
  assert_eq "claim ($mode) keeps lease_comment_id" "101" "$(jq -r '.lease_comment_id' <<<"$out")"
  assert_eq "claim ($mode) emits native_status null" "null" "$(jq -r '.native_status' <<<"$out")"
done

[[ $FAILED -eq 0 ]] || exit 1
