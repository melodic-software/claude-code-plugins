#!/usr/bin/env bash
# Regression tests for lane-launcher.sh.
#
# Coverage:
#   - config resolution + validation (missing / malformed / empty-lanes)
#   - status renders per-lane running/stopped state from an --agents-json fixture
#   - start (dry-run): launches only lanes not already running; mirrors
#     model/effort onto the command; keeps the prompt body out of the echo
#   - start refresh step: pull + marketplace update lines; --no-pull / --no-update
#   - restart (dry-run): stop-then-start for a running lane
#   - stop (real dispatch, PATH-stub claude): stops only running configured lanes
#   - stop / restart of an unknown lane name is rejected (exit 3)
#   - missing / empty prompt file and invalid effort are skipped, not launched
#
# Uses a per-suite fixture repo (config + prompt files) and PATH-stub `claude`
# and `git` so no real CLI or network is touched.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/lane-launcher.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAILED=0
CASE_NUM=0
pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: [%d] %s\n' "$CASE_NUM" "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'FAIL: [%d] %s\n      expected: %q\n      got:      %q\n' "$CASE_NUM" "$1" "$2" "$3" >&2
  FAILED=$((FAILED + 1))
}
assert_eq() { if [[ "$3" == "$2" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi; }
assert_contains() { if [[ "$2" == *"$3"* ]]; then pass "$1"; else fail "$1" "contains: $3" "$2"; fi; }
assert_not_contains() { if [[ "$2" != *"$3"* ]]; then pass "$1"; else fail "$1" "absent: $3" "$2"; fi; }

# --- Fixture repo -------------------------------------------------------------
REPO="$TMP/repo"
mkdir -p "$REPO/.work"
cat >"$REPO/.work/lanes.json" <<'JSON'
{
  "prompt_dir": ".work",
  "lanes": [
    { "name": "work",    "prompt": "work.md",    "model": "opus",   "effort": "high" },
    { "name": "babysit", "prompt": "babysit.md", "model": "sonnet", "effort": "medium" },
    { "name": "decide",  "prompt": "decide.md" }
  ]
}
JSON
printf 'You are the work lane.\n' >"$REPO/.work/work.md"
printf 'You are the babysit lane.\n' >"$REPO/.work/babysit.md"
printf 'You are the decide lane.\n' >"$REPO/.work/decide.md"

CONFIG="$REPO/.work/lanes.json"

# agents --json fixture: "work" running as a background session, others absent.
AGENTS_RUNNING="$TMP/agents-running.json"
cat >"$AGENTS_RUNNING" <<'JSON'
[
  { "pid": 111, "cwd": "/repo", "kind": "background", "startedAt": 100,
    "sessionId": "sid-work-1", "name": "work", "status": "idle" },
  { "pid": 222, "cwd": "/repo", "kind": "interactive", "startedAt": 90,
    "sessionId": "sid-other", "name": "PR Babysit", "status": "busy" }
]
JSON
AGENTS_EMPTY="$TMP/agents-empty.json"
echo '[]' >"$AGENTS_EMPTY"

# --- PATH-stub claude + git (log every invocation) ----------------------------
STUB_BIN="$TMP/bin"
mkdir -p "$STUB_BIN"
CLAUDE_LOG="$TMP/claude.log"
cat >"$STUB_BIN/claude" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$CLAUDE_LOG"
# A test can force a failed \`claude stop\` via STUB_CLAUDE_STOP_RC to exercise
# the stop-failure paths (no relaunch, non-zero exit).
if [[ "\$1" == "stop" ]]; then exit "\${STUB_CLAUDE_STOP_RC:-0}"; fi
STUB
cat >"$STUB_BIN/git" <<STUB
#!/usr/bin/env bash
printf 'git %s\n' "\$*" >>"$CLAUDE_LOG"
STUB
chmod +x "$STUB_BIN/claude" "$STUB_BIN/git"

# Hermetic: the suite must not depend on an ambient `claude` (CI runners have
# none). Every case resolves `claude`/`git` to the logging stubs; cases that
# inspect the log reset it first. Real git is never needed — repos are passed
# via --repo, so resolve_repo never shells out.
export PATH="$STUB_BIN:$PATH"

run_launcher() { bash "$SCRIPT" "$@"; }

# ============================================================================
# Config resolution + validation
# ============================================================================
out="$(run_launcher status --repo "$REPO" --config "$TMP/nope.json" --agents-json "$AGENTS_EMPTY" 2>&1)"
rc=$?
assert_eq "missing config exits 4" 4 "$rc"
assert_contains "missing config message" "$out" "lane config not found"

echo '{ not json' >"$TMP/bad.json"
out="$(run_launcher status --repo "$REPO" --config "$TMP/bad.json" --agents-json "$AGENTS_EMPTY" 2>&1)"
rc=$?
assert_eq "malformed config exits 3" 3 "$rc"

echo '{ "lanes": [] }' >"$TMP/empty.json"
out="$(run_launcher status --repo "$REPO" --config "$TMP/empty.json" --agents-json "$AGENTS_EMPTY" 2>&1)"
rc=$?
assert_eq "empty-lanes config exits 3" 3 "$rc"

# ============================================================================
# status
# ============================================================================
out="$(run_launcher status --repo "$REPO" --config "$CONFIG" --agents-json "$AGENTS_RUNNING" 2>&1)"
assert_contains "status: work is running" "$out" "work"
assert_contains "status: work shows sessionId" "$out" "sid-work-1"
assert_contains "status: work state running" "$out" "running"
assert_contains "status: decide present" "$out" "decide"
assert_contains "status: decide stopped" "$out" "stopped"
assert_not_contains "status ignores non-lane sessions" "$out" "sid-other"

# ============================================================================
# start (dry-run) — launch only lanes not already running
# ============================================================================
out="$(run_launcher start --repo "$REPO" --config "$CONFIG" --agents-json "$AGENTS_RUNNING" --dry-run 2>&1)"
assert_contains "start skips running lane" "$out" "skip work — already running"
assert_contains "start launches babysit" "$out" "claude --bg -n babysit"
assert_contains "start mirrors babysit model" "$out" "--model sonnet"
assert_contains "start mirrors babysit effort" "$out" "--effort medium"
assert_contains "start seeds prompt as placeholder" "$out" "<prompt:"
assert_not_contains "start hides prompt body" "$out" "You are the babysit lane"
assert_contains "start launches decide (no model/effort)" "$out" "claude --bg -n decide"
assert_not_contains "decide has no model flag" "$out" "-n decide --model"

# refresh step present by default; suppressible
assert_contains "start pulls by default" "$out" "git -C $REPO pull --ff-only"
assert_contains "start updates marketplace" "$out" "plugin marketplace update"
out2="$(run_launcher start --repo "$REPO" --config "$CONFIG" --agents-json "$AGENTS_EMPTY" --dry-run --no-pull --no-update 2>&1)"
assert_contains "--no-pull skips pull" "$out2" "skip git pull"
assert_contains "--no-update skips update" "$out2" "skip plugin marketplace update"
assert_contains "empty agents → all lanes start" "$out2" "claude --bg -n work"

# ============================================================================
# restart (dry-run) — stop then start a running lane
# ============================================================================
out="$(run_launcher restart work --repo "$REPO" --config "$CONFIG" --agents-json "$AGENTS_RUNNING" --dry-run 2>&1)"
assert_contains "restart stops running work" "$out" "stop work (sid-work-1)"
assert_contains "restart relaunches work" "$out" "claude --bg -n work"
assert_not_contains "restart scoped to work" "$out" "claude --bg -n babysit"

# ============================================================================
# stop (real dispatch via PATH-stub claude)
# ============================================================================
: >"$CLAUDE_LOG"
out="$(run_launcher stop --repo "$REPO" --config "$CONFIG" --agents-json "$AGENTS_RUNNING" 2>&1)"
log="$(cat "$CLAUDE_LOG")"
assert_contains "stop dispatches claude stop for running lane" "$log" "stop sid-work-1"
assert_contains "stop reports non-running lanes" "$out" "babysit — not running"
assert_not_contains "stop never targets a non-lane session" "$log" "sid-other"

# ============================================================================
# start (REAL dispatch via PATH-stub claude + git) — proves the launch path
# actually shells out: pull, marketplace update, and `claude --bg` seeded with
# the prompt-file BODY as a single trailing argument (not --dry-run).
# ============================================================================
: >"$CLAUDE_LOG"
out="$(run_launcher start --repo "$REPO" --config "$CONFIG" --agents-json "$AGENTS_EMPTY" 2>&1)"
log="$(cat "$CLAUDE_LOG")"
assert_contains "start really pulls the repo" "$log" "git -C $REPO pull --ff-only"
assert_contains "start really updates the marketplace" "$log" "plugin marketplace update"
assert_contains "start really launches work with model+effort" "$log" "--bg -n work --model opus --effort high"
assert_contains "start seeds the prompt-file body as the trailing arg" "$log" "--effort high You are the work lane."
assert_contains "start really launches babysit" "$log" "--bg -n babysit --model sonnet --effort medium"

# ============================================================================
# unknown lane rejected
# ============================================================================
out="$(run_launcher stop bogus --repo "$REPO" --config "$CONFIG" --agents-json "$AGENTS_EMPTY" 2>&1)"
rc=$?
assert_eq "stop unknown lane exits 3" 3 "$rc"
assert_contains "stop unknown lane message" "$out" "unknown lane 'bogus'"

# ============================================================================
# missing / empty prompt + invalid effort are skipped, not launched
# ============================================================================
cat >"$TMP/badprompt.json" <<'JSON'
{ "prompt_dir": ".work",
  "lanes": [
    { "name": "gone",  "prompt": "missing.md" },
    { "name": "blank", "prompt": "blank.md" },
    { "name": "baddy", "prompt": "work.md", "effort": "turbo" }
  ] }
JSON
: >"$REPO/.work/blank.md"
out="$(run_launcher start --repo "$REPO" --config "$TMP/badprompt.json" --agents-json "$AGENTS_EMPTY" --dry-run 2>&1)"
assert_contains "missing prompt file skipped" "$out" "prompt file not found"
assert_contains "empty prompt file skipped" "$out" "prompt file is empty"
assert_contains "invalid effort skipped" "$out" "invalid effort 'turbo'"
assert_not_contains "no launch for bad lanes" "$out" "claude --bg -n baddy"

# ============================================================================
# Medium 1 — an option must not swallow the next flag as its value
# ============================================================================
out="$(run_launcher status --config --dry-run --repo "$REPO" 2>&1)"
rc=$?
assert_eq "--config --dry-run rejected (exit 3)" 3 "$rc"
assert_contains "flag-squash message names the option" "$out" "option '--config' requires a non-option argument"
out="$(run_launcher status --repo --agents-json "$AGENTS_EMPTY" 2>&1)"
rc=$?
assert_eq "--repo followed by a flag rejected (exit 3)" 3 "$rc"
out="$(run_launcher status --agents-json --config "$CONFIG" --repo "$REPO" 2>&1)"
rc=$?
assert_eq "--agents-json followed by a flag rejected (exit 3)" 3 "$rc"

# ============================================================================
# Medium 3 — partial failure surfaces in the exit status (sweep still completes)
# ============================================================================
out="$(run_launcher start --repo "$REPO" --config "$TMP/badprompt.json" --agents-json "$AGENTS_EMPTY" 2>&1)"
rc=$?
assert_eq "partial launch failure exits non-zero" 1 "$rc"
out="$(run_launcher start --repo "$REPO" --config "$CONFIG" --agents-json "$AGENTS_EMPTY" 2>&1)"
rc=$?
assert_eq "all-lanes-ok start exits 0" 0 "$rc"

# ============================================================================
# Medium 3 / stop exit code — a failed `claude stop` must not relaunch, exits non-zero
# ============================================================================
: >"$CLAUDE_LOG"
out="$(STUB_CLAUDE_STOP_RC=1 run_launcher restart work --repo "$REPO" --config "$CONFIG" --agents-json "$AGENTS_RUNNING" 2>&1)"
rc=$?
log="$(cat "$CLAUDE_LOG")"
assert_eq "restart with failed stop exits non-zero" 1 "$rc"
assert_contains "restart with failed stop refuses relaunch" "$out" "not relaunching"
assert_not_contains "no relaunch after failed stop" "$log" "--bg -n work"
out="$(STUB_CLAUDE_STOP_RC=1 run_launcher stop work --repo "$REPO" --config "$CONFIG" --agents-json "$AGENTS_RUNNING" 2>&1)"
rc=$?
assert_eq "stop with failed claude stop exits non-zero" 1 "$rc"
assert_contains "stop failure reported" "$out" "work — stop failed"

# ============================================================================
# Low-priority carry-forwards — uncovered flag paths
# ============================================================================
out="$(run_launcher status --repo "$REPO" --config "$CONFIG" --agents-json "$TMP/no-such-agents.json" 2>&1)"
rc=$?
assert_eq "--agents-json missing file exits 4" 4 "$rc"
assert_contains "--agents-json missing file message" "$out" "agents-json file not found"
# `--` ends option parsing: tokens after it are lane names (options must precede it).
out="$(run_launcher stop --repo "$REPO" --config "$CONFIG" --agents-json "$AGENTS_EMPTY" -- babysit 2>&1)"
rc=$?
assert_eq "-- passthrough: known lane after -- is accepted (exit 0)" 0 "$rc"
assert_contains "-- passthrough targets the named lane" "$out" "babysit — not running"

# ============================================================================
echo
if ((FAILED)); then
  printf 'lane-launcher.test: FAIL — %d case(s) failed\n' "$FAILED" >&2
  exit 1
fi
printf 'lane-launcher.test: PASS — %d cases\n' "$CASE_NUM"
