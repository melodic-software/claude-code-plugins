#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced helper
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/put-artifact.sh"
source "$(dirname "$S")/../../lib/verb-test-helpers.sh"

MD_FILE="$TMP_ROOT/plan.md"
HTML_FILE="$TMP_ROOT/report.html"
EMPTY_FILE="$TMP_ROOT/empty.md"
printf '# Plan\n\nStep 1\n' >"$MD_FILE"
printf '<!doctype html><h1>Report</h1>\n' >"$HTML_FILE"
: >"$EMPTY_FILE"

assert_help "$S"
assert_usage_error "$S"
assert_usage_error "$S" "github:o/r#1"
assert_usage_error "$S" "github:o/r#1" --body "hi"
assert_usage_error "$S" "github:o/r#1" --body "hi" --name a.md --body-file "$MD_FILE"
assert_usage_error "$S" "github:o/r#1" --body-file "$TMP_ROOT/missing.md"
assert_usage_error "$S" "github:o/r#1" --body-file "$EMPTY_FILE"
assert_usage_error "$S" "github:o/r#1" --url "ftp://bad"
assert_usage_error "$S" "github:o/r#1" --url "https://example.com" --type generic
assert_usage_error "$S" "github:o/r#1" --body "hi" --name a.md --type bogus
assert_usage_error "$S" "github:o/r#1" --body "hi" --name a.md --artifact 0
assert_usage_error "$S" "local-markdown:o/r#1" --body "hi" --name a.md

command -v jq >/dev/null 2>&1 || skip_suite "jq not on PATH"

STUB="$TMP_ROOT/bin"
LOG="$TMP_ROOT/gh.log"
STORE="$TMP_ROOT/artifacts.json"
mkdir -p "$STUB"

cat >"$STUB/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "$1 $2 $3" == "issue artifact --help" ]]; then
  case "${GH_STUB_ART_HELP:-ok}" in
  ok) printf 'USAGE\n  gh issue artifact <command> [flags]\n'; exit 0 ;;
  cobra) printf 'USAGE\n  gh issue <command> [flags]\n'; exit 0 ;;
  fail) echo 'unknown command "artifact"' >&2; exit 1 ;;
  esac
fi
printf '%s\n' "$*" >>"$GH_STUB_LOG"

