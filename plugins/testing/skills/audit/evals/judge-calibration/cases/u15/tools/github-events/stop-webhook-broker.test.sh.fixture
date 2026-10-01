#!/usr/bin/env bash
# Regression tests for tools/github-events/stop-webhook-broker.sh.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/stop-webhook-broker.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=../../tests/shell/lib.sh
source "${TEST_REPO_ROOT:-$(git rev-parse --show-toplevel)}/tests/shell/lib.sh"

# --- Case 1: --help prints script header and exits 0 ---------------------

out=$(bash "$SCRIPT" --help 2>&1)
status=$?
assert_exit "help exits 0" 0 "$status"
assert_contains "help mentions Usage" "$out" "Usage:"

# --- Case 2: unknown argument exits 3 ------------------------------------

out=$(bash "$SCRIPT" --bogus 2>&1)
status=$?
assert_exit "unknown arg exits 3" 3 "$status"
assert_contains "unknown arg error" "$out" "unknown argument"

# --- Case 3: no PID file → exit 0 with message ---------------------------

slug="ut-no-pid-$RANDOM"
out=$(GITHUB_EVENTS_REPO_SLUG="$slug" GITHUB_EVENTS_STATE_DIR="$TEST_TMPDIR" bash "$SCRIPT" 2>&1)
status=$?
assert_exit "no PID file exits 0" 0 "$status"
assert_contains "no-PID-file message" "$out" "nothing to stop"

# --- Case 4: stale PID file (PID not alive) → cleans up + exit 0 ---------

slug="ut-stale-$RANDOM"
pid_file="$TEST_TMPDIR/broker-$slug.pid"
echo "999999" >"$pid_file"

out=$(GITHUB_EVENTS_REPO_SLUG="$slug" GITHUB_EVENTS_STATE_DIR="$TEST_TMPDIR" bash "$SCRIPT" 2>&1)
status=$?
assert_exit "stale PID exits 0" 0 "$status"
assert_contains "stale PID message" "$out" "not alive"
assert_file_absent "stale PID file removed" "$pid_file"

# --- Case 6: empty PID file → cleans up + exit 0 -------------------------

slug="ut-empty-$RANDOM"
pid_file="$TEST_TMPDIR/broker-$slug.pid"
: >"$pid_file"

out=$(GITHUB_EVENTS_REPO_SLUG="$slug" GITHUB_EVENTS_STATE_DIR="$TEST_TMPDIR" bash "$SCRIPT" 2>&1)
status=$?
assert_exit "empty PID exits 0" 0 "$status"
assert_file_absent "empty PID file removed" "$pid_file"

# --- Case 7: PID reuse — alive PID belongs to a non-node process ---------
# After a broker crash, the kernel may reassign the stale PID to an unrelated
# process. The script must NOT signal that process.

slug="ut-reuse-$RANDOM"
pid_file="$TEST_TMPDIR/broker-$slug.pid"

# Spawn a long-running non-node process whose PID we'll squat on. `sleep 60`
# is portable across Linux, macOS, and Git Bash.
sleep 60 &
victim_pid=$!
echo "$victim_pid" >"$pid_file"

out=$(GITHUB_EVENTS_REPO_SLUG="$slug" GITHUB_EVENTS_STATE_DIR="$TEST_TMPDIR" bash "$SCRIPT" 2>&1)
status=$?

assert_exit "PID-reuse exits 0" 0 "$status"
assert_contains "PID-reuse message" "$out" "assuming PID reuse"
assert_file_absent "PID-reuse PID file removed" "$pid_file"

# CRITICAL: the unrelated process must STILL be alive — the script must not
# have signaled it. If kill -0 fails, the script killed our victim (the bug).
if kill -0 "$victim_pid" 2>/dev/null; then
  pass "PID-reuse victim still alive (not signaled)"
else
  fail "PID-reuse victim still alive (not signaled)" "alive" "killed by stop script"
fi

# Cleanup: dispatch the sleep ourselves.
kill "$victim_pid" 2>/dev/null || true
wait "$victim_pid" 2>/dev/null || true

# --- Case 8: PID reuse — alive PID is a Node process but NOT our broker --
# A bare comm=node check is too loose — many node-based tools (npm, vite,
# ts-node, claude code) would match. The args check must verify the FULL
# command line includes build/broker/index.js.

if command -v node >/dev/null 2>&1; then
  slug="ut-reuse-node-$RANDOM"
  pid_file="$TEST_TMPDIR/broker-$slug.pid"

  # Spawn a long-running node process running an inline script — its `args`
  # will be "node -e ..." with no `build/broker/index.js` substring.
  node -e 'setInterval(()=>{}, 1000)' &
  victim_pid=$!
  echo "$victim_pid" >"$pid_file"

  out=$(GITHUB_EVENTS_REPO_SLUG="$slug" GITHUB_EVENTS_STATE_DIR="$TEST_TMPDIR" bash "$SCRIPT" 2>&1)
  status=$?

  assert_exit "node-not-broker exits 0" 0 "$status"
  assert_contains "node-not-broker message" "$out" "does not appear to be our broker"
  assert_file_absent "node-not-broker PID file removed" "$pid_file"

  if kill -0 "$victim_pid" 2>/dev/null; then
    pass "node-not-broker victim still alive (not signaled)"
  else
    fail "node-not-broker victim still alive (not signaled)" "alive" "killed by stop script"
  fi

  kill "$victim_pid" 2>/dev/null || true
  wait "$victim_pid" 2>/dev/null || true
