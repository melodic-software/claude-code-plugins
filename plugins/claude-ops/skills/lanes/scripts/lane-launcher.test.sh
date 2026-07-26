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
    { "name": "babysit", "prompt": "babysit.md", "model": "sonnet", "effort": "medium",
      "settings": { "pluginConfigs": { "autonomy@test-marketplace": { "options": { "lane_stop_gate_enabled": true } } } } },
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

# An INTERACTIVE session that happens to share a lane name ("work") must never be
# treated as the lane — it is not a `--bg` lane session.
AGENTS_INTERACTIVE_WORK="$TMP/agents-interactive-work.json"
cat >"$AGENTS_INTERACTIVE_WORK" <<'JSON'
[
  { "pid": 333, "cwd": "/repo", "kind": "interactive", "startedAt": 100,
    "sessionId": "sid-int-work", "name": "work", "status": "busy" }
]
JSON

# --- PATH-stub claude + git (log every invocation) ----------------------------
STUB_BIN="$TMP/bin"
mkdir -p "$STUB_BIN"
CLAUDE_LOG="$TMP/claude.log"
cat >"$STUB_BIN/claude" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$CLAUDE_LOG"
# A test can drive the live \`claude agents --json\` path (no --agents-json):
# STUB_CLAUDE_AGENTS_RC forces a non-zero exit (transient-failure simulation);
# STUB_CLAUDE_AGENTS_JSON supplies the emitted array (default []).
if [[ "\$1" == "agents" ]]; then
  [[ "\${STUB_CLAUDE_AGENTS_RC:-0}" != 0 ]] && exit "\$STUB_CLAUDE_AGENTS_RC"
  printf '%s\n' "\${STUB_CLAUDE_AGENTS_JSON:-[]}"
  exit 0
fi
# A test can force a failed \`claude stop\` via STUB_CLAUDE_STOP_RC to exercise
# the stop-failure paths (no relaunch, non-zero exit).
if [[ "\$1" == "stop" ]]; then exit "\${STUB_CLAUDE_STOP_RC:-0}"; fi
# A test can force a failed \`claude plugin marketplace update\` via
# STUB_CLAUDE_UPDATE_RC to exercise the refresh-failure abort path.
if [[ "\$1" == "plugin" ]]; then exit "\${STUB_CLAUDE_UPDATE_RC:-0}"; fi
STUB
cat >"$STUB_BIN/git" <<STUB
#!/usr/bin/env bash
printf 'git %s\n' "\$*" >>"$CLAUDE_LOG"
# A test can force a failed \`git pull\` via STUB_GIT_PULL_RC to exercise the
# refresh-failure abort path. git is only ever invoked for pull or rev-parse
# here (repos are passed via --repo), so matching on those subcommands is
# sufficient.
case "\$*" in
*pull*) exit "\${STUB_GIT_PULL_RC:-0}" ;;
*rev-parse*)
  [[ "\${STUB_GIT_REVPARSE_RC:-0}" != 0 ]] && exit "\${STUB_GIT_REVPARSE_RC}"
  printf '%s\n' "\${STUB_GIT_REVPARSE_SHA:-deadbeefcafefeedfacefeeddeadbeefcafefeed}"
  exit 0
  ;;
esac
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

cat >"$TMP/dupe.json" <<'JSON'
{ "lanes": [
  { "name": "work", "prompt": "work.md" },
  { "name": "work", "prompt": "babysit.md" }
] }
JSON
out="$(run_launcher start --repo "$REPO" --config "$TMP/dupe.json" --agents-json "$AGENTS_EMPTY" --dry-run 2>&1)"
rc=$?
assert_eq "duplicate lane names exit 3" 3 "$rc"
assert_contains "duplicate lane names named in message" "$out" "duplicate lane names: work"

# The lane name is also the launch-commit marker's filename (#792), so a name
# that is not a single path component would let two distinct lanes share one
# marker (`work` vs `group/../work`) or escape the data dir entirely.
for bad_name in 'group/../work' 'back\slash' '.' '..'; do
  jq -n --arg n "$bad_name" \
    '{lanes: [{name: $n, prompt: "work.md"}, {name: "other", prompt: "babysit.md"}]}' \
    >"$TMP/traversal.json"
  out="$(run_launcher start --repo "$REPO" --config "$TMP/traversal.json" --agents-json "$AGENTS_EMPTY" --dry-run 2>&1)"
  rc=$?
  assert_eq "lane name '$bad_name' is rejected with exit 3" 3 "$rc"
  assert_contains "lane name '$bad_name' is named in the message" "$out" "$bad_name"
