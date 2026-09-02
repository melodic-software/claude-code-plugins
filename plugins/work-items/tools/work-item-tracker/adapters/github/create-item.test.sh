#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced helper
set -uo pipefail
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/create-item.sh"
source "$(dirname "$S")/../../lib/verb-test-helpers.sh"

assert_help "$S"
assert_usage_error "$S" --nope
assert_usage_error "$S" --title x --type # --type needs a value

# --- plain create-item succeeds on mocked gh 2.45 (#3598) ---
# The stub rejects --parent / --blocked-by and the 2.94 --json fields, matching
# what an older gh does. --repo skips `gh repo view`, so the path is create +
# emit only. Direct adapter invocation (dispatcher gate is covered in
# work-item-tracker.test.sh).
if command -v jq >/dev/null 2>&1; then
  STUB="$(mktemp -d)"
  PROJECT="$(mktemp -d)"
  cat >"$STUB/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "--version" ]]; then
  printf 'gh version %s (test)\n' "${GH_STUB_VERSION:-2.45.0}"
  exit 0
fi
json="" create=0 native_flag=0
while [[ $# -gt 0 ]]; do
  case "$1" in
  --json)
    json="$2"
    shift 2
    ;;
  create)
    create=1
    shift
    ;;
  --parent | --blocked-by | --type)
    native_flag=1
    shift 2
    ;;
  *)
    shift
    ;;
  esac
done
if ((native_flag)); then
  printf 'unknown flag: native sub-issue/dependency surface\n' >&2
  exit 1
fi
if [[ -n "$json" ]]; then
  case "$json" in
  *blockedBy* | *parent* | *issueType*)
    printf 'Unknown JSON field: %s\n' "$json" >&2
    exit 1
    ;;
  *) ;;
  esac
  printf '{"number":42,"title":"t","state":"OPEN","assignees":[],"labels":[],"url":"https://github.com/o/r/issues/42"}\n'
  exit 0
fi
if ((create)); then
  printf 'https://github.com/o/r/issues/42\n'
  exit 0
fi
printf 'gh-stub: unhandled\n' >&2
exit 90
EOF
  chmod +x "$STUB/gh"

  OUT="$(CLAUDE_PROJECT_DIR="$PROJECT" GH_STUB_VERSION=2.45.0 PATH="$STUB:$PATH" \
    bash "$S" --title t --repo o/r)"
  rc=$?
  assert_eq "create-item on gh 2.45 (no gated flags) → exit 0" "0" "$rc"
  assert_eq "create-item on gh 2.45 emits id" "github:o/r#42" "$(jq -r '.id' <<<"$OUT")"
  assert_eq "create-item on gh 2.45 parent_id is null" "null" "$(jq -r '.parent_id' <<<"$OUT")"

  TYPED_ERR="$(mktemp)"
  TYPED_OUT="$(CLAUDE_PROJECT_DIR="$PROJECT" GH_STUB_VERSION=2.45.0 PATH="$STUB:$PATH" \
    bash "$S" --title t --type Task --repo o/r 2>"$TYPED_ERR")"
  rc=$?
  assert_eq "create-item --type on gh 2.45 degrades → exit 0" "0" "$rc"
  assert_eq "create-item --type on gh 2.45 still emits id" "github:o/r#42" \
    "$(jq -r '.id' <<<"$TYPED_OUT")"
  assert_contains "create-item --type on gh 2.45 names the label fallback" \
    "$(cat "$TYPED_ERR")" "type: task"
  rm -f "$TYPED_ERR"

  rm -rf "$STUB" "$PROJECT"
fi

[[ $FAILED -eq 0 ]] || exit 1
