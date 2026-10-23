#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced helper
# Offline: get-field-options against a gh stub. The org field listing is the trimmed recording
# set-fields.test.sh uses (GET orgs/melodic-software/issue-fields, 2026-10-18).
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/get-field-options.sh"
source "$(dirname "$S")/../../lib/verb-test-helpers.sh"

assert_help "$S"
assert_usage_error "$S"                                      # no --field
assert_usage_error "$S" --field                              # no value
assert_usage_error "$S" --field Size --field Complexity      # one field only
assert_usage_error "$S" --field Size --repo notarepo         # malformed --repo
assert_usage_error "$S" --field Size --bogus

command -v jq >/dev/null 2>&1 || skip_suite "jq not on PATH"

STUB="$TMP_ROOT/bin"
LOG="$TMP_ROOT/gh.log"
mkdir -p "$STUB"
cat >"$STUB/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$GH_STUB_LOG"
for a in "$@"; do
  case "$a" in
  orgs/*/issue-fields)
    [[ -z "${GH_STUB_ERR:-}" ]] || { printf '%s\n' "$GH_STUB_ERR" >&2; exit 1; }
    cat <<'JSON'
[{"data_type":"single_select","id":15462270,"name":"Size","options":[{"id":27053566,"name":"Large"},{"id":27053567,"name":"Medium"},{"id":27053568,"name":"Small"}]},
 {"data_type":"single_select","id":48625720,"name":"Complexity","options":[{"id":85127653,"name":"High"},{"id":85127651,"name":"Low"}]},
 {"data_type":"date","id":7,"name":"Target date","options":null}]
JSON
    exit 0
    ;;
  esac
done
printf 'gh-stub: unhandled %s\n' "$*" >&2
exit 90
EOF
chmod +x "$STUB/gh"

run() {
  : >"$LOG"
  OUT="$(PATH="$STUB:$PATH" GH_STUB_LOG="$LOG" bash "$S" "$@" 2>"$TMP_ROOT/err")"
  RC=$?
  ERR="$(<"$TMP_ROOT/err")"
}

run --field Size --repo o/r
assert_eq "named field → exit 0" "0" "$RC"
assert_eq "lists the field's options" '[{"id":27053566,"name":"Large"},{"id":27053567,"name":"Medium"},{"id":27053568,"name":"Small"}]' \
  "$(jq -c '.options' <<<"$OUT")"
assert_eq "output echoes the requested field" "Size" "$(jq -r '.field' <<<"$OUT")"
assert_contains "reads the repo owner's org" "$(head -n 1 "$LOG")" "orgs/o/issue-fields"

run --field 48625720 --repo o/r
assert_eq "field by numeric id → exit 0" "0" "$RC"
assert_eq "field by id lists its options" '["High","Low"]' "$(jq -c '[.options[].name]' <<<"$OUT")"

run --field Missing --repo o/r
assert_eq "absent field → exit 0" "0" "$RC"
assert_eq "absent field → empty list" "[]" "$(jq -c '.options' <<<"$OUT")"

run --field "Target date" --repo o/r
assert_eq "field with no options → exit 0" "0" "$RC"
assert_eq "field with no options → empty list" "[]" "$(jq -c '.options' <<<"$OUT")"

GH_STUB_ERR="HTTP 403: Forbidden" run --field Size --repo o/r
assert_eq "failed listing → mapped auth exit" "4" "$RC"
assert_contains "failed listing → gh error reaches stderr" "$ERR" "HTTP 403"

[[ $FAILED -eq 0 ]] || exit 1
