#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced helper
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/unlink-relates.sh"
source "$(dirname "$S")/../../lib/verb-test-helpers.sh"

assert_help "$S"
assert_usage_error "$S"
assert_usage_error "$S" "github:o/r#1"
assert_usage_error "$S" "github:o/r#1" --related-to "github:o/r#1"
assert_usage_error "$S" "local-markdown:o/r#1" --related-to "github:o/r#2"

command -v jq >/dev/null 2>&1 || skip_suite "jq not on PATH"

STUB="$TMP_ROOT/bin"
mkdir -p "$STUB"
cat >"$STUB/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"query("* ]]; then
  printf '{"data":{"a":{"issue":{"id":"I_1"}},"b":{"issue":{"id":"I_2"}}}}\n'
  exit 0
fi
if [[ -n "${GH_STUB_ERR:-}" ]]; then
  printf '%s\n' "$GH_STUB_ERR" >&2
  exit 1
fi
printf '{"data":{"removeRelatesTo":{"issue":{"number":1},"relatedIssue":{"number":2}}}}\n'
EOF
chmod +x "$STUB/gh"

run() {
  OUT="$(PATH="$STUB:$PATH" WIT_WRITE_SPACING_S=0 bash "$S" "$@" 2>"$TMP_ROOT/err")"
  RC=$?
}

run "github:o/r#1" --related-to "github:o/r#2"
assert_eq "unlink-relates happy path → exit 0" "0" "$RC"
assert_eq "unlink-relates linked=false" "false" "$(jq -r '.linked' <<<"$OUT")"
assert_eq "unlink-relates unlinked=true" "true" "$(jq -r '.unlinked' <<<"$OUT")"
assert_eq "unlink-relates symmetric=true" "true" "$(jq -r '.symmetric' <<<"$OUT")"

GH_STUB_ERR="GraphQL: Field 'removeRelatesTo' doesn't exist on type 'Mutation'" \
  run "github:o/r#1" --related-to "github:o/r#2"
assert_eq "missing removeRelatesTo mutation → exit 6" "6" "$RC"
assert_eq "fallback is refs-comment" "refs-comment" "$(jq -r '.fallback' <<<"$OUT")"

CLAUDE_CODE_REMOTE=true run "github:o/r#1" --related-to "github:o/r#2"
assert_eq "cloud session refusal → exit 6" "6" "$RC"

[[ $FAILED -eq 0 ]] || exit 1