if [[ "$1" == "api" && "$2" == repos/*/issues/* ]]; then
  if [[ "${GH_STUB_ISSUE_EXISTS:-1}" == "1" ]]; then
    echo "42"
    exit 0
  fi
  echo "gh: Not Found (HTTP 404)" >&2
  exit 1
fi

if [[ -n "${GH_STUB_FAIL_ERR:-}" ]]; then
  printf '%s\n' "$GH_STUB_FAIL_ERR" >&2
  exit 1
fi

sub="${3:-}"
case "$sub" in
list)
  cat "$GH_STUB_STORE"
  ;;
view)
  num="$5"
  jq -c --argjson n "$num" '[.[] | select(.number == $n)][0]' "$GH_STUB_STORE"
  ;;
create)
  issue="$4"
  shift 4
  name="" type="generic" url_arg=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
    -R) shift 2 ;;
    --name) name="$2"; shift 2 ;;
    --type) type="$2"; shift 2 ;;
    --body | --body-file) shift 2 ;;
    http://*|https://*) url_arg="$1"; type="link"; shift ;;
    *) shift ;;
    esac
  done
  [[ -n "$name" ]] || name="example.com"
  next="$(jq '([.[].number] | max // 0) + 1' "$GH_STUB_STORE")"
  art_url="https://github.com/o/r/issues/$issue/artifacts/$next"
  jq -c --argjson n "$next" --arg name "$name" --arg type "$type" --arg url "$art_url" \
    '. + [{id: ("A_" + ($n|tostring)), number: $n, name: $name, type: $type, url: $url}]' \
    "$GH_STUB_STORE" >"$GH_STUB_STORE.new" && mv "$GH_STUB_STORE.new" "$GH_STUB_STORE"
  printf '%s\n' "$art_url"
  ;;
edit)
  issue="$4" art_num="$5"
  printf 'https://github.com/o/r/issues/%s/artifacts/%s\n' "$issue" "$art_num"
  ;;
*) exit 90 ;;
esac
EOF
chmod +x "$STUB/gh"

run() {
  OUT="$(PATH="$STUB:$PATH" GH_STUB_LOG="$LOG" GH_STUB_STORE="$STORE" WIT_WRITE_SPACING_S=0 \
    bash "$S" "$@" 2>"$TMP_ROOT/err")"
  RC=$?
}

printf '[]\n' >"$STORE"
: >"$LOG"

run "github:o/r#42" --body-file "$MD_FILE"
assert_eq "create markdown artifact → exit 0" "0" "$RC"
assert_eq "create markdown action" "created" "$(jq -r '.action' <<<"$OUT")"
assert_eq "create markdown available" "true" "$(jq -r '.available' <<<"$OUT")"
assert_eq "create markdown defaults name to basename" "plan.md" "$(jq -r '.artifact.name' <<<"$OUT")"
assert_eq "create markdown type" "generic" "$(jq -r '.artifact.type' <<<"$OUT")"
assert_eq "create markdown number" "1" "$(jq -r '.artifact.number' <<<"$OUT")"
assert_eq "create markdown url" "https://github.com/o/r/issues/42/artifacts/1" "$(jq -r '.artifact.url' <<<"$OUT")"

run "github:o/r#42" --body-file "$HTML_FILE"
assert_eq "create html artifact → exit 0" "0" "$RC"
assert_eq "html artifact auto-detects embedded_html" "embedded_html" "$(jq -r '.artifact.type' <<<"$OUT")"
assert_contains "html create passes --type embedded_html" "$(cat "$LOG")" "--type embedded_html"

run "github:o/r#42" --body "# v1" --name "spec-plan.md" --type plan
assert_eq "create plan artifact → exit 0" "0" "$RC"
assert_eq "plan artifact type" "plan" "$(jq -r '.artifact.type' <<<"$OUT")"

run "github:o/r#42" --url "https://example.com/runbook" --name "Runbook"
assert_eq "create link artifact → exit 0" "0" "$RC"
assert_eq "link artifact type" "link" "$(jq -r '.artifact.type' <<<"$OUT")"

: >"$LOG"
run "github:o/r#42" --body-file "$MD_FILE"
assert_eq "upsert existing name → exit 0" "0" "$RC"
assert_eq "upsert action is updated" "updated" "$(jq -r '.action' <<<"$OUT")"
assert_eq "upsert keeps artifact number 1" "1" "$(jq -r '.artifact.number' <<<"$OUT")"
assert_contains "upsert invokes edit, not create" "$(cat "$LOG")" "issue artifact edit 42 1"
assert_not_contains "upsert does not call create" "$(cat "$LOG")" "issue artifact create"

: >"$LOG"
run "github:o/r#42" --artifact 2 --body "<h1>v2</h1>"
assert_eq "explicit --artifact edit → exit 0" "0" "$RC"
assert_eq "explicit --artifact action is updated" "updated" "$(jq -r '.action' <<<"$OUT")"
assert_eq "explicit --artifact keeps embedded_html" "embedded_html" "$(jq -r '.artifact.type' <<<"$OUT")"
assert_not_contains "explicit --artifact skips list" "$(cat "$LOG")" "issue artifact list"

run "github:o/r#42" --body "# conflict" --name "plan.md" --type plan
assert_eq "type mismatch on upsert → exit 7" "7" "$RC"

run "github:o/r#42" --url "https://example.com" --name "plan.md"
assert_eq "url over document artifact → exit 7" "7" "$RC"

GH_STUB_ART_HELP=cobra run "github:o/r#42" --body-file "$MD_FILE"
assert_eq "old gh without issue artifact → exit 6" "6" "$RC"
assert_eq "old gh emits available=false" "false" "$(jq -r '.available' <<<"$OUT")"
assert_eq "old gh emits fallback=comment" "comment" "$(jq -r '.fallback' <<<"$OUT")"
assert_eq "old gh emits schema_version 1.0" "1.0" "$(jq -r '.schema_version' <<<"$OUT")"

GH_STUB_FAIL_ERR="gh: Forbidden (HTTP 403)" run "github:o/r#42" --body-file "$MD_FILE"
assert_eq "HTTP 403 forbidden → graceful exit 6" "6" "$RC"
assert_eq "HTTP 403 emits available=false" "false" "$(jq -r '.available' <<<"$OUT")"
assert_eq "HTTP 403 emits fallback=comment" "comment" "$(jq -r '.fallback' <<<"$OUT")"

GH_STUB_FAIL_ERR="gh: Not Found (HTTP 404)" GH_STUB_ISSUE_EXISTS=1 run "github:o/r#42" --body-file "$MD_FILE"
assert_eq "HTTP 404 when issue exists → feature unavailable exit 6" "6" "$RC"
assert_eq "HTTP 404 feature unavailable emits available=false" "false" "$(jq -r '.available' <<<"$OUT")"

GH_STUB_FAIL_ERR="gh: Not Found (HTTP 404)" GH_STUB_ISSUE_EXISTS=0 run "github:o/r#42" --body-file "$MD_FILE"
assert_eq "HTTP 404 when issue is missing → exit 5" "5" "$RC"
assert_eq "HTTP 404 missing issue prints nothing on stdout" "" "$OUT"

GH_STUB_FAIL_ERR="gh: API rate limit exceeded (HTTP 403)" run "github:o/r#42" --body-file "$MD_FILE"
assert_eq "rate-limited 403 is not swallowed as exit 6" "4" "$RC"
assert_eq "rate-limited 403 prints nothing on stdout" "" "$OUT"

[[ $FAILED -eq 0 ]] || exit 1
