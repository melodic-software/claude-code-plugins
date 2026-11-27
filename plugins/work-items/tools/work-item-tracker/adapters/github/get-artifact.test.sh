#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced helper
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/get-artifact.sh"
source "$(dirname "$S")/../../lib/verb-test-helpers.sh"

assert_help "$S"
assert_usage_error "$S"
assert_usage_error "$S" "github:o/r#1"
assert_usage_error "$S" "github:o/r#1" --artifact 1 --name plan.md
assert_usage_error "$S" "github:o/r#1" --artifact 0
assert_usage_error "$S" "github:o/r#1" --artifact 1 --version 0
assert_usage_error "$S" "local-markdown:o/r#1" --artifact 1

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

sub="${3:-}"
if [[ -n "${GH_STUB_FAIL_ERR:-}" ]]; then
  if [[ "${GH_STUB_LIST_OK:-0}" == "1" && "$sub" == "list" ]]; then
    printf '[{"number":1,"name":"plan.md"}]\n'
    exit 0
  fi
  printf '%s\n' "$GH_STUB_FAIL_ERR" >&2
  exit 1
fi

case "$sub" in
list)
  printf '[{"number":1,"name":"plan.md"},{"number":2,"name":"report.html"}]\n'
  ;;
view)
  has_ver=0 has_json=0
  for a in "$@"; do
    [[ "$a" == "--version" ]] && has_ver=1
    [[ "$a" == "--json" ]] && has_json=1
  done
  if ((has_ver && has_json)); then
    echo "specify only one of --version or --json" >&2
    exit 1
  fi
  printf '%s\r\n' '{"id":"A1","number":1,"name":"plan.md","type":"generic","body":"# v2 body\n","url":"https://github.com/o/r/issues/42/artifacts/1","createdAt":"2026-11-27T14:00:00Z","updatedAt":"2026-11-27T14:15:00Z","versions":[{"number":1,"createdAt":"2026-11-27T14:00:00Z","actor":{"login":"alice"}},{"number":2,"createdAt":"2026-11-27T14:15:00Z","actor":{"login":"bob"}}]}'
  ;;
download)
  ver=""
  while [[ $# -gt 0 ]]; do
    [[ "$1" == "--version" ]] && { ver="$2"; shift 2; continue; }
    shift
  done
  case "$ver" in
  1) printf '# v1 body\r\nline 2\r\n' ;;
  2) printf '# v2 body\n' ;;
  *) echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
  esac
  ;;
*) exit 90 ;;
esac
EOF
chmod +x "$STUB/gh"

run() {
  OUT="$(PATH="$STUB:$PATH" GH_STUB_LOG="$LOG" bash "$S" "$@" 2>"$TMP_ROOT/err")"
  RC=$?
}

: >"$LOG"
run "github:o/r#42" --artifact 1
assert_eq "get-artifact current by --artifact → exit 0" "0" "$RC"
assert_eq "current body returned" '"# v2 body\n"' "$(jq -c '.artifact.body' <<<"$OUT")"
assert_eq "current version is null" "null" "$(jq -r '.artifact.version' <<<"$OUT")"
assert_eq "no versions array unless --versions requested" "false" "$(jq '.artifact | has("versions")' <<<"$OUT")"

: >"$LOG"
run "github:o/r#42" --name "plan.md" --versions
assert_eq "get-artifact by --name with --versions → exit 0" "0" "$RC"
assert_eq "versions length" "2" "$(jq '.artifact.versions | length' <<<"$OUT")"
assert_eq "first version actor" "alice" "$(jq -r '.artifact.versions[0].actor' <<<"$OUT")"

: >"$LOG"
run "github:o/r#42" --artifact 1 --version 1 --versions
assert_eq "historical --version avoids view --version+--json quirk → exit 0" "0" "$RC"
assert_eq "historical version number" "1" "$(jq -r '.artifact.version' <<<"$OUT")"
assert_eq "historical body from download --version 1 --output - (CR stripped)" '"# v1 body\nline 2\n"' \
  "$(jq -c '.artifact.body' <<<"$OUT")"
assert_eq "historical response includes versions metadata" "2" "$(jq '.artifact.versions | length' <<<"$OUT")"
assert_contains "uses download --version 1 --output -" "$(cat "$LOG")" "issue artifact download 42 1 -R o/r --version 1 --output -"
assert_not_contains "view never receives --version" "$(grep 'issue artifact view' "$LOG")" "--version"

run "github:o/r#42" --artifact 1 --version 99
assert_eq "missing version → exit 5" "5" "$RC"

run "github:o/r#42" --name "does-not-exist.md"
assert_eq "missing artifact name → exit 5" "5" "$RC"

GH_STUB_FAIL_ERR="gh: Not Found (HTTP 404)" GH_STUB_LIST_OK=1 run "github:o/r#42" --artifact 99
assert_eq "missing artifact number when list succeeds → exit 5" "5" "$RC"

GH_STUB_FAIL_ERR="gh: Not Found (HTTP 404)" GH_STUB_LIST_OK=0 GH_STUB_ISSUE_EXISTS=1 run "github:o/r#42" --artifact 1
assert_eq "HTTP 404 on artifact feature when issue exists → exit 6" "6" "$RC"
assert_eq "feature unavailable emits fallback=comment" "comment" "$(jq -r '.fallback' <<<"$OUT")"

GH_STUB_FAIL_ERR="gh: Forbidden (HTTP 403)" run "github:o/r#42" --artifact 1
assert_eq "HTTP 403 → exit 6" "6" "$RC"

GH_STUB_ART_HELP=old run "github:o/r#42" --artifact 1
assert_eq "missing gh issue artifact subcommand → exit 6" "6" "$RC"
assert_eq "missing subcommand available=false" "false" "$(jq -r '.available' <<<"$OUT")"

[[ $FAILED -eq 0 ]] || exit 1
