#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced helper
set -uo pipefail
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/create-item.sh"
source "$(dirname "$S")/../../lib/verb-test-helpers.sh"

assert_help "$S"
assert_usage_error "$S" --nope
assert_usage_error "$S" --title x --type # --type needs a value

# --- create-item succeeds on a mocked gh 2.45 that serves REST only ---
# GraphQL-backed calls (`issue create`, `issue view`, `repo view`) fail with the
# sandbox's HTTP 403; `gh api` succeeds. Below 2.94 the create, the emit read and
# the repo resolve must all take the REST path. Direct adapter invocation
# (dispatcher gate is covered in work-item-tracker.test.sh).
if command -v jq >/dev/null 2>&1; then
  STUB="$(mktemp -d)"
  PROJECT="$(mktemp -d)"
  cat >"$STUB/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "--version" ]]; then
  printf 'gh version %s (test)\n' "${GH_STUB_VERSION:-2.45.0}"
  exit 0
fi
printf '%s\n' "$*" >>"${GH_STUB_DIR:?}/calls.log"
native=0
[[ "${GH_STUB_VERSION:-2.45.0}" == 2.94.0 ]] && native=1
case "$1 $2" in
"issue create")
  if ((native)); then
    printf 'https://github.com/o/r/issues/42\n'
    exit 0
  fi
  ;;
"issue view")
  if ((native)); then
    printf '{"number":42,"title":"t","state":"OPEN","assignees":[],"labels":[{"name":"a"}],"url":"https://github.com/o/r/issues/42"}\n'
    exit 0
  fi
  ;;
esac
case "$1" in
issue | repo)
  printf 'HTTP 403: GitHub GraphQL is not available\n' >&2
  exit 1
  ;;
api)
  case "$*" in
  *"--method POST"*) printf '42\n' ;;
  *"/labels?"*) printf '%b' "${GH_STUB_LABELS-type: bug\ntype: feature\ntype: task\n}" ;;
  *"repos/{owner}/{repo}"*) printf 'o/r\n' ;;
  *) printf '{"number":42,"title":"t","state":"open","assignees":[],"labels":[{"name":"a"},{"name":"type: task"}],"type":{"name":"Task"},"html_url":"https://github.com/o/r/issues/42"}\n' ;;
  esac
  exit 0
  ;;
