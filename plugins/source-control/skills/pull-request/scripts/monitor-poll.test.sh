#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REF="$SCRIPT_DIR/../../../reference/providers/github/pull-request/monitor.md"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT
export TMPDIR="$TEST_TMPDIR"

# shellcheck source=../../../scripts/test-helpers.sh
source "$SCRIPT_DIR/../../../scripts/test-helpers.sh"

command -v jq >/dev/null 2>&1 || skip_suite "jq not installed"

STUB_DIR="$TEST_TMPDIR/stubs"
mkdir -p "$STUB_DIR"

CHECKOUT="$TEST_TMPDIR/checkout" OUTSIDE="$TEST_TMPDIR/outside"
git init -q "$CHECKOUT"
git -C "$CHECKOUT" remote add origin https://github.com/acme/app.git
mkdir -p "$OUTSIDE"
export GIT_CEILING_DIRECTORIES="$TEST_TMPDIR"
unset GH_REPO

PLUGIN="$TEST_TMPDIR/plugin"
mkdir -p "$PLUGIN/skills/pull-request/scripts" "$PLUGIN/scripts" "$PLUGIN/lib"
cp -p "$SCRIPT_DIR/monitor-poll.sh" "$SCRIPT_DIR/target-repo.sh" "$PLUGIN/skills/pull-request/scripts/"
cp -p "$SCRIPT_DIR/../../../lib/github-remote.sh" "$PLUGIN/lib/"
cat >"$PLUGIN/scripts/source-control-review-threads" <<'THREADS_EOF'
#!/usr/bin/env bash
if [[ -n "${STUB_THREADS_COUNT:-}" ]]; then
  tc=$(cat "$STUB_THREADS_COUNT" 2>/dev/null || echo 0)
  echo $((tc + 1)) >"$STUB_THREADS_COUNT"
fi
unresolved=0
if [[ -n "${STUB_THREADS_FILE:-}" && -f "$STUB_THREADS_FILE" ]]; then
  unresolved=$(cat "$STUB_THREADS_FILE")
fi
echo "THREADS_OK unresolved=$unresolved"
THREADS_EOF
chmod +x "$PLUGIN/scripts/source-control-review-threads"
POLL="$PLUGIN/skills/pull-request/scripts/monitor-poll.sh"

cat >"$STUB_DIR/gh" <<'STUB_EOF'
#!/usr/bin/env bash
if [[ "$1 $2" == "event listen" ]]; then
  [[ -n "${STUB_EV_ARGS:-}" ]] && printf '%s\n' "$*" >"$STUB_EV_ARGS"
  [[ -n "${STUB_EV_PID:-}" ]] && printf '%s\n' "$$" >"$STUB_EV_PID"
  case "${STUB_EV_MODE:-}" in
  feed)
    [[ -n "${STUB_EV_LOG:-}" ]] && echo "attached" >>"$STUB_EV_LOG"
    echo "Listening for events." >&2
    while IFS= read -r ev_line; do
      [[ "$ev_line" == "__EOF__" ]] && exit 0
      printf '%s\n' "$ev_line"
    done <"$STUB_EV_FEED"
    exit 0
    ;;
  silent)
    echo "Listening for events." >&2
    exec sleep 60
    ;;
  missing)
    echo 'unknown command "event" for "gh"' >&2
    exit 1
    ;;
  403)
    echo "gh: HTTP 403 Forbidden: Event Streams preview access required" >&2
    exit 1
    ;;
  hang)
    exec sleep 60
    ;;
  *)
    exit 1
    ;;
  esac
fi
if [[ "$1 $2" == "repo set-default" ]]; then
  echo "No default remote repository has been set." >&2
  exit 0
fi
if [[ "$1 $2" == "api repos/me/app" ]]; then
  echo acme/app
  exit 0
fi
# The PR on acme/app has the cross-repository head me:feature; a bare branch finds nothing.
if [[ "$1 $2" == "pr view" ]]; then
  [[ "$3" == me:feature && " $* " == *" -R acme/app "* ]] && { echo 17; exit 0; }
  echo "no pull requests found for branch \"$3\"" >&2
  exit 1