done

# …but a name with any other punctuation stays free-form and is accepted.
cat >"$TMP/ok-name.json" <<'JSON'
{ "lanes": [ { "name": "work.2 (alt)", "prompt": "work.md" } ] }
JSON
out="$(run_launcher start --repo "$REPO" --config "$TMP/ok-name.json" --agents-json "$AGENTS_EMPTY" --dry-run 2>&1)"
rc=$?
assert_eq "a free-form lane name without path separators is accepted" 0 "$rc"

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
assert_contains "start passes babysit settings inline" "$out" "--settings"
assert_contains "start settings carry the lane config object" "$out" "lane_stop_gate_enabled"
assert_not_contains "work has no settings flag" "$out" "-n work --settings"

# per-lane settings must be a JSON object — a non-object skips that lane only
cat >"$TMP/badsettings.json" <<'JSON'
{
  "prompt_dir": ".work",
  "lanes": [
    { "name": "work",   "prompt": "work.md", "settings": "not-an-object" },
    { "name": "decide", "prompt": "decide.md" }
  ]
}
JSON
outbad="$(run_launcher start --repo "$REPO" --config "$TMP/badsettings.json" --agents-json "$AGENTS_EMPTY" --dry-run --no-pull --no-update 2>&1)"
rcbad=$?
assert_contains "non-object settings skips the lane with an error" "$outbad" "settings must be a JSON object"
assert_not_contains "non-object settings lane not launched" "$outbad" "claude --bg -n work"
assert_contains "other lanes still launch past a bad-settings lane" "$outbad" "claude --bg -n decide"
assert_eq "bad settings surfaces a non-zero exit" 1 "$rcbad"

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
# Codex P1 — restart must preflight launch inputs BEFORE stopping a running
# lane: a recoverable prompt/effort error must not take the healthy session
# down. `work` is running (sid-work-1) but its prompt file is missing, so the
# stop must never fire and the session must stay up.
# ============================================================================
cat >"$TMP/restart-badprompt.json" <<'JSON'
{ "prompt_dir": ".work",
  "lanes": [ { "name": "work", "prompt": "missing.md" } ] }
JSON
: >"$CLAUDE_LOG"
out="$(run_launcher restart work --repo "$REPO" --config "$TMP/restart-badprompt.json" --agents-json "$AGENTS_RUNNING" 2>&1)"
rc=$?
log="$(cat "$CLAUDE_LOG")"
assert_eq "restart with a bad prompt exits non-zero" 1 "$rc"
assert_contains "restart bad-prompt error surfaced" "$out" "prompt file not found"
assert_not_contains "restart does not stop the healthy running lane" "$log" "stop sid-work-1"

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
# Codex P1 — an interactive session sharing a lane name is not the lane
# (kind must be background). `start` launches the lane, `status` shows stopped,
# `stop` never targets the interactive session.
# ============================================================================
out="$(run_launcher status --repo "$REPO" --config "$CONFIG" --agents-json "$AGENTS_INTERACTIVE_WORK" 2>&1)"
assert_contains "interactive same-name is not a running lane" "$out" "stopped"
assert_not_contains "interactive same-name sessionId not shown" "$out" "sid-int-work"
out="$(run_launcher start --repo "$REPO" --config "$CONFIG" --agents-json "$AGENTS_INTERACTIVE_WORK" --dry-run 2>&1)"
assert_contains "start launches lane despite interactive namesake" "$out" "claude --bg -n work"
assert_not_contains "start does not skip work for interactive namesake" "$out" "skip work"
: >"$CLAUDE_LOG"
out="$(run_launcher stop work --repo "$REPO" --config "$CONFIG" --agents-json "$AGENTS_INTERACTIVE_WORK" 2>&1)"
log="$(cat "$CLAUDE_LOG")"
assert_contains "stop treats interactive namesake as not running" "$out" "work — not running"
assert_not_contains "stop never targets the interactive namesake" "$log" "sid-int-work"

