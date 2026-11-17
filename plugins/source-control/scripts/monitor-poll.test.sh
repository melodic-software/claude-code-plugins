#!/usr/bin/env bash
# Regression tests for the PR monitor's poll script,
# skills/pull-request/scripts/monitor-poll.sh, the command the Monitor watch
# runs. It runs from a copy of the plugin's layout against a stub `gh`. No
# network.
#
# A failed check read must keep the baseline: the discriminating cases are a
# failed FIRST read (the second good poll must only record) and a failed read
# BETWEEN two good polls (nothing is emitted twice).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$SCRIPT_DIR/../skills/pull-request/scripts/monitor-poll.sh"

FAILED=0
CASE_NUM=0
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

command -v jq >/dev/null 2>&1 || skip_suite "jq not available"

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT
# Children that call mktemp land inside the trapped root.
export TMPDIR="$TEST_TMPDIR"

BIN="$TEST_TMPDIR/bin"
mkdir -p "$BIN"

# <checkout>: a checkout whose one GitHub remote is owner/repo, the only
# source of the repository the poll reads.
CHECKOUT="$TEST_TMPDIR/checkout"
git init -q "$CHECKOUT"
git -C "$CHECKOUT" remote add origin https://github.com/owner/repo.git
unset GH_REPO

# The poll script in a copy of the plugin's layout: target-repo.sh and its
# library are the real ones, the threads script is a stub (below).
PLUGIN="$TEST_TMPDIR/plugin"
mkdir -p "$PLUGIN/skills/pull-request/scripts" "$PLUGIN/scripts" "$PLUGIN/lib"
cp -p "$SRC" "$SCRIPT_DIR/../skills/pull-request/scripts/target-repo.sh" "$PLUGIN/skills/pull-request/scripts/"
cp -p "$SCRIPT_DIR/../lib/github-remote.sh" "$PLUGIN/lib/"
POLL="$PLUGIN/skills/pull-request/scripts/monitor-poll.sh"

cat >"$BIN/gh" <<'STUB'
#!/usr/bin/env bash
# Stub gh. $FX holds poll (the counter), checks.<n> (JSON, or FAIL) per poll
# and merged_at (the poll number at which the PR reports MERGED).
set -u
args="$*"
case "$args" in
  "repo set-default --view"*) echo "No default remote repository has been set." >&2 ;;
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
  *"/issues/7/comments"*)
    n=$(cat "$FX/poll")
    [ "$(cat "$FX/fault.$n" 2>/dev/null)" = comments-ratelimit ] && { echo "API rate limit exceeded" >&2; exit 1; } ;;
  *) ;;
esac
exit 0
STUB
# The threads read is poll 1's last call; its marker tells a test poll 1 ran.
cat >"$PLUGIN/scripts/source-control-review-threads" <<'STUB'
touch "$FX/threads-read"
echo "THREADS_OK unresolved=0"
STUB
chmod +x "$BIN/gh"

# runs_json <name>... — a check-runs payload with each named check completed.
runs_json() {
  local out="" n
  for n in "$@"; do
    out+="${out:+,}{\"name\":\"$n\",\"check_suite\":{\"id\":1},\"started_at\":\"t\",\"status\":\"completed\",\"conclusion\":\"success\"}"
  done
  printf '{"check_runs":[%s]}' "$out"
}

# run_poll <fixture-dir> [arg...] — runs the poll script on PR 7 against the
# stub, with no sleep between polls and any further arguments passed on;
# stdout only. Any temp file it made would land in POLL_TMP, which must stay
# empty.
POLL_TMP="$TEST_TMPDIR/poll-tmp"
mkdir -p "$POLL_TMP"
run_poll() {
  (cd "$TEST_TMPDIR" && FX="$1" TMPDIR="$POLL_TMP" PATH="$BIN:$PATH" \
    timeout 60 bash "$POLL" --pr 7 --interval 0 --checkout "$CHECKOUT" "${@:2}" 2>/dev/null)
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

# --- --once: the run ends after the first poll that prints a line, long
# before the PR merges.
FX7="$TEST_TMPDIR/fx7"
mkdir -p "$FX7"
runs_json a >"$FX7/checks.1"
runs_json a b >"$FX7/checks.2"
echo 9 >"$FX7/merged_at"
out7="$(run_poll "$FX7" --once)"
assert_exit "--once: exits 0 after the poll that printed" 0 "$?"
assert_eq "--once: b is emitted once" "1" "$(grep -c '^b: pass$' <<<"$out7")"
assert_not_contains "--once: the watch does not run on to the merge" "$out7" "watch complete"
assert_eq "--once: it stopped after poll 2" "2" "$(cat "$FX7/poll")"

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

# --- a rate limit on a later read of the poll (the comment reads) still stops
# the watch: stderr from every read collects in one variable.
FX6="$TEST_TMPDIR/fx6"
mkdir -p "$FX6"
runs_json a >"$FX6/checks.1"
echo comments-ratelimit >"$FX6/fault.1"
echo 9 >"$FX6/merged_at"
out6="$(run_poll "$FX6")"
rc6=$?
assert_eq "comment-read rate limit: exit status" "2" "$rc6"
assert_contains "comment-read rate limit: names the error" "$out6" "RATE-LIMITED — watch stopped: API rate limit exceeded"

# --- the script runs no rm and makes no temp file: an auto-mode session's
# safety check denied a Monitor command that ran rm.
assert_eq "poll script runs no rm" "" "$(grep -nE '(^|[^[:alnum:]_-])rm([^[:alnum:]_-]|$)' "$SRC")"
assert_eq "poll script makes no temp file" "" "$(grep -n 'mktemp' "$SRC")"

# --- a stopped watch exits. TaskStop sends TERM to the watch and its
# children; the real sleep holds the watch inside its loop until then.
FX5="$TEST_TMPDIR/fx5"
mkdir -p "$FX5"
runs_json a >"$FX5/checks.1"
echo 9 >"$FX5/merged_at"
FX="$FX5" TMPDIR="$POLL_TMP" PATH="$BIN:$PATH" bash "$POLL" --pr 7 --interval 30 --checkout "$CHECKOUT" >"$TEST_TMPDIR/out5" 2>&1 &
pid5=$!
for _ in $(seq 100); do
  [[ -e "$FX5/threads-read" ]] && break
  sleep 0.1
done
sleep 0.5 # the rate-limit check ends poll 1, then its sleep starts
assert_eq "running watch: poll 1 reached its threads read" "yes" "$([[ -e "$FX5/threads-read" ]] && echo yes || echo no)"
# target-repo.sh names the repository on stderr; any other line is an error.
assert_eq "running watch: poll 1 ran clean" "" "$(grep -v '^target repository: ' "$TEST_TMPDIR/out5")"
kill -TERM "$pid5" 2>/dev/null
pkill -TERM -P "$pid5" 2>/dev/null
for _ in $(seq 50); do
  kill -0 "$pid5" 2>/dev/null || break
  sleep 0.1
done
assert_eq "stopped watch: it exits within 5s of TERM" "gone" "$(kill -0 "$pid5" 2>/dev/null && echo running || echo gone)"
kill -0 "$pid5" 2>/dev/null && kill -KILL "$pid5" 2>/dev/null
wait "$pid5" 2>/dev/null

# Every run above ended (merged, rate-limited, stopped); none wrote a file.
assert_eq "poll script leaves no temp file behind" "" "$(find "$POLL_TMP" -mindepth 1)"

[[ $FAILED -eq 0 ]] || exit 1