fi
[[ "$1" == api && " $* " == *" repos/acme/app/"* ]] || exit 1
# What `gh api -i` prints on a 200: the headers, a blank line, then the body.
reply() { printf 'HTTP/2.0 200 OK\r\n\r\n%s\n' "$1"; }
case "$*" in
*/check-runs*)
  [[ -n "${STUB_FAIL_CHECKS:-}" ]] && exit 1
  if [[ -n "${STUB_B_FILE:-}" && -f "$STUB_B_FILE" ]]; then
    b_status=$(cat "$STUB_B_FILE")
  else
    b_status=${STUB_B:-completed}
  fi
  b_conclusion=null
  [[ "$b_status" == completed ]] && b_conclusion='"success"'
  reply '{"check_runs":[
    {"name":"a","check_suite":{"id":1},"started_at":"2026-01-01T00:00:00Z","status":"completed","conclusion":"success"},
    {"name":"b","check_suite":{"id":1},"started_at":"2026-01-01T00:00:00Z","status":"'"$b_status"'","conclusion":'"$b_conclusion"'},
    {"name":"c","check_suite":{"id":1},"started_at":"2026-01-01T00:00:00Z","status":"in_progress","conclusion":null}]}'
  ;;
*/pulls/5)
  n=$(cat "$GH_STUB_COUNT" 2>/dev/null || echo 0)
  n=$((n + 1))
  echo "$n" >"$GH_STUB_COUNT"
  [[ -n "${STUB_EV_LOG:-}" ]] && echo "poll:$n" >>"$STUB_EV_LOG"
  merge_at=${STUB_MERGE_AT:-2}
  if [[ -n "${STUB_MERGE_FILE:-}" && -f "$STUB_MERGE_FILE" ]]; then
    merge_at=$(cat "$STUB_MERGE_FILE")
  fi
  [[ "$n" -lt "$merge_at" ]] && merged=false || merged=true
  reply '{"state":"open","merged":'"$merged"',"head":{"sha":"h1"}}'
  ;;
*/actions/runs*) reply '{"workflow_runs":[]}' ;;
*/status*)
  n=$(cat "$GH_STUB_COUNT" 2>/dev/null || echo 0)
  if [[ -n "${STUB_STATUS_AT:-}" && "$n" -ge "$STUB_STATUS_AT" ]]; then
    reply '{"statuses":[{"context":"ci/legacy","state":"success"}]}'
  else
    reply '{"statuses":[]}'
  fi
  ;;
*) reply '[]' ;;
esac
exit 0
STUB_EOF
chmod +x "$STUB_DIR/gh"

run_poll() {
  rm -f "$TEST_TMPDIR/count"
  (cd "$OUTSIDE" && PATH="$STUB_DIR:$PATH" GH_STUB_COUNT="$TEST_TMPDIR/count" \
    timeout 30 bash "$POLL" --pr 5 --interval 0 --checkout "${TEST_CHECKOUT:-$CHECKOUT}" "$@" 2>&1)
}

out=$(cd "$OUTSIDE" && PATH="$STUB_DIR:$PATH" bash "$POLL" --checkout "$CHECKOUT" 2>&1)
assert_exit "no --pr: a usage error" 3 "$?"
out=$(cd "$OUTSIDE" && PATH="$STUB_DIR:$PATH" bash "$POLL" --pr 5 2>&1)
assert_exit "neither --checkout nor --repo: a usage error" 3 "$?"

out=$(TEST_CHECKOUT="$OUTSIDE" run_poll)
assert_exit "<checkout> names no repository: the watch exits 1" 1 "$?"
[[ -e "$TEST_TMPDIR/count" ]] && read_pr=yes || read_pr=no
assert_eq "<checkout> names no repository: no PR read is made" "no" "$read_pr"