# ============================================================================
# Codex P1 — a failed live `claude agents --json` must abort a mutating action,
# never fabricate an empty list (which would relaunch still-live lanes). These
# omit --agents-json so the live listing path is exercised via the stub.
# ============================================================================
: >"$CLAUDE_LOG"
out="$(STUB_CLAUDE_AGENTS_RC=1 run_launcher start --repo "$REPO" --config "$CONFIG" 2>&1)"
rc=$?
log="$(cat "$CLAUDE_LOG")"
assert_eq "failed live session list aborts start (exit 4)" 4 "$rc"
assert_contains "failed session list is reported" "$out" "could not list sessions"
assert_not_contains "no lane is launched when the session list failed" "$log" "--bg -n"

# A successful live list drives the same decisions as a fixture: empty → launch.
out="$(STUB_CLAUDE_AGENTS_JSON='[]' run_launcher start --repo "$REPO" --config "$CONFIG" --dry-run 2>&1)"
assert_contains "live empty session list → lanes launch" "$out" "claude --bg -n work"

# --dry-run mutates nothing, so a failed live list is tolerated (preview, exit 0)
# — preserving the documented offline-dry-run behaviour.
out="$(STUB_CLAUDE_AGENTS_RC=1 run_launcher start --repo "$REPO" --config "$CONFIG" --dry-run 2>&1)"
rc=$?
assert_eq "dry-run tolerates a failed live list (exit 0)" 0 "$rc"

# ============================================================================
# A failed pre-launch refresh ABORTS the launch: no lane is started/stopped and
# the action exits non-zero with an actionable message. The refresh is a
# documented launch prerequisite, so stale repo/plugin state must never seed
# background lanes.
# ============================================================================
: >"$CLAUDE_LOG"
out="$(STUB_GIT_PULL_RC=1 run_launcher start --repo "$REPO" --config "$CONFIG" --agents-json "$AGENTS_EMPTY" 2>&1)"
rc=$?
log="$(cat "$CLAUDE_LOG")"
assert_eq "start aborts when git pull fails (exit 1)" 1 "$rc"
assert_contains "start refresh-failure message is actionable" "$out" "refresh failed"
assert_not_contains "no lane launched after a failed pull" "$log" "--bg -n"

: >"$CLAUDE_LOG"
out="$(STUB_CLAUDE_UPDATE_RC=1 run_launcher start --repo "$REPO" --config "$CONFIG" --agents-json "$AGENTS_EMPTY" 2>&1)"
rc=$?
log="$(cat "$CLAUDE_LOG")"
assert_eq "start aborts when marketplace update fails (exit 1)" 1 "$rc"
assert_contains "start marketplace-update refresh-failure message is actionable" "$out" "refresh failed"
assert_not_contains "no lane launched after a failed update" "$log" "--bg -n"

: >"$CLAUDE_LOG"
out="$(STUB_GIT_PULL_RC=1 run_launcher restart work --repo "$REPO" --config "$CONFIG" --agents-json "$AGENTS_RUNNING" 2>&1)"
rc=$?
log="$(cat "$CLAUDE_LOG")"
assert_eq "restart aborts when git pull fails (exit 1)" 1 "$rc"
assert_not_contains "restart does not stop a lane after a failed pull" "$log" "stop sid-work-1"
assert_not_contains "restart does not relaunch after a failed pull" "$log" "--bg -n"

# The intentional-bypass path (--no-pull/--no-update) is NOT a refresh failure:
# the skipped-step status stays 0, so lanes still launch even with the failure
# env set (proves the abort keys on real failure, not on skipping).
out="$(STUB_GIT_PULL_RC=1 STUB_CLAUDE_UPDATE_RC=1 run_launcher start --repo "$REPO" --config "$CONFIG" --agents-json "$AGENTS_EMPTY" --no-pull --no-update --dry-run 2>&1)"
rc=$?
assert_eq "refresh bypass still launches despite failure env (exit 0)" 0 "$rc"
assert_contains "refresh bypass launches lanes" "$out" "claude --bg -n work"

# The same intentional-bypass invariant holds for restart, which refreshes via a
# different callback path (_restart_one): --no-pull/--no-update keeps the refresh
# status 0, so a targeted dry-run restart still previews the relaunch despite the
# failure env being set.
out="$(STUB_GIT_PULL_RC=1 STUB_CLAUDE_UPDATE_RC=1 run_launcher restart work --repo "$REPO" --config "$CONFIG" --agents-json "$AGENTS_RUNNING" --no-pull --no-update --dry-run 2>&1)"
rc=$?
assert_eq "restart refresh bypass still relaunches despite failure env (exit 0)" 0 "$rc"
assert_contains "restart refresh bypass previews the lane relaunch" "$out" "claude --bg -n work"

