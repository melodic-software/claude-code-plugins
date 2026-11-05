#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced helper
# Offline: get-statuses against a gh stub. The answer's shape is the GraphQL
# Issue.issueFieldValues read of one issue (melodic-software/claude-code-plugins,
# 2026-11-05), with the alias the script names.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/get-statuses.sh"
source "$(dirname "$S")/../../lib/verb-test-helpers.sh"

assert_help "$S"
assert_usage_error "$S" github:o/r#1                       # no --field
assert_usage_error "$S" --field                            # no value
assert_usage_error "$S" --field "Work status" --bogus
assert_usage_error "$S" --field "Work status" local-markdown:x#1

command -v jq >/dev/null 2>&1 || skip_suite "jq not on PATH"

STUB="$TMP_ROOT/bin"
LOG="$TMP_ROOT/gh.log"
mkdir -p "$STUB"
cat >"$STUB/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$GH_STUB_LOG"
[[ -z "${GH_STUB_ERR:-}" ]] || { printf '%s\n' "$GH_STUB_ERR" >&2; exit 1; }
cat <<'JSON'
{"data":{"repository":{
  "i1":{"issueFieldValues":{"nodes":[{"name":"Medium","field":{"name":"Size"}},{"name":"needs-human","field":{"name":"Work status"}}]}},
  "i2":{"issueFieldValues":{"nodes":[{"name":"Medium","field":{"name":"Size"}}]}},
  "i3":null}}}
JSON
EOF
chmod +x "$STUB/gh"

run() {
  : >"$LOG"
  OUT="$(PATH="$STUB:$PATH" GH_STUB_LOG="$LOG" bash "$S" "$@" 2>"$TMP_ROOT/err")"
  RC=$?
  ERR="$(<"$TMP_ROOT/err")"
}

run --field "Work status" "github:o/r#1" "github:o/r#2" "github:o/r#3"
assert_eq "statuses → exit 0" "0" "$RC"
assert_eq "each item's field value, null when unset or unanswered" \
  '{"github:o/r#1":"needs-human","github:o/r#2":null,"github:o/r#3":null}' "$(jq -c '.statuses' <<<"$OUT")"
assert_eq "one query for one repository" "1" "$(wc -l <"$LOG" | tr -d ' ')"
assert_contains "aliases each issue number" "$(cat "$LOG")" "i3: issue(number: 3)"

run --field "Work status" "github:o/r#1" "github:p/q#1"
assert_eq "one query per repository" "2" "$(wc -l <"$LOG" | tr -d ' ')"

run --field "Work status"
assert_eq "no ids → exit 0" "0" "$RC"
assert_eq "no ids → no statuses, no call" '{}|0' "$(jq -c '.statuses' <<<"$OUT")|$(wc -l <"$LOG" | tr -d ' ')"

GH_STUB_ERR="HTTP 403: Forbidden" run --field "Work status" "github:o/r#1"
assert_eq "failed read → mapped auth exit" "4" "$RC"
assert_contains "failed read → gh error reaches stderr" "$ERR" "HTTP 403"

CLAUDE_CODE_REMOTE=true run --field "Work status" "github:o/r#1"
assert_eq "a GraphQL-refusing session → exit 3" "3" "$RC"

[[ $FAILED -eq 0 ]] || exit 1