out=$(run_poll)
assert_exit "no baseline: the watch runs to the merge and exits 0" 0 "$?"
assert_not_contains "no baseline: the first poll only records, a is not emitted" "$out" "a: pass"
assert_not_contains "no baseline: the first poll only records, b is not emitted" "$out" "b: pass"
assert_contains "no baseline: the watch completes" "$out" "PR #5 MERGED — watch complete"

out=$(STUB_B=in_progress run_poll --snapshot "$TEST_TMPDIR/baseline")
assert_exit "snapshot run: exits 0 after writing the snapshot" 0 "$?"
snap=$(cat "$TEST_TMPDIR/baseline" 2>/dev/null)
assert_contains "snapshot run: the snapshot holds the finished check" "$snap" "a: pass"
assert_not_contains "snapshot run: the snapshot leaves out the running check" "$snap" "b: "
assert_not_contains "snapshot run: emits no check lines" "$out" "a: pass"

out=$(run_poll --baseline "$TEST_TMPDIR/baseline")
assert_exit "baseline: the watch runs to the merge and exits 0" 0 "$?"
assert_not_contains "baseline: a snapshot the script wrote is accepted" "$out" "BASELINE-UNREADABLE"
assert_contains "baseline: a check finished in the live read but not the baseline is emitted" "$out" "b: pass"
assert_not_contains "baseline: a check already in the baseline is not re-emitted" "$out" "a: pass"
assert_not_contains "baseline: a running check is not emitted" "$out" "c: "

out=$(run_poll --baseline "$TEST_TMPDIR/missing")
assert_exit "an unreadable baseline: the watch runs to the merge and exits 0" 0 "$?"
assert_contains "an unreadable baseline is reported, so the session runs a full scan" "$out" "BASELINE-UNREADABLE"
assert_contains "an unreadable baseline: the watch completes" "$out" "PR #5 MERGED — watch complete"
assert_not_contains "an unreadable baseline file falls back to record-only (a)" "$out" "a: pass"
assert_not_contains "an unreadable baseline file falls back to record-only (b)" "$out" "b: pass"

printf 'a\tpass\t1m\thttps://x/1\nb\tpass\t1m\thttps://x/2\n' >"$TEST_TMPDIR/malformed"
out=$(run_poll --baseline "$TEST_TMPDIR/malformed")
assert_exit "a malformed baseline: the watch runs to the merge and exits 0" 0 "$?"
assert_contains "a malformed baseline is refused, so the session runs a full scan" "$out" "BASELINE-UNREADABLE"
assert_not_contains "a malformed baseline: a is not re-emitted" "$out" "a: pass"
assert_not_contains "a malformed baseline: b is not re-emitted" "$out" "b: pass"

printf 'b: pass\n' >"$TEST_TMPDIR/handmade"
out=$(run_poll --baseline "$TEST_TMPDIR/handmade")
assert_contains "a hand-written baseline without the marker is refused" "$out" "BASELINE-UNREADABLE"
assert_not_contains "a hand-written baseline: a is not emitted" "$out" "a: pass"

rm -f "$TEST_TMPDIR/failed-snap"
out=$(STUB_FAIL_CHECKS=1 run_poll --snapshot "$TEST_TMPDIR/failed-snap")
assert_exit "snapshot run with a failed checks read exits non-zero" 1 "$?"
assert_contains "snapshot run with a failed checks read says so" "$out" "SNAPSHOT-FAILED"
[[ -e "$TEST_TMPDIR/failed-snap" ]] && snap_written=yes || snap_written=no
assert_eq "snapshot run with a failed checks read writes no file" "no" "$snap_written"

TRI="$TEST_TMPDIR/triangular"
git init -q -b feature "$TRI"
git -C "$TRI" remote add origin https://github.com/me/app.git
git -C "$TRI" remote add upstream https://github.com/acme/app.git
fork=$(PATH="$STUB_DIR:$PATH" bash "$SCRIPT_DIR/target-repo.sh" --dir "$TRI" 2>/dev/null)
assert_eq "triangular flow: target-repo.sh resolves the checkout to the fork" "me/app" "$fork"

