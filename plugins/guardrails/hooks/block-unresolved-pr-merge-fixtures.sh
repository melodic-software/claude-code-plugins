#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034,SC2329

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/block-unresolved-pr-merge.sh"

# shellcheck source=guardrails-test-helpers.sh
source "$HOOK_DIR/guardrails-test-helpers.sh"
jq_crlf_free
unset CLAUDE_CODE_REMOTE CLAUDE_PLUGIN_OPTION_BLOCK_UNRESOLVED_PR_MERGE_ENABLED

FIX="$TEST_TMPDIR/fixtures"
BIN="$TEST_TMPDIR/bin"
mkdir -p "$FIX" "$BIN"

cat >"$BIN/gh" <<'FAKE'
#!/usr/bin/env bash
fix="$FAKE_GH_DIR"
[[ "${1-}" == api ]] || exit 3
shift
endpoint="" filter="" query=""
while (($#)); do
  case "$1" in
  --jq | -q) filter="$2"; shift 2 ;;
  -f | -F | --raw-field | --field)
    [[ "$2" == query=* ]] && query="${2#query=}"
    [[ "$2" == id=* ]] && printf 'node %s\n' "${2#id=}" >>"$fix/calls"
    shift 2
    ;;
  -X | --method | -H | --header) shift 2 ;;
  --hostname) printf 'host %s\n' "$2" >>"$fix/calls"; shift 2 ;;
  -*) shift ;;
  *) [[ -z "$endpoint" ]] && endpoint="$1"; shift ;;
  esac
done
printf '%s\n' "$endpoint" >>"$fix/calls"
# exec, so a timeout kills this process itself and no orphan holds the pipe.
[[ -n "${FAKE_GH_SLEEP:-}" ]] && exec sleep "$FAKE_GH_SLEEP"
# A slow but answering gh: each call waits, then serves its fixture.
[[ -n "${FAKE_GH_DELAY:-}" ]] && sleep "$FAKE_GH_DELAY"
if [[ -f "$fix/fail" ]]; then
  echo "gh: Bad credentials (HTTP 401)" >&2
  exit 1
fi
if [[ -f "$fix/auth_forbidden" ]]; then
  echo "gh: Resource protected by organization SAML enforcement; authentication required (HTTP 403)" >&2
  exit 1
fi
case "$endpoint" in
graphql)
  if [[ -f "$fix/graphql_refused" ]]; then
    echo "gh: GitHub GraphQL is not available from Claude Code sessions; use the REST API (HTTP 403)" >&2
    exit 1
  fi
  if [[ "$query" == *"node("* ]]; then f=graphql_node.json
  elif [[ "$query" == *"object("* ]]; then f=graphql_scope.json
  elif [[ "$query" == *"nodes("* ]]; then f=graphql_labels.json
  else f=graphql_threads.json; fi
  ;;
*/actions/artifacts\?*)
  [[ -f "$fix/artifacts_error" ]] && { echo "gh: HTTP 502" >&2; exit 1; }
  name="${endpoint#*name=}"
  name="${name%%&*}"
  [[ -f "$fix/artifacts.json" ]] || echo '{"artifacts":[]}' >"$fix/artifacts.json"
  jq --arg n "$name" '{artifacts: [.artifacts[] | select(.name == $n)]}' "$fix/artifacts.json" >"$fix/artifacts_named.json"
  f=artifacts_named.json
  ;;
*/contents/*)
  [[ -f "$fix/contents_error" ]] && { echo "gh: HTTP 500" >&2; exit 1; }
  f="contents_$(basename "${endpoint%%\?*}")"
  ;;
*/ccr/review_threads) f=ccr.json ;;
*/reviews\?*) f=reviews.json ;;
*/check-runs/[0-9]*/annotations*) f="annotations_$(cut -d/ -f5 <<<"$endpoint").json" ;;
*/check-runs\?*) f=checks.json ;;
*/status\?*) f=status.json ;;
*/pulls/[0-9]*/files*) f=files.json ;;
*/rules/branches/*) f=rules.json ;;
*/actions/runs/[0-9]*) f="run_$(cut -d/ -f6 <<<"$endpoint").json" ;;
*/pulls\?*) f=pulls_list.json ;;
*/pulls/[0-9]*) f=pr.json ;;
*) echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
esac
if [[ ! -f "$fix/$f" ]]; then
  echo "gh: Not Found (HTTP 404)" >&2
  exit 1
fi
if [[ -n "$filter" ]]; then
  jq -r "$filter" "$fix/$f" || exit 1
else
  cat "$fix/$f"
fi
FAKE
chmod +x "$BIN/gh"

