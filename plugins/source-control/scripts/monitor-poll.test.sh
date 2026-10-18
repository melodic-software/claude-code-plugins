#!/usr/bin/env bash
# Regression tests for the PR monitor's poll script (the fenced block under
# "Poll checks over REST" in reference/providers/github/pull-request/monitor.md).
# The block is extracted from the doc and run against a stub `gh`, so the test
# drives exactly what the Monitor watch runs. No network.
#
# A failed check read must keep the baseline: the discriminating cases are a
# failed FIRST read (the second good poll must only record) and a failed read
# BETWEEN two good polls (nothing is emitted twice).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOC="$SCRIPT_DIR/../reference/providers/github/pull-request/monitor.md"

FAILED=0
CASE_NUM=0
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

command -v jq >/dev/null 2>&1 || skip_suite "jq not available"

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

BIN="$TEST_TMPDIR/bin"
mkdir -p "$BIN"

# The poll script: first fenced bash block after the "Poll checks over REST"
# heading, with its placeholders filled and the sleep removed.
POLL="$TEST_TMPDIR/poll.sh"
awk '
  /^## Poll checks over REST/ { in_sec = 1; next }
  in_sec && /^```bash/ { in_blk = 1; next }
  in_blk && /^```/ { exit }
  in_blk { print }
' "$DOC" |
  sed -e 's/<N>/7/' -e 's/^INTERVAL=60.*/INTERVAL=0/' \
    -e "s#<scripts-dir>#$BIN#" >"$POLL"
[[ -s "$POLL" ]] || { fail "extracted the poll script" "non-empty" "empty"; exit 1; }

cat >"$BIN/gh" <<'STUB'
#!/usr/bin/env bash
# Stub gh. $FX holds poll (the counter), checks.<n> (JSON, or FAIL) per poll
# and merged_at (the poll number at which the PR reports MERGED).
set -u
args="$*"
case "$args" in
  "repo view --json owner"*) echo owner ;;
  "repo view --json name"*) echo repo ;;
  *"/pulls/7 "*|*"/pulls/7")
    n=$(($(cat "$FX/poll" 2>/dev/null || echo 0) + 1))
    echo "$n" >"$FX/poll"
    if [ "$n" -ge "$(cat "$FX/merged_at")" ]; then echo "MERGED sha1"; else echo "OPEN sha1"; fi ;;
  *"/actions/runs"*)
    n=$(cat "$FX/poll")
    [ "$(cat "$FX/fault.$n" 2>/dev/null)" = actions ] && { echo "boom: transient" >&2; exit 1; } ;;
  *"/check-runs"*)
    n=$(cat "$FX/poll")
    [ "$(cat "$FX/fault.$n" 2>/dev/null)" = ratelimit ] && { echo "API rate limit exceeded" >&2; exit 1; }
    if [ "$(cat "$FX/checks.$n")" = FAIL ]; then echo "boom: transient" >&2; exit 1; fi
    cat "$FX/checks.$n" ;;
  *"/status"*)
    n=$(cat "$FX/poll")
    [ "$(cat "$FX/fault.$n" 2>/dev/null)" = status ] && { echo "boom: transient" >&2; exit 1; } ;;
  *) ;;
esac
exit 0
STUB
cat >"$BIN/sleep" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
cat >"$BIN/source-control-review-threads" <<'STUB'
echo "THREADS_OK unresolved=0"
STUB
chmod +x "$BIN/gh" "$BIN/sleep"

# runs_json <name>... — a check-runs payload with each named check completed.
runs_json() {
  local out="" n
  for n in "$@"; do
    out+="${out:+,}{\"name\":\"$n\",\"check_suite\":{\"id\":1},\"started_at\":\"t\",\"status\":\"completed\",\"conclusion\":\"success\"}"
  done
  printf '{"check_runs":[%s]}' "$out"
}

# run_poll <fixture-dir> — runs the poll script against the stub; stdout only.
run_poll() {
  FX="$1" PATH="$BIN:$PATH" timeout 60 bash "$POLL" 2>/dev/null
}

# --- failed FIRST read: the second poll is the baseline, the third emits once.
FX1="$TEST_TMPDIR/fx1"
mkdir -p "$FX1"
echo FAIL >"$FX1/checks.1"
runs_json a b >"$FX1/checks.2"
runs_json a b c >"$FX1/checks.3"
echo 4 >"$FX1/merged_at"
out1="$(run_poll "$FX1")"
assert_not_contains "failed first read: check a not emitted" "$out1" "a: pass"
assert_not_contains "failed first read: check b not emitted" "$out1" "b: pass"
assert_eq "failed first read: only c is emitted, once" "1" "$(grep -c '^c: pass$' <<<"$out1")"
assert_contains "failed first read: watch completes" "$out1" "PR #7 MERGED — watch complete"

# --- failed read BETWEEN two good polls: nothing is emitted twice.
FX2="$TEST_TMPDIR/fx2"
mkdir -p "$FX2"
runs_json a >"$FX2/checks.1"
echo FAIL >"$FX2/checks.2"
runs_json a b >"$FX2/checks.3"
echo 4 >"$FX2/merged_at"
out2="$(run_poll "$FX2")"
assert_not_contains "failed middle read: baseline check a not emitted" "$out2" "a: pass"
assert_eq "failed middle read: b is emitted exactly once" "1" "$(grep -c '^b: pass$' <<<"$out2")"

# --- no failures: behavior unchanged (baseline silent, later check emitted).
FX3="$TEST_TMPDIR/fx3"
mkdir -p "$FX3"
runs_json a >"$FX3/checks.1"
runs_json a b >"$FX3/checks.2"
echo 3 >"$FX3/merged_at"
out3="$(run_poll "$FX3")"
assert_not_contains "clean polls: baseline check a not emitted" "$out3" "a: pass"
assert_eq "clean polls: b is emitted once" "1" "$(grep -c '^b: pass$' <<<"$out3")"

# --- a fault in any single call of the read (actions/runs, status) keeps the
# baseline too: poll 1 faults, poll 2 is the baseline, poll 3 adds c.
for fault in actions status; do
  FXF="$TEST_TMPDIR/fx-$fault"
  mkdir -p "$FXF"
  runs_json a b >"$FXF/checks.1"
  echo "$fault" >"$FXF/fault.1"
  runs_json a b >"$FXF/checks.2"
  runs_json a b c >"$FXF/checks.3"
  echo 4 >"$FXF/merged_at"
  outf="$(run_poll "$FXF")"
  assert_not_contains "faulted $fault read: check a not emitted" "$outf" "a: pass"
  assert_eq "faulted $fault read: only c is emitted, once" "1" "$(grep -c '^c: pass$' <<<"$outf")"
  assert_contains "faulted $fault read: watch completes" "$outf" "PR #7 MERGED — watch complete"
done

# --- a rate limit on the check read still stops the watch with exit 2.
FX4="$TEST_TMPDIR/fx4"
mkdir -p "$FX4"
runs_json a >"$FX4/checks.1"
echo ratelimit >"$FX4/fault.1"
echo 9 >"$FX4/merged_at"
out4="$(run_poll "$FX4")"
rc4=$?
assert_eq "rate limit: exit status" "2" "$rc4"
assert_contains "rate limit: RATE-LIMITED line" "$out4" "RATE-LIMITED"

[[ $FAILED -eq 0 ]] || exit 1