# ============================================================================
# An unknown restart target is rejected BEFORE the refresh mutates anything
# (matches stop's fail-first behaviour): the log shows no git pull and no
# marketplace update. Regression guard against the old order that pulled +
# updated only to reject the misspelled target afterward.
# ============================================================================
: >"$CLAUDE_LOG"
out="$(run_launcher restart does-not-exist --repo "$REPO" --config "$CONFIG" --agents-json "$AGENTS_RUNNING" 2>&1)"
rc=$?
log="$(cat "$CLAUDE_LOG")"
assert_eq "restart unknown lane exits 3" 3 "$rc"
assert_contains "restart unknown lane message" "$out" "unknown lane 'does-not-exist'"
assert_not_contains "restart unknown lane does not pull" "$log" "pull --ff-only"
assert_not_contains "restart unknown lane does not update the marketplace" "$log" "plugin marketplace update"

# ============================================================================
# #792 — launch-commit marker: start (real dispatch) writes
# <data-dir>/lanes/<name>-launch-commit for every lane it actually launches,
# holding the captured `git rev-parse HEAD` SHA.
# ============================================================================
DATA_DIR="$TMP/data"
: >"$CLAUDE_LOG"
out="$(run_launcher start --repo "$REPO" --config "$CONFIG" --agents-json "$AGENTS_EMPTY" --data-dir "$DATA_DIR" 2>&1)"
rc=$?
assert_eq "marker: start with all lanes launching exits 0" 0 "$rc"
marker="$(cat "$DATA_DIR/lanes/work-launch-commit" 2>/dev/null)"
assert_eq "marker: work marker holds the stubbed HEAD sha" "deadbeefcafefeedfacefeeddeadbeefcafefeed" "$marker"
marker="$(cat "$DATA_DIR/lanes/babysit-launch-commit" 2>/dev/null)"
assert_eq "marker: babysit marker holds the stubbed HEAD sha" "deadbeefcafefeedfacefeeddeadbeefcafefeed" "$marker"

# A lane `start` SKIPS (already running) must not get a fresh/overwritten
# marker — only lanes actually (re)launched this run are recorded.
DATA_DIR2="$TMP/data2"
mkdir -p "$DATA_DIR2/lanes"
printf 'pre-existing-sha\n' >"$DATA_DIR2/lanes/work-launch-commit"
out="$(run_launcher start --repo "$REPO" --config "$CONFIG" --agents-json "$AGENTS_RUNNING" --data-dir "$DATA_DIR2" 2>&1)"
marker="$(cat "$DATA_DIR2/lanes/work-launch-commit" 2>/dev/null)"
assert_eq "marker: skipped (already-running) lane keeps its existing marker" "pre-existing-sha" "$marker"
marker="$(cat "$DATA_DIR2/lanes/babysit-launch-commit" 2>/dev/null)"
assert_eq "marker: a lane that DID launch this run still gets one" "deadbeefcafefeedfacefeeddeadbeefcafefeed" "$marker"

# restart re-records the marker for the restarted lane.
DATA_DIR3="$TMP/data3"
out="$(run_launcher restart work --repo "$REPO" --config "$CONFIG" --agents-json "$AGENTS_RUNNING" --data-dir "$DATA_DIR3" 2>&1)"
marker="$(cat "$DATA_DIR3/lanes/work-launch-commit" 2>/dev/null)"
assert_eq "marker: restart records the marker for the relaunched lane" "deadbeefcafefeedfacefeeddeadbeefcafefeed" "$marker"

# --dry-run mutates nothing: no marker file is written, but the preview names
# the would-be marker path and the resolved HEAD.
DATA_DIR4="$TMP/data4"
out="$(run_launcher start --repo "$REPO" --config "$CONFIG" --agents-json "$AGENTS_EMPTY" --data-dir "$DATA_DIR4" --dry-run 2>&1)"
assert_contains "marker: dry-run previews the marker write" "$out" "DRY-RUN: write launch-commit marker $DATA_DIR4/lanes/work-launch-commit <- deadbeefcafefeedfacefeeddeadbeefcafefeed"
if [[ -e "$DATA_DIR4/lanes/work-launch-commit" ]]; then notwritten=1; else notwritten=0; fi
assert_eq "marker: dry-run writes no file" 0 "$notwritten"

