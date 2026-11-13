#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced helper
set -uo pipefail
# In a CI job the adapter wraps its gh calls and records into the job's
# RUNNER_TEMP; the stub here answers the unwrapped calls.
unset RUNNER_TEMP
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/get-item.sh"
source "$(dirname "$S")/../../lib/verb-test-helpers.sh"

assert_help "$S"
assert_usage_error "$S" --nope
# Foreign-provider ID is well-formed by the shared grammar but must be rejected
# by the GitHub adapter (offline: fails before any gh call).
assert_usage_error "$S" "local-markdown:o/r#1"
assert_usage_error "$S" "github:o/r#1" --nope
assert_usage_error "$S" "github:o/r#1" --history --history

command -v jq >/dev/null 2>&1 || skip_suite "jq not on PATH"

# --history: a gh stub answers the issue read (native `gh issue view` or REST) and applies
# the script's own --jq program to raw timeline pages, as gh --paginate does. The expected
# history is the closed and reopened events in timeline order; every other event is dropped.
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
STUB="$TMP_ROOT/bin"
mkdir -p "$STUB"
cat >"$STUB/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$GH_STUB_LOG"
if [[ "$1" == "--version" ]]; then
  printf 'gh version %s (test)\n' "$GH_STUB_VERSION"
  exit 0
fi
issue='{"number":1,"title":"t","state":"OPEN","assignees":[],"labels":[],"url":"https://github.com/o/r/issues/1","createdAt":"2026-01-01T00:00:00Z","milestone":null}'
if [[ "$1" == issue && "$2" == view ]]; then
  printf '%s\n' "$issue"
  exit 0
fi
path="" prog=""
while [[ $# -gt 0 ]]; do
  case "$1" in
  --jq) prog="$2"; shift 2 ;;
  --paginate | api) shift ;;
  *) path="$1"; shift ;;
  esac
done
case "$path" in
*/timeline*)
  if [[ -n "${GH_STUB_TIMELINE_ERR:-}" ]]; then
    printf '%s\n' "$GH_STUB_TIMELINE_ERR" >&2
    exit 1
  fi
  jq -c "$prog" <<<"$GH_STUB_TIMELINE"
  [[ -z "${GH_STUB_TIMELINE_PAGE2:-}" ]] || jq -c "$prog" <<<"$GH_STUB_TIMELINE_PAGE2"
  ;;
repos/o/r/issues/1)
  printf '%s\n' '{"number":1,"title":"t","state":"open","assignees":[],"labels":[],"type":null,"html_url":"https://github.com/o/r/issues/1","created_at":"2026-01-01T00:00:00Z","milestone":null}'
  ;;
*)
  printf 'gh-stub: unhandled %s\n' "$path" >&2
  exit 90
  ;;
esac
EOF
chmod +x "$STUB/gh"

export GH_STUB_LOG="$TMP_ROOT/gh.log"
export PATH="$STUB:$PATH"
export WORK_ITEM_TRACKER_BINDING="$TMP_ROOT/no-binding.json"

page1='[{"event":"labeled","actor":{"login":"a"},"created_at":"2026-01-01T01:00:00Z"},
  {"event":"closed","actor":{"login":"a"},"created_at":"2026-01-02T00:00:00Z"},
  {"event":"commented","actor":{"login":"b"},"created_at":"2026-01-02T01:00:00Z"},
  {"event":"reopened","actor":{"login":"b"},"created_at":"2026-01-03T00:00:00Z"}]'
page2='[{"event":"closed","actor":null,"created_at":"2026-01-04T00:00:00Z"}]'
want='[{"state":"closed","at":"2026-01-02T00:00:00Z","actor":"a"},{"state":"reopened","at":"2026-01-03T00:00:00Z","actor":"b"},{"state":"closed","at":"2026-01-04T00:00:00Z","actor":null}]'

for version in 2.97.0 2.50.0; do
  export GH_STUB_VERSION="$version"
  : >"$GH_STUB_LOG"
  out="$(GH_STUB_TIMELINE="$page1" GH_STUB_TIMELINE_PAGE2="$page2" bash "$S" "github:o/r#1" --history 2>/dev/null)"
  assert_eq "gh $version: --history exits 0" "0" "$?"
  assert_eq "gh $version: item fields still emitted" "github:o/r#1|open" "$(jq -r '"\(.id)|\(.state)"' <<<"$out")"
  assert_eq "gh $version: history available" "true" "$(jq -r '.state_history.available' <<<"$out")"
  assert_eq "gh $version: closed and reopened events in order across pages" "$want" "$(jq -c '.state_history.events' <<<"$out")"
  assert_eq "gh $version: one reopen counted" "1" "$(jq -r '.state_history.reopen_count' <<<"$out")"
  assert_contains "gh $version: history read from the timeline" "$(cat "$GH_STUB_LOG")" "repos/o/r/issues/1/timeline"

  out="$(GH_STUB_TIMELINE='[{"event":"labeled","actor":{"login":"a"},"created_at":"2026-01-01T01:00:00Z"}]' bash "$S" "github:o/r#1" --history 2>/dev/null)"
  assert_eq "gh $version: never closed → empty events, zero reopens" "true|[]|0" \
    "$(jq -c -r '"\(.state_history.available)|\(.state_history.events)|\(.state_history.reopen_count)"' <<<"$out")"

  out="$(GH_STUB_TIMELINE_ERR='gh: API rate limit exceeded (HTTP 403)' bash "$S" "github:o/r#1" --history 2>/dev/null)"
  rc=$?
  assert_eq "gh $version: failed timeline read → mapped exit code" "4" "$rc"
  assert_eq "gh $version: failed timeline read prints nothing" "" "$out"

  : >"$GH_STUB_LOG"
  out="$(GH_STUB_TIMELINE="$page1" bash "$S" "github:o/r#1" 2>/dev/null)"
  assert_eq "gh $version: plain get-item has no state_history" "false" "$(jq 'has("state_history")' <<<"$out")"
  assert_not_contains "gh $version: plain get-item reads no timeline" "$(cat "$GH_STUB_LOG")" "timeline"
done

[[ $FAILED -eq 0 ]] || exit 1