else
  printf 'SKIP: Case 8 (node-not-broker) — node not on PATH\n' >&2
fi

# --- Case 9: relative-path broker invocation (npm run start:broker) ------
# `npm run start:broker` invokes `node build/broker/index.js` from the package
# directory — a RELATIVE path with no separator before `build`. The previous
# pattern required a leading `/` or `\`, which misclassified the live broker as
# PID reuse, removed state files, and exited without signaling.
#
# Requires `ps -p <pid> -o args=` to actually return the command line. On
# Git Bash on Windows, MSYS `ps` does not support `-o args=` (errors with
# "unknown option -- o") so the broker-identity check always returns empty
# and the script falls through to the "not our broker" path regardless of
# pattern shape. Skip this case there — the pattern fix is validated by
# CI (ubuntu-latest, GNU procps).

ps_supports_args() {
  local probe
  probe=$(ps -p $$ -o args= 2>/dev/null) || return 1
  [[ -n "$probe" ]]
}

if ! command -v node >/dev/null 2>&1; then
  printf 'SKIP: Case 9 (relative-path broker) — node not on PATH\n' >&2
elif ! ps_supports_args; then
  printf 'SKIP: Case 9 (relative-path broker) — ps -p X -o args= unsupported (likely Git Bash MSYS)\n' >&2
else
  slug="ut-rel-$RANDOM"
  pid_file="$TEST_TMPDIR/broker-$slug.pid"

  # Create a fake broker index.js under build/broker/ inside a tmpdir,
  # then cd into the tmpdir and spawn `node build/broker/index.js`. ps
  # will report args as "node build/broker/index.js" with no separator
  # before `build` — exactly the npm-run-start:broker shape.
  fake_pkg="$TEST_TMPDIR/fake-pkg-$slug"
  mkdir -p "$fake_pkg/build/broker"
  printf '%s\n' \
    "process.on('SIGINT', () => process.exit(0));" \
    "setInterval(() => {}, 1000);" >"$fake_pkg/build/broker/index.js"

  # `exec` replaces the subshell with node so $! is the node PID (not the
  # subshell's). Without it, ps -p $! reports the bash subshell's args
  # ("bash") and the broker-identity check fails on its own test fixture.
  (cd "$fake_pkg" && exec node build/broker/index.js) &
  victim_pid=$!
  echo "$victim_pid" >"$pid_file"

  # Give node a moment to settle so ps reports stable args.
  sleep 0.5

  out=$(GITHUB_EVENTS_REPO_SLUG="$slug" GITHUB_EVENTS_STATE_DIR="$TEST_TMPDIR" bash "$SCRIPT" 2>&1)
  status=$?

  assert_exit "relative-path broker exits 0" 0 "$status"
  assert_contains "relative-path broker signaled" "$out" "Stopping broker"
  assert_not_contains "relative-path NOT misclassified as PID reuse" \
    "$out" "assuming PID reuse"
  assert_not_contains "relative-path NOT misclassified as not-our-broker" \
    "$out" "does not appear to be our broker"
  assert_file_absent "relative-path PID file removed" "$pid_file"

  # Victim must NOT still be alive — script should have SIGINTed it and
  # the inline trap exits cleanly.
  if kill -0 "$victim_pid" 2>/dev/null; then
    fail "relative-path broker stopped" "exited" "still alive"
    kill -KILL "$victim_pid" 2>/dev/null || true
  else
    pass "relative-path broker stopped"
  fi
  wait "$victim_pid" 2>/dev/null || true
fi

[[ $FAILED -eq 0 ]] || exit 1

# --- Case 9: stale-PID gate is winpid-aware (W1-B / codex r3327743095) -------
SUT_BODY=$(cat "$SCRIPT")
if [[ "$SUT_BODY" == *'pid-alive.sh'* ]]; then
  pass "case 9: stop sources pid-alive.sh"
else
  fail "case 9: stop sources pid-alive.sh" "present" "missing"
fi
if [[ "$SUT_BODY" == *'pid::is_alive "$PID"'* ]]; then
  pass "case 9: stale-PID cleanup uses pid::is_alive"
else
  fail "case 9: stale-PID cleanup uses pid::is_alive" "present" "missing"
fi
if [[ "$SUT_BODY" == *'! kill -0 "$PID"'* ]]; then
  fail "case 9: no bare kill -0 stale-PID gate" "absent" "still present"
else
  pass "case 9: no bare kill -0 stale-PID gate"
fi

echo "All cases passed ($CASE_NUM)."
