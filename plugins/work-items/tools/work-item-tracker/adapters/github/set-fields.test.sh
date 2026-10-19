#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced helper
# Offline: set-fields against a gh stub. The org field listing is a trimmed recording of
# GET orgs/melodic-software/issue-fields (2026-10-18); the expected write is the documented
# REST body, {"issue_field_values": [{"field_id", "value": <option name>}]}, since the REST
# write takes the option's name, not its id.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/set-fields.sh"
source "$(dirname "$S")/../../lib/verb-test-helpers.sh"

assert_help "$S"
assert_usage_error "$S"                                                  # no id
assert_usage_error "$S" "github:o/r#1"                                   # no --field
assert_usage_error "$S" "github:o/r#1" --field 15462270                  # no option id
assert_usage_error "$S" "github:o/r#1" --field a=1                       # field id not a number
assert_usage_error "$S" "github:o/r#1" --field 1=2 --field 1=3           # one field twice
assert_usage_error "$S" "local-markdown:o/r#1" --field 15462270=27053568 # foreign provider

command -v jq >/dev/null 2>&1 || skip_suite "jq not on PATH"

STUB="$TMP_ROOT/bin"
LOG="$TMP_ROOT/gh.log"
BODY="$TMP_ROOT/body.json"
mkdir -p "$STUB"
cat >"$STUB/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$GH_STUB_LOG"
for a in "$@"; do
  case "$a" in
  orgs/*/issue-fields)
    cat <<'JSON'
[{"data_type":"single_select","id":15462270,"name":"Size","options":[{"id":27053566,"name":"Large"},{"id":27053567,"name":"Medium"},{"id":27053568,"name":"Small"}]},
 {"data_type":"single_select","id":48625720,"name":"Complexity","options":[{"id":85127653,"name":"High"},{"id":85127651,"name":"Low"},{"id":85127652,"name":"Medium"}]},
 {"data_type":"date","id":7,"name":"Target date","options":null}]
JSON
    exit 0
    ;;
  repos/*/issue-field-values)
    [[ " $* " == *" --input - "* ]] && cat >"$GH_STUB_BODY"
    [[ -z "${GH_STUB_WRITE_ERR:-}" ]] || { printf '%s\n' "$GH_STUB_WRITE_ERR" >&2; exit 1; }
    printf '[]\n'
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
  : >"$BODY"
  OUT="$(PATH="$STUB:$PATH" GH_STUB_LOG="$LOG" GH_STUB_BODY="$BODY" WIT_WRITE_SPACING_S=0 bash "$S" "$@" 2>"$TMP_ROOT/err")"
  RC=$?
  ERR="$(<"$TMP_ROOT/err")"
}

# Two fields in one write, each sent by the name its option id has in the org listing.
run "github:o/r#9" --field 15462270=27053568 --field 48625720=85127653
assert_eq "valid fields → exit 0" "0" "$RC"
assert_eq "output names each field's option name" '[{"field_id":15462270,"option_id":27053568,"value":"Small"},{"field_id":48625720,"option_id":85127653,"value":"High"}]' \
  "$(jq -c '.fields' <<<"$OUT")"
assert_eq "output carries the item id" "github:o/r#9" "$(jq -r '.id' <<<"$OUT")"
WRITE="$(grep 'issue-field-values' "$LOG")"
assert_contains "writes the issue's field values" "$WRITE" "repos/o/r/issues/9/issue-field-values"
assert_contains "POSTs, which leaves other fields alone" "$WRITE" "-X POST"
assert_eq "body pairs each field id with its option name in one object" \
  '{"issue_field_values":[{"field_id":15462270,"value":"Small"},{"field_id":48625720,"value":"High"}]}' \
  "$(jq -c . "$BODY" 2>/dev/null)"
assert_contains "reads the item's own org" "$(head -n 1 "$LOG")" "orgs/o/issue-fields"

# An option id the field does not hold is a stale map: refuse loudly, write nothing.
run "github:o/r#9" --field 15462270=27053568 --field 48625720=27053568
assert_eq "option of another field → exit 5" "5" "$RC"
assert_contains "error names the field and option" "$ERR" "48625720"
assert_eq "no write after a refused option" "" "$(grep 'issue-field-values' "$LOG")"

run "github:o/r#9" --field 99=1
assert_eq "unknown field → exit 5" "5" "$RC"
assert_eq "no write for an unknown field" "" "$(grep 'issue-field-values' "$LOG")"

run "github:o/r#9" --field 7=1
assert_eq "field with no options → exit 5" "5" "$RC"

GH_STUB_WRITE_ERR="HTTP 404: Not Found" run "github:o/r#9" --field 15462270=27053568
assert_eq "failed write → mapped not-found exit" "5" "$RC"

[[ $FAILED -eq 0 ]] || exit 1
