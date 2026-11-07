#!/usr/bin/env bash
# Tests for dispatcher-current.sh with stub gh and git on PATH. The stub gh
# serves the Actions run and contents reads, with a rate-limit header block
# first when called with -i as the api-budget wrapper calls it; the stub git
# prints the tip's blob. Each case runs with RUNNER_TEMP emptied, so the script
# leaves its gh calls unwrapped, except the one that sets CASE_RUNNER_TEMP.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/dispatcher-current.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

HEAD=1111111111111111111111111111111111111111
BLOB_A=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
BLOB_B=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
UNBLOCK=.github/workflows/pr-unblock-dispatch.yml
NO_ARTIFACTS='{"artifacts":[]}'
FAILED=0

ok() { printf 'ok - %s\n' "$1"; }
not_ok() {
  printf 'not ok - %s\n' "$1"
  FAILED=1
}
check() {
  if [[ $2 == "$3" ]]; then ok "$1"; else not_ok "$1: expected [$2], got [$3]"; fi
}

mkdir -p "$TMP/bin"
cat >"$TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
include=
[[ $2 == -i ]] && include=1 && set -- "$1" "${@:3}"
printf '%s\n' "$2" >>"$STUB/calls"
# The x-ratelimit-* response headers GitHub documents, ahead of the body.
emit() {
  [[ -z $include ]] || printf 'HTTP/2.0 200 OK\r\nX-Ratelimit-Limit: 5000\r\nX-Ratelimit-Remaining: 4990\r\nX-Ratelimit-Used: 10\r\nX-Ratelimit-Reset: 1790000000\r\nX-Ratelimit-Resource: core\r\n\r\n'
  cat "$1"
}
case $2 in
repos/o/r/actions/runs/*/artifacts\?*)
  [[ -f $STUB/fail_artifacts ]] && exit 1
  [[ -z $include ]] || printf 'HTTP/2.0 200 OK\r\nX-Ratelimit-Limit: 5000\r\nX-Ratelimit-Remaining: 4990\r\nX-Ratelimit-Used: 10\r\nX-Ratelimit-Reset: 1790000000\r\nX-Ratelimit-Resource: core\r\n\r\n'
  # The filter the script passes runs on the listing, as gh --jq would.
  jq -r "$4" "$STUB/artifacts"
  ;;
repos/o/r/actions/runs/*)
  [[ -f $STUB/fail_run ]] && exit 1
  emit "$STUB/run"
  ;;
repos/o/r/contents/*)
  [[ -f $STUB/fail_contents ]] && exit 1
  emit "$STUB/blob"
  ;;
*) exit 1 ;;
esac
STUB
cat >"$TMP/bin/git" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB/git"
cat "$STUB/tip"
STUB
chmod +x "$TMP/bin/gh" "$TMP/bin/git"

# run_case <path> <head> <blob at that head> <blob at the tip> [run id]
# EVENT is the dispatcher run's event (push), ARTIFACTS its artifact listing,
# SELF_RUN this run's id.
run_case() {
  STUB="$(mktemp -d "$TMP/case.XXXXXX")"
  printf '%s\n%s\n%s\n' "$1" "$2" "${EVENT-push}" >"$STUB/run"
  printf '%s\n' "${ARTIFACTS-$NO_ARTIFACTS}" >"$STUB/artifacts"
  printf '%s\n' "$3" >"$STUB/blob"
  printf '%s\n' "$4" >"$STUB/tip"
  : >"$STUB/calls"
  : >"$STUB/git"
  : >"$STUB/output"
  [[ -z ${FAIL:-} ]] || : >"$STUB/$FAIL"
  set +e
  env PATH="$TMP/bin:$PATH" STUB="$STUB" RUNNER_TEMP="${CASE_RUNNER_TEMP-}" GH_TOKEN=t GITHUB_REPOSITORY=o/r GITHUB_OUTPUT="$STUB/output" \
    DISPATCHER_RUN_ID="${5-41217038328}" GITHUB_RUN_ID="${SELF_RUN-41217040000}" "$SUT" >"$STUB/out" 2>&1
  RC=$?
  set -e
}

run_case "$UNBLOCK" "$HEAD" "$BLOB_A" "$BLOB_A"
check "same file: exit 0" 0 "$RC"
check "same file: not stale" '' "$(cat "$STUB/output")"
check "same file: reads the run, then the file at its head" \
  "repos/o/r/actions/runs/41217038328 repos/o/r/contents/$UNBLOCK?ref=$HEAD" "$(tr '\n' ' ' <"$STUB/calls" | sed 's/ $//')"
check "same file: reads the tip's blob of that path" "-C .base rev-parse -q --verify HEAD:$UNBLOCK" "$(cat "$STUB/git")"

run_case "$UNBLOCK" "$HEAD" "$BLOB_A" "$BLOB_B"
check "older file: exit 0" 0 "$RC"
check "older file: stale" 'stale=true' "$(cat "$STUB/output")"
check "older file: one warning naming the file" 1 "$(grep -c "^::warning::dispatcher-stale: $UNBLOCK" "$STUB/out")"

run_case "$UNBLOCK" "$HEAD" "$BLOB_A" ''
check "file gone from the tip: stale" 'stale=true' "$(cat "$STUB/output")"

run_case .github/workflows/pr-feedback-dispatch.yml "$HEAD" "$BLOB_A" "$BLOB_B"
check "the run's own dispatcher file is compared: stale" 'stale=true' "$(cat "$STUB/output")"
check "the run's own dispatcher file is the one read" "repos/o/r/contents/.github/workflows/pr-feedback-dispatch.yml?ref=$HEAD" "$(tail -n 1 "$STUB/calls")"

for fault in fail_run fail_contents; do
  FAIL=$fault run_case "$UNBLOCK" "$HEAD" "$BLOB_A" "$BLOB_B"
  check "$fault: exit 0" 0 "$RC"
  check "$fault: left to the broker" '' "$(cat "$STUB/output")"
  check "$fault: says so" 1 "$(grep -c '^::notice::.*the token broker decides$' "$STUB/out")"
done

run_case "$UNBLOCK" "$HEAD" 'not a blob' "$BLOB_B"
check "an unreadable blob is left to the broker" '' "$(cat "$STUB/output")"

run_case "$UNBLOCK" "$HEAD" "$BLOB_A" "$BLOB_B" '1/../2'
check "a malformed run id reads nothing" '' "$(cat "$STUB/calls")"
check "a malformed run id: exit 0" 0 "$RC"

run_case '../secrets.yml' "$HEAD" "$BLOB_A" "$BLOB_B"
check "a path outside the workflows reads no contents" 'repos/o/r/actions/runs/41217038328' "$(cat "$STUB/calls")"
run_case "$UNBLOCK" 'main' "$BLOB_A" "$BLOB_B"
check "a head that is no commit id reads no contents" 'repos/o/r/actions/runs/41217038328' "$(cat "$STUB/calls")"

# A pull_request_target dispatcher's head is the PR head; the commit it ran is
# the one its record names for this run.
REC=4444444444444444444444444444444444444444
artifact() { printf '{"name":"%s","expired":%s,"workflow_run":{"id":%s}}' "$1" "${2-false}" "${3-41217038328}"; }
listing() {
  local IFS=,
  printf '{"artifacts":[%s]}' "$*"
}
OWN_RECORD="$(artifact "pr-unblock-target-dispatched-$REC-41217040000")"

EVENT=pull_request_target ARTIFACTS="$(listing "$OWN_RECORD")" run_case "$UNBLOCK" "$HEAD" "$BLOB_A" "$BLOB_A"
check "target, same file: not stale" '' "$(cat "$STUB/output")"
check "target: reads the run, its record, then the file at the recorded commit, never at the PR head" \
  "repos/o/r/actions/runs/41217038328 repos/o/r/actions/runs/41217038328/artifacts?per_page=100 repos/o/r/contents/$UNBLOCK?ref=$REC" \
  "$(tr '\n' ' ' <"$STUB/calls" | sed 's/ $//')"

EVENT=pull_request_target ARTIFACTS="$(listing "$(artifact other)" "$OWN_RECORD")" run_case "$UNBLOCK" "$HEAD" "$BLOB_A" "$BLOB_B"
check "target, older file: stale" 'stale=true' "$(cat "$STUB/output")"

for case in \
  "no record|$(listing)" \
  "an expired record|$(listing "$(artifact "pr-unblock-target-dispatched-$REC-41217040000" true)")" \
  "another run's upload|$(listing "$(artifact "pr-unblock-target-dispatched-$REC-41217040000" false 41217038329)")" \
  "a record of another dispatched run|$(listing "$(artifact "pr-unblock-target-dispatched-$REC-41217040001")")" \
  "a record of a longer run id|$(listing "$(artifact "pr-unblock-target-dispatched-$REC-412170400000")")" \
  "a push dispatcher's record|$(listing "$(artifact pr-unblock-dispatched-41217040000)")" \
  "a record with a short commit|$(listing "$(artifact pr-unblock-target-dispatched-4444444-41217040000)")"; do
  EVENT=pull_request_target ARTIFACTS="${case#*|}" run_case "$UNBLOCK" "$HEAD" "$BLOB_A" "$BLOB_B"
  check "target, ${case%%|*}: left to the broker" '' "$(cat "$STUB/output")"
  check "target, ${case%%|*}: no file read" 0 "$(grep -c contents "$STUB/calls")"
  check "target, ${case%%|*}: says so" 1 "$(grep -c '^::notice::.*the token broker decides$' "$STUB/out")"
done

FAIL=fail_artifacts EVENT=pull_request_target ARTIFACTS="$(listing "$OWN_RECORD")" run_case "$UNBLOCK" "$HEAD" "$BLOB_A" "$BLOB_B"
check "target, failed record read: left to the broker" '' "$(cat "$STUB/output")"
check "target, failed record read: no file read" 0 "$(grep -c contents "$STUB/calls")"

SELF_RUN='1/../2' EVENT=pull_request_target ARTIFACTS="$(listing "$OWN_RECORD")" run_case "$UNBLOCK" "$HEAD" "$BLOB_A" "$BLOB_B"
check "target, malformed own run id: reads no record" 'repos/o/r/actions/runs/41217038328' "$(cat "$STUB/calls")"

ARTIFACTS="$(listing "$OWN_RECORD")" run_case "$UNBLOCK" "$HEAD" "$BLOB_A" "$BLOB_B"
check "push dispatcher: a target record is not read, and its head is compared" \
  "repos/o/r/actions/runs/41217038328 repos/o/r/contents/$UNBLOCK?ref=$HEAD" "$(tr '\n' ' ' <"$STUB/calls" | sed 's/ $//')"

# In a job the script wraps its gh calls: each response's header block becomes
# a reading in the job's api-budget state, and the verdict is unchanged.
CASE_RUNNER_TEMP="$TMP/runner" run_case "$UNBLOCK" "$HEAD" "$BLOB_A" "$BLOB_B"
check "in a job: exit 0" 0 "$RC"
check "in a job: stale" 'stale=true' "$(cat "$STUB/output")"
check "in a job: both reads still go out" \
  "repos/o/r/actions/runs/41217038328 repos/o/r/contents/$UNBLOCK?ref=$HEAD" "$(tr '\n' ' ' <"$STUB/calls" | sed 's/ $//')"
check "in a job: one reading per read, from its headers" 2 \
  "$(grep -c '^200 5000 4990 10 1790000000 core ' "$TMP/runner/api-budget/github-token" 2>/dev/null)"

exit "$FAILED"