scenario() {
  rm -rf "$FIX"
  mkdir -p "$FIX"
  : >"$FIX/calls"
  cat >"$FIX/pr.json" <<'J'
{"state":"open","head":{"sha":"abc123"},"base":{"repo":{"full_name":"acme/widgets"}}}
J
  echo '[{"number":42}]' >"$FIX/pulls_list.json"
  echo '{"data":{"node":{"number":42,"repository":{"nameWithOwner":"acme/widgets"}}}}' >"$FIX/graphql_node.json"
  local resolved=false
  [[ "$1" == resolved ]] && resolved=true
  if [[ "$1" == none ]]; then
    echo '{"data":{"repository":{"pullRequest":{"reviewThreads":{"pageInfo":{"hasNextPage":false},"nodes":[]}}}}}' >"$FIX/graphql_threads.json"
    echo '[]' >"$FIX/ccr.json"
  else
    cat >"$FIX/graphql_threads.json" <<J
{"data":{"repository":{"pullRequest":{"reviewThreads":{"pageInfo":{"hasNextPage":false},"nodes":[
 {"isResolved":$resolved,"path":"src/app.py","line":12,"originalLine":12,
  "comments":{"nodes":[{"body":"P2: this drops the error\nmore detail","url":"https://github.com/acme/widgets/pull/42#discussion_r7"}]}}]}}}}}
J
    echo "[{\"resolved\":$resolved,\"outdated\":false,\"path\":\"src/app.py\",\"line\":12,\"comment_ids\":[7,8]}]" >"$FIX/ccr.json"
  fi
  case "$2" in
  none) echo '[{"user":{"login":"amy"},"state":"COMMENTED"}]' >"$FIX/reviews.json" ;;
  requested) echo '[{"user":{"login":"amy"},"state":"APPROVED"},{"user":{"login":"bob"},"state":"CHANGES_REQUESTED"},{"user":{"login":"bob"},"state":"COMMENTED"}]' >"$FIX/reviews.json" ;;
  requested-then-approved) echo '[{"user":{"login":"bob"},"state":"CHANGES_REQUESTED"},{"user":{"login":"bob"},"state":"APPROVED"}]' >"$FIX/reviews.json" ;;
  *) return 1 ;;
  esac
  case "$3" in
  green) echo '{"total_count":2,"check_runs":[{"name":"build","status":"completed","conclusion":"success"},{"name":"lint","status":"completed","conclusion":"skipped"}]}' >"$FIX/checks.json" ;;
  failed) echo '{"total_count":2,"check_runs":[{"name":"build","status":"completed","conclusion":"failure"},{"name":"lint","status":"completed","conclusion":"success"}]}' >"$FIX/checks.json" ;;
  pending) echo '{"total_count":1,"check_runs":[{"name":"build","status":"in_progress","conclusion":null}]}' >"$FIX/checks.json" ;;
  superseded-failure | superseded-cancelled)
    local old="${3#superseded-}"
    echo '{"total_count":2,"check_runs":[{"id":902,"name":"ci-status","app":{"id":15368},"status":"completed","conclusion":"success","started_at":"2026-10-14T16:55:30Z","completed_at":"2026-10-14T16:55:43Z"},{"id":901,"name":"ci-status","app":{"id":15368},"status":"completed","conclusion":"'"$old"'","started_at":"2026-10-14T15:29:01Z","completed_at":"2026-10-14T15:29:16Z"}]}' >"$FIX/checks.json"
    ;;
  regressed) echo '{"total_count":2,"check_runs":[{"id":901,"name":"ci-status","app":{"id":15368},"status":"completed","conclusion":"success","started_at":"2026-10-14T15:29:01Z","completed_at":"2026-10-14T15:29:16Z"},{"id":902,"name":"ci-status","app":{"id":15368},"status":"completed","conclusion":"failure","started_at":"2026-10-14T16:55:30Z","completed_at":"2026-10-14T16:55:43Z"}]}' >"$FIX/checks.json" ;;
  regressed-early) echo '{"total_count":2,"check_runs":[{"id":901,"name":"ci-status","app":{"id":15368},"status":"completed","conclusion":"success","started_at":"2026-10-14T10:00:00Z","completed_at":"2099-01-01T00:00:00Z"},{"id":902,"name":"ci-status","app":{"id":15368},"status":"completed","conclusion":"failure","started_at":"2026-10-14T10:05:00Z","completed_at":"2026-10-14T10:10:00Z"}]}' >"$FIX/checks.json" ;;
  newer-pending) echo '{"total_count":2,"check_runs":[{"id":901,"name":"ci-status","app":{"id":15368},"status":"completed","conclusion":"success","started_at":"2026-10-14T10:00:00Z","completed_at":"2026-10-14T10:10:00Z"},{"id":902,"name":"ci-status","app":{"id":15368},"status":"in_progress","conclusion":null,"started_at":"2026-10-14T10:05:00Z","completed_at":null}]}' >"$FIX/checks.json" ;;
  pending-then-skipped) echo '{"total_count":2,"check_runs":[{"id":901,"name":"test","app":{"id":15368},"status":"in_progress","conclusion":null,"started_at":"2026-10-14T10:00:00Z","completed_at":null},{"id":902,"name":"test","app":{"id":15368},"status":"completed","conclusion":"skipped","started_at":"2026-10-14T10:20:00Z","completed_at":"2026-10-14T10:20:00Z"}]}' >"$FIX/checks.json" ;;
  failed-then-skipped) echo '{"total_count":2,"check_runs":[{"id":901,"name":"test","app":{"id":15368},"status":"completed","conclusion":"failure","started_at":"2026-10-14T10:00:00Z","completed_at":"2026-10-14T10:10:00Z"},{"id":902,"name":"test","app":{"id":15368},"status":"completed","conclusion":"skipped","started_at":"2026-10-14T10:20:00Z","completed_at":"2026-10-14T10:20:00Z"}]}' >"$FIX/checks.json" ;;
  cancelled-then-skipped) echo '{"total_count":2,"check_runs":[{"id":901,"name":"test-bash","app":{"id":15368},"status":"completed","conclusion":"cancelled","started_at":"2026-10-16T05:22:25Z","completed_at":"2026-10-16T05:22:40Z"},{"id":902,"name":"test-bash","app":{"id":15368},"status":"completed","conclusion":"skipped","started_at":"2026-10-16T05:25:10Z","completed_at":"2026-10-16T05:25:10Z"}]}' >"$FIX/checks.json" ;;
  failed-cancelled-skipped) echo '{"total_count":3,"check_runs":[{"id":900,"name":"test","app":{"id":15368},"status":"completed","conclusion":"failure","started_at":"2026-10-14T09:50:00Z","completed_at":"2026-10-14T09:55:00Z"},{"id":901,"name":"test","app":{"id":15368},"status":"completed","conclusion":"cancelled","started_at":"2026-10-14T10:00:00Z","completed_at":"2026-10-14T10:01:00Z"},{"id":902,"name":"test","app":{"id":15368},"status":"completed","conclusion":"skipped","started_at":"2026-10-14T10:20:00Z","completed_at":"2026-10-14T10:20:00Z"}]}' >"$FIX/checks.json" ;;
  newer-cancelled) echo '{"total_count":2,"check_runs":[{"id":901,"name":"test","app":{"id":15368},"status":"completed","conclusion":"success","started_at":"2026-10-14T10:00:00Z","completed_at":"2026-10-14T10:10:00Z"},{"id":902,"name":"test","app":{"id":15368},"status":"completed","conclusion":"cancelled","started_at":"2026-10-14T10:20:00Z","completed_at":"2026-10-14T10:21:00Z"}]}' >"$FIX/checks.json" ;;
  matrix-cancelled-then-legs) echo '{"total_count":4,"check_runs":[{"id":901,"name":"test-bash","app":{"id":15368},"check_suite":{"id":1},"status":"completed","conclusion":"cancelled"},{"id":902,"name":"test-python","app":{"id":15368},"check_suite":{"id":1},"status":"completed","conclusion":"cancelled"},{"id":903,"name":"test-bash (0)","app":{"id":15368},"check_suite":{"id":2},"status":"completed","conclusion":"success"},{"id":904,"name":"test-python (0)","app":{"id":15368},"check_suite":{"id":2},"status":"completed","conclusion":"success"}]}' >"$FIX/checks.json" ;;
  matrix-cancelled-then-leg-fails) echo '{"total_count":3,"check_runs":[{"id":901,"name":"test-bash","app":{"id":15368},"check_suite":{"id":1},"status":"completed","conclusion":"cancelled"},{"id":903,"name":"test-bash (0)","app":{"id":15368},"check_suite":{"id":2},"status":"completed","conclusion":"success"},{"id":904,"name":"test-bash (1)","app":{"id":15368},"check_suite":{"id":2},"status":"completed","conclusion":"failure"}]}' >"$FIX/checks.json" ;;
  matrix-leg-older) echo '{"total_count":2,"check_runs":[{"id":903,"name":"test-bash (0)","app":{"id":15368},"check_suite":{"id":1},"status":"completed","conclusion":"success"},{"id":905,"name":"test-bash","app":{"id":15368},"check_suite":{"id":2},"status":"completed","conclusion":"cancelled"}]}' >"$FIX/checks.json" ;;
  matrix-leg-other-app) echo '{"total_count":2,"check_runs":[{"id":901,"name":"test-bash","app":{"id":15368},"check_suite":{"id":1},"status":"completed","conclusion":"cancelled"},{"id":903,"name":"test-bash (0)","app":{"id":999},"check_suite":{"id":2},"status":"completed","conclusion":"success"}]}' >"$FIX/checks.json" ;;
  matrix-leg-cancelled) echo '{"total_count":2,"check_runs":[{"id":901,"name":"test-bash","app":{"id":15368},"check_suite":{"id":1},"status":"completed","conclusion":"cancelled"},{"id":903,"name":"test-bash (0)","app":{"id":15368},"check_suite":{"id":2},"status":"completed","conclusion":"cancelled"}]}' >"$FIX/checks.json" ;;
  matrix-other-name) echo '{"total_count":2,"check_runs":[{"id":901,"name":"test-bash","app":{"id":15368},"check_suite":{"id":1},"status":"completed","conclusion":"cancelled"},{"id":903,"name":"test-bash-node","app":{"id":15368},"check_suite":{"id":2},"status":"completed","conclusion":"success"}]}' >"$FIX/checks.json" ;;
  merge-lane-pending) echo '{"total_count":2,"check_runs":[{"id":901,"name":"build","app":{"id":15368,"slug":"github-actions"},"status":"completed","conclusion":"success"},{"id":902,"name":"Merge","app":{"id":15368,"slug":"github-actions"},"status":"pending","conclusion":null}]}' >"$FIX/checks.json" ;;
  merge-lane-renamed-pending) echo '{"total_count":2,"check_runs":[{"id":901,"name":"build","app":{"id":15368,"slug":"github-actions"},"status":"completed","conclusion":"success"},{"id":902,"name":"merge","app":{"id":15368,"slug":"github-actions"},"status":"pending","conclusion":null}]}' >"$FIX/checks.json" ;;
  merge-lane-and-build-pending) echo '{"total_count":2,"check_runs":[{"id":901,"name":"build","app":{"id":15368,"slug":"github-actions"},"status":"in_progress","conclusion":null},{"id":902,"name":"Merge","app":{"id":15368,"slug":"github-actions"},"status":"pending","conclusion":null}]}' >"$FIX/checks.json" ;;
  merge-other-app-pending) echo '{"total_count":1,"check_runs":[{"id":902,"name":"merge","app":{"id":999,"slug":"other-ci"},"status":"pending","conclusion":null}]}' >"$FIX/checks.json" ;;
  matrix-failed-then-leg) echo '{"total_count":2,"check_runs":[{"id":901,"name":"test","app":{"id":15368},"check_suite":{"id":1},"status":"completed","conclusion":"failure"},{"id":903,"name":"test (0)","app":{"id":15368},"check_suite":{"id":2},"status":"completed","conclusion":"success"}]}' >"$FIX/checks.json" ;;
  matrix-leg-skipped) echo '{"total_count":2,"check_runs":[{"id":901,"name":"test","app":{"id":15368},"check_suite":{"id":1},"status":"completed","conclusion":"cancelled"},{"id":903,"name":"test (0)","app":{"id":15368},"check_suite":{"id":2},"status":"completed","conclusion":"skipped"}]}' >"$FIX/checks.json" ;;
  ci-superseded-full-success | ci-superseded-full-failed | ci-superseded-full-absent | ci-superseded-other-sha | ci-superseded-mixed | ci-superseded-garbled | ci-superseded-other-check)
    local full='' sha=abc123 extra='' name=ci-status app='{"id":15368,"slug":"github-actions"}'
    [[ "$3" == *-other-check ]] && name='test'
    local sup='{"id":903,"name":"'"$name"'","app":'"$app"',"check_suite":{"id":3},"status":"completed","conclusion":"failure","details_url":"https://github.com/acme/widgets/actions/runs/5002/job/3"}'
    case "$3" in
    *-full-success | *-other-sha | *-mixed | *-garbled) full='{"id":902,"name":"ci-status","app":'"$app"',"check_suite":{"id":2},"status":"completed","conclusion":"success","details_url":"https://github.com/acme/widgets/actions/runs/5001/job/2"},' ;;
    *-full-failed) full='{"id":902,"name":"ci-status","app":'"$app"',"check_suite":{"id":2},"status":"completed","conclusion":"failure","details_url":"https://github.com/acme/widgets/actions/runs/5001/job/2"},' ;;
    *) ;;
    esac
    [[ "$3" == *-other-sha ]] && sha=def456
    [[ "$3" == *-mixed ]] && extra='{"annotation_level":"failure","message":"#42 carries the '\''do-not-merge'\'' label; the merge queue removes it."},'
    [[ "$3" == *-garbled ]] && extra='{"annotation_level":"failure","message":"superseded by full run garbage; real error"},'
    echo '{"total_count":3,"check_runs":[{"id":901,"name":"ci-status","app":'"$app"',"check_suite":{"id":1},"status":"completed","conclusion":"success","details_url":"https://github.com/acme/widgets/actions/runs/5000/job/1"},'"$full$sup"']}' >"$FIX/checks.json"
    echo '['"$extra"'{"annotation_level":"failure","message":"Process completed with exit code 1."},{"annotation_level":"failure","message":"superseded by full run https://github.com/acme/widgets/actions/runs/5001 in flight on '"$sha"': its own ci-status check run is newer than this one and decides the merge gate."}]' >"$FIX/annotations_903.json"
    ;;
  ci-renamed-superseded-full-success | ci-renamed-superseded-full-absent)
    local app='{"id":15368,"slug":"github-actions"}' full=''
    local gate='"app":'"$app"',"status":"completed","conclusion":"failure","details_url":"https://github.com/acme/widgets/actions/runs/5002/job/'
    [[ "$3" == *-full-success ]] && full='{"id":901,"name":"CI Status","app":'"$app"',"check_suite":{"id":2},"status":"completed","conclusion":"success","details_url":"https://github.com/acme/widgets/actions/runs/5001/job/1"},{"id":902,"name":"ci-status","app":'"$app"',"check_suite":{"id":2},"status":"completed","conclusion":"success","details_url":"https://github.com/acme/widgets/actions/runs/5001/job/2"},'
    echo '{"total_count":4,"check_runs":['"$full"'{"id":903,"name":"CI Status","check_suite":{"id":3},'"$gate"'3"},{"id":904,"name":"ci-status","check_suite":{"id":3},'"$gate"'4"}]}' >"$FIX/checks.json"
    echo '[{"annotation_level":"failure","message":"Process completed with exit code 1."},{"annotation_level":"failure","message":"superseded by full run https://github.com/acme/widgets/actions/runs/5001 in flight on abc123: its own ci-status check run is newer than this one and decides the merge gate."}]' >"$FIX/annotations_903.json"
    ;;
  ci-failed-plain)
    echo '{"total_count":1,"check_runs":[{"id":903,"name":"ci-status","app":{"id":15368},"check_suite":{"id":3},"status":"completed","conclusion":"failure","details_url":"https://github.com/acme/widgets/actions/runs/5002/job/3"}]}' >"$FIX/checks.json"
    echo '[{"annotation_level":"failure","message":"Process completed with exit code 1."}]' >"$FIX/annotations_903.json"
    ;;
  matrix-same-suite-sibling) echo '{"total_count":2,"check_runs":[{"id":901,"name":"build","app":{"id":15368},"check_suite":{"id":1},"status":"completed","conclusion":"cancelled"},{"id":902,"name":"build (arm64)","app":{"id":15368},"check_suite":{"id":1},"status":"completed","conclusion":"success"}]}' >"$FIX/checks.json" ;;
  *) return 1 ;;
  esac
  case "$4" in
  green) echo '{"state":"success","statuses":[{"context":"ci/legacy","state":"success"}]}' >"$FIX/status.json" ;;
  failed) echo '{"state":"failure","statuses":[{"context":"ci/legacy","state":"error"}]}' >"$FIX/status.json" ;;
  pending) echo '{"state":"pending","statuses":[{"context":"ci/legacy","state":"pending"}]}' >"$FIX/status.json" ;;
  *) return 1 ;;
  esac
}

OUT=""
ERR=""
RC=0
invoke() {
  local payload="$1"
  shift
  local errf="$TEST_TMPDIR/err"
  OUT=$(env PATH="$BIN:$PATH" FAKE_GH_DIR="$FIX" "$@" bash "$HOOK" <<<"$payload" 2>"$errf")
  RC=$?
  ERR=$(cat "$errf")
}
calls() { cat "$FIX/calls" 2>/dev/null; }

run() {
  local label="$1" command="$2" expected="$3"
  shift 3
  invoke "$(command_json "$command")" "$@"
  assert_exit "$label" "$expected" "$RC"
}
run_ps() {
  invoke "$(pwsh_command_json "$2")"
  assert_exit "$1" "$3" "$RC"
}