identity_block() {
  awk -v n="$1" '/^## Resolve PR identity/ { on = 1; next } on && /^## / { exit }
    on && /^```bash/ { if (++i == n) f = 1; next } f && /^```/ { exit } f' "$REF" |
    sed -e "s#<skill-dir>#$SCRIPT_DIR/..#" -e "s#<checkout>#$TRI#" -e 's#<base-owner>/<repo>#acme/app#'
  # shellcheck disable=SC2016 # expands in the generated script
  echo 'echo "PR_NUMBER=$PR_NUMBER OWNER=$OWNER REPO=$REPO"'
}
identity_block 2 >"$TEST_TMPDIR/identity-triangular.sh"
out=$(cd "$OUTSIDE" && PATH="$STUB_DIR:$PATH" bash "$TEST_TMPDIR/identity-triangular.sh" 2>&1)
assert_exit "triangular identity block: exits 0" 0 "$?"
assert_contains "triangular identity block: finds the PR by its fork-namespaced head on the base" "$out" \
  "PR_NUMBER=17 OWNER=acme REPO=app"
identity_block 1 >"$TEST_TMPDIR/identity-plain.sh"
out=$(cd "$OUTSIDE" && PATH="$STUB_DIR:$PATH" bash "$TEST_TMPDIR/identity-plain.sh" 2>&1)
assert_exit "plain identity block on a triangular checkout: an empty PR_NUMBER stops it" 1 "$?"
assert_not_contains "plain identity block on a triangular checkout: no identity is printed" "$out" "PR_NUMBER="

BASE_LINE=$(identity_block 2 | grep '^OWNER_REPO=')
assert_eq "triangular flow: the reference names the base repository explicitly" \
  'OWNER_REPO="acme/app"   # the PR'"'"'s target, not the push destination' "$BASE_LINE"
out=$(TEST_CHECKOUT="$TRI" run_poll --repo acme/app)
assert_exit "triangular flow with the base named: the watch runs to the merge and exits 0" 0 "$?"
assert_contains "triangular flow with the base named: the watch completes" "$out" "PR #5 MERGED — watch complete"

out=$(cd "$OUTSIDE" && PATH="$STUB_DIR:$PATH" bash "$POLL" --pr 5 --checkout "$CHECKOUT" --safety-interval 0 2>&1)
assert_exit "invalid --safety-interval 0: a usage error" 3 "$?"

wait_count() {
  local file="$1" target="$2"
  for _ in $(seq 100); do
    [[ "$(cat "$file" 2>/dev/null || echo 0)" -ge "$target" ]] && return 0
    sleep 0.05
  done
  return 1
}

EV1="$TEST_TMPDIR/ev1"
mkdir -p "$EV1"
mkfifo "$EV1/feed"
exec 4<>"$EV1/feed"
echo in_progress >"$EV1/b_status"
echo 99 >"$EV1/merge_at"
echo 0 >"$EV1/threads"
(cd "$OUTSIDE" && PATH="$STUB_DIR:$PATH" \
  GH_STUB_COUNT="$EV1/count" \
  STUB_EV_MODE=feed \
  STUB_EV_FEED="$EV1/feed" \
  STUB_EV_ARGS="$EV1/args" \
  STUB_EV_PID="$EV1/pid" \
  STUB_EV_LOG="$EV1/log" \
  STUB_B_FILE="$EV1/b_status" \
  STUB_MERGE_FILE="$EV1/merge_at" \
  STUB_THREADS_FILE="$EV1/threads" \
  STUB_THREADS_COUNT="$EV1/threads_count" \
  timeout 30 bash "$POLL" --pr 5 --interval 60 --safety-interval 60 --checkout "$CHECKOUT" >"$EV1/out" 2>&1) &
mp_pid=$!