# An unresolvable HEAD (git rev-parse fails) skips the write with a warning on
# stderr but must NOT fail the lane launch itself (best-effort).
DATA_DIR5="$TMP/data5"
out="$(STUB_GIT_REVPARSE_RC=1 run_launcher start --repo "$REPO" --config "$CONFIG" --agents-json "$AGENTS_EMPTY" --data-dir "$DATA_DIR5" 2>&1)"
rc=$?
assert_eq "marker: unresolvable HEAD still exits 0 (best-effort)" 0 "$rc"
assert_contains "marker: unresolvable HEAD warns on skip" "$out" "launch-commit marker skipped"
if [[ -e "$DATA_DIR5/lanes/work-launch-commit" ]]; then notwritten=1; else notwritten=0; fi
assert_eq "marker: unresolvable HEAD writes no file" 0 "$notwritten"

# …and when a PREVIOUS launch left a marker, an unrecordable relaunch must
# remove it rather than let the probe read that older commit as this session's
# launch point.
DATA_DIR5B="$TMP/data5b"
mkdir -p "$DATA_DIR5B/lanes"
printf 'previouslaunchsha\n' >"$DATA_DIR5B/lanes/work-launch-commit"
out="$(STUB_GIT_REVPARSE_RC=1 run_launcher restart work --repo "$REPO" --config "$CONFIG" --agents-json "$AGENTS_RUNNING" --data-dir "$DATA_DIR5B" 2>&1)"
rc=$?
assert_eq "marker: unrecordable relaunch still exits 0 (best-effort)" 0 "$rc"
if [[ -e "$DATA_DIR5B/lanes/work-launch-commit" ]]; then stale=1; else stale=0; fi
assert_eq "marker: unrecordable relaunch invalidates the previous launch's marker" 0 "$stale"
assert_contains "marker: invalidation is announced on stderr" "$out" "removed the previous launch's marker"

# A write failure (marker path occupied by a directory) is the other
# unrecordable path: same invalidation, same best-effort exit.
DATA_DIR5C="$TMP/data5c"
mkdir -p "$DATA_DIR5C/lanes/work-launch-commit"
out="$(run_launcher restart work --repo "$REPO" --config "$CONFIG" --agents-json "$AGENTS_RUNNING" --data-dir "$DATA_DIR5C" 2>&1)"
rc=$?
assert_eq "marker: failed write still exits 0 (best-effort)" 0 "$rc"
assert_contains "marker: failed write warns" "$out" "launch-commit marker write failed"

# --dry-run must never touch an existing marker, even when HEAD is unresolvable:
# it returns before the marker write/invalidate path entirely.
DATA_DIR5D="$TMP/data5d"
mkdir -p "$DATA_DIR5D/lanes"
printf 'previouslaunchsha\n' >"$DATA_DIR5D/lanes/work-launch-commit"
out="$(STUB_GIT_REVPARSE_RC=1 run_launcher restart work --repo "$REPO" --config "$CONFIG" --agents-json "$AGENTS_RUNNING" --data-dir "$DATA_DIR5D" --dry-run 2>&1)"
marker="$(cat "$DATA_DIR5D/lanes/work-launch-commit" 2>/dev/null)"
assert_eq "marker: dry-run leaves an existing marker untouched" "previouslaunchsha" "$marker"

# CLAUDE_PLUGIN_DATA env var is honored when --data-dir is not passed.
DATA_DIR6="$TMP/data6"
out="$(CLAUDE_PLUGIN_DATA="$DATA_DIR6" run_launcher start --repo "$REPO" --config "$CONFIG" --agents-json "$AGENTS_EMPTY" 2>&1)"
marker="$(cat "$DATA_DIR6/lanes/work-launch-commit" 2>/dev/null)"
assert_eq "marker: falls back to \$CLAUDE_PLUGIN_DATA when --data-dir is unset" "deadbeefcafefeedfacefeeddeadbeefcafefeed" "$marker"

# ============================================================================
echo
if ((FAILED)); then
  printf 'lane-launcher.test: FAIL — %d case(s) failed\n' "$FAILED" >&2
  exit 1
fi
printf 'lane-launcher.test: PASS — %d cases\n' "$CASE_NUM"