esac
printf 'gh-stub: unhandled\n' >&2
exit 90
EOF
  chmod +x "$STUB/gh"
  run_create() {
    : >"$STUB/calls.log"
    CLAUDE_PROJECT_DIR="$PROJECT" GH_STUB_DIR="$STUB" PATH="$STUB:$PATH" bash "$S" "$@"
  }

  OUT="$(GH_STUB_VERSION=2.45.0 run_create --title t --body b --labels a,b --repo o/r)"
  rc=$?
  assert_eq "create-item on gh 2.45 (REST only) → exit 0" "0" "$rc"
  assert_eq "create-item on gh 2.45 emits id" "github:o/r#42" "$(jq -r '.id' <<<"$OUT")"
  assert_eq "create-item on gh 2.45 emits state" "open" "$(jq -r '.state' <<<"$OUT")"
  assert_eq "create-item on gh 2.45 emits labels" '["a","type: task"]' "$(jq -c '.labels' <<<"$OUT")"
  assert_eq "create-item on gh 2.45 emits the html url" "https://github.com/o/r/issues/42" \
    "$(jq -r '.url' <<<"$OUT")"
  assert_eq "create-item on gh 2.45 emits the issue type" "Task" "$(jq -r '.type' <<<"$OUT")"
  assert_eq "create-item on gh 2.45 parent_id is null" "null" "$(jq -r '.parent_id' <<<"$OUT")"
  assert_eq "create-item on gh 2.45 blocked_by_count is 0" "0" "$(jq -r '.blocked_by_count' <<<"$OUT")"
  CALLS="$(<"$STUB/calls.log")"
  assert_contains "create-item on gh 2.45 POSTs to the issues endpoint" "$CALLS" \
    "api --method POST repos/o/r/issues -f title=t -f body=b -f labels[]=a -f labels[]=b --jq .number"
  assert_not_contains "create-item on gh 2.45 never calls issue create" "$CALLS" "issue create"

  OUT="$(GH_STUB_VERSION=2.45.0 run_create --title t)"
  rc=$?
  assert_eq "create-item on gh 2.45 resolves the repo over REST → exit 0" "0" "$rc"
  assert_eq "create-item on gh 2.45 repo resolve id" "github:o/r#42" "$(jq -r '.id' <<<"$OUT")"
  assert_not_contains "create-item on gh 2.45 never calls repo view" "$(<"$STUB/calls.log")" "repo view"

  TYPED_ERR="$(mktemp)"
  TYPED_OUT="$(GH_STUB_VERSION=2.45.0 run_create --title t --type Task --repo o/r 2>"$TYPED_ERR")"
  rc=$?
  assert_eq "create-item --type on gh 2.45 degrades → exit 0" "0" "$rc"
  assert_eq "create-item --type on gh 2.45 still emits id" "github:o/r#42" \
    "$(jq -r '.id' <<<"$TYPED_OUT")"
  assert_contains "create-item --type on gh 2.45 names the label fallback" \
    "$(<"$TYPED_ERR")" "type: task"
  assert_contains "create-item --type on gh 2.45 sends the type label" "$(<"$STUB/calls.log")" \
    "labels[]=type: task"
  assert_contains "create-item --type on gh 2.45 reads the repo labels" "$(<"$STUB/calls.log")" \
    "repos/o/r/labels?per_page=100"

  GH_STUB_VERSION=2.45.0 GH_STUB_LABELS='bug\nenhancement\n' \
    run_create --title t --type Task --repo o/r >/dev/null 2>"$TYPED_ERR"
  rc=$?
  assert_eq "create-item --type without the repo label → exit 0" "0" "$rc"
  assert_not_contains "create-item --type without the repo label sends no type label" \
    "$(<"$STUB/calls.log")" "labels[]=type:"
  assert_contains "create-item --type without the repo label notes the drop" \
    "$(<"$TYPED_ERR")" "dropped the type"

  GH_STUB_VERSION=2.45.0 GH_STUB_LABELS='Type: Task\n' \
    run_create --title t --type Task --repo o/r >/dev/null 2>"$TYPED_ERR"
  assert_contains "create-item --type matches the repo label case-insensitively" \
    "$(<"$STUB/calls.log")" "labels[]=type: task"
  rm -f "$TYPED_ERR"

  GH_STUB_VERSION=2.45.0 run_create --title t --parent github:o/r#1 --repo o/r >/dev/null 2>&1
  assert_eq "create-item --parent on gh 2.45 → usage error" "2" "$?"
  assert_not_contains "create-item --parent on gh 2.45 sends nothing" "$(<"$STUB/calls.log")" "POST"
  GH_STUB_VERSION=2.45.0 run_create --title t --blocked-by github:o/r#1 --repo o/r >/dev/null 2>&1
  assert_eq "create-item --blocked-by on gh 2.45 → usage error" "2" "$?"
  assert_not_contains "create-item --blocked-by on gh 2.45 sends nothing" "$(<"$STUB/calls.log")" "POST"

  OUT="$(GH_STUB_VERSION=2.94.0 run_create --title t --labels a --repo o/r)"
  rc=$?
  assert_eq "create-item on gh 2.94 keeps the native path → exit 0" "0" "$rc"
  assert_eq "create-item on gh 2.94 emits id" "github:o/r#42" "$(jq -r '.id' <<<"$OUT")"
  assert_contains "create-item on gh 2.94 calls issue create" "$(<"$STUB/calls.log")" "issue create"

  rm -rf "$STUB" "$PROJECT"
fi

[[ $FAILED -eq 0 ]] || exit 1