wait_count "$EV1/threads_count" 1
assert_eq "event stream: initial poll ran after attach" "1" "$(cat "$EV1/count" 2>/dev/null || echo 0)"
assert_eq "event stream: attached before initial poll (no replay gap)" $'attached\npoll:1' "$(head -n 2 "$EV1/log")"
ev_args=$(cat "$EV1/args" 2>/dev/null || true)
assert_contains "event stream: passes --follow" "$ev_args" "--follow"
assert_contains "event stream: passes PR resource URL" "$ev_args" "--resource https://github.com/acme/app/pull/5"
assert_contains "event stream: subscribes to all five PR event types" "$ev_args" \
  "com.github.pull_request.review.submitted.v1,com.github.pull_request.state.changed.v1,com.github.pull_request.head.changed.v1,com.github.pull_request.merge_conflict.v1,com.github.pull_request.check_suite.status.changed.v1"
assert_eq "event stream: poll 0 ran initial review-threads read" "1" "$(cat "$EV1/threads_count" 2>/dev/null || echo 0)"

echo completed >"$EV1/b_status"
printf '%s\n%s\n%s\n' \
  '{"type":"com.github.pull_request.check_suite.status.changed.v1","data":{"conclusion":"success"}}' \
  '{"type":"com.github.pull_request.check_suite.status.changed.v1","data":{"conclusion":"success"}}' \
  '{"type":"com.github.pull_request.check_suite.status.changed.v1","data":{"conclusion":"success"}}' >&4
wait_count "$EV1/count" 2
sleep 0.4
assert_eq "event stream: burst of 3 check_suite events coalesces into 1 poll pass" "2" "$(cat "$EV1/count" 2>/dev/null || echo 0)"
assert_eq "event stream: check_suite wakeup skips non-review thread read" "1" "$(cat "$EV1/threads_count" 2>/dev/null || echo 0)"

echo 2 >"$EV1/threads"
printf '%s\n' '{"type":"com.github.pull_request.review.submitted.v1","data":{"state":"commented"}}' >&4
wait_count "$EV1/threads_count" 2
assert_eq "event stream: review.submitted wakes immediately for poll 3" "3" "$(cat "$EV1/count" 2>/dev/null || echo 0)"
assert_eq "event stream: review.submitted triggers immediate thread read" "2" "$(cat "$EV1/threads_count" 2>/dev/null || echo 0)"

echo 4 >"$EV1/merge_at"
printf '%s\n' '{"type":"com.github.pull_request.state.changed.v1","data":{"state":"merged"}}' >&4
wait "$mp_pid"
assert_exit "event stream: watch exits 0 on merge" 0 "$?"
ev1_out=$(cat "$EV1/out")
assert_contains "event stream: emits finished check b" "$ev1_out" "b: pass"
assert_contains "event stream: emits immediate review-thread change" "$ev1_out" "REVIEW-THREADS unresolved=2"
assert_contains "event stream: emits merge completion" "$ev1_out" "PR #5 MERGED — watch complete"
ev1_bg_pid=$(cat "$EV1/pid" 2>/dev/null || true)
sleep 0.2
assert_eq "event stream: cleans up background gh event listen on exit" "gone" \
  "$(kill -0 "$ev1_bg_pid" 2>/dev/null && echo running || echo gone)"
exec 4>&-

EV2="$TEST_TMPDIR/ev2"
mkdir -p "$EV2"
out=$(cd "$OUTSIDE" && PATH="$STUB_DIR:$PATH" \
  GH_STUB_COUNT="$EV2/count" \
  STUB_EV_MODE=silent \
  STUB_EV_PID="$EV2/pid" \
  STUB_STATUS_AT=2 \
  STUB_MERGE_AT=3 \
  timeout 15 bash "$POLL" --pr 5 --interval 60 --safety-interval 1 --checkout "$CHECKOUT" 2>&1)
assert_exit "safety timeout: exits 0 when silent stream hits safety poll and merges" 0 "$?"
assert_contains "safety timeout: catches legacy commit status on safety poll" "$out" "ci/legacy: pass"
assert_contains "safety timeout: completes on merge" "$out" "PR #5 MERGED — watch complete"
ev2_bg_pid=$(cat "$EV2/pid" 2>/dev/null || true)
sleep 0.2
assert_eq "safety timeout: cleans up background gh event listen on exit" "gone" \
  "$(kill -0 "$ev2_bg_pid" 2>/dev/null && echo running || echo gone)"

