#!/usr/bin/env bash
# Regression tests for the Monitor watch's poll script (the "Poll checks over REST" block of the
# GitHub monitor reference): the checks baseline a re-arm starts from. Black-box, with the block
# extracted from the reference and run against a stubbed `gh` on PATH.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REF="$SCRIPT_DIR/../../../reference/providers/github/pull-request/monitor.md"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=../../../scripts/test-helpers.sh
source "$SCRIPT_DIR/../../../scripts/test-helpers.sh"

command -v jq >/dev/null 2>&1 || skip_suite "jq not installed"

STUB_DIR="$TEST_TMPDIR/stubs"
mkdir -p "$STUB_DIR"

# The first fenced block under the heading, with the placeholders filled in: no sleep between
# polls, the baseline file taken from the environment, the threads script stubbed.
POLL="$TEST_TMPDIR/poll.sh"
# shellcheck disable=SC2016 # the ${TEST_BASELINE:-} expansion is meant for the generated script, not this one
awk '/^## Poll checks over REST/ { on = 1 } on && /^```bash/ { f = 1; next } f && /^```/ { exit } f' "$REF" |
  sed -e 's/^PR_NUMBER=<N>/PR_NUMBER=5/' \
    -e 's/^INTERVAL=60.*/INTERVAL=0/' \
    -e 's/^BASELINE_FILE=  #.*/BASELINE_FILE="${TEST_BASELINE:-}"/' \
    -e "s#<scripts-dir>#$STUB_DIR#" >"$POLL"
[[ -s "$POLL" ]] || {
  echo "FAIL: no poll script found in $REF" >&2
  exit 1
}

printf '#!/usr/bin/env bash\necho "THREADS_OK unresolved=0"\n' >"$STUB_DIR/source-control-review-threads"

# The PR is open for the first read and merged for the second, so the watch runs one poll and
# exits. The checks a and b are finished, c is still running.
cat >"$STUB_DIR/gh" <<'STUB_EOF'
#!/usr/bin/env bash
if [[ "$1 $2" == "repo view" ]]; then
  [[ "$*" == *owner* ]] && echo acme || echo app
  exit 0
fi
[[ "$1" == api ]] || exit 1
case "$*" in
*/check-runs*)
  printf '%s' '{"check_runs":[
    {"name":"a","check_suite":{"id":1},"started_at":"2026-01-01T00:00:00Z","status":"completed","conclusion":"success"},
    {"name":"b","check_suite":{"id":1},"started_at":"2026-01-01T00:00:00Z","status":"completed","conclusion":"success"},
    {"name":"c","check_suite":{"id":1},"started_at":"2026-01-01T00:00:00Z","status":"in_progress","conclusion":null}]}'
  ;;
*/pulls/5\ *)
  n=$(cat "$GH_STUB_COUNT" 2>/dev/null || echo 0)
  echo $((n + 1)) >"$GH_STUB_COUNT"
  [[ "$n" -eq 0 ]] && echo "OPEN h1" || echo "MERGED h1"
  ;;
esac
exit 0
STUB_EOF
chmod +x "$STUB_DIR/gh"

run_poll() {
  rm -f "$TEST_TMPDIR/count"
  PATH="$STUB_DIR:$PATH" GH_STUB_COUNT="$TEST_TMPDIR/count" timeout 30 bash "$POLL" 2>&1
}

out=$(TEST_BASELINE="" run_poll)
assert_exit "no baseline: the watch runs to the merge and exits 0" 0 "$?"
assert_not_contains "no baseline: the first poll only records, a is not emitted" "$out" "a: pass"
assert_not_contains "no baseline: the first poll only records, b is not emitted" "$out" "b: pass"
assert_contains "no baseline: the watch completes" "$out" "PR #5 MERGED — watch complete"

printf 'a: pass\n' >"$TEST_TMPDIR/baseline"
out=$(TEST_BASELINE="$TEST_TMPDIR/baseline" run_poll)
assert_exit "baseline: the watch runs to the merge and exits 0" 0 "$?"
assert_contains "baseline: a check finished in the live read but not the baseline is emitted" "$out" "b: pass"
assert_not_contains "baseline: a check already in the baseline is not re-emitted" "$out" "a: pass"
assert_not_contains "baseline: a running check is not emitted" "$out" "c: "

out=$(TEST_BASELINE="$TEST_TMPDIR/missing" run_poll)
assert_exit "an unreadable baseline: the watch runs to the merge and exits 0" 0 "$?"
assert_contains "an unreadable baseline is reported, so the session runs a full scan" "$out" "BASELINE-UNREADABLE"
assert_contains "an unreadable baseline: the watch completes" "$out" "PR #5 MERGED — watch complete"
assert_not_contains "an unreadable baseline file falls back to record-only (a)" "$out" "a: pass"
assert_not_contains "an unreadable baseline file falls back to record-only (b)" "$out" "b: pass"

[[ $FAILED -eq 0 ]] || exit 1
exit 0
