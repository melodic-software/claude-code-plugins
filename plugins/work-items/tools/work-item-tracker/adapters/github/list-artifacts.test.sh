#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced helper
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/list-artifacts.sh"
source "$(dirname "$S")/../../lib/verb-test-helpers.sh"

assert_help "$S"
assert_usage_error "$S"
assert_usage_error "$S" "github:o/r#1" --type bogus
assert_usage_error "$S" "github:o/r#1" --limit 0
assert_usage_error "$S" "github:o/r#1" --limit abc
assert_usage_error "$S" "local-markdown:o/r#1"

command -v jq >/dev/null 2>&1 || skip_suite "jq not on PATH"

STUB="$TMP_ROOT/bin"
LOG="$TMP_ROOT/gh.log"
mkdir -p "$STUB"

cat >"$STUB/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "$1 $2 $3" == "issue artifact --help" ]]; then
  [[ "${GH_STUB_ART_HELP:-ok}" == "ok" ]] && { printf 'USAGE\n  gh issue artifact <command> [flags]\n'; exit 0; }
  printf 'USAGE\n  gh issue <command> [flags]\n'
  exit 0
fi
printf '%s\n' "$*" >>"$GH_STUB_LOG"

if [[ "$1" == "api" && "$2" == repos/*/issues/* ]]; then
  [[ "${GH_STUB_ISSUE_EXISTS:-1}" == "1" ]] && { echo "42"; exit 0; }
  echo "gh: Not Found (HTTP 404)" >&2
  exit 1
fi

if [[ -n "${GH_STUB_FAIL_ERR:-}" ]]; then
  printf '%s\n' "$GH_STUB_FAIL_ERR" >&2
  exit 1
fi

printf '%s\r\n' '[{"id":"A1","number":1,"name":"plan.md","type":"generic","url":"https://github.com/o/r/issues/42/artifacts/1","createdAt":"2026-11-27T14:00:00Z","updatedAt":"2026-11-27T14:10:00Z"},{"id":"A2","number":2,"name":"report.html","type":"embedded_html","url":"https://github.com/o/r/issues/42/artifacts/2","createdAt":"2026-11-27T14:05:00Z","updatedAt":"2026-11-27T14:05:00Z"}]'
EOF
chmod +x "$STUB/gh"

run() {
  OUT="$(PATH="$STUB:$PATH" GH_STUB_LOG="$LOG" bash "$S" "$@" 2>"$TMP_ROOT/err")"
  RC=$?
}

: >"$LOG"
run "github:o/r#42" --type embedded_html --limit 10
assert_eq "list-artifacts happy path → exit 0" "0" "$RC"
assert_eq "list-artifacts available" "true" "$(jq -r '.available' <<<"$OUT")"
assert_eq "list-artifacts count" "2" "$(jq '.artifacts | length' <<<"$OUT")"
assert_eq "list-artifacts normalizes created_at" "2026-11-27T14:00:00Z" "$(jq -r '.artifacts[0].created_at' <<<"$OUT")"
assert_contains "list-artifacts passes --type and --limit" "$(cat "$LOG")" "--type embedded_html --limit 10"

GH_STUB_ART_HELP=old run "github:o/r#42"
assert_eq "missing subcommand → exit 6" "6" "$RC"
assert_eq "missing subcommand emits empty artifacts" "[]" "$(jq -c '.artifacts' <<<"$OUT")"
assert_eq "missing subcommand emits fallback=comment" "comment" "$(jq -r '.fallback' <<<"$OUT")"

GH_STUB_FAIL_ERR="gh: Forbidden (HTTP 403)" run "github:o/r#42"
assert_eq "HTTP 403 → exit 6" "6" "$RC"
assert_eq "HTTP 403 available=false" "false" "$(jq -r '.available' <<<"$OUT")"

GH_STUB_FAIL_ERR="gh: Not Found (HTTP 404)" GH_STUB_ISSUE_EXISTS=1 run "github:o/r#42"
assert_eq "HTTP 404 with existing issue → exit 6" "6" "$RC"

GH_STUB_FAIL_ERR="gh: Not Found (HTTP 404)" GH_STUB_ISSUE_EXISTS=0 run "github:o/r#42"
assert_eq "HTTP 404 with missing issue → exit 5" "5" "$RC"

[[ $FAILED -eq 0 ]] || exit 1