out=$(STUB_EV_MODE=missing run_poll --safety-interval 60)
assert_exit "missing gh event subcommand: falls back and exits 0" 0 "$?"
assert_contains "missing gh event subcommand: watch completes" "$out" "PR #5 MERGED — watch complete"
assert_not_contains "missing gh event subcommand: zero error output to callers" "$out" "unknown command"

out=$(STUB_EV_MODE=403 run_poll --safety-interval 60)
assert_exit "HTTP 403 on gh event listen: falls back and exits 0" 0 "$?"
assert_contains "HTTP 403 on gh event listen: watch completes" "$out" "PR #5 MERGED — watch complete"
assert_not_contains "HTTP 403 on gh event listen: zero error output to callers" "$out" "403"

EV_HANG="$TEST_TMPDIR/ev-hang"
mkdir -p "$EV_HANG"
out=$(MONITOR_POLL_ATTACH_TIMEOUT=1 STUB_EV_MODE=hang STUB_EV_PID="$EV_HANG/pid" run_poll --safety-interval 60)
assert_exit "hung gh event listen attach: falls back after timeout and exits 0" 0 "$?"
assert_contains "hung gh event listen attach: watch completes" "$out" "PR #5 MERGED — watch complete"
hang_pid=$(cat "$EV_HANG/pid" 2>/dev/null || true)
sleep 0.2
assert_eq "hung gh event listen attach: timed-out child is killed" "gone" \
  "$(kill -0 "$hang_pid" 2>/dev/null && echo running || echo gone)"

EV_OFF="$TEST_TMPDIR/ev-off"
mkdir -p "$EV_OFF"
out=$(STUB_EV_MODE=silent STUB_EV_ARGS="$EV_OFF/args-flag" run_poll --no-events)
assert_exit "--no-events: runs cleanly and exits 0" 0 "$?"
assert_file_absent "--no-events: does not start gh event listen" "$EV_OFF/args-flag"

out=$(MONITOR_POLL_EVENTS=0 STUB_EV_MODE=silent STUB_EV_ARGS="$EV_OFF/args-env" run_poll)
assert_exit "MONITOR_POLL_EVENTS=0: runs cleanly and exits 0" 0 "$?"
assert_file_absent "MONITOR_POLL_EVENTS=0: does not start gh event listen" "$EV_OFF/args-env"

out=$(STUB_EV_MODE=silent STUB_EV_ARGS="$EV_OFF/args-snap" run_poll --snapshot "$EV_OFF/snap")
assert_exit "--snapshot: exits 0 without starting event stream" 0 "$?"
assert_file_absent "--snapshot: does not start gh event listen" "$EV_OFF/args-snap"

EV4="$TEST_TMPDIR/ev4"
mkdir -p "$EV4"
mkfifo "$EV4/feed"
exec 5<>"$EV4/feed"
t_start=$SECONDS
(cd "$OUTSIDE" && PATH="$STUB_DIR:$PATH" \
  GH_STUB_COUNT="$EV4/count" \
  STUB_EV_MODE=feed \
  STUB_EV_FEED="$EV4/feed" \
  STUB_MERGE_AT=3 \
  timeout 15 bash "$POLL" --pr 5 --interval 1 --safety-interval 60 --checkout "$CHECKOUT" >"$EV4/out" 2>&1) &
mp_pid=$!
wait_count "$EV4/count" 1
printf '__EOF__\n' >&5
wait "$mp_pid"
rc=$?
elapsed=$((SECONDS - t_start))
exec 5>&-
assert_exit "mid-watch EOF: degrades to sleep and exits 0 on merge" 0 "$rc"
assert_contains "mid-watch EOF: watch completes" "$(cat "$EV4/out")" "PR #5 MERGED — watch complete"
assert_eq "mid-watch EOF: slept --interval instead of busy-spinning (>= 2s for 2 waits)" "yes" \
  "$( ((elapsed >= 2)) && echo yes || echo "no (${elapsed}s)")"

[[ $FAILED -eq 0 ]] || exit 1
exit 0
